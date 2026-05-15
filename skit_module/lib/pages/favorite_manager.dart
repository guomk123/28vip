import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

enum FavoriteType { football, basketball }

class FavoriteItem {
  final int matchId;
  final FavoriteType type;
  final String homeTeamName;
  final String awayTeamName;
  final String? homeTeamLogoUrl;
  final String? awayTeamLogoUrl;
  final String? competitionName;
  final int? homeScore;
  final int? awayScore;
  final String? timeText;
  final String? periodText;

  FavoriteItem({
    required this.matchId,
    required this.type,
    required this.homeTeamName,
    required this.awayTeamName,
    this.homeTeamLogoUrl,
    this.awayTeamLogoUrl,
    this.competitionName,
    this.homeScore,
    this.awayScore,
    this.timeText,
    this.periodText,
  });

  Map<String, dynamic> toJson() => {
        'matchId': matchId,
        'type': type.index,
        'homeTeamName': homeTeamName,
        'awayTeamName': awayTeamName,
        'homeTeamLogoUrl': homeTeamLogoUrl,
        'awayTeamLogoUrl': awayTeamLogoUrl,
        'competitionName': competitionName,
        'homeScore': homeScore,
        'awayScore': awayScore,
        'timeText': timeText,
        'periodText': periodText,
      };

  factory FavoriteItem.fromJson(Map<String, dynamic> json) => FavoriteItem(
        matchId: json['matchId'],
        type: FavoriteType.values[json['type']],
        homeTeamName: json['homeTeamName'],
        awayTeamName: json['awayTeamName'],
        homeTeamLogoUrl: json['homeTeamLogoUrl'],
        awayTeamLogoUrl: json['awayTeamLogoUrl'],
        competitionName: json['competitionName'],
        homeScore: json['homeScore'],
        awayScore: json['awayScore'],
        timeText: json['timeText'],
        periodText: json['periodText'],
      );
}

class FavoriteManager {
  static const _key = 'user_favorites';

  static Future<List<FavoriteItem>> getFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    return raw.map((e) => FavoriteItem.fromJson(jsonDecode(e))).toList();
  }

  static Future<bool> isFavorite(int matchId, FavoriteType type) async {
    final list = await getFavorites();
    return list.any((e) => e.matchId == matchId && e.type == type);
  }

  static Future<void> toggleFavorite(FavoriteItem item) async {
    final list = await getFavorites();
    final idx = list.indexWhere((e) => e.matchId == item.matchId && e.type == item.type);
    if (idx >= 0) {
      list.removeAt(idx);
    } else {
      list.add(item);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, list.map((e) => jsonEncode(e.toJson())).toList());
  }
}
