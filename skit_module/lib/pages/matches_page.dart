import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'basketball_match_details_page.dart';
import 'match_details_page.dart';
import 'common_widgets.dart';

extension _ColorWithValuesCompat on Color {
  Color withValues({double? alpha}) {
    if (alpha == null) return this;
    final a = alpha.clamp(0.0, 1.0);
    return withOpacity(a);
  }
}

class MatchesPage extends StatefulWidget {
  const MatchesPage({super.key});

  @override
  State<MatchesPage> createState() => _MatchesPageState();
}

class _MatchesPageState extends State<MatchesPage> with WidgetsBindingObserver {
  static const _footballMatchesEndpoint =
      'https://api.z8vips.com/api/v1/football/matches';
  static const _basketballMatchesEndpoint =
      'https://api.z8vips.com/api/v1/basketball/matches';

  int _sportIndex = 0;
  late final PageController _pageController;
  late final ScrollController _footballScrollController;
  late final ScrollController _basketballScrollController;

  bool _loadingUpcomingFootball = false;
  String? _upcomingFootballErrorText;
  List<_UpcomingMatchItem> _upcomingFootball = const [];
  int _upcomingFootballTotal = 0;
  int _upcomingFootballPage = 1;
  int _upcomingFootballRequestSeq = 0;

  bool _loadingUpcomingBasketball = false;
  String? _upcomingBasketballErrorText;
  List<_UpcomingMatchItem> _upcomingBasketball = const [];
  int _upcomingBasketballTotal = 0;
  int _upcomingBasketballPage = 1;
  int _upcomingBasketballRequestSeq = 0;

  bool _loadingLiveFootball = false;
  String? _liveFootballErrorText;
  List<_LiveMatchItem> _liveFootball = const [];
  int _liveFootballRequestSeq = 0;

  bool _loadingLiveBasketball = false;
  String? _liveBasketballErrorText;
  List<_LiveMatchItem> _liveBasketball = const [];
  int _liveBasketballRequestSeq = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageController = PageController(initialPage: _sportIndex);
    _footballScrollController = ScrollController()
      ..addListener(_onFootballScroll);
    _basketballScrollController = ScrollController()
      ..addListener(_onBasketballScroll);
    _fetchLiveFootball();
    _fetchLiveBasketball();
    _fetchUpcomingFootball(reset: true);
    _fetchUpcomingBasketball(reset: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _footballScrollController
      ..removeListener(_onFootballScroll)
      ..dispose();
    _basketballScrollController
      ..removeListener(_onBasketballScroll)
      ..dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 当从后台切回前台（如网络权限弹窗消失后），检查是否需要刷新数据
      // 如果当前没有数据且处于错误状态，或者数据列表为空，则尝试刷新
      final hasNoFootball = _liveFootball.isEmpty && _upcomingFootball.isEmpty;
      final hasNoBasketball =
          _liveBasketball.isEmpty && _upcomingBasketball.isEmpty;

      if (hasNoFootball ||
          _liveFootballErrorText != null ||
          _upcomingFootballErrorText != null) {
        _fetchLiveFootball();
        _fetchUpcomingFootball(reset: true);
      }

      if (hasNoBasketball ||
          _liveBasketballErrorText != null ||
          _upcomingBasketballErrorText != null) {
        _fetchLiveBasketball();
        _fetchUpcomingBasketball(reset: true);
      }
    }
  }

  void _onFootballScroll() {
    if (!_footballScrollController.hasClients) return;
    final pos = _footballScrollController.position;
    if (pos.maxScrollExtent <= 0) return;
    if (pos.pixels < pos.maxScrollExtent - 240) return;
    _fetchUpcomingFootball(reset: false);
  }

  void _onBasketballScroll() {
    if (!_basketballScrollController.hasClients) return;
    final pos = _basketballScrollController.position;
    if (pos.maxScrollExtent <= 0) return;
    if (pos.pixels < pos.maxScrollExtent - 240) return;
    _fetchUpcomingBasketball(reset: false);
  }

  int _tomorrowMidnightTimestampSeconds() {
    final now = DateTime.now().toLocal();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    return tomorrow.millisecondsSinceEpoch ~/ 1000;
  }

  int? _toNullableInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse((value ?? '').toString());
  }

  int _sumScoresCsv(dynamic value) {
    final raw = (value ?? '').toString().replaceAll('`', '').trim();
    if (raw.isEmpty) return 0;
    final parts = raw.split(',');
    int sum = 0;
    for (final p in parts) {
      final v = int.tryParse(p.trim());
      if (v != null) sum += v;
    }
    return sum;
  }

  String _pickText(Map map, List<String> keys) {
    for (final k in keys) {
      final v = (map[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  String _sanitizeUrl(dynamic value) {
    final raw = (value ?? '').toString();
    final cleaned = raw.replaceAll('`', '').trim();
    if (cleaned.startsWith('//')) return 'https:$cleaned';
    if (cleaned.startsWith('http://')) {
      return cleaned.replaceFirst('http://', 'https://');
    }
    return cleaned;
  }

  dynamic _tryDecodeJson(List<int> bytes) {
    try {
      final text = utf8.decode(bytes, allowMalformed: true).trim();
      if (text.isEmpty) return null;
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  void _debugPrintLong(String text, {String? prefix, int chunkSize = 800}) {
    if (text.isEmpty) {
      debugPrint(prefix == null ? '' : prefix);
      return;
    }
    for (int i = 0; i < text.length; i += chunkSize) {
      final end = (i + chunkSize < text.length) ? (i + chunkSize) : text.length;
      final chunk = text.substring(i, end);
      if (prefix == null) {
        debugPrint(chunk);
      } else {
        debugPrint('$prefix$chunk');
      }
    }
  }

  void _printHttpResponse(String prefix, http.Response response) {
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    debugPrint('$prefix status: ${response.statusCode}');
    debugPrint('$prefix length: ${text.length}');
    _debugPrintLong(text, prefix: '$prefix body: ');
  }

  String _truncateLogText(String text, {int maxChars = 3000}) {
    final t = text.trim();
    if (t.length <= maxChars) return t;
    return '${t.substring(0, maxChars)}...(truncated ${t.length - maxChars} chars)';
  }

  String _formatMatchTime(dynamic raw) {
    int? seconds;
    if (raw is int) {
      seconds = raw > 9999999999 ? (raw ~/ 1000) : raw;
    } else if (raw is double) {
      return _formatMatchTime(raw.round());
    } else {
      seconds = int.tryParse((raw ?? '').toString());
    }
    if (seconds == null) return '-';
    final dt = DateTime.fromMillisecondsSinceEpoch(seconds * 1000).toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  String _formatClockTime(dynamic raw) {
    int? seconds;
    if (raw is int) {
      seconds = raw > 9999999999 ? (raw ~/ 1000) : raw;
    } else if (raw is double) {
      return _formatClockTime(raw.round());
    } else {
      seconds = int.tryParse((raw ?? '').toString());
    }
    if (seconds == null) return '-';
    final dt = DateTime.fromMillisecondsSinceEpoch(seconds * 1000).toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(dt.hour)}:${two(dt.minute)}';
  }

  Future<void> _fetchLiveFootball() async {
    final requestId = ++_liveFootballRequestSeq;
    setState(() {
      _loadingLiveFootball = true;
      _liveFootballErrorText = null;
    });

    try {
      final uri = Uri.parse(_footballMatchesEndpoint);
      final body = jsonEncode({'tab': 1, 'page': 1, 'type': 0});
      debugPrint('[matches] POST $uri');
      debugPrint('[matches] body: $body');
      final response = await http.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: body,
      );
      _printHttpResponse('[matches][football][live]', response);
      if (response.statusCode != 200) {
        throw Exception('http ${response.statusCode}');
      }
      final decoded = _tryDecodeJson(response.bodyBytes);
      if (decoded is! Map) {
        throw Exception('invalid json');
      }
      if (decoded['code'] != 0) {
        throw Exception('invalid response');
      }
      final data = decoded['data'];
      if (data is! Map) {
        throw Exception('invalid response');
      }
      final results = data['results'];
      final List list = results is List ? results : const [];

      final items = <_LiveMatchItem>[];
      for (final e in list) {
        if (e is! Map) continue;
        final homeName = _pickText(e, [
          'home_team_name_en',
          'home_team_en',
          'home_team_name',
        ]);
        final awayName = _pickText(e, [
          'away_team_name_en',
          'away_team_en',
          'away_team_name',
        ]);
        final league = _pickText(e, [
          'competition_name_en',
          'league_name_en',
          'competition_name',
          'league_name',
        ]);
        final timeText = _formatClockTime(e['match_time']);
        final minuteText = (e['minutes'] ?? '').toString().trim();
        final statusText = (e['status_name'] ?? '').toString().trim();
        final homeScore = _toNullableInt(e['home_normal_score']) ?? 0;
        final awayScore = _toNullableInt(e['away_normal_score']) ?? 0;
        final homeLogo = _sanitizeUrl(e['home_team_logo']);
        final awayLogo = _sanitizeUrl(e['away_team_logo']);
        final matchId = _toNullableInt(
          e['match_id'] ?? e['matchId'] ?? e['id'] ?? e['matchid'],
        );

        items.add(
          _LiveMatchItem(
            leftTeamName: homeName.isEmpty ? '-' : homeName,
            rightTeamName: awayName.isEmpty ? '-' : awayName,
            league: league.isEmpty ? '-' : league,
            leftScore: homeScore,
            rightScore: awayScore,
            timeText: timeText,
            minuteText: minuteText.isNotEmpty ? minuteText : statusText,
            matchId: matchId,
            leftTeamLogoUrl: homeLogo.isEmpty ? null : homeLogo,
            rightTeamLogoUrl: awayLogo.isEmpty ? null : awayLogo,
          ),
        );
      }

      if (!mounted || requestId != _liveFootballRequestSeq) return;
      setState(() {
        _liveFootball = items;
      });
    } catch (_) {
      if (!mounted || requestId != _liveFootballRequestSeq) return;
      setState(() {
        _liveFootballErrorText = 'Live Matches 加载失败';
      });
    } finally {
      if (mounted && requestId == _liveFootballRequestSeq) {
        setState(() {
          _loadingLiveFootball = false;
        });
      }
    }
  }

  Future<void> _fetchLiveBasketball() async {
    final requestId = ++_liveBasketballRequestSeq;
    setState(() {
      _loadingLiveBasketball = true;
      _liveBasketballErrorText = null;
    });

    try {
      final uri = Uri.parse(_basketballMatchesEndpoint);
      final body = jsonEncode({'tab': 1, 'page': 1, 'size': 10});
      debugPrint('[matches] POST $uri');
      debugPrint('[matches] body: $body');
      final response = await http.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: body,
      );
      _printHttpResponse('[matches][basketball][live]', response);
      if (response.statusCode != 200) {
        throw Exception('http ${response.statusCode}');
      }
      final decoded = _tryDecodeJson(response.bodyBytes);
      if (decoded is! Map) {
        throw Exception('invalid json');
      }
      if (decoded['code'] != 0) {
        throw Exception('invalid response');
      }
      final data = decoded['data'];
      if (data is! Map) {
        throw Exception('invalid response');
      }
      final results = data['results'];
      final List list = results is List ? results : const [];

      final items = <_LiveMatchItem>[];
      for (final e in list) {
        if (e is! Map) continue;
        final homeName = _pickText(e, [
          'home_team_name',
          'home_team_name_en',
          'home_team_short_name_en',
          'home_team_en',
          'home_team_short_name',
          'home_team',
        ]);
        final awayName = _pickText(e, [
          'away_team_name',
          'away_team_name_en',
          'away_team_short_name_en',
          'away_team_en',
          'away_team_short_name',
          'away_team',
        ]);
        final league = _pickText(e, [
          'competition_name',
          'competition_name_en',
          'league_name_en',
          'league_name',
        ]);
        final timeText = _formatClockTime(
          e['match_time'] ?? e['start_time'] ?? e['match_start_time'],
        );
        final minuteText = _pickText(e, [
          'status_name',
          'period_name',
          'stage_name',
          'minutes',
        ]);
        final homeScoresCsv = (e['home_scores'] ?? '').toString().trim();
        final awayScoresCsv = (e['away_scores'] ?? '').toString().trim();
        final homeScore = homeScoresCsv.isNotEmpty
            ? _sumScoresCsv(homeScoresCsv)
            : (_toNullableInt(e['home_normal_score']) ??
                _toNullableInt(e['home_score']) ??
                _toNullableInt(e['home_total_score']) ??
                0);
        final awayScore = awayScoresCsv.isNotEmpty
            ? _sumScoresCsv(awayScoresCsv)
            : (_toNullableInt(e['away_normal_score']) ??
                _toNullableInt(e['away_score']) ??
                _toNullableInt(e['away_total_score']) ??
                0);
        final homeLogo = _sanitizeUrl(e['home_team_logo']);
        final awayLogo = _sanitizeUrl(e['away_team_logo']);
        final matchId = _toNullableInt(
          e['match_id'] ?? e['matchId'] ?? e['id'] ?? e['matchid'] ?? e['ID'],
        );

        items.add(
          _LiveMatchItem(
            leftTeamName: homeName.isEmpty ? '-' : homeName,
            rightTeamName: awayName.isEmpty ? '-' : awayName,
            league: league.isEmpty ? '-' : league,
            leftScore: homeScore,
            rightScore: awayScore,
            timeText: timeText,
            minuteText: minuteText.isEmpty ? '-' : minuteText,
            matchId: matchId,
            leftTeamLogoUrl: homeLogo.isEmpty ? null : homeLogo,
            rightTeamLogoUrl: awayLogo.isEmpty ? null : awayLogo,
          ),
        );
      }

      if (!mounted || requestId != _liveBasketballRequestSeq) return;
      setState(() {
        _liveBasketball = items;
      });
    } catch (_) {
      if (!mounted || requestId != _liveBasketballRequestSeq) return;
      setState(() {
        _liveBasketballErrorText = 'Live Matches 加载失败';
      });
    } finally {
      if (mounted && requestId == _liveBasketballRequestSeq) {
        setState(() {
          _loadingLiveBasketball = false;
        });
      }
    }
  }

  Future<void> _fetchUpcomingFootball({required bool reset}) async {
    if (_loadingUpcomingFootball) return;

    final page = reset ? 1 : (_upcomingFootballPage + 1);
    if (!reset) {
      final total = _upcomingFootballTotal;
      if (total > 0 && _upcomingFootball.length >= total) return;
    }

    final requestId = ++_upcomingFootballRequestSeq;
    setState(() {
      _loadingUpcomingFootball = true;
      if (reset) _upcomingFootballErrorText = null;
    });

    try {
      final uri = Uri.parse(_footballMatchesEndpoint);
      final body = jsonEncode({
        'tab': 5,
        'page': page,
        'size': 20,
        'timestamp': _tomorrowMidnightTimestampSeconds(),
        'competion_ids': <dynamic>[],
        'competition_ids': <dynamic>[],
        'type': 2,
      });
      final response = await http.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: body,
      );
      if (response.statusCode != 200) {
        throw Exception('http ${response.statusCode}');
      }
      final decoded = _tryDecodeJson(response.bodyBytes);
      if (decoded is! Map) {
        throw Exception('invalid json');
      }
      if (decoded['code'] != 0) {
        throw Exception('invalid response');
      }
      final data = decoded['data'];
      if (data is! Map) {
        throw Exception('invalid response');
      }
      final total = _toNullableInt(data['total']) ?? 0;
      final results = data['results'];
      final List list = results is List ? results : const [];

      final items = <_UpcomingMatchItem>[];
      for (final e in list) {
        if (e is! Map) continue;
        final matchId = _toNullableInt(
          e['match_id'] ?? e['matchId'] ?? e['id'],
        );
        final homeName = _pickText(e, [
          'home_team_name_en',
          'home_team_en',
          'home_team_name',
        ]);
        final awayName = _pickText(e, [
          'away_team_name_en',
          'away_team_en',
          'away_team_name',
        ]);
        final league = _pickText(e, [
          'competition_name_en',
          'league_name_en',
          'competition_name',
          'league_name',
        ]);
        final timeText = _formatMatchTime(e['match_time']);
        final homeLogo = _sanitizeUrl(e['home_team_logo']);
        final awayLogo = _sanitizeUrl(e['away_team_logo']);
        items.add(
          _UpcomingMatchItem(
            matchId: matchId,
            dateTimeText: timeText,
            homeName: homeName.isEmpty ? '-' : homeName,
            awayName: awayName.isEmpty ? '-' : awayName,
            leagueName: league.isEmpty ? '-' : league,
            homeLogoUrl: homeLogo.isEmpty ? null : homeLogo,
            awayLogoUrl: awayLogo.isEmpty ? null : awayLogo,
          ),
        );
      }

      if (!mounted || requestId != _upcomingFootballRequestSeq) return;
      setState(() {
        _upcomingFootballTotal = total;
        _upcomingFootballPage = page;
        _upcomingFootball = reset ? items : [..._upcomingFootball, ...items];
      });
    } catch (_) {
      if (!mounted || requestId != _upcomingFootballRequestSeq) return;
      setState(() {
        _upcomingFootballErrorText = 'Upcoming Matches 加载失败';
      });
    } finally {
      if (mounted && requestId == _upcomingFootballRequestSeq) {
        setState(() {
          _loadingUpcomingFootball = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const _MatchesBackground(),
        SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _SportToggle(
                  index: _sportIndex,
                  onChanged: (v) {
                    setState(() => _sportIndex = v);
                    _pageController.animateToPage(
                      v,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                    );
                  },
                ),
              ),
              const SizedBox(height: 22),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (v) => setState(() => _sportIndex = v),
                  children: [_buildMatchesList(0), _buildMatchesList(1)],
                ),
              ),
            ],
          ),
        ),
        Positioned(
          right: 18,
          bottom: kBottomNavigationBarHeight +
              MediaQuery.of(context).padding.bottom +
              -10,
          child: _RefreshFab(onTap: _refreshSelectedTab),
        ),
      ],
    );
  }

  Future<void> _fetchUpcomingBasketball({required bool reset}) async {
    if (_loadingUpcomingBasketball) return;

    final page = reset ? 1 : (_upcomingBasketballPage + 1);
    if (!reset) {
      final total = _upcomingBasketballTotal;
      if (total > 0 && _upcomingBasketball.length >= total) return;
    }

    final requestId = ++_upcomingBasketballRequestSeq;
    setState(() {
      _loadingUpcomingBasketball = true;
      if (reset) _upcomingBasketballErrorText = null;
    });

    try {
      final uri = Uri.parse(_basketballMatchesEndpoint);
      final body = jsonEncode({
        'tab': 5,
        'page': page,
        'size': 20,
        'timestamp': _tomorrowMidnightTimestampSeconds(),
        'competion_ids': <dynamic>[],
        'competition_ids': <dynamic>[],
        'type': 1,
      });
      debugPrint('[matches] POST $uri');
      debugPrint('[matches] body: $body');
      final response = await http.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: body,
      );
      _printHttpResponse('[matches][basketball][upcoming]', response);
      if (response.statusCode != 200) {
        throw Exception('http ${response.statusCode}');
      }
      final decoded = _tryDecodeJson(response.bodyBytes);
      if (decoded is! Map) {
        throw Exception('invalid json');
      }
      if (decoded['code'] != 0) {
        throw Exception('invalid response');
      }
      final data = decoded['data'];
      if (data is! Map) {
        throw Exception('invalid response');
      }
      final total = _toNullableInt(data['total']) ?? 0;
      final results = data['results'];
      final List list = results is List ? results : const [];

      final items = <_UpcomingMatchItem>[];
      for (final e in list) {
        if (e is! Map) continue;
        final matchId = _toNullableInt(
          e['match_id'] ?? e['matchId'] ?? e['id'],
        );
        final homeName = _pickText(e, [
          'home_team_name_en',
          'home_team_short_name_en',
          'home_team_en',
          'home_team_name',
          'home_team_short_name',
          'home_team',
        ]);
        final awayName = _pickText(e, [
          'away_team_name_en',
          'away_team_short_name_en',
          'away_team_en',
          'away_team_name',
          'away_team_short_name',
          'away_team',
        ]);
        final league = _pickText(e, [
          'competition_name_en',
          'league_name_en',
          'competition_name',
          'league_name',
        ]);
        final timeText = _formatMatchTime(e['match_time']);
        final homeLogo = _sanitizeUrl(e['home_team_logo']);
        final awayLogo = _sanitizeUrl(e['away_team_logo']);
        items.add(
          _UpcomingMatchItem(
            matchId: matchId,
            dateTimeText: timeText,
            homeName: homeName.isEmpty ? '-' : homeName,
            awayName: awayName.isEmpty ? '-' : awayName,
            leagueName: league.isEmpty ? '-' : league,
            homeLogoUrl: homeLogo.isEmpty ? null : homeLogo,
            awayLogoUrl: awayLogo.isEmpty ? null : awayLogo,
          ),
        );
      }

      if (!mounted || requestId != _upcomingBasketballRequestSeq) return;
      setState(() {
        _upcomingBasketballTotal = total;
        _upcomingBasketballPage = page;
        _upcomingBasketball =
            reset ? items : [..._upcomingBasketball, ...items];
      });
    } catch (_) {
      if (!mounted || requestId != _upcomingBasketballRequestSeq) return;
      setState(() {
        _upcomingBasketballErrorText = 'Upcoming Matches 加载失败';
      });
    } finally {
      if (mounted && requestId == _upcomingBasketballRequestSeq) {
        setState(() {
          _loadingUpcomingBasketball = false;
        });
      }
    }
  }

  void _refreshSelectedTab() {
    if (_sportIndex == 0) {
      _fetchLiveFootball();
      _fetchUpcomingFootball(reset: true);
      return;
    }
    _fetchLiveBasketball();
    _fetchUpcomingBasketball(reset: true);
  }

  Widget _buildMatchesList(int index) {
    return ListView(
      controller:
          index == 0 ? _footballScrollController : _basketballScrollController,
      key: PageStorageKey('matches_$index'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        _SectionHeader(
          title: 'Live Matches',
          actionText: 'View all',
          onAction: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => LiveMatchesViewAllPage(sportIndex: index),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (index == 0) ...[
          if (_loadingLiveFootball && _liveFootball.isEmpty)
            const SizedBox(
              height: 186,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_liveFootballErrorText != null && _liveFootball.isEmpty)
            SizedBox(
              height: 186,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _liveFootballErrorText!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 32,
                    child: ElevatedButton(
                      onPressed: _fetchLiveFootball,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.10),
                        foregroundColor: Colors.white.withValues(alpha: 0.9),
                        elevation: 0,
                        shape: const StadiumBorder(),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: const Text('重试'),
                    ),
                  ),
                ],
              ),
            )
          else if (_liveFootball.isEmpty)
            const SizedBox(
              height: 186,
              child: NoDataPlaceholder(message: 'No live matches'),
            )
          else
            SizedBox(
              height: 186,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _liveFootball.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (context, i) {
                  final m = _liveFootball[i];
                  return _LiveMatchCard(
                    onTap: m.matchId == null
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => MatchDetailsPage(
                                  matchId: m.matchId,
                                  initialHomeTeamName: m.leftTeamName,
                                  initialAwayTeamName: m.rightTeamName,
                                  initialHomeTeamLogoUrl: m.leftTeamLogoUrl,
                                  initialAwayTeamLogoUrl: m.rightTeamLogoUrl,
                                  initialCompetitionName: m.league,
                                  initialHomeScore: m.leftScore,
                                  initialAwayScore: m.rightScore,
                                ),
                              ),
                            ),
                    leftTeamName: m.leftTeamName,
                    rightTeamName: m.rightTeamName,
                    league: m.league,
                    leftScore: m.leftScore,
                    rightScore: m.rightScore,
                    time: m.timeText,
                    minute: m.minuteText,
                    leftTeamLogoUrl: m.leftTeamLogoUrl,
                    rightTeamLogoUrl: m.rightTeamLogoUrl,
                  );
                },
              ),
            ),
        ] else ...[
          if (_loadingLiveBasketball && _liveBasketball.isEmpty)
            const SizedBox(
              height: 186,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_liveBasketballErrorText != null && _liveBasketball.isEmpty)
            SizedBox(
              height: 186,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _liveBasketballErrorText!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 32,
                    child: ElevatedButton(
                      onPressed: _fetchLiveBasketball,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.10),
                        foregroundColor: Colors.white.withValues(alpha: 0.9),
                        elevation: 0,
                        shape: const StadiumBorder(),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: const Text('重试'),
                    ),
                  ),
                ],
              ),
            )
          else if (_liveBasketball.isEmpty)
            const SizedBox(
              height: 186,
              child: NoDataPlaceholder(message: 'No live matches'),
            )
          else
            SizedBox(
              height: 186,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _liveBasketball.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (context, i) {
                  final m = _liveBasketball[i];
                  return _LiveMatchCard(
                    onTap: m.matchId == null
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => BasketballMatchDetailsPage(
                                  matchId: m.matchId,
                                  initialHomeTeamName: m.leftTeamName,
                                  initialAwayTeamName: m.rightTeamName,
                                  initialHomeTeamLogoUrl: m.leftTeamLogoUrl,
                                  initialAwayTeamLogoUrl: m.rightTeamLogoUrl,
                                  initialCompetitionName: m.league,
                                  initialHomeScore: m.leftScore,
                                  initialAwayScore: m.rightScore,
                                  initialTimeText: m.timeText,
                                  initialPeriodText: m.minuteText,
                                ),
                              ),
                            ),
                    sportIcon: Icons.sports_basketball_rounded,
                    leftTeamName: m.leftTeamName,
                    rightTeamName: m.rightTeamName,
                    league: m.league,
                    leftScore: m.leftScore,
                    rightScore: m.rightScore,
                    time: m.timeText,
                    minute: m.minuteText,
                    leftTeamLogoUrl: m.leftTeamLogoUrl,
                    rightTeamLogoUrl: m.rightTeamLogoUrl,
                  );
                },
              ),
            ),
        ],
        const SizedBox(height: 26),
        const _SectionHeader(title: 'Upcoming Matches'),
        const SizedBox(height: 12),
        if (index == 0) ...[
          if (_loadingUpcomingFootball && _upcomingFootball.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_upcomingFootballErrorText != null &&
              _upcomingFootball.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Column(
                children: [
                  Text(
                    _upcomingFootballErrorText!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 32,
                    child: ElevatedButton(
                      onPressed: () => _fetchUpcomingFootball(reset: true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.10),
                        foregroundColor: Colors.white.withValues(alpha: 0.9),
                        elevation: 0,
                        shape: const StadiumBorder(),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: const Text('重试'),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            if (_upcomingFootball.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: NoDataPlaceholder(message: 'No upcoming matches'),
              )
            else
              for (int i = 0; i < _upcomingFootball.length; i++) ...[
                () {
                  final m = _upcomingFootball[i];
                  return _UpcomingMatchCard(
                    onTap: m.matchId == null
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => MatchDetailsPage(
                                  matchId: m.matchId,
                                  initialHomeTeamName: m.homeName,
                                  initialAwayTeamName: m.awayName,
                                  initialHomeTeamLogoUrl: m.homeLogoUrl,
                                  initialAwayTeamLogoUrl: m.awayLogoUrl,
                                  initialCompetitionName: m.leagueName,
                                ),
                              ),
                            ),
                    dateTime: m.dateTimeText,
                    leftTeamName: m.homeName,
                    rightTeamName: m.awayName,
                    league: m.leagueName,
                    leftTeamLogoUrl: m.homeLogoUrl,
                    rightTeamLogoUrl: m.awayLogoUrl,
                  );
                }(),
                if (i != _upcomingFootball.length - 1)
                  const SizedBox(height: 14),
              ],
            if (_loadingUpcomingFootball && _upcomingFootball.isNotEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              const SizedBox(height: 10),
          ],
        ] else ...[
          if (_loadingUpcomingBasketball && _upcomingBasketball.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_upcomingBasketballErrorText != null &&
              _upcomingBasketball.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Column(
                children: [
                  Text(
                    _upcomingBasketballErrorText!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 32,
                    child: ElevatedButton(
                      onPressed: () => _fetchUpcomingBasketball(reset: true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.10),
                        foregroundColor: Colors.white.withValues(alpha: 0.9),
                        elevation: 0,
                        shape: const StadiumBorder(),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: const Text('重试'),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            if (_upcomingBasketball.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: NoDataPlaceholder(message: 'No upcoming matches'),
              )
            else
              for (int i = 0; i < _upcomingBasketball.length; i++) ...[
                () {
                  final m = _upcomingBasketball[i];
                  return _UpcomingMatchCard(
                    onTap: m.matchId == null
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => BasketballMatchDetailsPage(
                                  matchId: m.matchId,
                                  initialHomeTeamName: m.homeName,
                                  initialAwayTeamName: m.awayName,
                                  initialHomeTeamLogoUrl: m.homeLogoUrl,
                                  initialAwayTeamLogoUrl: m.awayLogoUrl,
                                  initialCompetitionName: m.leagueName,
                                  initialTimeText: m.dateTimeText,
                                  initialPeriodText: '',
                                ),
                              ),
                            ),
                    dateTime: m.dateTimeText,
                    leftTeamName: m.homeName,
                    rightTeamName: m.awayName,
                    league: m.leagueName,
                    leftTeamLogoUrl: m.homeLogoUrl,
                    rightTeamLogoUrl: m.awayLogoUrl,
                  );
                }(),
                if (i != _upcomingBasketball.length - 1)
                  const SizedBox(height: 14),
              ],
            if (_loadingUpcomingBasketball && _upcomingBasketball.isNotEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              const SizedBox(height: 10),
          ],
        ],
      ],
    );
  }
}

class _UpcomingMatchItem {
  const _UpcomingMatchItem({
    required this.matchId,
    required this.dateTimeText,
    required this.homeName,
    required this.awayName,
    required this.leagueName,
    required this.homeLogoUrl,
    required this.awayLogoUrl,
  });

  final int? matchId;
  final String dateTimeText;
  final String homeName;
  final String awayName;
  final String leagueName;
  final String? homeLogoUrl;
  final String? awayLogoUrl;
}

class _LiveMatchItem {
  const _LiveMatchItem({
    required this.leftTeamName,
    required this.rightTeamName,
    required this.league,
    required this.leftScore,
    required this.rightScore,
    required this.timeText,
    required this.minuteText,
    required this.matchId,
    this.leftTeamLogoUrl,
    this.rightTeamLogoUrl,
  });

  final String leftTeamName;
  final String rightTeamName;
  final String league;
  final int leftScore;
  final int rightScore;
  final String timeText;
  final String minuteText;
  final int? matchId;
  final String? leftTeamLogoUrl;
  final String? rightTeamLogoUrl;
}

class _MatchesBackground extends StatelessWidget {
  const _MatchesBackground();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0F2B20), Color(0xFF071813)],
        ),
      ),
    );
  }
}

class _SportToggle extends StatelessWidget {
  const _SportToggle({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SportToggleItem(
              selected: index == 0,
              label: 'Football',
              leading: const Icon(Icons.sports_soccer_rounded, size: 18),
              onTap: () => onChanged(0),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _SportToggleItem(
              selected: index == 1,
              label: 'Basketball',
              onTap: () => onChanged(1),
            ),
          ),
        ],
      ),
    );
  }
}

class _SportToggleItem extends StatelessWidget {
  const _SportToggleItem({
    required this.selected,
    required this.label,
    required this.onTap,
    this.leading,
  });

  final bool selected;
  final String label;
  final VoidCallback onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? const LinearGradient(colors: [Color(0xFF2D63FF), Color(0xFF1DE9B6)])
        : null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            gradient: bg,
            color: selected ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(26),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 16,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leading != null) ...[
                  IconTheme(
                    data: IconThemeData(
                      color: selected
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.75),
                    ),
                    child: leading!,
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: selected
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.65),
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.actionText, this.onAction});

  final String title;
  final String? actionText;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 0.2,
            ),
          ),
        ),
        if (actionText != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF00E676),
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              actionText!,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ),
      ],
    );
  }
}

class _LiveMatchCard extends StatelessWidget {
  const _LiveMatchCard({
    this.onTap,
    this.width = 240,
    this.height,
    this.background = _LiveMatchCardBackground.image,
    this.sportIcon = Icons.sports_soccer_rounded,
    required this.leftTeamName,
    required this.rightTeamName,
    required this.league,
    required this.leftScore,
    required this.rightScore,
    required this.time,
    required this.minute,
    this.leftTeamLogoUrl,
    this.rightTeamLogoUrl,
  });

  final String leftTeamName;
  final String rightTeamName;
  final String league;
  final int leftScore;
  final int rightScore;
  final String time;
  final String minute;
  final String? leftTeamLogoUrl;
  final String? rightTeamLogoUrl;
  final VoidCallback? onTap;
  final double width;
  final double? height;
  final _LiveMatchCardBackground background;
  final IconData sportIcon;

  static const double _bgAspectRatio = 434 / 318;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 22,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFF3B30),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'LIVE',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Text(
                  time,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 1),
                    child: Text(
                      minute,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  leftTeamName,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              _BadgeLogo(seed: leftTeamName, url: leftTeamLogoUrl),
              const SizedBox(width: 10),
              _BadgeLogo(seed: rightTeamName, url: rightTeamLogoUrl),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  rightTeamName,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
          const Spacer(),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$leftScore',
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  sportIcon,
                  size: 20,
                  color: Colors.white.withValues(alpha: 0.92),
                ),
                const SizedBox(width: 10),
                Text(
                  '$rightScore',
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              league,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.78),
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );

    return SizedBox(
      width: width,
      height: background == _LiveMatchCardBackground.gradient ? height : null,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: background == _LiveMatchCardBackground.gradient
                ? Ink(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0x99173788), Color(0xFF00FD64)],
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: content,
                  )
                : AspectRatio(
                    aspectRatio: _bgAspectRatio,
                    child: Stack(
                      children: [
                        const Positioned.fill(
                          child: Image(
                            image: AssetImage('assets/images/home_card_bg.png'),
                            fit: BoxFit.contain,
                          ),
                        ),
                        content,
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

enum _LiveMatchCardBackground { image, gradient }

class _UpcomingMatchCard extends StatelessWidget {
  const _UpcomingMatchCard({
    this.onTap,
    required this.dateTime,
    required this.leftTeamName,
    required this.rightTeamName,
    required this.league,
    this.leftTeamLogoUrl,
    this.rightTeamLogoUrl,
  });

  static const double _bgAspectRatio = 702 / 224;

  final VoidCallback? onTap;
  final String dateTime;
  final String leftTeamName;
  final String rightTeamName;
  final String league;
  final String? leftTeamLogoUrl;
  final String? rightTeamLogoUrl;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: AspectRatio(
          aspectRatio: _bgAspectRatio,
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  'assets/images/home_matches_bg.png',
                  fit: BoxFit.contain,
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.12),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      dateTime,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.88),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              leftTeamName,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          _BadgeLogo(seed: leftTeamName, url: leftTeamLogoUrl),
                          const SizedBox(width: 10),
                          const Text(
                            'VS',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(width: 10),
                          _BadgeLogo(
                            seed: rightTeamName,
                            url: rightTeamLogoUrl,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              rightTeamName,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      league,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: card,
      ),
    );
  }
}

class _BadgeLogo extends StatelessWidget {
  const _BadgeLogo({required this.seed, this.url});

  final String seed;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final raw0 = (url ?? '').replaceAll('`', '').trim();
    final raw = raw0.startsWith('//')
        ? 'https:$raw0'
        : (raw0.startsWith('http://')
            ? raw0.replaceFirst('http://', 'https://')
            : raw0);

    if (raw.isEmpty) {
      return const SizedBox(width: 26, height: 26);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.network(
        raw,
        width: 26,
        height: 26,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const SizedBox(width: 26, height: 26),
      ),
    );
  }
}

class _RefreshFab extends StatelessWidget {
  const _RefreshFab({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(35),
        child: SizedBox(
          width: 70,
          height: 70,
          child: Image.asset('assets/images/home_ref.png', fit: BoxFit.contain),
        ),
      ),
    );
  }
}

class _BackIconButton extends StatelessWidget {
  const _BackIconButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Center(
            child: Image.asset(
              'assets/images/back_icon.png',
              width: 38,
              height: 38,
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
    );
  }
}

class LiveMatchesViewAllPage extends StatefulWidget {
  const LiveMatchesViewAllPage({super.key, required this.sportIndex});

  final int sportIndex;

  @override
  State<LiveMatchesViewAllPage> createState() => _LiveMatchesViewAllPageState();
}

class _LiveMatchesViewAllPageState extends State<LiveMatchesViewAllPage> {
  static const _footballMatchesEndpoint =
      'https://api.v8-ball.com/api/v1/football/matches';
  static const _basketballMatchesEndpoint =
      'https://api.v8-ball.com/api/v1/basketball/matches';

  late final ScrollController _scrollController;

  bool _loading = false;
  bool _loadingMore = false;
  String? _errorText;
  String? _moreErrorText;
  int _page = 1;
  bool _hasMore = true;
  int _requestSeq = 0;

  List<_LiveMatchItem> _items = const [];

  bool get _isFootball => widget.sportIndex == 0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    _fetch(reset: true);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.maxScrollExtent <= 0) return;
    if (pos.pixels < pos.maxScrollExtent - 240) return;
    if (_loadingMore || _loading || !_hasMore) return;
    _fetch(reset: false);
  }

  dynamic _tryDecodeJson(List<int> bytes) {
    try {
      final text = utf8.decode(bytes, allowMalformed: true).trim();
      if (text.isEmpty) return null;
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  int? _toNullableInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse((value ?? '').toString());
  }

  String _pickText(Map map, List<String> keys) {
    for (final k in keys) {
      final v = (map[k] ?? '').toString().trim();
      if (v.isNotEmpty && v != 'null') return v;
    }
    return '';
  }

  String _sanitizeUrl(dynamic value) {
    final raw = (value ?? '').toString();
    final cleaned = raw.replaceAll('`', '').trim();
    if (cleaned.startsWith('//')) return 'https:$cleaned';
    if (cleaned.startsWith('http://')) {
      return cleaned.replaceFirst('http://', 'https://');
    }
    return cleaned;
  }

  String _formatClockTime(dynamic raw) {
    int? seconds;
    if (raw is int) {
      seconds = raw > 9999999999 ? (raw ~/ 1000) : raw;
    } else if (raw is double) {
      return _formatClockTime(raw.round());
    } else {
      seconds = int.tryParse((raw ?? '').toString());
    }
    if (seconds == null) return '-';
    final dt = DateTime.fromMillisecondsSinceEpoch(seconds * 1000).toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(dt.hour)}:${two(dt.minute)}';
  }

  int _sumScoresCsv(dynamic value) {
    final raw = (value ?? '').toString().replaceAll('`', '').trim();
    if (raw.isEmpty) return 0;
    final parts = raw.split(',');
    int sum = 0;
    for (final p in parts) {
      final v = int.tryParse(p.trim());
      if (v != null) sum += v;
    }
    return sum;
  }

  Future<void> _fetch({required bool reset}) async {
    final requestId = ++_requestSeq;
    final page = reset ? 1 : (_page + 1);
    final endpoint =
        _isFootball ? _footballMatchesEndpoint : _basketballMatchesEndpoint;

    if (reset) {
      setState(() {
        _loading = true;
        _errorText = null;
        _moreErrorText = null;
      });
    } else {
      setState(() {
        _loadingMore = true;
        _moreErrorText = null;
      });
    }

    try {
      final uri = Uri.parse(endpoint);
      final body = _isFootball
          ? jsonEncode({'tab': 1, 'page': page, 'size': 20, 'type': 0})
          : jsonEncode({'tab': 1, 'page': page, 'size': 20});

      final response = await http.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: body,
      );
      if (response.statusCode != 200) {
        throw Exception('http ${response.statusCode}');
      }
      final decoded = _tryDecodeJson(response.bodyBytes);
      if (decoded is! Map) throw Exception('invalid json');
      final Object? code = decoded['code'];
      if (code != null && code != 0) throw Exception('invalid response');
      final Object? rawData = decoded['data'];
      final Map data = rawData is Map ? rawData : decoded;
      final results = data['results'];
      final List list = results is List ? results : const [];

      final items = <_LiveMatchItem>[];
      for (final e in list) {
        if (e is! Map) continue;

        if (_isFootball) {
          final homeName = _pickText(e, [
            'home_team_name_en',
            'home_team_en',
            'home_team_name',
          ]);
          final awayName = _pickText(e, [
            'away_team_name_en',
            'away_team_en',
            'away_team_name',
          ]);
          final league = _pickText(e, [
            'competition_name_en',
            'league_name_en',
            'competition_name',
            'league_name',
          ]);
          final timeText = _formatClockTime(e['match_time']);
          final minuteText = (e['minutes'] ?? '').toString().trim();
          final statusText = (e['status_name'] ?? '').toString().trim();
          final homeScore = _toNullableInt(e['home_normal_score']) ?? 0;
          final awayScore = _toNullableInt(e['away_normal_score']) ?? 0;
          final homeLogo = _sanitizeUrl(e['home_team_logo']);
          final awayLogo = _sanitizeUrl(e['away_team_logo']);
          final matchId = _toNullableInt(
            e['match_id'] ?? e['matchId'] ?? e['id'] ?? e['matchid'],
          );

          items.add(
            _LiveMatchItem(
              leftTeamName: homeName.isEmpty ? '-' : homeName,
              rightTeamName: awayName.isEmpty ? '-' : awayName,
              league: league.isEmpty ? '-' : league,
              leftScore: homeScore,
              rightScore: awayScore,
              timeText: timeText,
              minuteText: minuteText.isNotEmpty ? minuteText : statusText,
              matchId: matchId,
              leftTeamLogoUrl: homeLogo.isEmpty ? null : homeLogo,
              rightTeamLogoUrl: awayLogo.isEmpty ? null : awayLogo,
            ),
          );
        } else {
          final homeName = _pickText(e, [
            'home_team_name',
            'home_team_name_en',
            'home_team_short_name_en',
            'home_team_en',
            'home_team_short_name',
            'home_team',
          ]);
          final awayName = _pickText(e, [
            'away_team_name',
            'away_team_name_en',
            'away_team_short_name_en',
            'away_team_en',
            'away_team_short_name',
            'away_team',
          ]);
          final league = _pickText(e, [
            'competition_name',
            'competition_name_en',
            'league_name_en',
            'league_name',
          ]);
          final timeText = _formatClockTime(
            e['match_time'] ?? e['start_time'] ?? e['match_start_time'],
          );
          final minuteText = _pickText(e, [
            'status_name',
            'period_name',
            'stage_name',
            'minutes',
          ]);
          final homeScoresCsv = (e['home_scores'] ?? '').toString().trim();
          final awayScoresCsv = (e['away_scores'] ?? '').toString().trim();
          final homeScore = homeScoresCsv.isNotEmpty
              ? _sumScoresCsv(homeScoresCsv)
              : (_toNullableInt(e['home_normal_score']) ??
                  _toNullableInt(e['home_score']) ??
                  _toNullableInt(e['home_total_score']) ??
                  0);
          final awayScore = awayScoresCsv.isNotEmpty
              ? _sumScoresCsv(awayScoresCsv)
              : (_toNullableInt(e['away_normal_score']) ??
                  _toNullableInt(e['away_score']) ??
                  _toNullableInt(e['away_total_score']) ??
                  0);
          final homeLogo = _sanitizeUrl(e['home_team_logo']);
          final awayLogo = _sanitizeUrl(e['away_team_logo']);
          final matchId = _toNullableInt(
            e['match_id'] ?? e['matchId'] ?? e['id'] ?? e['matchid'] ?? e['ID'],
          );

          items.add(
            _LiveMatchItem(
              leftTeamName: homeName.isEmpty ? '-' : homeName,
              rightTeamName: awayName.isEmpty ? '-' : awayName,
              league: league.isEmpty ? '-' : league,
              leftScore: homeScore,
              rightScore: awayScore,
              timeText: timeText,
              minuteText: minuteText.isEmpty ? '-' : minuteText,
              matchId: matchId,
              leftTeamLogoUrl: homeLogo.isEmpty ? null : homeLogo,
              rightTeamLogoUrl: awayLogo.isEmpty ? null : awayLogo,
            ),
          );
        }
      }

      if (!mounted || requestId != _requestSeq) return;
      setState(() {
        _page = page;
        _hasMore = items.length == 20;
        _items = reset ? items : [..._items, ...items];
      });
    } catch (_) {
      if (!mounted || requestId != _requestSeq) return;
      setState(() {
        if (reset) {
          _errorText = '加载失败';
        } else {
          _moreErrorText = '加载失败';
        }
      });
    } finally {
      if (!mounted || requestId != _requestSeq) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _refresh() => _fetch(reset: true);

  @override
  Widget build(BuildContext context) {
    final title =
        _isFootball ? 'Football - Live Matches' : 'Basketball - Live Matches';
    final icon = _isFootball
        ? Icons.sports_soccer_rounded
        : Icons.sports_basketball_rounded;

    return Scaffold(
      body: Stack(
        children: [
          const _MatchesBackground(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Row(
                    children: [
                      _BackIconButton(
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        onPressed: _refresh,
                        icon: const Icon(
                          Icons.refresh_rounded,
                          color: Color(0xFF00E676),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _refresh,
                    child: _loading && _items.isEmpty
                        ? ListView(
                            children: [
                              const SizedBox(height: 200),
                              const Center(child: CircularProgressIndicator()),
                            ],
                          )
                        : (_errorText != null && _items.isEmpty)
                            ? ListView(
                                children: [
                                  const SizedBox(height: 180),
                                  Center(
                                    child: Text(
                                      _errorText!,
                                      style: TextStyle(
                                        color:
                                            Colors.white.withValues(alpha: 0.7),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Center(
                                    child: SizedBox(
                                      height: 34,
                                      child: ElevatedButton(
                                        onPressed: _refresh,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              Colors.white.withValues(
                                            alpha: 0.10,
                                          ),
                                          foregroundColor:
                                              Colors.white.withValues(
                                            alpha: 0.9,
                                          ),
                                          elevation: 0,
                                          shape: const StadiumBorder(),
                                          textStyle: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        child: const Text('重试'),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : ListView.separated(
                                controller: _scrollController,
                                padding:
                                    const EdgeInsets.fromLTRB(16, 4, 16, 24),
                                itemCount: _items.length + (_hasMore ? 1 : 0),
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 14),
                                itemBuilder: (context, i) {
                                  if (i >= _items.length) {
                                    if (_loadingMore) {
                                      return const SizedBox(
                                        height: 70,
                                        child: Center(
                                          child: CircularProgressIndicator(),
                                        ),
                                      );
                                    }
                                    if (_moreErrorText != null) {
                                      return SizedBox(
                                        height: 70,
                                        child: Center(
                                          child: TextButton(
                                            onPressed: () =>
                                                _fetch(reset: false),
                                            style: TextButton.styleFrom(
                                              foregroundColor: const Color(
                                                0xFF00E676,
                                              ),
                                            ),
                                            child: const Text('加载失败，点击重试'),
                                          ),
                                        ),
                                      );
                                    }
                                    return const SizedBox(height: 70);
                                  }

                                  final m = _items[i];
                                  return _LiveMatchCard(
                                    width: double.infinity,
                                    height: 160,
                                    background:
                                        _LiveMatchCardBackground.gradient,
                                    sportIcon: icon,
                                    onTap: m.matchId == null
                                        ? null
                                        : () => Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) => _isFootball
                                                    ? MatchDetailsPage(
                                                        matchId: m.matchId,
                                                        initialHomeTeamName:
                                                            m.leftTeamName,
                                                        initialAwayTeamName:
                                                            m.rightTeamName,
                                                        initialHomeTeamLogoUrl:
                                                            m.leftTeamLogoUrl,
                                                        initialAwayTeamLogoUrl:
                                                            m.rightTeamLogoUrl,
                                                        initialCompetitionName:
                                                            m.league,
                                                        initialHomeScore:
                                                            m.leftScore,
                                                        initialAwayScore:
                                                            m.rightScore,
                                                      )
                                                    : BasketballMatchDetailsPage(
                                                        matchId: m.matchId,
                                                        initialHomeTeamName:
                                                            m.leftTeamName,
                                                        initialAwayTeamName:
                                                            m.rightTeamName,
                                                        initialHomeTeamLogoUrl:
                                                            m.leftTeamLogoUrl,
                                                        initialAwayTeamLogoUrl:
                                                            m.rightTeamLogoUrl,
                                                        initialCompetitionName:
                                                            m.league,
                                                        initialHomeScore:
                                                            m.leftScore,
                                                        initialAwayScore:
                                                            m.rightScore,
                                                        initialTimeText:
                                                            m.timeText,
                                                        initialPeriodText:
                                                            m.minuteText,
                                                      ),
                                              ),
                                            ),
                                    leftTeamName: m.leftTeamName,
                                    rightTeamName: m.rightTeamName,
                                    league: m.league,
                                    leftScore: m.leftScore,
                                    rightScore: m.rightScore,
                                    time: m.timeText,
                                    minute: m.minuteText,
                                    leftTeamLogoUrl: m.leftTeamLogoUrl,
                                    rightTeamLogoUrl: m.rightTeamLogoUrl,
                                  );
                                },
                              ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
