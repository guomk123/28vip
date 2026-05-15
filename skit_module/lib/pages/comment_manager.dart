import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LocalComment {
  final String id;
  final String objectId;
  final String content;
  final String userName;
  final String? userAvatar;
  final String createdAt;

  LocalComment({
    required this.id,
    required this.objectId,
    required this.content,
    required this.userName,
    this.userAvatar,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'objectId': objectId,
        'content': content,
        'userName': userName,
        'userAvatar': userAvatar,
        'createdAt': createdAt,
      };

  factory LocalComment.fromJson(Map<String, dynamic> json) => LocalComment(
        id: json['id'],
        objectId: json['objectId'],
        content: json['content'],
        userName: json['userName'],
        userAvatar: json['userAvatar'],
        createdAt: json['createdAt'],
      );
}

class LocalCommentManager {
  static const _key = 'user_local_comments';

  static Future<List<LocalComment>> getComments(String objectId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    final allComments = raw.map((e) => LocalComment.fromJson(jsonDecode(e))).toList();
    return allComments.where((e) => e.objectId == objectId).toList();
  }

  static Future<void> addComment(LocalComment comment) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    raw.insert(0, jsonEncode(comment.toJson()));
    await prefs.setStringList(_key, raw);
  }
}
