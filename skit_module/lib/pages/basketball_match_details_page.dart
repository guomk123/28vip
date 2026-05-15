import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'match_stat_details_page.dart';
import 'favorite_manager.dart';
import 'login_page.dart';

class BasketballMatchDetailsPage extends StatefulWidget {
  const BasketballMatchDetailsPage({
    super.key,
    this.matchId,
    this.initialHomeTeamName,
    this.initialAwayTeamName,
    this.initialHomeTeamLogoUrl,
    this.initialAwayTeamLogoUrl,
    this.initialCompetitionName,
    this.initialHomeScore,
    this.initialAwayScore,
    this.initialTimeText,
    this.initialPeriodText,
  });

  final int? matchId;
  final String? initialHomeTeamName;
  final String? initialAwayTeamName;
  final String? initialHomeTeamLogoUrl;
  final String? initialAwayTeamLogoUrl;
  final String? initialCompetitionName;
  final int? initialHomeScore;
  final int? initialAwayScore;
  final String? initialTimeText;
  final String? initialPeriodText;

  @override
  State<BasketballMatchDetailsPage> createState() =>
      _BasketballMatchDetailsPageState();
}

class _BasketballMatchDetailsPageState
    extends State<BasketballMatchDetailsPage> {
  static const _matchDetailEndpoint =
      'https://api.z8vips.com/api/v1/basketball/match/detail';
  static const _matchProcessEndpoint =
      'https://api.z8vips.com/api/v1/basketball/match/process';

  bool _loading = false;
  String? _errorText;
  _BasketballMatchDetail? _detail;
  int _requestSeq = 0;

  bool _processLoading = false;
  String? _processErrorText;
  _BasketballMatchProcess? _process;
  int _processRequestSeq = 0;

  bool _isFavorite = false;

  @override
  void initState() {
    super.initState();
    _checkFavoriteStatus();
    if (widget.matchId != null) {
      _fetchDetail();
      _fetchProcess();
    }
  }

  Future<void> _checkFavoriteStatus() async {
    if (widget.matchId == null) return;
    final fav = await FavoriteManager.isFavorite(
        widget.matchId!, FavoriteType.basketball);
    if (mounted) setState(() => _isFavorite = fav);
  }

  Future<void> _toggleFavorite() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('is_logged_in') ?? false;

    if (!isLoggedIn) {
      if (!mounted) return;
      final result = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const LoginPage(fromProfile: true)),
      );
      if (result != true) return;
    }

    if (widget.matchId == null) return;

    final item = FavoriteItem(
      matchId: widget.matchId!,
      type: FavoriteType.basketball,
      homeTeamName: _detail?.homeTeamName ?? widget.initialHomeTeamName ?? '-',
      awayTeamName: _detail?.awayTeamName ?? widget.initialAwayTeamName ?? '-',
      homeTeamLogoUrl:
          _detail?.homeTeamLogoUrl ?? widget.initialHomeTeamLogoUrl,
      awayTeamLogoUrl:
          _detail?.awayTeamLogoUrl ?? widget.initialAwayTeamLogoUrl,
      competitionName:
          _detail?.competitionName ?? widget.initialCompetitionName,
      homeScore: _detail?.homeScore ?? widget.initialHomeScore,
      awayScore: _detail?.awayScore ?? widget.initialAwayScore,
      timeText: widget.initialTimeText,
      periodText: widget.initialPeriodText,
    );

    await FavoriteManager.toggleFavorite(item);
    await _checkFavoriteStatus();
  }

  String? _sanitizeUrl(Object? v) {
    if (v == null) return null;
    final s = v.toString().replaceAll('`', '').trim();
    if (s.isEmpty || s == 'null') return null;
    if (s.startsWith('//')) return 'https:$s';
    if (s.startsWith('http://'))
      return 'https://${s.substring('http://'.length)}';
    return s;
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

  String _truncateLogText(String text, {int maxChars = 20000}) {
    final t = text.trim();
    if (t.length <= maxChars) return t;
    return '${t.substring(0, maxChars)}...(truncated ${t.length - maxChars} chars)';
  }

  void _printHttpResponse(String prefix, http.Response response) {
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    debugPrint('$prefix status: ${response.statusCode}');
    debugPrint('$prefix length: ${text.length}');
    debugPrint('$prefix body: ${_truncateLogText(text)}');
  }

  int? _toNullableInt(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.round();
    return int.tryParse(v.toString());
  }

  String _pickText(Map data, List<String> keys) {
    for (final k in keys) {
      final v = data[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty && s != 'null') return s;
    }
    return '';
  }

  Future<void> _fetchDetail() async {
    final matchId = widget.matchId;
    if (matchId == null) return;

    final requestId = ++_requestSeq;
    setState(() {
      _loading = true;
      _errorText = null;
    });

    try {
      final uri = Uri.parse(
        _matchDetailEndpoint,
      ).replace(queryParameters: {'match_id': '$matchId'});
      debugPrint('[basketball][detail] GET $uri');
      final response = await http.get(uri);
      _printHttpResponse('[basketball][detail]', response);
      if (response.statusCode != 200) {
        throw Exception('http ${response.statusCode}');
      }
      final decoded = _tryDecodeJson(response.bodyBytes);
      if (decoded is! Map) throw Exception('invalid json');
      final Object? code = decoded['code'];
      if (code != null && code != 0) throw Exception('invalid response');
      final Object? rawData = decoded['data'];
      final Map data = rawData is Map ? rawData : decoded;
      final detail = _BasketballMatchDetail.fromJson(
        data,
        toNullableInt: _toNullableInt,
        pickText: _pickText,
        sanitizeUrl: _sanitizeUrl,
      );

      if (!mounted || requestId != _requestSeq) return;
      setState(() {
        _detail = detail;
      });
    } catch (_) {
      if (!mounted || requestId != _requestSeq) return;
      setState(() {
        _errorText = '详情加载失败';
      });
    } finally {
      if (mounted && requestId == _requestSeq) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _fetchProcess() async {
    final matchId = widget.matchId;
    if (matchId == null) return;

    final requestId = ++_processRequestSeq;
    setState(() {
      _processLoading = true;
      _processErrorText = null;
    });

    try {
      final uri = Uri.parse(
        _matchProcessEndpoint,
      ).replace(queryParameters: {'match_id': '$matchId'});
      debugPrint('[basketball][process] GET $uri');
      final response = await http.get(uri);
      _printHttpResponse('[basketball][process]', response);
      if (response.statusCode != 200) {
        throw Exception('http ${response.statusCode}');
      }
      final decoded = _tryDecodeJson(response.bodyBytes);
      if (decoded is! Map) throw Exception('invalid json');
      final Object? code = decoded['code'];
      if (code != null && code != 0) throw Exception('invalid response');
      final Object? rawData = decoded['data'];
      final Map data = rawData is Map ? rawData : decoded;
      final process = _BasketballMatchProcess.fromJson(
        data,
        toNullableInt: _toNullableInt,
        pickText: _pickText,
      );

      if (!mounted || requestId != _processRequestSeq) return;
      setState(() {
        _process = process;
      });
    } catch (_) {
      if (!mounted || requestId != _processRequestSeq) return;
      setState(() {
        _processErrorText = '实时数据加载失败';
      });
    } finally {
      if (mounted && requestId == _processRequestSeq) {
        setState(() {
          _processLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final process = _process;

    final homeName = (detail?.homeTeamName ?? widget.initialHomeTeamName ?? '-')
            .trim()
            .isEmpty
        ? '-'
        : (detail?.homeTeamName ?? widget.initialHomeTeamName ?? '-');
    final awayName = (detail?.awayTeamName ?? widget.initialAwayTeamName ?? '-')
            .trim()
            .isEmpty
        ? '-'
        : (detail?.awayTeamName ?? widget.initialAwayTeamName ?? '-');
    final homeLogoUrl =
        detail?.homeTeamLogoUrl ?? widget.initialHomeTeamLogoUrl;
    final awayLogoUrl =
        detail?.awayTeamLogoUrl ?? widget.initialAwayTeamLogoUrl;
    final homeScore = detail?.homeScore ?? widget.initialHomeScore ?? 0;
    final awayScore = detail?.awayScore ?? widget.initialAwayScore ?? 0;
    final league =
        detail?.competitionName ?? widget.initialCompetitionName ?? '-';
    final timeText = detail?.matchTimeText ?? widget.initialTimeText ?? '';
    final periodText = detail?.periodText ?? widget.initialPeriodText ?? '';
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final matchTimeSeconds = detail?.matchTime;
    final isFuture =
        matchTimeSeconds != null && matchTimeSeconds > nowSeconds + 60;
    final periodLower = periodText.toLowerCase();
    final notStarted = periodLower.contains('not started') ||
        periodLower == 'ns' ||
        periodLower.contains('pending') ||
        periodLower.contains('未');
    final showVs = (homeScore == 0 && awayScore == 0) &&
        ((detail == null &&
                widget.initialHomeScore == null &&
                widget.initialAwayScore == null) ||
            (isFuture || notStarted));

    return Scaffold(
      body: Stack(
        children: [
          const _BasketballDetailsBackground(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                  child: Row(
                    children: [
                      _BackIconButton(
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                      const Spacer(),
                      if (timeText.trim().isNotEmpty)
                        Text(
                          timeText,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.55),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      if (timeText.trim().isNotEmpty) const SizedBox(width: 10),
                      if (periodText.trim().isNotEmpty)
                        Text(
                          periodText,
                          style: const TextStyle(
                            color: Color(0xFF00E676),
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      const Spacer(),
                      IconButton(
                        onPressed: _toggleFavorite,
                        icon: Icon(
                          _isFavorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: _isFavorite
                              ? const Color(0xFF00E676)
                              : Colors.white.withOpacity(0.55),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _ScoreHeader(
                    leftName: homeName,
                    rightName: awayName,
                    leftLogoUrl: homeLogoUrl,
                    rightLogoUrl: awayLogoUrl,
                    leftScore: homeScore,
                    rightScore: awayScore,
                    showVs: showVs,
                    league: league,
                  ),
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      if (_errorText != null && _detail == null) ...[
                        SizedBox(
                          height: 120,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _errorText!,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.75),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  height: 34,
                                  child: ElevatedButton(
                                    onPressed: _fetchDetail,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          Colors.white.withOpacity(0.10),
                                      foregroundColor:
                                          Colors.white.withOpacity(0.9),
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
                          ),
                        ),
                        const SizedBox(height: 14),
                      ] else if (_loading && _detail == null) ...[
                        const SizedBox(
                          height: 120,
                          child: Center(child: CircularProgressIndicator()),
                        ),
                        const SizedBox(height: 14),
                      ],
                      const _SectionHeader(title: 'Real time'),
                      const SizedBox(height: 10),
                      _TrendChart(
                        leftLogoUrl: homeLogoUrl,
                        rightLogoUrl: awayLogoUrl,
                        points: process?.trendPoints,
                        trendCount: process?.trendCount,
                        trendPer: process?.trendPer,
                        isFinished: periodLower.contains('ft') ||
                            periodLower.contains('finish') ||
                            periodLower.contains('final') ||
                            periodLower.contains('ended'),
                      ),
                      const SizedBox(height: 14),
                      if (_processErrorText != null && process == null) ...[
                        SizedBox(
                          height: 110,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _processErrorText!,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.75),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  height: 34,
                                  child: ElevatedButton(
                                    onPressed: _fetchProcess,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          Colors.white.withOpacity(0.10),
                                      foregroundColor:
                                          Colors.white.withOpacity(0.9),
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
                          ),
                        ),
                        const SizedBox(height: 14),
                      ] else if (_processLoading && process == null) ...[
                        const SizedBox(
                          height: 110,
                          child: Center(child: CircularProgressIndicator()),
                        ),
                        const SizedBox(height: 14),
                      ],
                      _BasketballStatsCard(
                        leftScore: homeScore,
                        rightScore: awayScore,
                        leftLogoUrl: homeLogoUrl,
                        rightLogoUrl: awayLogoUrl,
                        stats: process?.stats,
                      ),
                    ],
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

class _BasketballMatchDetail {
  const _BasketballMatchDetail({
    required this.matchId,
    required this.competitionName,
    required this.homeTeamName,
    required this.awayTeamName,
    required this.homeTeamLogoUrl,
    required this.awayTeamLogoUrl,
    required this.homeScore,
    required this.awayScore,
    required this.matchTime,
    required this.periodText,
  });

  final int matchId;
  final String competitionName;
  final String homeTeamName;
  final String awayTeamName;
  final String? homeTeamLogoUrl;
  final String? awayTeamLogoUrl;
  final int homeScore;
  final int awayScore;
  final int? matchTime;
  final String? periodText;

  String get matchTimeText {
    final seconds = matchTime;
    if (seconds == null || seconds <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(seconds * 1000).toLocal();
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$m/$d $hh:$mm';
  }

  factory _BasketballMatchDetail.fromJson(
    Map data, {
    required int? Function(Object?) toNullableInt,
    required String Function(Map, List<String>) pickText,
    required String? Function(Object?) sanitizeUrl,
  }) {
    int sumScoresCsv(Object? v) {
      final raw = (v ?? '').toString().replaceAll('`', '').trim();
      if (raw.isEmpty) return 0;
      final parts = raw.split(',');
      int sum = 0;
      for (final p in parts) {
        final n = int.tryParse(p.trim());
        if (n != null) sum += n;
      }
      return sum;
    }

    final matchId =
        toNullableInt(data['match_id'] ?? data['matchId'] ?? data['id']) ?? 0;
    final homeScoresCsv = (data['home_scores'] ?? '').toString().trim();
    final awayScoresCsv = (data['away_scores'] ?? '').toString().trim();
    final homeScore = homeScoresCsv.isNotEmpty
        ? sumScoresCsv(homeScoresCsv)
        : (toNullableInt(data['home_score'] ?? data['home_total_score']) ??
            toNullableInt(data['home_normal_score']) ??
            0);
    final awayScore = awayScoresCsv.isNotEmpty
        ? sumScoresCsv(awayScoresCsv)
        : (toNullableInt(data['away_score'] ?? data['away_total_score']) ??
            toNullableInt(data['away_normal_score']) ??
            0);

    return _BasketballMatchDetail(
      matchId: matchId,
      competitionName: pickText(data, [
        'competition_name_en',
        'league_name_en',
        'competition_name',
        'league_name',
      ]),
      homeTeamName: pickText(data, [
        'home_team_name_en',
        'home_team_short_name_en',
        'home_team_name',
        'home_team_short_name',
        'home_team',
      ]),
      awayTeamName: pickText(data, [
        'away_team_name_en',
        'away_team_short_name_en',
        'away_team_name',
        'away_team_short_name',
        'away_team',
      ]),
      homeTeamLogoUrl: sanitizeUrl(data['home_team_logo']),
      awayTeamLogoUrl: sanitizeUrl(data['away_team_logo']),
      homeScore: homeScore,
      awayScore: awayScore,
      matchTime: toNullableInt(data['match_time'] ?? data['start_time']),
      periodText: pickText(data, [
        'status_name',
        'period_name',
        'stage_name',
        'minutes',
      ]).trim().isEmpty
          ? null
          : pickText(data, [
              'status_name',
              'period_name',
              'stage_name',
              'minutes',
            ]),
    );
  }
}

class _BasketballMatchProcess {
  const _BasketballMatchProcess({
    required this.stats,
    required this.trendPoints,
    required this.trendCount,
    required this.trendPer,
  });

  final List<_StatItem> stats;
  final List<double>? trendPoints;
  final int? trendCount;
  final int? trendPer;

  factory _BasketballMatchProcess.fromJson(
    Map data, {
    required int? Function(Object?) toNullableInt,
    required String Function(Map, List<String>) pickText,
  }) {
    double? toNullableDouble(Object? v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    List<_StatItem> parseStats(Object? v) {
      if (v is! List) return const [];
      final out = <_StatItem>[];
      for (final e in v) {
        if (e is! Map) continue;
        out.add(
          _StatItem(
            name: pickText(e, ['name_en', 'name', 'title']),
            home:
                toNullableInt(e['home']) ?? toNullableInt(e['home_value']) ?? 0,
            away:
                toNullableInt(e['away']) ?? toNullableInt(e['away_value']) ?? 0,
            isPercent: (pickText(e, ['name_en', 'name']).contains('%') ||
                toNullableInt(e['is_percent']) == 1),
          ),
        );
      }
      return out;
    }

    List<double>? parseTrend(Object? v) {
      Object? unwrapMap(Map m) {
        return m['data'] ??
            m['points'] ??
            m['trend'] ??
            m['list'] ??
            m['items'] ??
            m['values'];
      }

      double? extractPoint(Object? e) {
        if (e == null) return null;
        if (e is num) return e.toDouble();
        if (e is String) return double.tryParse(e.trim());
        if (e is Map) {
          double? readAny(List<String> keys) {
            for (final k in keys) {
              final d = toNullableDouble(e[k]);
              if (d != null) return d;
            }
            return null;
          }

          final direct = readAny([
            'value',
            'v',
            'y',
            'point',
            'points',
            'trend',
            'score',
            'diff',
          ]);
          if (direct != null) return direct;

          final home = readAny([
            'home',
            'home_value',
            'homeScore',
            'home_score',
            'h',
          ]);
          final away = readAny([
            'away',
            'away_value',
            'awayScore',
            'away_score',
            'a',
          ]);
          if (home != null && away != null) return home - away;
          return home ?? away;
        }
        return null;
      }

      final pts = <double>[];

      void collect(Object? node) {
        if (node == null) return;
        if (node is num) {
          pts.add(node.toDouble());
          return;
        }
        if (node is String) {
          final raw = node.trim();
          if (raw.isEmpty) return;
          if (raw.startsWith('[') && raw.endsWith(']')) {
            try {
              collect(jsonDecode(raw));
              return;
            } catch (_) {}
          }
          if (raw.contains(',')) {
            for (final part in raw.split(',')) {
              final d = double.tryParse(part.trim());
              if (d != null) pts.add(d);
            }
            return;
          }
          final d = double.tryParse(raw);
          if (d != null) pts.add(d);
          return;
        }
        if (node is List) {
          for (final item in node) {
            collect(item);
          }
          return;
        }
        if (node is Map) {
          final inner = unwrapMap(node);
          if (inner != null && !identical(inner, node)) {
            collect(inner);
            return;
          }
          final d = extractPoint(node);
          if (d != null) pts.add(d);
        }
      }

      if (v is Map) {
        final count = toNullableInt(v['count']);
        if (count != null && count <= 0) return null;
      }

      collect(v);
      return pts.isEmpty ? null : pts;
    }

    final stats = parseStats(data['stats']);
    Object? findTrendPayload(Map root) {
      final direct = root['trend'] ??
          root['Trend'] ??
          root['trend_points'] ??
          root['trendPoints'];
      if (direct != null) return direct;

      final modules = root['modules'] ?? root['module'];
      if (modules is Map) {
        final m = modules['trend'] ?? modules['Trend'];
        if (m != null) return m;
      }

      final inner = root['data'];
      if (inner is Map) {
        final d = inner['trend'] ??
            inner['Trend'] ??
            inner['trend_points'] ??
            inner['trendPoints'];
        if (d != null) return d;
        final innerModules = inner['modules'] ?? inner['module'];
        if (innerModules is Map) {
          final m = innerModules['trend'] ?? innerModules['Trend'];
          if (m != null) return m;
        }
      }

      return null;
    }

    final trendPayload = findTrendPayload(data);
    final points = parseTrend(trendPayload);

    int? trendCount;
    int? trendPer;
    if (trendPayload is Map) {
      trendCount = toNullableInt(trendPayload['count']);
      trendPer = toNullableInt(trendPayload['per']);
    }

    return _BasketballMatchProcess(
      stats: stats,
      trendPoints: points,
      trendCount: trendCount,
      trendPer: trendPer,
    );
  }
}

class _StatItem {
  const _StatItem({
    required this.name,
    required this.home,
    required this.away,
    required this.isPercent,
  });

  final String name;
  final int home;
  final int away;
  final bool isPercent;
}

class _BasketballDetailsBackground extends StatelessWidget {
  const _BasketballDetailsBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0E3B2E), Color(0xFF08201B), Color(0xFF061815)],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.35, -0.35),
                  radius: 1.2,
                  colors: [
                    const Color(0xFF00E676).withOpacity(0.20),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
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

class _ScoreHeader extends StatelessWidget {
  const _ScoreHeader({
    required this.leftName,
    required this.rightName,
    required this.leftLogoUrl,
    required this.rightLogoUrl,
    required this.leftScore,
    required this.rightScore,
    required this.showVs,
    required this.league,
  });

  final String leftName;
  final String rightName;
  final String? leftLogoUrl;
  final String? rightLogoUrl;
  final int leftScore;
  final int rightScore;
  final bool showVs;
  final String league;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  _TeamBadge(seed: 1, logoUrl: leftLogoUrl),
                  const SizedBox(height: 10),
                  Text(
                    leftName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  SizedBox(
                    height: 38,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.center,
                      child: Text(
                        showVs ? 'VS' : '$leftScore - $rightScore',
                        maxLines: 1,
                        softWrap: false,
                        style: const TextStyle(
                          color: Color(0xFF00E676),
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  _TeamBadge(seed: 2, logoUrl: rightLogoUrl),
                  const SizedBox(height: 10),
                  Text(
                    rightName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          league,
          style: TextStyle(
            color: Colors.white.withOpacity(0.45),
            fontSize: 13,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

class _TeamBadge extends StatelessWidget {
  const _TeamBadge({required this.seed, required this.logoUrl});

  final int seed;
  final String? logoUrl;

  @override
  Widget build(BuildContext context) {
    final colors = [
      const Color(0xFF42A5F5),
      const Color(0xFFEF5350),
      const Color(0xFF7E57C2),
      const Color(0xFF26A69A),
    ];
    final c = colors[seed % colors.length];
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      clipBehavior: Clip.antiAlias,
      child: (logoUrl ?? '').trim().isEmpty
          ? Center(
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle),
              ),
            )
          : Center(
              child: SizedBox(
                width: 46,
                height: 46,
                child: ClipOval(
                  child: Image.network(
                    logoUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Center(
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: 52,
          height: 2,
          decoration: BoxDecoration(
            color: const Color(0xFF00E676),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({
    required this.leftLogoUrl,
    required this.rightLogoUrl,
    required this.points,
    required this.trendCount,
    required this.trendPer,
    required this.isFinished,
  });

  final String? leftLogoUrl;
  final String? rightLogoUrl;
  final List<double>? points;
  final int? trendCount;
  final int? trendPer;
  final bool isFinished;

  @override
  Widget build(BuildContext context) {
    final per = (trendPer != null && trendPer! > 0) ? trendPer! : 10;
    final lineNums =
        (trendCount != null && trendCount! > 0) ? trendCount! + 1 : 5;
    final totalCount = (trendCount != null && trendCount! > 0)
        ? (trendCount! * per).toDouble()
        : 40.0;

    final data = points ?? const <double>[];
    var maxHeight = 0;
    for (final v in data) {
      maxHeight = math.max(maxHeight, v.abs().round());
    }
    final showCurrent = data.isNotEmpty && !isFinished;
    final currentText = "${data.length}'";

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.black.withOpacity(0.14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(
        children: [
          SizedBox(
            height: 80,
            child: Row(
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _TinyLogo(logoUrl: leftLogoUrl, seed: 1),
                    _TinyLogo(logoUrl: rightLogoUrl, seed: 2),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final w = constraints.maxWidth;
                      final currentX =
                          (w / totalCount * data.length).clamp(0.0, w);
                      const labelHeight = 16.0;
                      return Stack(
                        children: [
                          Positioned.fill(
                            top: labelHeight,
                            child: CustomPaint(
                              painter: _TrendPainter(
                                points: data.isEmpty ? null : data,
                                totalCount: totalCount,
                                showMarker: showCurrent,
                              ),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            top: labelHeight,
                            bottom: 0,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _AxisLabel(
                                    text: '${maxHeight > 0 ? maxHeight : 0}'),
                                _AxisLabel(text: '0'),
                                _AxisLabel(
                                    text: '${maxHeight > 0 ? maxHeight : 0}'),
                              ],
                            ),
                          ),
                          Positioned.fill(
                            top: labelHeight,
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: _TrendGridPainter(
                                  totalCount: totalCount,
                                  per: per,
                                  lineNums: lineNums,
                                ),
                              ),
                            ),
                          ),
                          if (showCurrent)
                            Positioned(
                              left: (currentX - 14).clamp(0.0, w - 28),
                              top: 0,
                              child: Text(
                                currentText,
                                style: TextStyle(
                                  color:
                                      const Color(0xFF00E676).withOpacity(0.9),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              return SizedBox(
                height: 14,
                child: Stack(
                  children: [
                    for (int i = 0; i < lineNums; i++)
                      Positioned(
                        left: (w / totalCount * (i * per)).clamp(0.0, w),
                        bottom: 0,
                        child: Transform.translate(
                          offset: const Offset(-10, 0),
                          child: _AxisBottomLabel(
                            text: i == lineNums - 1 ? 'FT' : "${i * per}'",
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AxisLabel extends StatelessWidget {
  const _AxisLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      child: Text(
        text,
        textAlign: TextAlign.right,
        style: TextStyle(
          color: Colors.white.withOpacity(0.45),
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _AxisBottomLabel extends StatelessWidget {
  const _AxisBottomLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.white.withOpacity(0.45),
        fontSize: 10,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _TinyLogo extends StatelessWidget {
  const _TinyLogo({required this.logoUrl, required this.seed});

  final String? logoUrl;
  final int seed;

  @override
  Widget build(BuildContext context) {
    final colors = [
      const Color(0xFF42A5F5),
      const Color(0xFFEF5350),
      const Color(0xFF7E57C2),
      const Color(0xFF26A69A),
    ];
    final c = colors[seed % colors.length];
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      clipBehavior: Clip.antiAlias,
      child: (logoUrl ?? '').trim().isEmpty
          ? Center(
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle),
              ),
            )
          : Image.network(
              logoUrl!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Center(
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                ),
              ),
            ),
    );
  }
}

class _TrendGridPainter extends CustomPainter {
  const _TrendGridPainter({
    required this.totalCount,
    required this.per,
    required this.lineNums,
  });

  final double totalCount;
  final int per;
  final int lineNums;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..strokeWidth = 1;

    final h = size.height;
    for (int i = 0; i < lineNums; i++) {
      final x = (size.width / totalCount) * (i * per);
      canvas.drawLine(Offset(x, 0), Offset(x, h), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TrendGridPainter oldDelegate) {
    return oldDelegate.totalCount != totalCount ||
        oldDelegate.per != per ||
        oldDelegate.lineNums != lineNums;
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.points,
    required this.totalCount,
    required this.showMarker,
  });

  final List<double>? points;
  final double totalCount;
  final bool showMarker;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    final basePaint = Paint()
      ..color = Colors.white.withOpacity(0.12)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, rect.center.dy),
      Offset(rect.right, rect.center.dy),
      basePaint,
    );

    final list = points;
    if (list == null || list.length < 2) {
      final band = Rect.fromLTRB(
        rect.left,
        rect.center.dy - rect.height * 0.06,
        rect.right,
        rect.center.dy + rect.height * 0.06,
      );
      final fill = Paint()
        ..color = Colors.white.withOpacity(0.10)
        ..style = PaintingStyle.fill;
      canvas.drawRect(band, fill);
      return;
    }

    double maxAbs = 1;
    for (final v in list) {
      maxAbs = math.max(maxAbs, v.abs());
    }

    final currentX = (rect.width / totalCount * list.length).clamp(
      rect.left,
      rect.right,
    );

    final upFill = Paint()
      ..color = const Color(0xFF00E676).withOpacity(0.85)
      ..style = PaintingStyle.fill;
    final downFill = Paint()
      ..color = Colors.white.withOpacity(0.45)
      ..style = PaintingStyle.fill;

    int sideOf(double y) {
      if (y < rect.center.dy) return 1;
      if (y > rect.center.dy) return -1;
      return 0;
    }

    final line = Path()..moveTo(rect.left, rect.center.dy);
    Path? fillPath;
    int fillSide = 0;
    double prevX = rect.left;
    double prevY = rect.center.dy;

    void flushFill() {
      final p = fillPath;
      if (p == null) return;
      if (fillSide == 1) {
        canvas.drawPath(p, upFill);
      } else if (fillSide == -1) {
        canvas.drawPath(p, downFill);
      }
      fillPath = null;
    }

    for (int i = 0; i < list.length; i++) {
      final x = (rect.left + (rect.width / totalCount) * (i + 1)).clamp(
        rect.left,
        rect.right,
      );
      final value = -list[i];
      final y = rect.center.dy - (value / maxAbs) * (rect.height * 0.40);

      line.lineTo(x, y);

      int segSide = sideOf(y);
      if (segSide == 0) segSide = fillSide == 0 ? 1 : fillSide;
      if (fillPath == null) {
        fillSide = segSide;
        fillPath = Path()
          ..moveTo(prevX, rect.center.dy)
          ..lineTo(x, y);
      } else if (segSide == fillSide) {
        fillPath!.lineTo(x, y);
      } else {
        final denom = (y - prevY);
        final t = denom == 0 ? 0.0 : ((rect.center.dy - prevY) / denom);
        final xi = (prevX + (x - prevX) * t).clamp(rect.left, rect.right);
        fillPath!
          ..lineTo(xi, rect.center.dy)
          ..close();
        flushFill();
        fillSide = segSide;
        fillPath = Path()
          ..moveTo(xi, rect.center.dy)
          ..lineTo(x, y);
      }

      prevX = x;
      prevY = y;
    }

    if (fillPath != null) {
      fillPath!
        ..lineTo(currentX, rect.center.dy)
        ..close();
      flushFill();
    }

    if (showMarker) {
      final markerPaint = Paint()
        ..color = const Color(0xFF00E676)
        ..strokeWidth = 2;
      canvas.drawLine(
        Offset(currentX, 0),
        Offset(currentX, rect.bottom),
        markerPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.totalCount != totalCount ||
        oldDelegate.showMarker != showMarker;
  }
}

class _BasketballStatsCard extends StatelessWidget {
  const _BasketballStatsCard({
    required this.leftScore,
    required this.rightScore,
    required this.leftLogoUrl,
    required this.rightLogoUrl,
    required this.stats,
  });

  final int leftScore;
  final int rightScore;
  final String? leftLogoUrl;
  final String? rightLogoUrl;
  final List<_StatItem>? stats;

  List<_StatItem> _fallbackStats() {
    return const [
      _StatItem(name: '3-PT made', home: 0, away: 0, isPercent: false),
      _StatItem(name: '2-PT made', home: 0, away: 0, isPercent: false),
      _StatItem(name: 'FT made', home: 0, away: 0, isPercent: false),
      _StatItem(name: 'Timeouts left', home: 0, away: 0, isPercent: false),
      _StatItem(name: 'Fouls', home: 0, away: 0, isPercent: false),
      _StatItem(name: 'FT%', home: 0, away: 0, isPercent: true),
      _StatItem(name: 'Total timeouts', home: 0, away: 0, isPercent: false),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final list = (stats == null || stats!.isEmpty) ? _fallbackStats() : stats!;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withOpacity(0.08),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 18,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          children: [
            _StatsHeader(
              leftScore: leftScore,
              rightScore: rightScore,
              leftLogoUrl: leftLogoUrl,
              rightLogoUrl: rightLogoUrl,
            ),
            const SizedBox(height: 12),
            for (int i = 0; i < list.length; i++) ...[
              _StatRow(
                label: list[i].name.isEmpty ? '-' : list[i].name,
                left: list[i].home,
                right: list[i].away,
                isPercent: list[i].isPercent,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MatchStatDetailsPage(
                      title: list[i].name.isEmpty ? '-' : list[i].name,
                      leftValue: list[i].home,
                      rightValue: list[i].away,
                      isPercent: list[i].isPercent,
                    ),
                  ),
                ),
              ),
              if (i != list.length - 1) const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatsHeader extends StatelessWidget {
  const _StatsHeader({
    required this.leftScore,
    required this.rightScore,
    required this.leftLogoUrl,
    required this.rightLogoUrl,
  });

  final int leftScore;
  final int rightScore;
  final String? leftLogoUrl;
  final String? rightLogoUrl;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '$leftScore',
          style: TextStyle(
            color: Colors.white.withOpacity(0.95),
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(width: 10),
        const Spacer(),
        _MiniTeamBadge(seed: 1, logoUrl: leftLogoUrl),
        const SizedBox(width: 6),
        Expanded(
          flex: 2,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: Text(
              'Live Score',
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                color: Colors.white.withOpacity(0.95),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        _MiniTeamBadge(seed: 2, logoUrl: rightLogoUrl),
        const Spacer(),
        const SizedBox(width: 10),
        Text(
          '$rightScore',
          style: TextStyle(
            color: Colors.white.withOpacity(0.95),
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _MiniTeamBadge extends StatelessWidget {
  const _MiniTeamBadge({required this.seed, required this.logoUrl});

  final int seed;
  final String? logoUrl;

  @override
  Widget build(BuildContext context) {
    final colors = [
      const Color(0xFF42A5F5),
      const Color(0xFFE53935),
      const Color(0xFF7E57C2),
      const Color(0xFF26A69A),
    ];
    final c = colors[seed % colors.length];
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      clipBehavior: Clip.antiAlias,
      child: (logoUrl ?? '').trim().isEmpty
          ? Center(
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle),
              ),
            )
          : Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: ClipOval(
                  child: Image.network(
                    logoUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Center(
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.label,
    required this.left,
    required this.right,
    required this.isPercent,
    required this.onTap,
  });

  final String label;
  final int left;
  final int right;
  final bool isPercent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final leftText = isPercent ? '$left%' : '$left';
    final rightText = isPercent ? '$right%' : '$right';

    final double leftFraction;
    final double rightFraction;
    if (isPercent) {
      leftFraction = (left / 100).clamp(0.0, 1.0);
      rightFraction = (right / 100).clamp(0.0, 1.0);
    } else {
      final maxValue = math.max(1, math.max(left, right));
      leftFraction = (left / maxValue).clamp(0.0, 1.0);
      rightFraction = (right / maxValue).clamp(0.0, 1.0);
    }

    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Row(
            children: [
              _ValuePill(
                text: leftText,
                bg: const Color(0xFF00E676).withOpacity(0.22),
                fg: const Color(0xFF00E676),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _ValuePill(
                text: rightText,
                bg: const Color(0xFFFFC107).withOpacity(0.20),
                fg: const Color(0xFFFFC107),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: _SplitProgressBar(
              leftFraction: leftFraction,
              rightFraction: rightFraction,
            ),
          ),
        ],
      ),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: content,
      ),
    );
  }
}

class _SplitProgressBar extends StatelessWidget {
  const _SplitProgressBar({
    required this.leftFraction,
    required this.rightFraction,
  });

  final double leftFraction;
  final double rightFraction;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(6);
    return SizedBox(
      height: 8,
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: radius,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      color: const Color(0xFF00E676).withOpacity(0.22),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: leftFraction,
                    alignment: Alignment.centerLeft,
                    child: Container(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: ClipRRect(
              borderRadius: radius,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      color: const Color(0xFFFFC107).withOpacity(0.20),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: rightFraction,
                    alignment: Alignment.centerRight,
                    child: Container(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ValuePill extends StatelessWidget {
  const _ValuePill({required this.text, required this.bg, required this.fg});

  final String text;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 28,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            color: fg,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
