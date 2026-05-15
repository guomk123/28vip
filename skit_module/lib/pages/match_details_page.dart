import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'league_details_page.dart';
import 'match_stat_details_page.dart';
import 'favorite_manager.dart';
import 'login_page.dart';

extension _ColorWithValuesCompat on Color {
  Color withValues({double? alpha}) {
    if (alpha == null) return this;
    final a = alpha.clamp(0.0, 1.0);
    return withOpacity(a);
  }
}

class MatchDetailsPage extends StatefulWidget {
  const MatchDetailsPage({
    super.key,
    this.matchId,
    this.initialHomeTeamName,
    this.initialAwayTeamName,
    this.initialHomeTeamLogoUrl,
    this.initialAwayTeamLogoUrl,
    this.initialCompetitionName,
    this.initialHomeScore,
    this.initialAwayScore,
  });

  final int? matchId;
  final String? initialHomeTeamName;
  final String? initialAwayTeamName;
  final String? initialHomeTeamLogoUrl;
  final String? initialAwayTeamLogoUrl;
  final String? initialCompetitionName;
  final int? initialHomeScore;
  final int? initialAwayScore;

  @override
  State<MatchDetailsPage> createState() => _MatchDetailsPageState();
}

class _MatchDetailsPageState extends State<MatchDetailsPage> {
  static const _matchDetailEndpoint =
      'https://api.z8vips.com/api/v1/football/match/detail';
  static const _matchProcessEndpoint =
      'https://api.z8vips.com/api/v1/football/match/process';
  static const _matchLineupEndpoint =
      'https://api.z8vips.com/api/v1/football/match/lineup';

  int _tabIndex = 0;
  bool _loading = false;
  String? _errorText;
  _MatchDetail? _detail;
  int _requestSeq = 0;

  bool _processLoading = false;
  String? _processErrorText;
  _MatchProcess? _process;
  int _processRequestSeq = 0;

  bool _lineupLoading = false;
  String? _lineupErrorText;
  _MatchLineup? _lineup;
  int _lineupRequestSeq = 0;

  bool _isFavorite = false;

  @override
  void initState() {
    super.initState();
    _checkFavoriteStatus();
    if (widget.matchId != null) {
      _fetchMatchDetail();
      _fetchMatchProcess();
      _fetchMatchLineup();
    }
  }

  Future<void> _checkFavoriteStatus() async {
    if (widget.matchId == null) return;
    final fav = await FavoriteManager.isFavorite(
        widget.matchId!, FavoriteType.football);
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
      type: FavoriteType.football,
      homeTeamName: _detail?.homeTeamName ?? widget.initialHomeTeamName ?? '-',
      awayTeamName: _detail?.awayTeamName ?? widget.initialAwayTeamName ?? '-',
      homeTeamLogoUrl:
          _detail?.homeTeamLogoUrl ?? widget.initialHomeTeamLogoUrl,
      awayTeamLogoUrl:
          _detail?.awayTeamLogoUrl ?? widget.initialAwayTeamLogoUrl,
      competitionName:
          _detail?.competitionName ?? widget.initialCompetitionName,
      homeScore: _detail?.homeNormalScore ?? widget.initialHomeScore,
      awayScore: _detail?.awayNormalScore ?? widget.initialAwayScore,
    );

    await FavoriteManager.toggleFavorite(item);
    await _checkFavoriteStatus();
  }

  Future<void> _fetchMatchDetail() async {
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
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('http ${response.statusCode}');
      }
      final decoded = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
      if (decoded is! Map) throw Exception('invalid json');
      if (decoded['code'] != 0) throw Exception('invalid response');
      final data = decoded['data'];
      if (data is! Map) throw Exception('invalid response');
      final detail = _MatchDetail.fromJson(data);

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

  Future<void> _fetchMatchProcess() async {
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
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('http ${response.statusCode}');
      }
      final decoded = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
      if (decoded is! Map) throw Exception('invalid json');
      if (decoded['code'] != 0) throw Exception('invalid response');
      final data = decoded['data'];
      if (data is! Map) throw Exception('invalid response');
      final process = _MatchProcess.fromJson(data);

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

  Future<void> _fetchMatchLineup() async {
    final matchId = widget.matchId;
    if (matchId == null) return;

    final requestId = ++_lineupRequestSeq;
    setState(() {
      _lineupLoading = true;
      _lineupErrorText = null;
    });

    try {
      final uri = Uri.parse(
        _matchLineupEndpoint,
      ).replace(queryParameters: {'match_id': '$matchId'});
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('http ${response.statusCode}');
      }
      final decoded = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
      if (decoded is! Map) throw Exception('invalid json');
      if (decoded['code'] != 0) throw Exception('invalid response');
      final data = decoded['data'];
      if (data is! Map) throw Exception('invalid response');
      final lineup = _MatchLineup.fromJson(data);

      if (!mounted || requestId != _lineupRequestSeq) return;
      setState(() {
        _lineup = lineup;
      });
    } catch (_) {
      if (!mounted || requestId != _lineupRequestSeq) return;
      setState(() {
        _lineupErrorText = '阵容加载失败';
      });
    } finally {
      if (mounted && requestId == _lineupRequestSeq) {
        setState(() {
          _lineupLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final process = _process;
    final homeName = detail?.homeTeamName ?? widget.initialHomeTeamName ?? '-';
    final awayName = detail?.awayTeamName ?? widget.initialAwayTeamName ?? '-';
    final homeLogoUrl =
        detail?.homeTeamLogoUrl ?? widget.initialHomeTeamLogoUrl;
    final awayLogoUrl =
        detail?.awayTeamLogoUrl ?? widget.initialAwayTeamLogoUrl;
    final homeScore = detail?.homeNormalScore ?? widget.initialHomeScore ?? 0;
    final awayScore = detail?.awayNormalScore ?? widget.initialAwayScore ?? 0;
    final league =
        detail?.competitionName ?? widget.initialCompetitionName ?? '-';
    final competitionId = detail?.competitionId;
    final homeTeamId = detail?.homeTeamId;
    final awayTeamId = detail?.awayTeamId;
    final timeText = detail?.matchTimeText ?? '—';
    final statusText = (detail?.minutes?.trim().isNotEmpty ?? false)
        ? detail!.minutes!.trim()
        : (detail?.statusName?.trim().isNotEmpty ?? false)
            ? detail!.statusName!.trim()
            : '';
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final statusLower = (detail?.statusName ?? '').toLowerCase();
    final notStarted = statusLower.contains('not started') ||
        statusLower == 'ns' ||
        statusLower.contains('pending') ||
        (detail?.statusName?.contains('未') ?? false);
    final isFuture = (detail?.matchTime ?? 0) > nowSeconds + 60;
    final minutesText = detail?.minutes?.trim() ?? '';
    final showVs = (homeScore == 0 && awayScore == 0) &&
        ((detail == null &&
                widget.initialHomeScore == null &&
                widget.initialAwayScore == null) ||
            (minutesText.isEmpty && (isFuture || notStarted)));
    final halfText = showVs
        ? ''
        : (detail?.homeHalfScore != null && detail?.awayHalfScore != null)
            ? 'HT${detail!.homeHalfScore}-${detail.awayHalfScore}'
            : 'HT-';
    final matchNotStarted = showVs || isFuture || notStarted;

    int? parseMinuteText(String raw) {
      final s = raw.trim();
      if (s.isEmpty) return null;
      final plus = s.contains('+');
      final matches = RegExp(r'\d+').allMatches(s).toList(growable: false);
      if (matches.isEmpty) return null;
      final first = int.tryParse(matches[0].group(0) ?? '');
      if (first == null) return null;
      if (plus && matches.length >= 2) {
        final second = int.tryParse(matches[1].group(0) ?? '') ?? 0;
        return first + second;
      }
      return first;
    }

    int inferCurrentMinute() {
      if (matchNotStarted) return 0;
      final fromText = parseMinuteText(minutesText);
      if (fromText != null) return fromText;
      final incidents = process?.incidents ?? const <_Incident>[];
      int maxMinute = 0;
      for (final e in incidents) {
        final m =
            e.time ?? (e.second == null ? null : (e.second! / 60).round());
        if (m != null && m > maxMinute) maxMinute = m;
      }
      if (maxMinute > 0) return maxMinute;
      final st = statusLower;
      final finished = st.contains('finished') ||
          st.contains('ft') ||
          st.contains('end') ||
          (detail?.statusName?.contains('完') ?? false) ||
          (detail?.statusName?.contains('结束') ?? false);
      if (finished) return 120;
      return 0;
    }

    final currentMinute = inferCurrentMinute().clamp(0, 120);

    return Scaffold(
      body: Stack(
        children: [
          const _MatchDetailsBackground(),
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
                      Text(
                        timeText,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: statusText.isEmpty
                              ? Colors.white.withValues(alpha: 0.55)
                              : const Color(0xFF00E676),
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
                              : Colors.white.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
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
                    halfText: halfText,
                    league: league,
                    competitionId: competitionId,
                    leftTeamId: homeTeamId,
                    rightTeamId: awayTeamId,
                  ),
                ),
                const SizedBox(height: 18),
                _TopTabs(
                  index: _tabIndex,
                  onChanged: (v) => setState(() => _tabIndex = v),
                  items: const ['Real time', 'Lineup'],
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      _tabIndex == 1 ? 0 : 16,
                      0,
                      _tabIndex == 1 ? 0 : 16,
                      24,
                    ),
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
                                    color: Colors.white.withValues(alpha: 0.75),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  height: 34,
                                  child: ElevatedButton(
                                    onPressed: _fetchMatchDetail,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white.withValues(
                                        alpha: 0.10,
                                      ),
                                      foregroundColor: Colors.white.withValues(
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
                      if (_tabIndex == 0) ...[
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
                                      color: Colors.white.withValues(
                                        alpha: 0.75,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    height: 34,
                                    child: ElevatedButton(
                                      onPressed: _fetchMatchProcess,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.white
                                            .withValues(alpha: 0.10),
                                        foregroundColor:
                                            Colors.white.withValues(alpha: 0.9),
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
                        _TimelineCard(
                          incidents: process?.incidents ?? const [],
                          trend: process?.trend,
                          matchNotStarted: matchNotStarted,
                          currentMinute: currentMinute,
                        ),
                        const SizedBox(height: 14),
                        _StatsCard(
                          leftScore: homeScore,
                          rightScore: awayScore,
                          leftLogoUrl: homeLogoUrl,
                          rightLogoUrl: awayLogoUrl,
                          stats: process?.stats,
                          matchNotStarted: matchNotStarted,
                        ),
                        if ((process?.tlive.isNotEmpty ?? false)) ...[
                          const SizedBox(height: 14),
                          _TLiveCard(items: process!.tlive),
                        ],
                      ] else ...[
                        if (_lineupErrorText != null && _lineup == null) ...[
                          SizedBox(
                            height: 140,
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    _lineupErrorText!,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.75,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    height: 34,
                                    child: ElevatedButton(
                                      onPressed: _fetchMatchLineup,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.white
                                            .withValues(alpha: 0.10),
                                        foregroundColor:
                                            Colors.white.withValues(alpha: 0.9),
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
                        ] else if (_lineupLoading && _lineup == null) ...[
                          const SizedBox(
                            height: 180,
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        ] else if (_lineup != null) ...[
                          _Lineup(
                            lineup: _lineup!,
                            homeName: homeName,
                            awayName: awayName,
                          ),
                        ] else ...[
                          const _LineupPlaceholder(),
                        ],
                      ],
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

class _MatchDetail {
  const _MatchDetail({
    required this.matchId,
    required this.competitionId,
    required this.competitionName,
    required this.homeTeamId,
    required this.homeTeamName,
    required this.awayTeamId,
    required this.awayTeamName,
    required this.homeTeamLogoUrl,
    required this.awayTeamLogoUrl,
    required this.homeNormalScore,
    required this.awayNormalScore,
    required this.homeHalfScore,
    required this.awayHalfScore,
    required this.matchTime,
    required this.statusName,
    required this.minutes,
  });

  final int matchId;
  final int? competitionId;
  final String competitionName;
  final int? homeTeamId;
  final String homeTeamName;
  final int? awayTeamId;
  final String awayTeamName;
  final String? homeTeamLogoUrl;
  final String? awayTeamLogoUrl;
  final int homeNormalScore;
  final int awayNormalScore;
  final int? homeHalfScore;
  final int? awayHalfScore;
  final int? matchTime;
  final String? statusName;
  final String? minutes;

  String get matchTimeText {
    final seconds = matchTime;
    if (seconds == null || seconds <= 0) return '—';
    final dt = DateTime.fromMillisecondsSinceEpoch(seconds * 1000).toLocal();
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y/$m/$d $hh:$mm';
  }

  factory _MatchDetail.fromJson(Map data) {
    String pickText(List<String> keys) {
      for (final k in keys) {
        final v = data[k];
        if (v == null) continue;
        final s = v.toString().trim();
        if (s.isNotEmpty && s != 'null') return s;
      }
      return '';
    }

    int? toNullableInt(Object? v) {
      if (v == null) return null;
      if (v is int) return v;
      return int.tryParse(v.toString());
    }

    String? sanitizeUrl(Object? v) {
      if (v == null) return null;
      final s = v.toString().replaceAll('`', '').trim();
      if (s.isEmpty || s == 'null') return null;
      if (s.startsWith('//')) return 'https:$s';
      if (s.startsWith('http://')) {
        return 'https://${s.substring('http://'.length)}';
      }
      return s;
    }

    final matchId =
        toNullableInt(data['match_id'] ?? data['matchId'] ?? data['id']) ?? 0;
    int? pickNullableInt(List<String> keys) {
      for (final k in keys) {
        final n = toNullableInt(data[k]);
        if (n != null) return n;
      }
      return null;
    }

    int? pickNestedTeamId(Object? raw) {
      if (raw is! Map) return null;
      return toNullableInt(
        raw['team_id'] ?? raw['teamId'] ?? raw['id'] ?? raw['ID'],
      );
    }

    final nestedHomeId = pickNestedTeamId(data['home_team']);
    final nestedAwayId = pickNestedTeamId(data['away_team']);
    final statusNameText = pickText(['status_name']);
    final minutesText = pickText(['minutes']);
    return _MatchDetail(
      matchId: matchId,
      competitionId: pickNullableInt([
        'competition_id',
        'competitionId',
        'league_id',
        'leagueId',
      ]),
      competitionName: pickText(['competition_name_en', 'competition_name']),
      homeTeamId:
          pickNullableInt(['home_team_id', 'homeTeamId']) ?? nestedHomeId,
      homeTeamName: pickText(['home_team_name_en', 'home_team_name']),
      awayTeamId:
          pickNullableInt(['away_team_id', 'awayTeamId']) ?? nestedAwayId,
      awayTeamName: pickText(['away_team_name_en', 'away_team_name']),
      homeTeamLogoUrl: sanitizeUrl(data['home_team_logo']),
      awayTeamLogoUrl: sanitizeUrl(data['away_team_logo']),
      homeNormalScore: toNullableInt(data['home_normal_score']) ?? 0,
      awayNormalScore: toNullableInt(data['away_normal_score']) ?? 0,
      homeHalfScore: toNullableInt(data['home_half_score']),
      awayHalfScore: toNullableInt(data['away_half_score']),
      matchTime: toNullableInt(data['match_time']),
      statusName: statusNameText.isEmpty ? null : statusNameText,
      minutes: minutesText.isEmpty ? null : minutesText,
    );
  }
}

class _MatchProcess {
  const _MatchProcess({
    required this.tlive,
    required this.stats,
    required this.incidents,
    required this.trend,
  });

  final List<_TLiveItem> tlive;
  final List<_StatItem> stats;
  final List<_Incident> incidents;
  final _MatchTrend? trend;

  factory _MatchProcess.fromJson(Map data) {
    int? toNullableInt(Object? v) {
      if (v == null) return null;
      if (v is int) return v;
      return int.tryParse(v.toString());
    }

    List<int> parseCsvInts(Object? raw) {
      final s = (raw ?? '').toString().replaceAll('`', '').trim();
      if (s.isEmpty || s == 'null') return const [];
      final parts = s.split(',');
      final out = <int>[];
      for (final p in parts) {
        final v = int.tryParse(p.trim());
        if (v != null) out.add(v);
      }
      return out;
    }

    _MatchTrend? parseTrend(Object? v) {
      if (v is! Map) return null;
      final per = toNullableInt(v['per']);
      final count = toNullableInt(v['count']);
      final first = parseCsvInts(v['first_data'] ?? v['firstData']);
      final second = parseCsvInts(v['second_data'] ?? v['secondData']);
      if (first.isEmpty && second.isEmpty) return null;
      return _MatchTrend(
        per: per ?? 45,
        count: count ?? 2,
        firstData: first,
        secondData: second,
      );
    }

    List<_TLiveItem> parseTlive(Object? v) {
      if (v is! List) return const [];
      final items = <_TLiveItem>[];
      for (final e in v) {
        if (e is! Map) continue;
        items.add(
          _TLiveItem(
            data: (e['data'] ?? '').toString(),
            timeText: (e['time'] ?? '').toString(),
            position: toNullableInt(e['position']) ?? 0,
            type: toNullableInt(e['type']) ?? 0,
          ),
        );
      }
      return items;
    }

    List<_StatItem> parseStats(Object? v) {
      if (v is! List) return const [];
      final items = <_StatItem>[];
      for (final e in v) {
        if (e is! Map) continue;
        items.add(
          _StatItem(
            type: toNullableInt(e['type']) ?? 0,
            name: (e['name'] ?? '').toString(),
            home: toNullableInt(e['home']) ?? 0,
            away: toNullableInt(e['away']) ?? 0,
          ),
        );
      }
      return items;
    }

    List<_Incident> parseIncidents(Object? v) {
      if (v is! List) return const [];
      final items = <_Incident>[];
      for (final e in v) {
        if (e is! Map) continue;
        items.add(
          _Incident(
            type: toNullableInt(e['type']) ?? 0,
            typeV2: toNullableInt(e['type_v2']) ?? 0,
            position: toNullableInt(e['position']) ?? 0,
            time: toNullableInt(e['time']),
            second: toNullableInt(e['second']),
            homeScore: toNullableInt(e['home_score']),
            awayScore: toNullableInt(e['away_score']),
          ),
        );
      }
      return items;
    }

    return _MatchProcess(
      tlive: parseTlive(data['tlive']),
      stats: parseStats(data['stats']),
      incidents: parseIncidents(data['incidents']),
      trend: parseTrend(data['trend'] ?? data['tren']),
    );
  }
}

class _MatchTrend {
  const _MatchTrend({
    required this.per,
    required this.count,
    required this.firstData,
    required this.secondData,
  });

  final int per;
  final int count;
  final List<int> firstData;
  final List<int> secondData;

  List<int> get values => [...firstData, ...secondData];
}

class _TLiveItem {
  const _TLiveItem({
    required this.data,
    required this.timeText,
    required this.position,
    required this.type,
  });

  final String data;
  final String timeText;
  final int position;
  final int type;
}

class _StatItem {
  const _StatItem({
    required this.type,
    required this.name,
    required this.home,
    required this.away,
  });

  final int type;
  final String name;
  final int home;
  final int away;
}

class _Incident {
  const _Incident({
    required this.type,
    required this.typeV2,
    required this.position,
    required this.time,
    required this.second,
    required this.homeScore,
    required this.awayScore,
  });

  final int type;
  final int typeV2;
  final int position;
  final int? time;
  final int? second;
  final int? homeScore;
  final int? awayScore;
}

class _MatchLineup {
  const _MatchLineup({
    required this.first,
    required this.sub,
    required this.injury,
    required this.homeFormation,
    required this.awayFormation,
  });

  final _LineupGroup first;
  final _LineupGroup sub;
  final _LineupGroup injury;
  final String? homeFormation;
  final String? awayFormation;

  factory _MatchLineup.fromJson(Map data) {
    int? toNullableInt(Object? v) {
      if (v == null) return null;
      if (v is int) return v;
      return int.tryParse(v.toString());
    }

    double? toNullableDouble(Object? v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    String? sanitizeUrl(Object? v) {
      if (v == null) return null;
      final s = v.toString().replaceAll('`', '').trim();
      if (s.isEmpty || s == 'null') return null;
      if (s.startsWith('//')) return 'https:$s';
      if (s.startsWith('http://')) {
        return 'https://${s.substring('http://'.length)}';
      }
      return s;
    }

    List<_LineupPlayer> parsePlayers(Object? v) {
      if (v is! List) return const [];
      final items = <_LineupPlayer>[];
      for (final e in v) {
        if (e is! Map) continue;
        final incidentsRaw = e['incidents'];
        final incidents = <_LineupIncident>[];
        if (incidentsRaw is List) {
          for (final it in incidentsRaw) {
            if (it is! Map) continue;
            incidents.add(
              _LineupIncident(
                timeText: (it['time'] ?? '').toString(),
                type: toNullableInt(it['type']) ?? 0,
              ),
            );
          }
        }
        items.add(
          _LineupPlayer(
            position: (e['position'] ?? '').toString(),
            playerId: toNullableInt(e['player_id'] ?? e['playerId']),
            playerName: (e['player_name'] ?? e['playerName'] ?? '').toString(),
            playerLogoUrl: sanitizeUrl(e['player_logo'] ?? e['playerLogo']),
            x: toNullableDouble(e['x']) ?? 0,
            y: toNullableDouble(e['y']) ?? 0,
            rating: (e['rating'] ?? '').toString(),
            shirtNumber: toNullableInt(e['shirt_number'] ?? e['shirtNumber']),
            incidents: incidents,
          ),
        );
      }
      return items;
    }

    _LineupGroup parseGroup(Object? v) {
      if (v is! Map) return const _LineupGroup(home: [], away: []);
      return _LineupGroup(
        home: parsePlayers(v['home']),
        away: parsePlayers(v['away']),
      );
    }

    final first = parseGroup(data['first']);
    final sub = parseGroup(data['sub']);
    final injury = parseGroup(data['injury']);
    final homeFormation =
        (data['home_formation'] ?? data['homeFormation'])?.toString().trim();
    final awayFormation =
        (data['away_formation'] ?? data['awayFormation'])?.toString().trim();

    return _MatchLineup(
      first: first,
      sub: sub,
      injury: injury,
      homeFormation: (homeFormation?.isEmpty ?? true) ? null : homeFormation,
      awayFormation: (awayFormation?.isEmpty ?? true) ? null : awayFormation,
    );
  }
}

class _LineupGroup {
  const _LineupGroup({required this.home, required this.away});

  final List<_LineupPlayer> home;
  final List<_LineupPlayer> away;
}

class _LineupPlayer {
  const _LineupPlayer({
    required this.position,
    required this.playerId,
    required this.playerName,
    required this.playerLogoUrl,
    required this.x,
    required this.y,
    required this.rating,
    required this.shirtNumber,
    required this.incidents,
  });

  final String position;
  final int? playerId;
  final String playerName;
  final String? playerLogoUrl;
  final double x;
  final double y;
  final String rating;
  final int? shirtNumber;
  final List<_LineupIncident> incidents;
}

class _LineupIncident {
  const _LineupIncident({required this.timeText, required this.type});

  final String timeText;
  final int type;
}

class _MatchDetailsBackground extends StatelessWidget {
  const _MatchDetailsBackground();

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
    required this.halfText,
    required this.league,
    required this.competitionId,
    required this.leftTeamId,
    required this.rightTeamId,
  });

  final String leftName;
  final String rightName;
  final String? leftLogoUrl;
  final String? rightLogoUrl;
  final int leftScore;
  final int rightScore;
  final bool showVs;
  final String halfText;
  final String league;
  final int? competitionId;
  final int? leftTeamId;
  final int? rightTeamId;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  _TeamBadge(
                    seed: 1,
                    logoUrl: leftLogoUrl,
                    onTap: competitionId == null || leftTeamId == null
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => LeagueDetailsPage(
                                  teamId: leftTeamId!,
                                  competitionId: competitionId!,
                                  initialTeamName: leftName,
                                  initialTeamLogoUrl: leftLogoUrl,
                                ),
                              ),
                            ),
                  ),
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
                  const SizedBox(height: 6),
                  if (halfText.trim().isNotEmpty)
                    Text(
                      halfText,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  _TeamBadge(
                    seed: 2,
                    logoUrl: rightLogoUrl,
                    onTap: competitionId == null || rightTeamId == null
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => LeagueDetailsPage(
                                  teamId: rightTeamId!,
                                  competitionId: competitionId!,
                                  initialTeamName: rightName,
                                  initialTeamLogoUrl: rightLogoUrl,
                                ),
                              ),
                            ),
                  ),
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
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 13,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

class _TeamBadge extends StatelessWidget {
  const _TeamBadge({required this.seed, required this.logoUrl, this.onTap});

  final int seed;
  final String? logoUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = [
      const Color(0xFF42A5F5),
      const Color(0xFFEF5350),
      const Color(0xFF7E57C2),
      const Color(0xFF26A69A),
    ];
    final c = colors[seed % colors.length];
    final badge = Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
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

    if (onTap == null) return badge;
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: badge,
      ),
    );
  }
}

class _TopTabs extends StatelessWidget {
  const _TopTabs({
    required this.index,
    required this.items,
    required this.onChanged,
  });

  final int index;
  final List<String> items;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            children: [
              for (int i = 0; i < items.length; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onChanged(i),
                    child: SizedBox(
                      height: 30,
                      child: Center(
                        child: Text(
                          items[i],
                          style: TextStyle(
                            color: i == index
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.4),
                            fontSize: 14,
                            fontWeight:
                                i == index ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 2,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(color: Colors.white.withValues(alpha: 0.12)),
                ),
                AnimatedAlign(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  alignment:
                      index == 0 ? Alignment.centerLeft : Alignment.centerRight,
                  child: FractionallySizedBox(
                    widthFactor: 0.5,
                    child: Container(color: const Color(0xFF00E676)),
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

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({
    required this.incidents,
    required this.trend,
    required this.matchNotStarted,
    required this.currentMinute,
  });

  final List<_Incident> incidents;
  final _MatchTrend? trend;
  final bool matchNotStarted;
  final int currentMinute;

  @override
  Widget build(BuildContext context) {
    final values =
        matchNotStarted ? const <int>[] : (trend?.values ?? const []);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              _TLabel("0'"),
              _TLabel("15'"),
              _TLabel("30'"),
              _TLabel('HT'),
              _TLabel("60'"),
              _TLabel("75'"),
              _TLabel("90'"),
              _TLabel("120'"),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 70,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _TimelinePainter(
                      values: values,
                      currentMinute: matchNotStarted ? null : currentMinute,
                    ),
                  ),
                ),
                Positioned.fill(child: _TimelineEvents(incidents: incidents)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TLabel extends StatelessWidget {
  const _TLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.45),
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  const _TimelinePainter({required this.values, required this.currentMinute});

  final List<int> values;
  final int? currentMinute;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final basePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), basePaint);

    final tickPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..strokeWidth = 1;

    const tickCount = 8;
    for (int i = 0; i < tickCount; i++) {
      final x = (size.width / (tickCount - 1)) * i;
      canvas.drawLine(
        Offset(x, centerY - 18),
        Offset(x, centerY + 18),
        tickPaint,
      );
    }

    final upFill = Paint()
      ..color = const Color(0xFF00E676).withValues(alpha: 0.95)
      ..style = PaintingStyle.fill;
    final downFill = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;

    final data = values;
    if (data.isNotEmpty) {
      final maxH = math.max(6.0, centerY - 4);
      final barW = math.max(4.0, size.width / (data.length * 1.35));
      final count = data.length;
      final minuteLimit = currentMinute?.toDouble();
      for (int i = 0; i < count; i++) {
        if (minuteLimit != null && count > 1) {
          final minuteAt = (i / (count - 1)) * 120.0;
          if (minuteAt > minuteLimit) break;
        } else if (minuteLimit != null && count == 1 && minuteLimit <= 0) {
          break;
        }
        final x = count == 1 ? size.width / 2 : (size.width / (count - 1)) * i;
        final v = data[i].clamp(-100, 100);
        final mag = (v.abs() / 100.0).clamp(0.0, 1.0);
        final h = mag * maxH;
        if (h <= 0.5) continue;
        final up = v >= 0;
        final path = Path()
          ..moveTo(x - barW / 2, centerY)
          ..lineTo(x, centerY + (up ? -h : h))
          ..lineTo(x + barW / 2, centerY)
          ..close();
        canvas.drawPath(path, up ? upFill : downFill);
      }
    }

    if (currentMinute != null) {
      final x = size.width * ((currentMinute!.clamp(0, 120)) / 120.0);
      final paint = Paint()
        ..color = const Color(0xFF00E676)
        ..strokeWidth = 2.2;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);

      // 新增一条短的绿色竖线
      final shortLinePaint = Paint()
        ..color = const Color(0xFF00E676)
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(x, -8),
        Offset(x, -2),
        shortLinePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _TimelineEvents extends StatelessWidget {
  const _TimelineEvents({required this.incidents});

  final List<_Incident> incidents;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final centerY = h / 2;

        Widget icon({
          required double x,
          required double y,
          required IconData icon,
          required Color color,
        }) {
          return Positioned(
            left: x - 9,
            top: y - 9,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.25),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
              ),
              child: Icon(icon, size: 12, color: color),
            ),
          );
        }

        double xAt(double t) => w * t;

        int? minuteOf(_Incident e) {
          final m = e.time;
          if (m != null) return m;
          final s = e.second;
          if (s != null) return (s / 60).round();
          return null;
        }

        (IconData, Color)? iconFor(_Incident e) {
          switch (e.type) {
            case 1:
              return (
                Icons.sports_soccer_rounded,
                Colors.white.withValues(alpha: 0.9),
              );
            case 3:
              return (Icons.crop_square_rounded, const Color(0xFFFFC107));
            case 4:
              return (Icons.crop_square_rounded, const Color(0xFFE53935));
          }
          return null;
        }

        final items = incidents
            .where((e) => minuteOf(e) != null)
            .toList(growable: false)
          ..sort((a, b) => minuteOf(a)!.compareTo(minuteOf(b)!));

        return Stack(
          children: [
            for (int i = 0; i < items.length; i++)
              () {
                final e = items[i];
                final minute = minuteOf(e) ?? 0;
                final resolved = iconFor(e);
                if (resolved == null) return const SizedBox.shrink();

                final (ico, color) = resolved;
                final t = (minute / 120).clamp(0.0, 1.0);
                final dy = e.position == 1
                    ? -18.0
                    : e.position == 2
                        ? 18.0
                        : 0.0;
                final jitter = (i % 3 - 1) * 10.0;
                return icon(
                  x: xAt(t) + jitter,
                  y: centerY + dy,
                  icon: ico,
                  color: color,
                );
              }(),
          ],
        );
      },
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({
    this.leftScore,
    this.rightScore,
    this.leftLogoUrl,
    this.rightLogoUrl,
    this.stats,
    required this.matchNotStarted,
  });

  final int? leftScore;
  final int? rightScore;
  final String? leftLogoUrl;
  final String? rightLogoUrl;
  final List<_StatItem>? stats;
  final bool matchNotStarted;

  @override
  Widget build(BuildContext context) {
    final statsData = stats ?? const <_StatItem>[];
    if (statsData.isNotEmpty) {
      bool isPercent(_StatItem s) =>
          s.type == 25 || s.name.contains('%') || s.name.contains('控球');

      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: Colors.white.withValues(alpha: 0.08),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
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
                leftScore: leftScore ?? 0,
                rightScore: rightScore ?? 0,
                leftLogoUrl: leftLogoUrl,
                rightLogoUrl: rightLogoUrl,
              ),
              const SizedBox(height: 12),
              for (int i = 0; i < statsData.length; i++) ...[
                _StatRow(
                  label: statsData[i].name,
                  left: statsData[i].home,
                  right: statsData[i].away,
                  isPercent: isPercent(statsData[i]),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MatchStatDetailsPage(
                        title: statsData[i].name,
                        leftValue: statsData[i].home,
                        rightValue: statsData[i].away,
                        isPercent: isPercent(statsData[i]),
                      ),
                    ),
                  ),
                ),
                if (i != statsData.length - 1) const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      );
    }

    Widget placeholderRow({
      required String label,
      required bool isPercent,
    }) {
      return _StatRow(
        label: label,
        left: 0,
        right: 0,
        isPercent: isPercent,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MatchStatDetailsPage(
              title: label,
              leftValue: 0,
              rightValue: 0,
              isPercent: isPercent,
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withValues(alpha: 0.08),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
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
              leftScore: leftScore ?? 0,
              rightScore: rightScore ?? 0,
              leftLogoUrl: leftLogoUrl,
              rightLogoUrl: rightLogoUrl,
            ),
            const SizedBox(height: 12),
            if (matchNotStarted) ...[
              placeholderRow(label: 'Ball possession', isPercent: true),
              const SizedBox(height: 10),
              placeholderRow(label: 'Shot on target', isPercent: false),
              const SizedBox(height: 10),
              placeholderRow(label: 'Shoot off target', isPercent: false),
              const SizedBox(height: 10),
              placeholderRow(label: 'attack', isPercent: false),
              const SizedBox(height: 10),
              placeholderRow(label: 'Dangerous Attack', isPercent: false),
              const SizedBox(height: 10),
              placeholderRow(label: 'Corner Kick', isPercent: false),
              const SizedBox(height: 10),
              placeholderRow(label: 'Red Card', isPercent: false),
              const SizedBox(height: 10),
              placeholderRow(label: 'Yellow Card', isPercent: false),
            ] else ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Center(
                  child: Text(
                    '暂无数据',
                    style:
                        TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TLiveCard extends StatelessWidget {
  const _TLiveCard({required this.items});

  final List<_TLiveItem> items;

  @override
  Widget build(BuildContext context) {
    Color stripeColor(_TLiveItem item) {
      if (item.position == 1) return const Color(0xFF00E676);
      if (item.position == 2) return Colors.white.withValues(alpha: 0.65);
      return Colors.white.withValues(alpha: 0.35);
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withValues(alpha: 0.08),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '文字直播',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.95),
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 3,
                      height: 34,
                      decoration: BoxDecoration(
                        color: stripeColor(item),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 46,
                      child: Text(
                        item.timeText.isEmpty ? '—' : item.timeText,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.data,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 12,
                          height: 1.25,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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
    this.leftLogoUrl,
    this.rightLogoUrl,
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
            color: Colors.white.withValues(alpha: 0.95),
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
                color: Colors.white.withValues(alpha: 0.95),
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
            color: Colors.white.withValues(alpha: 0.95),
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
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
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
    this.isPercent = false,
    this.onTap,
  });

  final String label;
  final int left;
  final int right;
  final bool isPercent;
  final VoidCallback? onTap;

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
                bg: const Color(0xFF00E676).withValues(alpha: 0.22),
                fg: const Color(0xFF00E676),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _ValuePill(
                text: rightText,
                bg: const Color(0xFFFFC107).withValues(alpha: 0.20),
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

    if (onTap == null) return content;

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
                      color: const Color(0xFF00E676).withValues(alpha: 0.22),
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
                      color: const Color(0xFFFFC107).withValues(alpha: 0.20),
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

class _LineupPlaceholder extends StatelessWidget {
  const _LineupPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/match_detail_lineup_bg.png',
      width: double.infinity,
      fit: BoxFit.fitWidth,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          height: 220,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
          ),
          alignment: Alignment.center,
          child: Text(
            'Lineup image missing',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      },
    );
  }
}

class _Lineup extends StatelessWidget {
  const _Lineup({
    required this.lineup,
    required this.homeName,
    required this.awayName,
  });

  final _MatchLineup lineup;
  final String homeName;
  final String awayName;

  @override
  Widget build(BuildContext context) {
    final homeFormation = lineup.homeFormation ?? '-';
    final awayFormation = lineup.awayFormation ?? '-';
    final homePlaced = lineup.first.home
        .where((p) => p.x != 0 || p.y != 0)
        .toList(growable: false);
    final awayPlaced = lineup.first.away
        .where((p) => p.x != 0 || p.y != 0)
        .toList(growable: false);
    final showPitch = homePlaced.length >= 6 && awayPlaced.length >= 6;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      homeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      homeFormation,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      awayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      awayFormation,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showPitch)
          AspectRatio(
            aspectRatio: 750 / 1360,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final h = constraints.maxHeight;
                final halfH = h / 2;

                final markerW = math.min(92.0, w * 0.18);
                final markerH = markerW + 22;
                final avatarSize = math.min(44.0, markerW * 0.58);
                final safePadX = math.max(10.0, w * 0.045);
                final safePadY = math.max(10.0, h * 0.025);

                Offset posFor(_LineupPlayer p, {required bool isHome}) {
                  final x = (p.x.clamp(0, 100) / 100);
                  final y = (p.y.clamp(0, 100) / 100);
                  final px = safePadX + x * (w - safePadX * 2);
                  final yy = isHome ? y : (1 - y);
                  final pyInHalf = safePadY + yy * (halfH - safePadY * 2);
                  final py = isHome ? pyInHalf : halfH + pyInHalf;
                  return Offset(px, py);
                }

                Positioned markerFor(_LineupPlayer p, {required bool isHome}) {
                  final pos = posFor(p, isHome: isHome);
                  final left = (pos.dx - markerW / 2).clamp(0.0, w - markerW);
                  final top = (pos.dy - markerH / 2).clamp(0.0, h - markerH);
                  return Positioned(
                    left: left,
                    top: top,
                    width: markerW,
                    height: markerH,
                    child: _LineupMarker(
                      name: p.playerName.trim().isEmpty
                          ? '-'
                          : p.playerName.trim(),
                      number: p.shirtNumber?.toString(),
                      avatarUrl: p.playerLogoUrl,
                      avatarSize: avatarSize,
                      showDot: p.incidents.isNotEmpty,
                    ),
                  );
                }

                return Stack(
                  children: [
                    Positioned.fill(
                      child: Image.asset(
                        'assets/images/match_detail_lineup_bg.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                    for (final p in homePlaced) markerFor(p, isHome: true),
                    for (final p in awayPlaced) markerFor(p, isHome: false),
                  ],
                );
              },
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _LineupListSection(
              title: '首发阵容',
              homeName: homeName,
              awayName: awayName,
              homePlayers: lineup.first.home,
              awayPlayers: lineup.first.away,
            ),
          ),
        const SizedBox(height: 12),
        if (lineup.sub.home.isNotEmpty || lineup.sub.away.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _LineupListSection(
              title: '替补',
              homeName: homeName,
              awayName: awayName,
              homePlayers: lineup.sub.home,
              awayPlayers: lineup.sub.away,
            ),
          ),
        if (lineup.injury.home.isNotEmpty || lineup.injury.away.isNotEmpty) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _LineupListSection(
              title: '伤停',
              homeName: homeName,
              awayName: awayName,
              homePlayers: lineup.injury.home,
              awayPlayers: lineup.injury.away,
            ),
          ),
        ],
      ],
    );
  }
}

class _LineupMarker extends StatelessWidget {
  const _LineupMarker({
    required this.name,
    required this.number,
    required this.showDot,
    required this.avatarUrl,
    required this.avatarSize,
  });

  final String name;
  final String? number;
  final String? avatarUrl;
  final double avatarSize;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    final hasUrl = (avatarUrl ?? '').trim().isNotEmpty;
    final badgeText = (number ?? '').trim();

    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        SizedBox(
          width: avatarSize,
          height: avatarSize,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: ClipOval(
                  child: hasUrl
                      ? Image.network(
                          avatarUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              _AvatarFallback(name: name),
                        )
                      : _AvatarFallback(name: name),
                ),
              ),
              if (showDot)
                Positioned(
                  right: 2,
                  top: 2,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFC107),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.85),
                        width: 1,
                      ),
                    ),
                  ),
                ),
              if (badgeText.isNotEmpty)
                Positioned(
                  left: (avatarSize - 18) / 2,
                  bottom: -6,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: const Color(0xFF00C853),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.85),
                        width: 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      badgeText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.92),
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isEmpty ? '?' : name.trim().characters.first;
    return Container(
      color: Colors.white.withValues(alpha: 0.10),
      child: Center(
        child: Text(
          letter,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _LineupListSection extends StatelessWidget {
  const _LineupListSection({
    required this.title,
    required this.homeName,
    required this.awayName,
    required this.homePlayers,
    required this.awayPlayers,
  });

  final String title;
  final String homeName;
  final String awayName;
  final List<_LineupPlayer> homePlayers;
  final List<_LineupPlayer> awayPlayers;

  @override
  Widget build(BuildContext context) {
    final maxLen = math.max(homePlayers.length, awayPlayers.length);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                '${homePlayers.length} - ${awayPlayers.length}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  homeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  awayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (maxLen == 0)
            SizedBox(
              height: 44,
              child: Center(
                child: Text(
                  '暂无数据',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )
          else
            Column(
              children: List.generate(maxLen, (i) {
                final l = i < homePlayers.length ? homePlayers[i] : null;
                final r = i < awayPlayers.length ? awayPlayers[i] : null;
                return Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: _LineupListRow(player: l, alignRight: false),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _LineupListRow(player: r, alignRight: true),
                      ),
                    ],
                  ),
                );
              }),
            ),
        ],
      ),
    );
  }
}

class _LineupListRow extends StatelessWidget {
  const _LineupListRow({required this.player, required this.alignRight});

  final _LineupPlayer? player;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    final p = player;
    if (p == null) return const SizedBox(height: 28);
    final name = p.playerName.trim().isEmpty ? '-' : p.playerName.trim();
    final number = p.shirtNumber?.toString();
    final pos = p.position.trim();

    final badge = (number ?? '').trim().isEmpty
        ? null
        : Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: const Color(0xFF00C853),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            alignment: Alignment.center,
            child: Text(
              number!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                height: 1.1,
              ),
            ),
          );

    final posChip = pos.isEmpty
        ? null
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: Text(
              pos,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                height: 1.15,
              ),
            ),
          );

    final nameText = Text(
      name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: alignRight ? TextAlign.end : TextAlign.start,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.9),
        fontSize: 12,
        fontWeight: FontWeight.w700,
        height: 1.1,
      ),
    );

    final children = <Widget>[
      if (!alignRight) ...[
        if (badge != null) badge,
        if (badge != null) const SizedBox(width: 8),
        Expanded(child: nameText),
        if (posChip != null) ...[const SizedBox(width: 8), posChip],
      ] else ...[
        if (posChip != null) ...[posChip, const SizedBox(width: 8)],
        Expanded(child: nameText),
        if (badge != null) const SizedBox(width: 8),
        if (badge != null) badge,
      ],
    ];

    return SizedBox(height: 28, child: Row(children: children));
  }
}
