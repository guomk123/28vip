import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'match_details_page.dart';

extension _ColorWithValuesCompat on Color {
  Color withValues({double? alpha}) {
    if (alpha == null) return this;
    final a = alpha.clamp(0.0, 1.0);
    return withOpacity(a);
  }
}

class LeagueDetailsPage extends StatefulWidget {
  const LeagueDetailsPage({
    super.key,
    required this.teamId,
    required this.competitionId,
    this.initialTeamName,
    this.initialTeamLogoUrl,
  });

  final int teamId;
  final int competitionId;
  final String? initialTeamName;
  final String? initialTeamLogoUrl;

  @override
  State<LeagueDetailsPage> createState() => _LeagueDetailsPageState();
}

class _LeagueDetailsPageState extends State<LeagueDetailsPage> {
  static const _teamDataEndpoint =
      'https://api.z8vips.com/api/v1/football/team/data';
  static const _seasonListEndpoint =
      'https://api.z8vips.com/api/v1/football/competition/season-list';
  static const _teamFixturesEndpoint =
      'https://api.z8vips.com/api/v1/football/team/fixtures';

  bool _loadingTeam = false;
  String? _teamErrorText;
  _TeamInfo? _teamInfo;
  int _teamRequestSeq = 0;

  int? _seasonId;
  bool _loadingFixtures = false;
  String? _fixturesErrorText;
  List<_FixtureItem> _fixtures = const [];
  int _fixturesRequestSeq = 0;

  @override
  void initState() {
    super.initState();
    final initialName = (widget.initialTeamName ?? '').trim();
    final initialLogo = (widget.initialTeamLogoUrl ?? '').trim();
    _teamInfo = _TeamInfo(
      name: initialName.isEmpty ? 'Team' : initialName,
      logoUrl: initialLogo.isEmpty ? null : initialLogo,
      stadium: null,
      founded: null,
      events: null,
      squadValueText: null,
    );
    _fetchTeam();
    _fetchFixtures();
  }

  Future<void> _fetchTeam() async {
    final requestId = ++_teamRequestSeq;
    setState(() {
      _loadingTeam = true;
      _teamErrorText = null;
    });

    try {
      final uri = Uri.parse(_teamDataEndpoint).replace(
        queryParameters: {
          'team_id': widget.teamId.toString(),
          'TeamId': widget.teamId.toString(),
          'teamId': widget.teamId.toString(),
        },
      );
      final response = await http.get(uri);
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

      final name =
          (data['name_en'] ??
                  data['short_name_en'] ??
                  data['team_name'] ??
                  data['name'] ??
                  '')
              .toString()
              .trim();
      final logo = _sanitizeUrl(data['logo'] ?? data['team_logo']);
      final stadium =
          (data['stadium'] ?? data['venue_name'] ?? data['venue'] ?? '')
              .toString()
              .trim();
      final founded = _toNullableInt(
        data['foundation_time'] ?? data['founded'] ?? data['founded_year'],
      );
      final events = (data['competition_name'] ?? data['league_name'] ?? '')
          .toString()
          .trim();
      final marketValue = _toNullableInt(data['market_value']);
      final marketCurrency = (data['market_value_currency'] ?? '')
          .toString()
          .trim();
      final squadValueText = marketValue == null || marketValue <= 0
          ? ''
          : 'Total squad value:$marketCurrency${(marketValue / 100000000).toStringAsFixed(1)} (unit: 100M)';

      final info = _TeamInfo(
        name: name.isEmpty ? (_teamInfo?.name ?? 'Team') : name,
        logoUrl: logo.isEmpty ? _teamInfo?.logoUrl : logo,
        stadium: stadium.isEmpty ? null : stadium,
        founded: founded,
        events: events.isEmpty ? null : events,
        squadValueText: squadValueText.isEmpty ? null : squadValueText,
      );

      if (!mounted || requestId != _teamRequestSeq) return;
      setState(() {
        _teamInfo = info;
      });
    } catch (_) {
      if (!mounted || requestId != _teamRequestSeq) return;
      setState(() {
        _teamErrorText = '球队信息加载失败，请重试';
      });
    } finally {
      if (mounted && requestId == _teamRequestSeq) {
        setState(() {
          _loadingTeam = false;
        });
      } else if (requestId == _teamRequestSeq) {
        _loadingTeam = false;
      }
    }
  }

  Future<void> _fetchFixtures() async {
    final requestId = ++_fixturesRequestSeq;
    setState(() {
      _loadingFixtures = true;
      _fixturesErrorText = null;
    });

    try {
      final seasonId =
          _seasonId ?? await _resolveSeasonId(requestId: requestId);
      if (!mounted || requestId != _fixturesRequestSeq) return;

      final uri = Uri.parse(_teamFixturesEndpoint).replace(
        queryParameters: {
          'team_id': widget.teamId.toString(),
          'TeamId': widget.teamId.toString(),
          'teamId': widget.teamId.toString(),
          'competition_id': widget.competitionId.toString(),
          'CompetitionId': widget.competitionId.toString(),
          'competitionId': widget.competitionId.toString(),
          'season_id': seasonId.toString(),
          'SeasonId': seasonId.toString(),
          'seasonId': seasonId.toString(),
        },
      );
      final response = await http.get(uri);
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
      final List list = switch (data) {
        List() => data,
        Map() when data['list'] is List => data['list'] as List,
        _ => const [],
      };

      final items = <_FixtureItem>[];
      for (final raw in list) {
        if (raw is! Map) continue;
        final dt = _formatDateTimeToMinute(
          raw['match_time'] ?? raw['start_time'] ?? raw['time'],
        );
        final matchId = _toNullableInt(
          raw['match_id'] ?? raw['matchId'] ?? raw['id'] ?? raw['matchid'],
        );
        final awayName =
            (raw['away_team_name'] ??
                    raw['awayTeamName'] ??
                    raw['away_name'] ??
                    '')
                .toString()
                .trim();
        final homeName =
            (raw['home_team_name'] ??
                    raw['homeTeamName'] ??
                    raw['home_name'] ??
                    '')
                .toString()
                .trim();
        final awayLogo = _sanitizeUrl(
          raw['away_team_logo'] ?? raw['awayTeamLogo'] ?? raw['away_logo'],
        );
        final homeLogo = _sanitizeUrl(
          raw['home_team_logo'] ?? raw['homeTeamLogo'] ?? raw['home_logo'],
        );
        final homeId = _toNullableInt(raw['home_team_id'] ?? raw['homeTeamId']);
        final awayId = _toNullableInt(raw['away_team_id'] ?? raw['awayTeamId']);
        final status = _toNullableInt(raw['status']) ?? -1;
        final ended = status == 8;
        final awayNormalScore = _toNullableInt(
          raw['away_normal_score'] ?? raw['awayNormalScore'],
        );
        final homeNormalScore = _toNullableInt(
          raw['home_normal_score'] ?? raw['homeNormalScore'],
        );
        final leagueText =
            (raw['competition_name'] ??
                    raw['league_name'] ??
                    raw['competitionName'] ??
                    '')
                .toString()
                .trim();
        final statusText = ended
            ? 'End'
            : _formatStatusText(
                raw['status_text'] ?? raw['statusText'] ?? raw['status'],
              );
        final scoreText =
            ended && awayNormalScore != null && homeNormalScore != null
            ? '${awayNormalScore.toString()} - ${homeNormalScore.toString()}'
            : 'VS';

        final tagText = _winTagForMatch(
          teamId: widget.teamId,
          homeId: homeId,
          awayId: awayId,
          homeScore: homeNormalScore,
          awayScore: awayNormalScore,
          ended: ended,
        );

        if (homeName.isEmpty && awayName.isEmpty) continue;
        items.add(
          _FixtureItem(
            matchId: matchId,
            dateTimeText: dt,
            awayTeam: awayName.isEmpty ? 'Away' : awayName,
            awayTeamLogoUrl: awayLogo.isEmpty ? null : awayLogo,
            homeTeam: homeName.isEmpty ? 'Home' : homeName,
            homeTeamLogoUrl: homeLogo.isEmpty ? null : homeLogo,
            scoreText: scoreText,
            statusText: statusText,
            leagueText: leagueText.isEmpty ? 'Competition' : leagueText,
            tagText: tagText,
            timeCentered: !ended,
            homeScore: ended ? homeNormalScore : null,
            awayScore: ended ? awayNormalScore : null,
          ),
        );
      }

      if (!mounted || requestId != _fixturesRequestSeq) return;
      setState(() {
        _fixtures = items;
      });
    } catch (_) {
      if (!mounted || requestId != _fixturesRequestSeq) return;
      setState(() {
        _fixturesErrorText = '赛程加载失败，请重试';
        _fixtures = const [];
      });
    } finally {
      if (mounted && requestId == _fixturesRequestSeq) {
        setState(() {
          _loadingFixtures = false;
        });
      } else if (requestId == _fixturesRequestSeq) {
        _loadingFixtures = false;
      }
    }
  }

  Future<int> _resolveSeasonId({required int requestId}) async {
    final uri = Uri.parse(_seasonListEndpoint).replace(
      queryParameters: {
        'CompetitionId': widget.competitionId.toString(),
        'competition_id': widget.competitionId.toString(),
        'competitionId': widget.competitionId.toString(),
      },
    );
    final response = await http.get(uri);
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
    final List list = switch (data) {
      List() => data,
      Map() when data['list'] is List => data['list'] as List,
      _ => const [],
    };
    if (list.isEmpty) {
      throw Exception('empty season list');
    }
    final first = list.first;
    if (first is! Map) {
      throw Exception('invalid season item');
    }
    final id = _toNullableInt(
      first['season_id'] ?? first['seasonId'] ?? first['id'],
    );
    if (id == null) {
      throw Exception('invalid season id');
    }

    if (mounted && requestId == _fixturesRequestSeq) {
      setState(() {
        _seasonId = id;
      });
    } else if (requestId == _fixturesRequestSeq) {
      _seasonId = id;
    }
    return id;
  }

  int? _toNullableInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse((value ?? '').toString());
  }

  String _sanitizeUrl(dynamic value) {
    final raw = (value ?? '').toString();
    return raw.replaceAll('`', '').trim();
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

  String _formatDateTimeToMinute(dynamic raw) {
    DateTime? dt;
    if (raw is int) {
      if (raw > 9999999999) {
        dt = DateTime.fromMillisecondsSinceEpoch(raw);
      } else {
        dt = DateTime.fromMillisecondsSinceEpoch(raw * 1000);
      }
    }
    if (raw is double) return _formatDateTimeToMinute(raw.round());

    if (dt == null) {
      final text = (raw ?? '').toString().trim();
      if (text.isEmpty) return '-';
      final parsed = DateTime.tryParse(text);
      if (parsed != null) {
        dt = parsed;
      } else {
        final cleaned = text.replaceAll('-', '/');
        if (cleaned.length >= 16) return cleaned.substring(0, 16);
        return cleaned;
      }
    }
    final local = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year.toString().padLeft(4, '0')}/${two(local.month)}/${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  String _formatStatusText(dynamic raw) {
    if (raw is String) {
      final t = raw.trim();
      if (t.isNotEmpty) return t;
    }
    final code = _toNullableInt(raw);
    return switch (code) {
      0 => 'Not started',
      1 => '1st half',
      2 => 'Half time',
      3 => '2nd half',
      4 => 'End',
      8 => 'End',
      _ => 'Unknown',
    };
  }

  String? _winTagForMatch({
    required int teamId,
    required int? homeId,
    required int? awayId,
    required int? homeScore,
    required int? awayScore,
    required bool ended,
  }) {
    if (!ended) return null;
    if (homeScore == null || awayScore == null) return null;
    if (homeId == null && awayId == null) return null;
    final isHome = homeId == teamId;
    final isAway = awayId == teamId;
    if (!isHome && !isAway) return null;
    final myScore = isHome ? homeScore : awayScore;
    final oppScore = isHome ? awayScore : homeScore;
    if (myScore > oppScore) return 'WIN';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const _DetailsBackground(),
          SafeArea(
            top: false,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                _HeaderCard(
                  loading: _loadingTeam,
                  errorText: _teamErrorText,
                  team: _teamInfo,
                  onRetry: _fetchTeam,
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Fixtures',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_loadingFixtures)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 22),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_fixturesErrorText != null)
                        Column(
                          children: [
                            Text(
                              _fixturesErrorText!,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.75),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 36,
                              child: ElevatedButton(
                                onPressed: _fetchFixtures,
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
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                child: const Text('重试'),
                              ),
                            ),
                          ],
                        )
                      else if (_fixtures.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 22),
                          child: Center(
                            child: Text(
                              '暂无赛程数据',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                        )
                      else
                        for (int i = 0; i < _fixtures.length; i++) ...[
                          _FixtureCard(
                            dateTime: _fixtures[i].dateTimeText,
                            leftTeam: _fixtures[i].awayTeam,
                            leftTeamLogoUrl: _fixtures[i].awayTeamLogoUrl,
                            rightTeam: _fixtures[i].homeTeam,
                            rightTeamLogoUrl: _fixtures[i].homeTeamLogoUrl,
                            scoreText: _fixtures[i].scoreText,
                            statusText: _fixtures[i].statusText,
                            leagueText: _fixtures[i].leagueText,
                            tagText: _fixtures[i].tagText,
                            timeCentered: _fixtures[i].timeCentered,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => MatchDetailsPage(
                                  matchId: _fixtures[i].matchId,
                                  initialHomeTeamName: _fixtures[i].homeTeam,
                                  initialAwayTeamName: _fixtures[i].awayTeam,
                                  initialHomeTeamLogoUrl:
                                      _fixtures[i].homeTeamLogoUrl,
                                  initialAwayTeamLogoUrl:
                                      _fixtures[i].awayTeamLogoUrl,
                                  initialCompetitionName: _fixtures[i].leagueText,
                                  initialHomeScore: _fixtures[i].homeScore,
                                  initialAwayScore: _fixtures[i].awayScore,
                                ),
                              ),
                            ),
                          ),
                          if (i != _fixtures.length - 1)
                            const SizedBox(height: 14),
                        ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 38,
                  height: 38,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => Navigator.of(context).maybePop(),
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
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailsBackground extends StatelessWidget {
  const _DetailsBackground();

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

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.loading,
    required this.errorText,
    required this.team,
    required this.onRetry,
  });

  final bool loading;
  final String? errorText;
  final _TeamInfo? team;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    const badgeSize = 74.0;
    const overlap = badgeSize * 0.4;
    final name = team?.name ?? 'Team';
    final squadValueText = (team?.squadValueText ?? '').trim();
    final events = (team?.events ?? '').trim();
    final stadium = (team?.stadium ?? '').trim();
    final founded = team?.founded;

    return Column(
      children: [
        SizedBox(
          height: 210,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                'assets/images/leagues_detai_top.png',
                fit: BoxFit.cover,
              ),
              Container(color: Colors.black.withValues(alpha: 0.25)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Column(
            children: [
              Row(
                children: [
                  Transform.translate(
                    offset: const Offset(0, -overlap),
                    child: _BadgeLogo(size: badgeSize, url: team?.logoUrl),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.zero,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            squadValueText.isEmpty ? ' ' : squadValueText,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _InfoTile(
                      title: events.isEmpty ? '-' : events,
                      subtitle: 'Events',
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: _InfoTile(
                      title: stadium.isEmpty ? '-' : stadium,
                      subtitle: 'Stadium',
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: _InfoTile(
                      title: founded?.toString() ?? '-',
                      subtitle: 'Founded',
                    ),
                  ),
                ],
              ),
              if (loading || errorText != null) const SizedBox(height: 10),
              if (loading)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (errorText != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          errorText!,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        height: 28,
                        child: ElevatedButton(
                          onPressed: onRetry,
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
              const SizedBox(height: 10),
            ],
          ),
        ),
      ],
    );
  }
}

class _BadgeLogo extends StatelessWidget {
  const _BadgeLogo({required this.size, required this.url});

  final double size;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final u = (url ?? '').trim();
    final innerSize = (size * 0.78 - 10).clamp(0, size);
    final fallbackSize = (size * 0.62 - 10).clamp(0, size);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Center(
        child: u.isEmpty
            ? Container(
                width: fallbackSize.toDouble(),
                height: fallbackSize.toDouble(),
                decoration: const BoxDecoration(
                  color: Color(0xFF42A5F5),
                  shape: BoxShape.circle,
                ),
              )
            : ClipOval(
                child: Image.network(
                  u,
                  width: innerSize.toDouble(),
                  height: innerSize.toDouble(),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: fallbackSize.toDouble(),
                    height: fallbackSize.toDouble(),
                    decoration: const BoxDecoration(
                      color: Color(0xFF42A5F5),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 66,
      decoration: BoxDecoration(
        color: const Color(0xFF0B1E16).withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: const Color(0xFF00E676).withValues(alpha: 0.95),
              fontSize: 13,
              fontWeight: FontWeight.w800,
              height: 1.05,
            ),
          ),
          const Spacer(),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 11,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _FixtureCard extends StatelessWidget {
  const _FixtureCard({
    required this.dateTime,
    required this.leftTeam,
    required this.leftTeamLogoUrl,
    required this.rightTeam,
    required this.rightTeamLogoUrl,
    required this.scoreText,
    required this.statusText,
    required this.leagueText,
    required this.onTap,
    required this.timeCentered,
    this.tagText,
  });

  final String dateTime;
  final String leftTeam;
  final String? leftTeamLogoUrl;
  final String rightTeam;
  final String? rightTeamLogoUrl;
  final String scoreText;
  final String statusText;
  final String leagueText;
  final String? tagText;
  final VoidCallback onTap;
  final bool timeCentered;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: Colors.white.withValues(alpha: 0.06),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 18,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        if (!timeCentered)
                          Text(
                            dateTime,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.55),
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                            ),
                          )
                        else
                          Expanded(
                            child: Center(
                              child: Text(
                                dateTime,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.55),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ),
                          ),
                        if (!timeCentered) const Spacer(),
                        if (tagText != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF00E676,
                              ).withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              tagText!,
                              style: const TextStyle(
                                color: Color(0xFF00E676),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: onTap,
                            child: Column(
                              children: [
                                _SmallBadge(seed: 1, url: leftTeamLogoUrl),
                                const SizedBox(height: 8),
                                Text(
                                  leftTeam,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: onTap,
                            child: Column(
                              children: [
                                Text(
                                  scoreText,
                                  style: TextStyle(
                                    color: const Color(0xFF00E676),
                                    fontSize: scoreText == 'VS' ? 18 : 22,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  statusText,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.55),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: onTap,
                            child: Column(
                              children: [
                                _SmallBadge(seed: 2, url: rightTeamLogoUrl),
                                const SizedBox(height: 8),
                                Text(
                                  rightTeam,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      leagueText,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
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
  }
}

class _SmallBadge extends StatelessWidget {
  const _SmallBadge({required this.seed, required this.url});

  final int seed;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final colors = [
      const Color(0xFF42A5F5),
      const Color(0xFFE53935),
      const Color(0xFF7E57C2),
      const Color(0xFF26A69A),
    ];
    final c = colors[seed % colors.length];
    final u = (url ?? '').trim();
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: Center(
        child: u.isEmpty
            ? Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle),
              )
            : ClipOval(
                child: Image.network(
                  u,
                  width: 32,
                  height: 32,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                  ),
                ),
              ),
      ),
    );
  }
}

class _TeamInfo {
  const _TeamInfo({
    required this.name,
    required this.logoUrl,
    required this.stadium,
    required this.founded,
    required this.events,
    required this.squadValueText,
  });

  final String name;
  final String? logoUrl;
  final String? stadium;
  final int? founded;
  final String? events;
  final String? squadValueText;
}

class _FixtureItem {
  const _FixtureItem({
    required this.matchId,
    required this.dateTimeText,
    required this.awayTeam,
    required this.awayTeamLogoUrl,
    required this.homeTeam,
    required this.homeTeamLogoUrl,
    required this.scoreText,
    required this.statusText,
    required this.leagueText,
    required this.tagText,
    required this.timeCentered,
    required this.homeScore,
    required this.awayScore,
  });

  final int? matchId;
  final String dateTimeText;
  final String awayTeam;
  final String? awayTeamLogoUrl;
  final String homeTeam;
  final String? homeTeamLogoUrl;
  final String scoreText;
  final String statusText;
  final String leagueText;
  final String? tagText;
  final bool timeCentered;
  final int? homeScore;
  final int? awayScore;
}
