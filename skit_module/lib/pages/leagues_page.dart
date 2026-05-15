import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'league_details_page.dart';
import 'player_details_page.dart';
import 'common_widgets.dart';

extension _ColorWithValuesCompat on Color {
  Color withValues({double? alpha}) {
    if (alpha == null) return this;
    final a = alpha.clamp(0.0, 1.0);
    return withOpacity(a);
  }
}

class LeaguesPage extends StatefulWidget {
  const LeaguesPage({super.key});

  @override
  State<LeaguesPage> createState() => _LeaguesPageState();
}

class _LeaguesPageState extends State<LeaguesPage> with WidgetsBindingObserver {
  static const _competitionEndpoint =
      'https://api.z8vips.com/api/v1/football/competition/list';
  static const _competitionTableEndpoint =
      'https://api.z8vips.com/api/v1/football/competition/table-list';
  static const _playerRankEndpoint =
      'https://api.z8vips.com/api/v1/football/competition/player-rank';
  static const _teamRankKeysEndpoint =
      'https://api.z8vips.com/api/v1/football/competition/team-rank-keys';
  static const _teamRankEndpoint =
      'https://api.z8vips.com/api/v1/football/competition/team-rank';
  static const _defaultLeagueLogoAsset = 'assets/images/login_logo.png';

  int _leagueIndex = 0;
  int _topIndex = 0;
  int _playerFilterIndex = 0;
  int _teamFilterIndex = 0;
  late final PageController _pageController;
  late final ScrollController _featuredLeaguesController;

  bool _loadingCompetitions = false;
  String? _competitionErrorText;
  List<_CompetitionItem> _competitions = const [];

  bool _loadingTable = false;
  String? _tableErrorText;
  List<_StandingRowData> _tableRows = const [];
  int _tableRequestSeq = 0;

  bool _loadingPlayerRankKeys = false;
  String? _playerRankKeysErrorText;
  List<_PlayerRankKey> _playerRankKeys = const [];

  bool _loadingPlayerRank = false;
  String? _playerRankErrorText;
  List<_PlayerRankRowData> _playerRankRows = const [];
  int _playerRankRequestSeq = 0;

  bool _loadingTeamRankKeys = false;
  String? _teamRankKeysErrorText;
  List<_PlayerRankKey> _teamRankKeys = const [];

  bool _loadingTeamRank = false;
  String? _teamRankErrorText;
  List<_TeamRankRowData> _teamRankRows = const [];
  int _teamRankRequestSeq = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageController = PageController(initialPage: _topIndex);
    _featuredLeaguesController = ScrollController();
    _fetchCompetitions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    _featuredLeaguesController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_competitions.isEmpty || _competitionErrorText != null) {
        _fetchCompetitions();
      }
    }
  }

  void _selectCompetitionIndex(int index) {
    if (_competitions.isEmpty) return;
    if (index < 0 || index >= _competitions.length) return;
    final item = _competitions[index];
    setState(() => _leagueIndex = index);
    _fetchCompetitionTable(item.id);
    _refreshPlayerRankForCompetition(item.id);
    _refreshTeamRankForCompetition(item.id);
  }

  void _scrollToFeaturedLeague(int index) {
    if (!_featuredLeaguesController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToFeaturedLeague(index);
      });
      return;
    }
    final itemWidth = 78.0;
    final separator = 22.0;
    final padding = 16.0;
    final viewport = _featuredLeaguesController.position.viewportDimension;
    final targetCenter =
        padding + index * (itemWidth + separator) + itemWidth / 2;
    final offset = (targetCenter - viewport / 2)
        .clamp(
          _featuredLeaguesController.position.minScrollExtent,
          _featuredLeaguesController.position.maxScrollExtent,
        )
        .toDouble();
    _featuredLeaguesController.animateTo(
      offset,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  Future<void> _openAllLeagues() async {
    final selectedIndex =
        _leagueIndex >= 0 && _leagueIndex < _competitions.length
            ? _leagueIndex
            : 0;
    final selectedCompetitionId =
        _competitions.isNotEmpty ? _competitions[selectedIndex].id : null;
    final result = await Navigator.of(context).push<_AllLeaguesResult>(
      MaterialPageRoute(
        builder: (_) => _AllLeaguesPage(
          competitions: _competitions,
          selectedCompetitionId: selectedCompetitionId,
        ),
      ),
    );
    if (!mounted || result == null) return;
    final idx = _competitions.indexWhere((e) => e.id == result.competitionId);
    if (idx < 0) return;
    _selectCompetitionIndex(idx);
    _scrollToFeaturedLeague(idx);
  }

  @override
  Widget build(BuildContext context) {
    final safeCompetitionIndex = _competitions.isNotEmpty && _leagueIndex >= 0
        ? (_leagueIndex < _competitions.length ? _leagueIndex : 0)
        : 0;
    final safeDemoIndex = _leagueIndex >= 0
        ? (_leagueIndex < _demoLeagues.length ? _leagueIndex : 0)
        : 0;
    final leagueName = _competitions.isNotEmpty
        ? _competitions[safeCompetitionIndex].name
        : _demoLeagues[safeDemoIndex].name;
    final competitionId = _competitions.isNotEmpty
        ? _competitions[safeCompetitionIndex].id
        : null;

    return Stack(
      children: [
        const _LeaguesBackground(),
        SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Featured leagues',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _openAllLeagues,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF00E676),
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'All leagues',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(height: 96, child: _buildTopLeagues()),
              const SizedBox(height: 10),
              _UnderlineTabs(
                index: _topIndex,
                onChanged: (v) {
                  setState(() => _topIndex = v);
                  _maybeLoadForTab(v, competitionId);
                  _pageController.animateToPage(
                    v,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                  );
                },
                items: const ['Points', "Players' Rankings", 'Team Rankings'],
              ),
              const SizedBox(height: 12),
              if (_topIndex == 1)
                _buildPlayerRankFilters(competitionId)
              else if (_topIndex == 2)
                _buildTeamRankFilters(competitionId)
              else
                const SizedBox.shrink(),
              const SizedBox(height: 16),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (v) {
                    setState(() => _topIndex = v);
                    _maybeLoadForTab(v, competitionId);
                  },
                  children: [
                    _PointsPanel(
                      competitionId: competitionId,
                      leagueName: leagueName,
                      loading: _loadingTable,
                      errorText: _tableErrorText,
                      rows: _tableRows,
                      onRetry: competitionId == null
                          ? null
                          : () => _fetchCompetitionTable(competitionId),
                    ),
                    _PlayersPanel(
                      title: _selectedPlayerRankName,
                      loading: _loadingPlayerRank,
                      errorText: _playerRankErrorText,
                      rows: _playerRankRows,
                      onRetry: competitionId == null
                          ? null
                          : () => _fetchPlayerRankRows(
                                competitionId: competitionId,
                                key: _selectedPlayerRankKey,
                              ),
                    ),
                    _TeamRankPanel(
                      title: _selectedTeamRankName,
                      competitionId: competitionId,
                      loading: _loadingTeamRank,
                      errorText: _teamRankErrorText,
                      rows: _teamRankRows,
                      onRetry: competitionId == null
                          ? null
                          : () => _fetchTeamRankRows(
                                competitionId: competitionId,
                                key: _selectedTeamRankKey,
                              ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTopLeagues() {
    if (_loadingCompetitions && _competitions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_competitions.isEmpty && _competitionErrorText == null) {
      return const NoDataPlaceholder(message: 'No leagues available');
    }

    if (_competitions.isEmpty && _competitionErrorText != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _competitionErrorText!,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.75)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 36,
                child: ElevatedButton(
                  onPressed: _fetchCompetitions,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.10),
                    foregroundColor: Colors.white.withValues(alpha: 0.9),
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
          ),
        ),
      );
    }

    final items = _competitions;
    final selectedIndex =
        _leagueIndex >= 0 && _leagueIndex < items.length ? _leagueIndex : 0;

    return ListView.separated(
      controller: _featuredLeaguesController,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      scrollDirection: Axis.horizontal,
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(width: 22),
      itemBuilder: (context, index) {
        final item = items[index];
        final color = _leagueColors[index % _leagueColors.length];
        return _LeagueChip(
          name: item.name,
          selected: index == selectedIndex,
          color: color,
          logoUrl: item.logo,
          defaultLogoAsset: _defaultLeagueLogoAsset,
          onTap: () {
            _selectCompetitionIndex(index);
          },
        );
      },
    );
  }

  String get _selectedPlayerRankKey {
    if (_playerRankKeys.isEmpty) return 'k_goals';
    final safeIndex = _playerFilterIndex >= 0
        ? (_playerFilterIndex < _playerRankKeys.length ? _playerFilterIndex : 0)
        : 0;
    return _playerRankKeys[safeIndex].key;
  }

  String get _selectedPlayerRankName {
    if (_playerRankKeys.isEmpty) return 'Top scorers';
    final safeIndex = _playerFilterIndex >= 0
        ? (_playerFilterIndex < _playerRankKeys.length ? _playerFilterIndex : 0)
        : 0;
    return _playerRankKeys[safeIndex].name;
  }

  void _maybeLoadForTab(int tabIndex, int? competitionId) {
    if (competitionId == null) return;
    if (tabIndex == 1) {
      _refreshPlayerRankForCompetition(competitionId);
      return;
    }
    if (tabIndex == 2) {
      _refreshTeamRankForCompetition(competitionId);
      return;
    }
  }

  void _refreshPlayerRankForCompetition(int competitionId) {
    _ensurePlayerRankKeysLoaded(competitionId);
    _fetchPlayerRankRows(
      competitionId: competitionId,
      key: _selectedPlayerRankKey,
    );
  }

  String get _selectedTeamRankKey {
    final keys =
        _teamRankKeys.isNotEmpty ? _teamRankKeys : _fallbackTeamRankKeys;
    final safeIndex = _teamFilterIndex >= 0
        ? (_teamFilterIndex < keys.length ? _teamFilterIndex : 0)
        : 0;
    return keys[safeIndex].key;
  }

  String get _selectedTeamRankName {
    final keys =
        _teamRankKeys.isNotEmpty ? _teamRankKeys : _fallbackTeamRankKeys;
    final safeIndex = _teamFilterIndex >= 0
        ? (_teamFilterIndex < keys.length ? _teamFilterIndex : 0)
        : 0;
    return keys[safeIndex].name;
  }

  void _refreshTeamRankForCompetition(int competitionId) {
    _ensureTeamRankKeysLoaded();
    _fetchTeamRankRows(competitionId: competitionId, key: _selectedTeamRankKey);
  }

  Future<void> _fetchCompetitions() async {
    if (_loadingCompetitions) return;
    setState(() {
      _loadingCompetitions = true;
      _competitionErrorText = null;
    });

    try {
      final uri = Uri.parse(_competitionEndpoint);
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('http ${response.statusCode}');
      }

      final decoded = _tryDecodeJson(response.bodyBytes);
      if (decoded is! Map) {
        throw Exception('invalid json');
      }
      final code = decoded['code'];
      final data = decoded['data'];
      if (code != 0 || data is! List) {
        throw Exception('invalid response');
      }

      final List<_CompetitionItem> items = [];
      for (final raw in data) {
        if (raw is! Map) continue;
        final id = int.tryParse((raw['id'] ?? '').toString());
        final name = (raw['name'] ?? '').toString().trim();
        if (id == null || name.isEmpty) continue;
        final logo = _sanitizeUrl(raw['logo']);
        items.add(
          _CompetitionItem(
            id: id,
            name: name,
            logo: logo.isEmpty ? null : logo,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _competitions = items;
        if (_leagueIndex >= _competitions.length) _leagueIndex = 0;
      });
      if (items.isNotEmpty) {
        _fetchCompetitionTable(items[0].id);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _competitionErrorText = '联赛列表加载失败，请重试';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingCompetitions = false;
        });
      } else {
        _loadingCompetitions = false;
      }
    }
  }

  Future<void> _fetchCompetitionTable(int competitionId) async {
    final requestId = ++_tableRequestSeq;
    setState(() {
      _loadingTable = true;
      _tableErrorText = null;
    });

    try {
      final uri = Uri.parse(_competitionTableEndpoint).replace(
        queryParameters: {
          'competition_id': competitionId.toString(),
          'CompetitionId': competitionId.toString(),
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
      final code = decoded['code'];
      final data = decoded['data'];
      if (code != 0 || data is! Map) {
        throw Exception('invalid response');
      }

      final isGroup = data['is_group'] == true;
      final List rawList;
      if (isGroup) {
        final groups = data['groups'];
        if (groups is List) {
          final flattened = <dynamic>[];
          for (final g in groups) {
            if (g is List) {
              flattened.addAll(g);
            }
          }
          rawList = flattened;
        } else {
          rawList = const [];
        }
      } else {
        final tables = data['tables'];
        final list = tables is Map ? tables['all'] : null;
        rawList = list is List ? list : const [];
      }

      final List<_StandingRowData> rows = [];
      for (final raw in rawList) {
        if (raw is! Map) continue;
        final teamId = _toNullableId(raw['team_id'] ?? raw['teamId']);
        final team =
            (raw['team_name'] ?? raw['teamName'] ?? '').toString().trim();
        if (team.isEmpty) continue;
        final position = _toInt(raw['position']);
        final w = _toInt(raw['won']);
        final d = _toInt(raw['drawn']);
        final l = _toInt(raw['lost']);
        final pts = _toInt(raw['pts']);
        final logo = _sanitizeUrl(raw['team_logo'] ?? raw['teamLogo']);
        rows.add(
          _StandingRowData(
            teamId: teamId,
            position: position,
            team: team,
            w: w,
            d: d,
            l: l,
            points: pts,
            logoUrl: logo.isEmpty ? null : logo,
          ),
        );
      }

      if (!mounted || requestId != _tableRequestSeq) return;
      setState(() {
        _tableRows = rows;
      });
    } catch (_) {
      if (!mounted || requestId != _tableRequestSeq) return;
      setState(() {
        _tableErrorText = '积分榜加载失败，请重试';
        _tableRows = const [];
      });
    } finally {
      if (mounted && requestId == _tableRequestSeq) {
        setState(() {
          _loadingTable = false;
        });
      } else if (requestId == _tableRequestSeq) {
        _loadingTable = false;
      }
    }
  }

  Widget _buildPlayerRankFilters(int? competitionId) {
    if (_loadingPlayerRankKeys && _playerRankKeys.isEmpty) {
      return const SizedBox(
        height: 38,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_playerRankKeys.isEmpty && _playerRankKeysErrorText != null) {
      return SizedBox(
        height: 38,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _playerRankKeysErrorText!,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            ),
            const SizedBox(width: 12),
            if (competitionId != null)
              SizedBox(
                height: 30,
                child: ElevatedButton(
                  onPressed: () => _ensurePlayerRankKeysLoaded(competitionId),
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
      );
    }

    final keys =
        _playerRankKeys.isNotEmpty ? _playerRankKeys : _fallbackPlayerRankKeys;
    final safeIndex = _playerFilterIndex >= 0
        ? (_playerFilterIndex < keys.length ? _playerFilterIndex : 0)
        : 0;

    return _PlayerFilters(
      index: safeIndex,
      onChanged: (v) {
        setState(() => _playerFilterIndex = v);
        final id = competitionId;
        if (id != null) {
          _fetchPlayerRankRows(competitionId: id, key: keys[v].key);
        }
      },
      items: keys.map((e) => e.name).toList(growable: false),
    );
  }

  Future<void> _ensurePlayerRankKeysLoaded(int competitionId) async {
    if (_loadingPlayerRankKeys) return;
    if (_playerRankKeys.isNotEmpty) return;
    setState(() {
      _loadingPlayerRankKeys = true;
      _playerRankKeysErrorText = null;
    });

    try {
      final uri = Uri.parse(_competitionTableEndpoint).replace(
        queryParameters: {
          'competition_id': competitionId.toString(),
          'CompetitionId': competitionId.toString(),
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
      final code = decoded['code'];
      final data = decoded['data'];
      if (code != 0) {
        throw Exception('invalid response');
      }

      final List<_PlayerRankKey> items = [];
      if (data is List) {
        for (final raw in data) {
          if (raw is! Map) continue;
          final key = (raw['key'] ?? '').toString().trim();
          final name = (raw['name'] ?? '').toString().trim();
          if (key.isEmpty || name.isEmpty) continue;
          items.add(_PlayerRankKey(key: key, name: name));
        }
      }

      if (!mounted) return;
      setState(() {
        _playerRankKeys = items.isEmpty ? _fallbackPlayerRankKeys : items;
        if (_playerFilterIndex >= _playerRankKeys.length)
          _playerFilterIndex = 0;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _playerRankKeysErrorText = '排行榜类型加载失败';
        _playerRankKeys = _fallbackPlayerRankKeys;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingPlayerRankKeys = false;
        });
      } else {
        _loadingPlayerRankKeys = false;
      }
    }
  }

  Future<void> _fetchPlayerRankRows({
    required int competitionId,
    required String key,
  }) async {
    final requestId = ++_playerRankRequestSeq;
    setState(() {
      _loadingPlayerRank = true;
      _playerRankErrorText = null;
    });

    try {
      final uri = Uri.parse(_playerRankEndpoint).replace(
        queryParameters: {
          'competition_id': competitionId.toString(),
          'key': key,
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
      final code = decoded['code'];
      final data = decoded['data'];
      if (code != 0 || data is! List) {
        throw Exception('invalid response');
      }

      final List<_PlayerRankRowData> rows = [];
      for (final raw in data) {
        if (raw is! Map) continue;
        final playerId = _toNullableId(
          raw['player_id'] ?? raw['playerId'] ?? raw['id'],
        );
        final player = (raw['player_name'] ?? '').toString().trim();
        final team = (raw['team_name'] ?? '').toString().trim();
        if (player.isEmpty) continue;
        final position = _toInt(raw['position']);
        final valueText =
            (raw['value'] ?? raw['total'] ?? '').toString().trim();
        final playerLogo = _sanitizeUrl(raw['player_logo']);
        final teamLogo = _sanitizeUrl(raw['team_logo']);
        rows.add(
          _PlayerRankRowData(
            playerId: playerId,
            position: position,
            playerName: player,
            playerLogoUrl: playerLogo.isEmpty ? null : playerLogo,
            teamName: team,
            teamLogoUrl: teamLogo.isEmpty ? null : teamLogo,
            valueText: valueText,
          ),
        );
      }

      if (!mounted || requestId != _playerRankRequestSeq) return;
      setState(() {
        _playerRankRows = rows;
      });
    } catch (_) {
      if (!mounted || requestId != _playerRankRequestSeq) return;
      setState(() {
        _playerRankErrorText = '球员榜单加载失败，请重试';
        _playerRankRows = const [];
      });
    } finally {
      if (mounted && requestId == _playerRankRequestSeq) {
        setState(() {
          _loadingPlayerRank = false;
        });
      } else if (requestId == _playerRankRequestSeq) {
        _loadingPlayerRank = false;
      }
    }
  }

  Widget _buildTeamRankFilters(int? competitionId) {
    if (_loadingTeamRankKeys && _teamRankKeys.isEmpty) {
      return const SizedBox(
        height: 38,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_teamRankKeys.isEmpty && _teamRankKeysErrorText != null) {
      return SizedBox(
        height: 38,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _teamRankKeysErrorText!,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            ),
            const SizedBox(width: 12),
            SizedBox(
              height: 30,
              child: ElevatedButton(
                onPressed: _ensureTeamRankKeysLoaded,
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
      );
    }

    final keys =
        _teamRankKeys.isNotEmpty ? _teamRankKeys : _fallbackTeamRankKeys;
    final safeIndex = _teamFilterIndex >= 0
        ? (_teamFilterIndex < keys.length ? _teamFilterIndex : 0)
        : 0;

    return _PlayerFilters(
      index: safeIndex,
      onChanged: (v) {
        setState(() => _teamFilterIndex = v);
        final id = competitionId;
        if (id != null) {
          _fetchTeamRankRows(competitionId: id, key: keys[v].key);
        }
      },
      items: keys.map((e) => e.name).toList(growable: false),
    );
  }

  Future<void> _ensureTeamRankKeysLoaded() async {
    if (_loadingTeamRankKeys) return;
    if (_teamRankKeys.isNotEmpty) return;
    setState(() {
      _loadingTeamRankKeys = true;
      _teamRankKeysErrorText = null;
    });

    try {
      final uri = Uri.parse(_teamRankKeysEndpoint);
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('http ${response.statusCode}');
      }

      final decoded = _tryDecodeJson(response.bodyBytes);
      if (decoded is! Map) {
        throw Exception('invalid json');
      }
      final code = decoded['code'];
      final data = decoded['data'];
      if (code != 0 || data is! List) {
        throw Exception('invalid response');
      }

      final List<_PlayerRankKey> items = [];
      for (final raw in data) {
        if (raw is! Map) continue;
        final key = (raw['key'] ?? '').toString().trim();
        final name = (raw['name'] ?? '').toString().trim();
        if (key.isEmpty || name.isEmpty) continue;
        items.add(_PlayerRankKey(key: key, name: name));
      }

      if (!mounted) return;
      setState(() {
        _teamRankKeys = items.isEmpty ? _fallbackTeamRankKeys : items;
        if (_teamFilterIndex >= _teamRankKeys.length) _teamFilterIndex = 0;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _teamRankKeysErrorText = '排行榜类型加载失败';
        _teamRankKeys = _fallbackTeamRankKeys;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingTeamRankKeys = false;
        });
      } else {
        _loadingTeamRankKeys = false;
      }
    }
  }

  Future<void> _fetchTeamRankRows({
    required int competitionId,
    required String key,
  }) async {
    final requestId = ++_teamRankRequestSeq;
    setState(() {
      _loadingTeamRank = true;
      _teamRankErrorText = null;
    });

    try {
      final uri = Uri.parse(_teamRankEndpoint).replace(
        queryParameters: {
          'competition_id': competitionId.toString(),
          'key': key,
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
      final code = decoded['code'];
      final data = decoded['data'];
      if (code != 0 || data is! List) {
        throw Exception('invalid response');
      }

      final List<_TeamRankRowData> rows = [];
      for (final raw in data) {
        if (raw is! Map) continue;
        final teamId = _toNullableId(raw['team_id'] ?? raw['teamId']);
        final team = (raw['team_name'] ?? '').toString().trim();
        if (team.isEmpty) continue;
        final position = _toInt(raw['position']);
        final teamLogo = _sanitizeUrl(raw['team_logo']);
        final valueText =
            (raw['value'] ?? raw['total'] ?? '').toString().trim();
        rows.add(
          _TeamRankRowData(
            teamId: teamId,
            position: position,
            teamName: team,
            teamLogoUrl: teamLogo.isEmpty ? null : teamLogo,
            valueText: valueText,
          ),
        );
      }

      if (!mounted || requestId != _teamRankRequestSeq) return;
      setState(() {
        _teamRankRows = rows;
      });
    } catch (_) {
      if (!mounted || requestId != _teamRankRequestSeq) return;
      setState(() {
        _teamRankErrorText = '球队榜单加载失败，请重试';
        _teamRankRows = const [];
      });
    } finally {
      if (mounted && requestId == _teamRankRequestSeq) {
        setState(() {
          _loadingTeamRank = false;
        });
      } else if (requestId == _teamRankRequestSeq) {
        _loadingTeamRank = false;
      }
    }
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse((value ?? '').toString()) ?? 0;
  }

  int? _toNullableId(dynamic value) {
    if (value is int) return value > 0 ? value : null;
    if (value is double) return value > 0 ? value.round() : null;
    final parsed = int.tryParse((value ?? '').toString());
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  String _sanitizeUrl(dynamic value) {
    final raw = (value ?? '').toString();
    final cleaned = raw.replaceAll('`', '').trim();
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
}

class _PlayerFilters extends StatelessWidget {
  const _PlayerFilters({
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
      child: Align(
        alignment: Alignment.centerLeft,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (int i = 0; i < items.length; i++) ...[
                _PlayerFilterChip(
                  label: items[i],
                  selected: i == index,
                  onTap: () => onChanged(i),
                ),
                if (i != items.length - 1) const SizedBox(width: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerFilterChip extends StatelessWidget {
  const _PlayerFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? const Color(0xFF00E676)
        : Colors.white.withValues(alpha: 0.06);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: const Color(0xFF00E676).withValues(alpha: 0.20),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected
                    ? const Color(0xFF0B1E16)
                    : Colors.white.withValues(alpha: 0.9),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayersPanel extends StatelessWidget {
  const _PlayersPanel({
    required this.title,
    required this.loading,
    required this.errorText,
    required this.rows,
    required this.onRetry,
  });

  final String title;
  final bool loading;
  final String? errorText;
  final List<_PlayerRankRowData> rows;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        const SizedBox(height: 8),
        _PlayersTableCard(
          title: title,
          loading: loading,
          errorText: errorText,
          rows: rows,
          onRetry: onRetry,
        ),
      ],
    );
  }
}

class _TeamRankPanel extends StatelessWidget {
  const _TeamRankPanel({
    required this.title,
    required this.competitionId,
    required this.loading,
    required this.errorText,
    required this.rows,
    required this.onRetry,
  });

  final String title;
  final int? competitionId;
  final bool loading;
  final String? errorText;
  final List<_TeamRankRowData> rows;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        const SizedBox(height: 8),
        _TeamRankTableCard(
          title: title,
          competitionId: competitionId,
          loading: loading,
          errorText: errorText,
          rows: rows,
          onRetry: onRetry,
        ),
      ],
    );
  }
}

class _TeamRankTableCard extends StatelessWidget {
  const _TeamRankTableCard({
    required this.title,
    required this.competitionId,
    required this.loading,
    required this.errorText,
    required this.rows,
    required this.onRetry,
  });

  final String title;
  final int? competitionId;
  final bool loading;
  final String? errorText;
  final List<_TeamRankRowData> rows;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: Colors.white.withValues(alpha: 0.06),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 20,
            offset: const Offset(0, 12),
          ),
        ],
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Row(
              children: [
                Text(
                  '#',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Text(
                    'Team',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(
                  width: 52,
                  child: Text(
                    'Stats',
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Divider(
              height: 1,
              thickness: 1,
              color: Colors.white.withValues(alpha: 0.10),
            ),
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 22),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (errorText != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              child: Column(
                children: [
                  Text(
                    errorText!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  if (onRetry != null)
                    SizedBox(
                      height: 36,
                      child: ElevatedButton(
                        onPressed: onRetry,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.10),
                          foregroundColor: Colors.white.withValues(alpha: 0.9),
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
              ),
            )
          else if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: NoDataPlaceholder(message: 'No data'),
            )
          else
            for (int i = 0; i < rows.length; i++) ...[
              _TeamRankRow(
                rank: rows[i].position > 0 ? rows[i].position : i + 1,
                team: rows[i].teamName,
                teamLogoUrl: rows[i].teamLogoUrl,
                statsText: rows[i].valueText,
                badgeColor: _leagueColors[i % _leagueColors.length],
                onTap: rows[i].teamId == null || competitionId == null
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => LeagueDetailsPage(
                              teamId: rows[i].teamId!,
                              competitionId: competitionId!,
                              initialTeamName: rows[i].teamName,
                              initialTeamLogoUrl: rows[i].teamLogoUrl,
                            ),
                          ),
                        ),
              ),
              if (i != rows.length - 1)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                ),
            ],
        ],
      ),
    );
  }
}

class _TeamRankRow extends StatelessWidget {
  const _TeamRankRow({
    required this.rank,
    required this.team,
    required this.teamLogoUrl,
    required this.statsText,
    required this.badgeColor,
    required this.onTap,
  });

  final int rank;
  final String team;
  final String? teamLogoUrl;
  final String statsText;
  final Color badgeColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: Text(
                  '$rank',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 18),
              _TeamBadge(color: badgeColor, logoUrl: teamLogoUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  team,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(
                width: 52,
                child: Text(
                  statsText,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayersTableCard extends StatelessWidget {
  const _PlayersTableCard({
    required this.title,
    required this.loading,
    required this.errorText,
    required this.rows,
    required this.onRetry,
  });

  final String title;
  final bool loading;
  final String? errorText;
  final List<_PlayerRankRowData> rows;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: Colors.white.withValues(alpha: 0.06),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 20,
            offset: const Offset(0, 12),
          ),
        ],
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Row(
              children: [
                Text(
                  '#',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  flex: 3,
                  child: Text(
                    'Player',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'Team',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(
                  width: 52,
                  child: Text(
                    'Stats',
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Divider(
              height: 1,
              thickness: 1,
              color: Colors.white.withValues(alpha: 0.10),
            ),
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 22),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (errorText != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              child: Column(
                children: [
                  Text(
                    errorText!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  if (onRetry != null)
                    SizedBox(
                      height: 36,
                      child: ElevatedButton(
                        onPressed: onRetry,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.10),
                          foregroundColor: Colors.white.withValues(alpha: 0.9),
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
              ),
            )
          else if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: NoDataPlaceholder(message: 'No data'),
            )
          else
            for (int i = 0; i < rows.length; i++) ...[
              _PlayerRow(
                rank: rows[i].position > 0 ? rows[i].position : i + 1,
                player: rows[i].playerName,
                playerLogoUrl: rows[i].playerLogoUrl,
                team: rows[i].teamName,
                teamLogoUrl: rows[i].teamLogoUrl,
                statsText: rows[i].valueText,
                onTap: rows[i].playerId == null
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PlayerDetailsPage(
                              playerId: rows[i].playerId!,
                              playerName: rows[i].playerName,
                              playerLogoUrl: rows[i].playerLogoUrl,
                              teamName: rows[i].teamName,
                              teamLogoUrl: rows[i].teamLogoUrl,
                              statsText: rows[i].valueText,
                            ),
                          ),
                        ),
              ),
              if (i != rows.length - 1)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                ),
            ],
        ],
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.rank,
    required this.player,
    required this.playerLogoUrl,
    required this.team,
    required this.teamLogoUrl,
    required this.statsText,
    required this.onTap,
  });

  final int rank;
  final String player;
  final String? playerLogoUrl;
  final String team;
  final String? teamLogoUrl;
  final String statsText;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: Text(
                  '$rank',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                      ),
                      child: _PlayerAvatar(url: playerLogoUrl),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        player,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    _TeamLogoBadge(url: teamLogoUrl),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        team,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 52,
                child: Text(
                  statsText,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeaguesBackground extends StatelessWidget {
  const _LeaguesBackground();

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

class _LeagueChip extends StatelessWidget {
  const _LeagueChip({
    required this.name,
    required this.selected,
    required this.color,
    required this.logoUrl,
    required this.defaultLogoAsset,
    required this.onTap,
  });

  final String name;
  final bool selected;
  final Color color;
  final String? logoUrl;
  final String defaultLogoAsset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final circle = selected ? const Color(0xFF00E676) : Colors.white;

    return SizedBox(
      width: 78,
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(44),
              child: Ink(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: circle,
                  shape: BoxShape.circle,
                  boxShadow: selected
                      ? null
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 16,
                            offset: const Offset(0, 10),
                          ),
                        ],
                ),
                child: Center(
                  child: _LeagueLogo(
                    logoUrl: logoUrl,
                    defaultLogoAsset: defaultLogoAsset,
                    tintColor: selected ? const Color(0xFF0B1E16) : color,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _LeagueLogo extends StatelessWidget {
  const _LeagueLogo({
    required this.logoUrl,
    required this.defaultLogoAsset,
    required this.tintColor,
  });

  final String? logoUrl;
  final String defaultLogoAsset;
  final Color tintColor;

  @override
  Widget build(BuildContext context) {
    final url = (logoUrl ?? '').trim();
    if (url.isEmpty) {
      return Image.asset(
        defaultLogoAsset,
        width: 34,
        height: 34,
        fit: BoxFit.contain,
      );
    }

    return Image.network(
      url,
      width: 34,
      height: 34,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Image.asset(
        defaultLogoAsset,
        width: 34,
        height: 34,
        fit: BoxFit.contain,
      ),
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Icon(Icons.shield_outlined, size: 28, color: tintColor);
      },
    );
  }
}

class _UnderlineTabs extends StatelessWidget {
  const _UnderlineTabs({
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
                  child: _UnderlineTab(
                    label: items[i],
                    selected: i == index,
                    onTap: () => onChanged(i),
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
                  alignment: switch (index) {
                    0 => Alignment.centerLeft,
                    1 => Alignment.center,
                    _ => Alignment.centerRight,
                  },
                  child: FractionallySizedBox(
                    widthFactor: 1 / 3,
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

class _UnderlineTab extends StatelessWidget {
  const _UnderlineTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color =
        selected ? Colors.white : Colors.white.withValues(alpha: 0.35);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 30,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PointsPanel extends StatelessWidget {
  const _PointsPanel({
    required this.competitionId,
    required this.leagueName,
    required this.loading,
    required this.errorText,
    required this.rows,
    required this.onRetry,
  });

  final int? competitionId;
  final String leagueName;
  final bool loading;
  final String? errorText;
  final List<_StandingRowData> rows;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        const SizedBox(height: 8),
        const Text(
          'Champions League league stage',
          style: TextStyle(
            color: Color(0xFF00E676),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 14),
        _TableCard(
          title: leagueName,
          competitionId: competitionId,
          loading: loading,
          errorText: errorText,
          rows: rows,
          onRetry: onRetry,
        ),
      ],
    );
  }
}

class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.title,
    required this.competitionId,
    required this.loading,
    required this.errorText,
    required this.rows,
    required this.onRetry,
  });

  final String title;
  final int? competitionId;
  final bool loading;
  final String? errorText;
  final List<_StandingRowData> rows;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: Colors.white.withValues(alpha: 0.06),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 20,
            offset: const Offset(0, 12),
          ),
        ],
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Row(
              children: [
                Text(
                  '#',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Text(
                    'Team',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _HeaderNum('W'),
                _HeaderNum('D'),
                _HeaderNum('L'),
                const SizedBox(width: 10),
                SizedBox(
                  width: 54,
                  child: Text(
                    'Points',
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Divider(
              height: 1,
              thickness: 1,
              color: Colors.white.withValues(alpha: 0.10),
            ),
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 22),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (errorText != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              child: Column(
                children: [
                  Text(
                    errorText!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  if (onRetry != null)
                    SizedBox(
                      height: 36,
                      child: ElevatedButton(
                        onPressed: onRetry,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.10),
                          foregroundColor: Colors.white.withValues(alpha: 0.9),
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
              ),
            )
          else if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: NoDataPlaceholder(message: 'No standings data'),
            )
          else
            for (int i = 0; i < rows.length; i++) ...[
              _RowItem(
                rank: rows[i].position > 0 ? rows[i].position : i + 1,
                team: rows[i].team,
                w: rows[i].w,
                d: rows[i].d,
                l: rows[i].l,
                points: rows[i].points,
                teamLogoUrl: rows[i].logoUrl,
                badgeColor: _leagueColors[i % _leagueColors.length],
                onTap: rows[i].teamId == null || competitionId == null
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => LeagueDetailsPage(
                              teamId: rows[i].teamId!,
                              competitionId: competitionId!,
                              initialTeamName: rows[i].team,
                              initialTeamLogoUrl: rows[i].logoUrl,
                            ),
                          ),
                        ),
              ),
              if (i != rows.length - 1)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                ),
            ],
        ],
      ),
    );
  }
}

class _HeaderNum extends StatelessWidget {
  const _HeaderNum(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.35),
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _RowItem extends StatelessWidget {
  const _RowItem({
    required this.rank,
    required this.team,
    required this.w,
    required this.d,
    required this.l,
    required this.points,
    required this.teamLogoUrl,
    required this.badgeColor,
    required this.onTap,
  });

  final int rank;
  final String team;
  final int w;
  final int d;
  final int l;
  final int points;
  final String? teamLogoUrl;
  final Color badgeColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: Text(
                  '$rank',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              _TeamBadge(color: badgeColor, logoUrl: teamLogoUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  team,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _CellNum(w),
              _CellNum(d),
              _CellNum(l),
              const SizedBox(width: 10),
              SizedBox(
                width: 54,
                child: Text(
                  '$points',
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CellNum extends StatelessWidget {
  const _CellNum(this.value);

  final int value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34,
      child: Text(
        '$value',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _TeamBadge extends StatelessWidget {
  const _TeamBadge({required this.color, required this.logoUrl});

  final Color color;
  final String? logoUrl;

  @override
  Widget build(BuildContext context) {
    final url = (logoUrl ?? '').trim();
    if (url.isNotEmpty) {
      return Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 14,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipOval(
          child: Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Center(
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

class _PlayerAvatar extends StatelessWidget {
  const _PlayerAvatar({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final raw = (url ?? '').trim();
    if (raw.isEmpty) {
      return Center(
        child: Icon(
          Icons.person_rounded,
          size: 18,
          color: Colors.white.withValues(alpha: 0.55),
        ),
      );
    }

    return ClipOval(
      child: Image.network(
        raw,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Center(
          child: Icon(
            Icons.person_rounded,
            size: 18,
            color: Colors.white.withValues(alpha: 0.55),
          ),
        ),
      ),
    );
  }
}

class _TeamLogoBadge extends StatelessWidget {
  const _TeamLogoBadge({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final raw = (url ?? '').trim();
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: raw.isEmpty
          ? Center(
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
              ),
            )
          : ClipOval(
              child: Image.network(
                raw,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Center(
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class _LeagueData {
  const _LeagueData(this.name, this.color);

  final String name;
  final Color color;
}

class _StandingRowData {
  const _StandingRowData({
    required this.teamId,
    required this.position,
    required this.team,
    required this.w,
    required this.d,
    required this.l,
    required this.points,
    required this.logoUrl,
  });

  final int? teamId;
  final int position;
  final String team;
  final int w;
  final int d;
  final int l;
  final int points;
  final String? logoUrl;
}

class _PlayerRankKey {
  const _PlayerRankKey({required this.key, required this.name});

  final String key;
  final String name;
}

const _fallbackPlayerRankKeys = [
  _PlayerRankKey(key: 'k_goals', name: '射手榜'),
  _PlayerRankKey(key: 'k_assists', name: '助攻榜'),
  _PlayerRankKey(key: 'k_shots', name: '射门'),
  _PlayerRankKey(key: 'k_shots_on', name: '射正'),
  _PlayerRankKey(key: 'k_passes', name: '传球'),
  _PlayerRankKey(key: 'k_passes_accuracy', name: '成功传球'),
  _PlayerRankKey(key: 'k_key', name: '关键传球'),
  _PlayerRankKey(key: 'k_interception', name: '拦截'),
  _PlayerRankKey(key: 'k_blocked', name: '封堵'),
  _PlayerRankKey(key: 'k_clearances', name: '解围'),
  _PlayerRankKey(key: 'k_saves', name: '扑救'),
  _PlayerRankKey(key: 'k_yellow', name: '黄牌'),
  _PlayerRankKey(key: 'k_red', name: '红牌'),
  _PlayerRankKey(key: 'k_minutes', name: '出场时间'),
];

const _fallbackTeamRankKeys = [
  _PlayerRankKey(key: 'k_goals', name: '进球'),
  _PlayerRankKey(key: 'k_assists', name: '失球'),
  _PlayerRankKey(key: 'k_penalty', name: '获得点球'),
  _PlayerRankKey(key: 'k_shots', name: '射门'),
  _PlayerRankKey(key: 'k_shots_on', name: '射正'),
  _PlayerRankKey(key: 'k_key', name: '关键传球'),
  _PlayerRankKey(key: 'k_interception', name: '拦截'),
  _PlayerRankKey(key: 'k_blocked', name: '封堵'),
  _PlayerRankKey(key: 'k_clearances', name: '解围'),
  _PlayerRankKey(key: 'k_yellow', name: '黄牌'),
  _PlayerRankKey(key: 'k_red', name: '红牌'),
];

class _PlayerRankRowData {
  const _PlayerRankRowData({
    required this.playerId,
    required this.position,
    required this.playerName,
    required this.playerLogoUrl,
    required this.teamName,
    required this.teamLogoUrl,
    required this.valueText,
  });

  final int? playerId;
  final int position;
  final String playerName;
  final String? playerLogoUrl;
  final String teamName;
  final String? teamLogoUrl;
  final String valueText;
}

class _TeamRankRowData {
  const _TeamRankRowData({
    required this.teamId,
    required this.position,
    required this.teamName,
    required this.teamLogoUrl,
    required this.valueText,
  });

  final int? teamId;
  final int position;
  final String teamName;
  final String? teamLogoUrl;
  final String valueText;
}

const _demoLeagues = [
  _LeagueData('Premier Le...', Color(0xFF3F51B5)),
  _LeagueData('La Liga', Color(0xFFF44336)),
  _LeagueData('Serie A', Color(0xFF1565C0)),
  _LeagueData('Bundesliga', Color(0xFFD32F2F)),
  _LeagueData('Ligue 1', Color(0xFF512DA8)),
];

const _leagueColors = [
  Color(0xFF3F51B5),
  Color(0xFFF44336),
  Color(0xFF1565C0),
  Color(0xFFD32F2F),
  Color(0xFF512DA8),
];

class _CompetitionItem {
  const _CompetitionItem({
    required this.id,
    required this.name,
    required this.logo,
  });

  final int id;
  final String name;
  final String? logo;
}

class _AllLeaguesResult {
  const _AllLeaguesResult({required this.competitionId});
  final int competitionId;
}

class _AllLeaguesPage extends StatefulWidget {
  const _AllLeaguesPage({
    required this.competitions,
    required this.selectedCompetitionId,
  });

  final List<_CompetitionItem> competitions;
  final int? selectedCompetitionId;

  @override
  State<_AllLeaguesPage> createState() => _AllLeaguesPageState();
}

class _AllLeaguesPageState extends State<_AllLeaguesPage> {
  late int? _selectedCompetitionId;

  @override
  void initState() {
    super.initState();
    _selectedCompetitionId = widget.selectedCompetitionId;
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.competitions;
    return Scaffold(
      backgroundColor: const Color(0xFF071813),
      body: Stack(
        children: [
          const _LeaguesBackground(),
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
                      const Spacer(),
                      const Text(
                        'All leagues',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      const SizedBox(width: 38, height: 38),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: Text(
                            '暂无联赛数据',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 14,
                            childAspectRatio: 1.55,
                          ),
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];
                            final selected = item.id == _selectedCompetitionId;
                            return _AllLeagueTile(
                              name: item.name,
                              logoUrl: item.logo,
                              selected: selected,
                              defaultLogoAsset: 'assets/images/login_logo.png',
                              onTap: () {
                                setState(
                                  () => _selectedCompetitionId = item.id,
                                );
                                Navigator.of(context).pop(
                                  _AllLeaguesResult(competitionId: item.id),
                                );
                              },
                            );
                          },
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

class _AllLeagueTile extends StatelessWidget {
  const _AllLeagueTile({
    required this.name,
    required this.logoUrl,
    required this.selected,
    required this.defaultLogoAsset,
    required this.onTap,
  });

  final String name;
  final String? logoUrl;
  final bool selected;
  final String defaultLogoAsset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final border = selected
        ? Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.65))
        : Border.all(color: Colors.white.withValues(alpha: 0.06));
    final bg = selected
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.white.withValues(alpha: 0.06);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(18),
            border: border,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF00E676)
                        : Colors.white.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: _LeagueLogo(
                      logoUrl: logoUrl,
                      defaultLogoAsset: defaultLogoAsset,
                      tintColor:
                          selected ? const Color(0xFF0B1E16) : Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                    ),
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
