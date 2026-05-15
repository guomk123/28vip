import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

extension _ColorWithValuesCompat on Color {
  Color withValues({double? alpha}) {
    if (alpha == null) return this;
    final a = alpha.clamp(0.0, 1.0);
    return withOpacity(a);
  }
}

class PlayerDetailsPage extends StatefulWidget {
  const PlayerDetailsPage({
    super.key,
    required this.playerId,
    required this.playerName,
    required this.playerLogoUrl,
    required this.teamName,
    required this.teamLogoUrl,
    required this.statsText,
  });

  final int playerId;
  final String playerName;
  final String? playerLogoUrl;
  final String teamName;
  final String? teamLogoUrl;
  final String statsText;

  @override
  State<PlayerDetailsPage> createState() => _PlayerDetailsPageState();
}

class _PlayerDetailsPageState extends State<PlayerDetailsPage> {
  static const _playerInfoEndpoint =
      'https://api.z8vips.com/api/v1/football/info';

  bool _loadingInfo = false;
  String? _infoErrorText;
  _PlayerInfo? _info;
  int _infoRequestSeq = 0;

  @override
  void initState() {
    super.initState();
    _fetchPlayerInfo();
  }

  Future<void> _fetchPlayerInfo() async {
    final requestId = ++_infoRequestSeq;
    setState(() {
      _loadingInfo = true;
      _infoErrorText = null;
    });

    try {
      final uri = Uri.parse(_playerInfoEndpoint).replace(
        queryParameters: {
          'id': widget.playerId.toString(),
          'Id': widget.playerId.toString(),
          'player_id': widget.playerId.toString(),
          'PlayerId': widget.playerId.toString(),
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
          (_toNullableText(data['short_name_en']) ??
                  _toNullableText(data['name_en']) ??
                  _toNullableText(data['short_name_zh']) ??
                  _toNullableText(data['name_zh']) ??
                  _toNullableText(data['player_name']) ??
                  _toNullableText(data['name']) ??
                  widget.playerName)
              .trim();
      final logo = _sanitizeUrl(
        data['logo'] ?? data['player_logo'] ?? data['player_img'],
      );
      final teamName =
          (_toNullableText(
                    data['team_name'] ?? data['club_name'] ?? data['teamName'],
                  ) ??
                  widget.teamName)
              .trim();
      final teamLogo = _sanitizeUrl(
        data['team_logo'] ?? data['club_logo'] ?? data['teamLogo'],
      );

      final nationality = _toNullableText(
        data['nationality'] ?? data['country_name'] ?? data['country'],
      );
      final jerseyNumber = _toNullableInt(
        data['shirt_number'] ??
            data['jersey_number'] ??
            data['shirtNumber'] ??
            data['number'],
      );
      final age = _toNullableInt(data['age']);
      final heightCm = _toNullableInt(data['height_cm'] ?? data['height']);
      final weightKg = _toNullableInt(data['weight_kg'] ?? data['weight']);
      final mainPosition = _toNullableText(
        data['position'] ?? data['position_name'] ?? data['main_position'],
      );
      final preferredFoot = _toNullableText(
        data['preferred_foot'] ?? data['foot'],
      );
      final contractUntil = _toNullableInt(
        data['contract_until'] ??
            data['contract_end_time'] ??
            data['contract_end'],
      );

      final marketValue = _toNullableInt(data['market_value'] ?? data['value']);
      final marketCurrency = _toNullableText(
        data['market_value_currency'] ?? data['currency'],
      );
      final valueText = _formatMarketValue(
        currency: marketCurrency,
        marketValue: marketValue,
        fallback: widget.statsText,
      );

      final rawTransfers = data['transfer_list'];
      final transfers = <_TransferItem>[];
      if (rawTransfers is List) {
        for (final raw in rawTransfers) {
          if (raw is! Map) continue;
          final timeText = _toNullableText(raw['transfer_time']);
          final date = _formatDateYmd(timeText);
          final desc = _toNullableText(raw['transfer_desc']) ?? '';
          final fromLogo = _sanitizeUrl(raw['from_team_logo']);
          final toLogo = _sanitizeUrl(raw['to_team_logo']);
          transfers.add(
            _TransferItem(
              transferDate: date,
              feeText: desc.isEmpty ? '-' : '$desc (unit:10k)',
              fromTeamLogoUrl: fromLogo.isEmpty ? null : fromLogo,
              toTeamLogoUrl: toLogo.isEmpty ? null : toLogo,
            ),
          );
        }
      }

      final info = _PlayerInfo(
        playerName: name.isEmpty ? widget.playerName : name,
        playerLogoUrl: logo.isEmpty ? widget.playerLogoUrl : logo,
        teamName: teamName.isEmpty ? widget.teamName : teamName,
        teamLogoUrl: teamLogo.isEmpty ? widget.teamLogoUrl : teamLogo,
        nationality: nationality,
        jerseyNumber: jerseyNumber,
        age: age,
        heightCm: heightCm,
        weightKg: weightKg,
        mainPosition: mainPosition,
        preferredFoot: preferredFoot,
        contractUntil: contractUntil,
        valueText: valueText,
        transfers: transfers,
      );

      if (!mounted || requestId != _infoRequestSeq) return;
      setState(() {
        _info = info;
      });
    } catch (_) {
      if (!mounted || requestId != _infoRequestSeq) return;
      setState(() {
        _infoErrorText = '球员信息加载失败，请重试';
      });
    } finally {
      if (mounted && requestId == _infoRequestSeq) {
        setState(() => _loadingInfo = false);
      } else if (requestId == _infoRequestSeq) {
        _loadingInfo = false;
      }
    }
  }

  String _sanitizeUrl(dynamic value) {
    final raw = (value ?? '').toString();
    return raw.replaceAll('`', '').trim();
  }

  String? _toNullableText(dynamic value) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? null : text;
  }

  int? _toNullableInt(dynamic value) {
    if (value is int) return value > 0 ? value : null;
    if (value is double) return value > 0 ? value.round() : null;
    final raw = (value ?? '').toString();
    final onlyDigits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    final parsed = int.tryParse(onlyDigits);
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  String _formatDateYmd(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return '-';
    final dt = DateTime.tryParse(text);
    if (dt == null) return '-';
    final local = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }

  String _formatDateSlashFromUnixSeconds(int? seconds) {
    if (seconds == null || seconds <= 0) return '-';
    final dt = DateTime.fromMillisecondsSinceEpoch(
      seconds * 1000,
      isUtc: true,
    ).toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}/${two(dt.month)}/${two(dt.day)}';
  }

  String _formatMarketValue({
    required String? currency,
    required int? marketValue,
    required String fallback,
  }) {
    final c = (currency ?? '').trim();
    final v = marketValue;
    if (v == null || v <= 0) {
      final raw = fallback.trim();
      return raw.isEmpty ? '-' : raw;
    }
    final unit = 100000000;
    final num = v / unit;
    final numText = (num % 1 == 0)
        ? num.toStringAsFixed(0)
        : num.toStringAsFixed(1);
    final prefix = c.isEmpty ? '' : c;
    return '$prefix$numText (unit:100M)';
  }

  String _mapFoot(dynamic value) {
    final v = _toNullableInt(value);
    if (v == 1) return 'Left';
    if (v == 2) return 'Right';
    return '-';
  }

  String _mapPosition(String? code) {
    final v = (code ?? '').trim().toUpperCase();
    return switch (v) {
      'F' || 'FW' => 'forward',
      'M' || 'MF' => 'midfield',
      'D' || 'DF' => 'defender',
      'G' || 'GK' => 'goalkeeper',
      _ => '-',
    };
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

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final playerName = (info?.playerName ?? widget.playerName).trim();
    final playerLogoUrl = info?.playerLogoUrl ?? widget.playerLogoUrl;
    final teamName = (info?.teamName ?? widget.teamName).trim();
    final teamLogoUrl = info?.teamLogoUrl ?? widget.teamLogoUrl;
    final safeNationality = (info?.nationality ?? '').trim();

    final jerseyNumber = info?.jerseyNumber;
    final jersey = jerseyNumber != null && jerseyNumber > 0
        ? 'Jersey #$jerseyNumber'
        : 'Jersey # -';
    final age = info?.age;
    final heightCm = info?.heightCm;
    final weightKg = info?.weightKg;
    final ageText = age != null && age > 0 ? '$age y/o' : '-';
    final heightText = heightCm != null && heightCm > 0 ? '${heightCm}cm' : '-';
    final weightText = weightKg != null && weightKg > 0 ? '${weightKg}kg' : '-';
    final positionText = (info?.mainPosition ?? '').trim().isEmpty
        ? '-'
        : _mapPosition((info?.mainPosition ?? '').trim());
    final footText = _mapFoot(info?.preferredFoot);
    final contractText = _formatDateSlashFromUnixSeconds(info?.contractUntil);
    final valueText = (info?.valueText ?? widget.statsText).trim();
    final transfers = info?.transfers ?? const <_TransferItem>[];

    return Scaffold(
      body: Stack(
        children: [
          const _PlayerDetailsBackground(),
          SafeArea(
            top: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 132, 16, 24),
              children: [
                if (_loadingInfo && info == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_infoErrorText != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        color: Colors.white.withValues(alpha: 0.06),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.06),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _infoErrorText!,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.75),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            height: 34,
                            child: ElevatedButton(
                              onPressed: _fetchPlayerInfo,
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
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              child: const Text('重试'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                _TopProfileCard(
                  playerName: playerName,
                  playerLogoUrl: playerLogoUrl,
                  teamName: teamName,
                  teamLogoUrl: teamLogoUrl,
                  nationality: safeNationality.isEmpty ? null : safeNationality,
                  jerseyText: jersey,
                  ageText: ageText,
                  heightText: heightText,
                  weightText: weightText,
                ),
                const SizedBox(height: 14),
                _ValueCard(valueText: valueText.isEmpty ? '-' : valueText),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _MiniInfoCard(
                        iconAsset: 'assets/images/player_changdi_icon.png',
                        title: positionText,
                        subtitle: 'Main position',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _MiniInfoCard(
                        iconAsset: 'assets/images/player_footer_icon.png',
                        title: footText,
                        subtitle: 'Foot',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _MiniInfoCard(
                        iconAsset: 'assets/images/player_time_icon.png',
                        title: contractText,
                        subtitle: 'Contract until',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'Transfers',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '(in EUR)',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _TransfersCard(transfers: transfers),
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

class _PlayerDetailsBackground extends StatelessWidget {
  const _PlayerDetailsBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Image.asset(
            'assets/images/player_detail_top.png',
            fit: BoxFit.fitWidth,
            alignment: Alignment.topCenter,
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.06),
                  const Color(0xFF071813).withValues(alpha: 0.92),
                ],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: ColoredBox(color: Colors.black.withValues(alpha: 0.18)),
        ),
      ],
    );
  }
}

class _PlayerInfo {
  const _PlayerInfo({
    required this.playerName,
    required this.playerLogoUrl,
    required this.teamName,
    required this.teamLogoUrl,
    required this.valueText,
    required this.nationality,
    required this.jerseyNumber,
    required this.age,
    required this.heightCm,
    required this.weightKg,
    required this.mainPosition,
    required this.preferredFoot,
    required this.contractUntil,
    required this.transfers,
  });

  final String playerName;
  final String? playerLogoUrl;
  final String teamName;
  final String? teamLogoUrl;
  final String valueText;
  final String? nationality;
  final int? jerseyNumber;
  final int? age;
  final int? heightCm;
  final int? weightKg;
  final String? mainPosition;
  final String? preferredFoot;
  final int? contractUntil;
  final List<_TransferItem> transfers;
}

class _TopProfileCard extends StatelessWidget {
  const _TopProfileCard({
    required this.playerName,
    required this.playerLogoUrl,
    required this.teamName,
    required this.teamLogoUrl,
    required this.nationality,
    required this.jerseyText,
    required this.ageText,
    required this.heightText,
    required this.weightText,
  });

  final String playerName;
  final String? playerLogoUrl;
  final String teamName;
  final String? teamLogoUrl;
  final String? nationality;
  final String jerseyText;
  final String ageText;
  final String heightText;
  final String weightText;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: Colors.white.withValues(alpha: 0.06),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.20),
                blurRadius: 20,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (nationality != null)
                    _Pill(
                      label: nationality!,
                      bg: const Color(0xFFBCA51A).withValues(alpha: 0.28),
                      fg: const Color(0xFFE3D46B),
                    ),
                  if (nationality != null) const SizedBox(width: 10),
                  _Pill(
                    label: jerseyText,
                    bg: const Color(0xFF00E676).withValues(alpha: 0.16),
                    fg: const Color(0xFF00E676),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: _TeamLogoBadge(url: teamLogoUrl),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                playerName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _StatItem(label: 'Age', value: ageText),
                  ),
                  Expanded(
                    child: _StatItem(label: 'Height', value: heightText),
                  ),
                  Expanded(
                    child: _StatItem(label: 'Weight', value: weightText),
                  ),
                ],
              ),
            ],
          ),
        ),
        Positioned(top: -18, right: 10, child: _AvatarRing(url: playerLogoUrl)),
      ],
    );
  }
}

class _AvatarRing extends StatelessWidget {
  const _AvatarRing({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      height: 92,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF00E676),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00E676).withValues(alpha: 0.18),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.95),
            width: 2,
          ),
        ),
        child: ClipOval(
          child: _NetworkOrIcon(url: url, icon: Icons.person_rounded),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.bg, required this.fg});

  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ValueCard extends StatelessWidget {
  const _ValueCard({required this.valueText});

  final String valueText;

  @override
  Widget build(BuildContext context) {
    final raw = valueText.trim();
    final text = raw.isEmpty ? '-' : raw;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: const Color(0xFF0A1C16).withValues(alpha: 0.96),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.20),
            blurRadius: 20,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.max,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Image.asset(
                'assets/images/player_cup_icon.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Value',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniInfoCard extends StatelessWidget {
  const _MiniInfoCard({
    required this.iconAsset,
    required this.title,
    required this.subtitle,
  });

  final String iconAsset;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 96,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFF0B2019).withValues(alpha: 0.92),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: Image.asset(iconAsset, fit: BoxFit.contain),
          ),
          const Spacer(),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TransfersCard extends StatelessWidget {
  const _TransfersCard({required this.transfers});

  final List<_TransferItem> transfers;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 20,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Date',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  'Transfer',
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(
            height: 1,
            thickness: 1,
            color: Colors.white.withValues(alpha: 0.10),
          ),
          if (transfers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text(
                  '暂无转会记录',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )
          else
            for (int i = 0; i < transfers.length; i++) ...[
              _TransferRow(item: transfers[i]),
              if (i != transfers.length - 1)
                Divider(
                  height: 16,
                  thickness: 1,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
            ],
        ],
      ),
    );
  }
}

class _TransferItem {
  const _TransferItem({
    required this.transferDate,
    required this.feeText,
    required this.fromTeamLogoUrl,
    required this.toTeamLogoUrl,
  });

  final String transferDate;
  final String feeText;
  final String? fromTeamLogoUrl;
  final String? toTeamLogoUrl;
}

class _TransferRow extends StatelessWidget {
  const _TransferRow({required this.item});

  final _TransferItem item;

  @override
  Widget build(BuildContext context) {
    const badgeSize = 18.0;
    const arrowSize = 18.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              item.transferDate,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.center,
                    child: Text(
                      item.feeText,
                      maxLines: 1,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: badgeSize,
                  height: badgeSize,
                  child: _TeamLogoBadge(url: item.fromTeamLogoUrl),
                ),
                const SizedBox(width: 8),
                Container(
                  width: arrowSize,
                  height: arrowSize,
                  decoration: const BoxDecoration(
                    color: Color(0xFF00E676),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_forward_rounded,
                    size: 12,
                    color: Color(0xFF0B1E16),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: badgeSize,
                  height: badgeSize,
                  child: _TeamLogoBadge(url: item.toTeamLogoUrl),
                ),
              ],
            ),
          ),
        ],
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
    if (raw.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.shield_rounded,
          size: 14,
          color: Colors.white.withValues(alpha: 0.55),
        ),
      );
    }

    return ClipOval(
      child: Image.network(
        raw,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.shield_rounded,
            size: 14,
            color: Colors.white.withValues(alpha: 0.55),
          ),
        ),
      ),
    );
  }
}

class _NetworkOrIcon extends StatelessWidget {
  const _NetworkOrIcon({required this.url, required this.icon});

  final String? url;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final raw = (url ?? '').trim();
    if (raw.isEmpty) {
      return Center(
        child: Icon(
          icon,
          color: Colors.white.withValues(alpha: 0.60),
          size: 34,
        ),
      );
    }
    return Image.network(
      raw,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Center(
        child: Icon(
          icon,
          color: Colors.white.withValues(alpha: 0.60),
          size: 34,
        ),
      ),
    );
  }
}
