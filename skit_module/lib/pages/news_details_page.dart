import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'common_widgets.dart';
import 'comment_manager.dart';
import 'login_page.dart';

class NewsDetailsPage extends StatefulWidget {
  const NewsDetailsPage({
    super.key,
    required this.id,
    required this.content,
    required this.h5Url,
  });

  final int id;
  final String content;
  final String h5Url;

  @override
  State<NewsDetailsPage> createState() => _NewsDetailsPageState();
}

class _NewsDetailsPageState extends State<NewsDetailsPage> {
  static const _detailEndpoint = 'https://api.z8vips.com/api/v1/info/detail';
  static const _commentListEndpoint =
      'https://api.z8vips.com/api/v1/comment/list';

  bool _loading = true;
  String? _errorText;
  String _html = '';

  final List<_CommentItem> _comments = [];
  bool _commentsLoading = false;
  String? _commentsError;

  @override
  void initState() {
    super.initState();
    _loadContent();
    _loadComments();
  }

  Future<void> _loadContent() async {
    setState(() {
      _loading = true;
      _errorText = null;
    });

    final firstContent = widget.content;
    if (firstContent.trim().isNotEmpty) {
      setState(() {
        _loading = false;
        _html = _sanitizeHtml(firstContent);
      });
      return;
    }

    try {
      final uri = Uri.parse('$_detailEndpoint?id=${widget.id}');
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('http ${response.statusCode}');
      }

      final decoded = _tryDecodeJson(response.bodyBytes);
      final data = decoded is Map ? decoded['data'] : null;
      if (data is! Map) {
        throw Exception('invalid json');
      }

      final htmlBody = (data['content'] ?? '').toString();
      if (htmlBody.trim().isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _html = _sanitizeHtml(htmlBody);
        });
        return;
      }

      throw Exception('empty content');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorText = '加载失败，请重试';
      });
    }
  }

  Future<void> _loadComments() async {
    setState(() {
      _commentsLoading = true;
      _commentsError = null;
    });

    try {
      final uri = Uri.parse('$_commentListEndpoint').replace(queryParameters: {
        'page': '1',
        'size': '20',
        'object_id': '${widget.id}',
      });
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('http ${response.statusCode}');
      }

      final decoded = _tryDecodeJson(response.bodyBytes);
      if (decoded is! Map) throw Exception('invalid json');

      final data = decoded['data'];
      final results = data is Map ? data['results'] : null;
      final List list = results is List ? results : const [];

      final List<_CommentItem> items = [];

      // 先加载本地评论
      final localComments =
          await LocalCommentManager.getComments('${widget.id}');
      for (final lc in localComments) {
        items.add(_CommentItem(
          id: lc.id,
          content: lc.content,
          userName: lc.userName,
          userAvatar: lc.userAvatar,
          createdAt: lc.createdAt,
        ));
      }

      for (final e in list) {
        if (e is! Map) continue;
        items.add(_CommentItem.fromJson(e));
      }

      if (!mounted) return;
      setState(() {
        _comments.clear();
        _comments.addAll(items);
        _commentsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _commentsLoading = false;
        _commentsError = '评论加载失败';
      });
    }
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

  String _sanitizeHtml(String html) {
    final noTicks = html.replaceAll('`', '');
    return noTicks.replaceAllMapped(
      RegExp(r'(src|href)\s*=\s*"([^"]*?)"', caseSensitive: false),
      (m) {
        final attr = m.group(1)!;
        final value = (m.group(2) ?? '').trim();
        return '$attr="$value"';
      },
    );
  }

  Future<void> _sendComment(String text) async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('is_logged_in') ?? false;

    if (!isLoggedIn) {
      if (!mounted) return;
      final result = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const LoginPage(fromProfile: true)),
      );
      if (result != true) return;
    }

    final name = prefs.getString('user_name') ?? 'Z8VIP User';
    final avatar = prefs.getString('user_avatar_path');
    final now = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();

    final newComment = LocalComment(
      id: 'local_${DateTime.now().millisecondsSinceEpoch}',
      objectId: '${widget.id}',
      content: text,
      userName: name,
      userAvatar: avatar,
      createdAt: now,
    );

    await LocalCommentManager.addComment(newComment);
    await _loadComments();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Comment posted successfully')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const _DetailsBackground(),
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
                        'News details',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const Spacer(),
                      _RoundIconButton(
                        icon: Icons.refresh_rounded,
                        onTap: () {
                          _loadContent();
                          _loadComments();
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      children: [
                        if (!_loading && _errorText == null)
                          ListView(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                            children: [
                              HtmlWidget(
                                _html,
                                textStyle: TextStyle(
                                  color: Colors.white.withOpacity(0.92),
                                  fontSize: 15.5,
                                  height: 1.55,
                                ),
                              ),
                              const SizedBox(height: 40),
                              _buildCommentSection(),
                            ],
                          ),
                        if (_loading)
                          const Positioned.fill(
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        if (_errorText != null && !_loading)
                          Positioned.fill(
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                ),
                                child: Text(
                                  _errorText!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.75),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                _CommentInputBar(onSend: _sendComment),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Comments',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF00E676).withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${_comments.length}',
                style: const TextStyle(
                  color: Color(0xFF00E676),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (_commentsLoading && _comments.isEmpty)
          const Center(child: CircularProgressIndicator())
        else if (_commentsError != null && _comments.isEmpty)
          Center(
            child: TextButton(
              onPressed: _loadComments,
              child: Text(
                _commentsError!,
                style: TextStyle(color: Colors.white.withOpacity(0.5)),
              ),
            ),
          )
        else if (_comments.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 48,
                    color: Colors.white.withOpacity(0.1),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No comments yet. Be the first!',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.3),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _comments.length,
            separatorBuilder: (_, __) => const SizedBox(height: 20),
            itemBuilder: (context, index) {
              final item = _comments[index];
              return _CommentTile(item: item);
            },
          ),
      ],
    );
  }
}

class _CommentItem {
  final String id;
  final String content;
  final String userName;
  final String? userAvatar;
  final String createdAt;

  _CommentItem({
    required this.id,
    required this.content,
    required this.userName,
    this.userAvatar,
    required this.createdAt,
  });

  factory _CommentItem.fromJson(Map json) {
    return _CommentItem(
      id: (json['id'] ?? '').toString(),
      content: (json['content'] ?? '').toString(),
      userName: (json['username'] ?? json['user_name'] ?? 'Guest').toString(),
      userAvatar: json['avatar'] ?? json['user_avatar'],
      createdAt: (json['created_at'] ?? '').toString(),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.item});

  final _CommentItem item;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            shape: BoxShape.circle,
          ),
          child: item.userAvatar != null && item.userAvatar!.isNotEmpty
              ? ClipOval(
                  child: Image.network(item.userAvatar!, fit: BoxFit.cover))
              : Icon(Icons.person_rounded,
                  color: Colors.white.withOpacity(0.3), size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    item.userName,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    _formatDate(item.createdAt),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.3),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                item.content,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDate(String raw) {
    if (raw.isEmpty) return '';
    try {
      final dt = DateTime.fromMillisecondsSinceEpoch(int.parse(raw) * 1000);
      return '${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw;
    }
  }
}

class _CommentInputBar extends StatefulWidget {
  const _CommentInputBar({required this.onSend});

  final ValueChanged<String> onSend;

  @override
  State<_CommentInputBar> createState() => _CommentInputBarState();
}

class _CommentInputBarState extends State<_CommentInputBar> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1E16),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.06)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(22),
              ),
              child: TextField(
                controller: _controller,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Say something...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () {
              final text = _controller.text.trim();
              if (text.isNotEmpty) {
                widget.onSend(text);
                _controller.clear();
                FocusScope.of(context).unfocus();
              }
            },
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: Color(0xFF00E676),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.send_rounded, color: Colors.black, size: 20),
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

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Icon(icon, color: Colors.white.withOpacity(0.9)),
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
