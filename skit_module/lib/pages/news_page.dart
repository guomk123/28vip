import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'news_details_page.dart';
import 'common_widgets.dart';

class NewsPage extends StatefulWidget {
  const NewsPage({super.key});

  @override
  State<NewsPage> createState() => _NewsPageState();
}

class _NewsPageState extends State<NewsPage> with WidgetsBindingObserver {
  static const _pageSize = 20;
  static const _endpoint = 'https://api.z8vips.com/api/v1/info/list';

  final _scrollController = ScrollController();

  final List<_NewsItem> _items = [];
  int _page = 1;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _fetchFirstPage();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_items.isEmpty || _errorText != null) {
        _fetchFirstPage();
      }
    }
  }

  void _onScroll() {
    if (!_hasMore || _loading || _loadingMore) return;
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 600) {
      _fetchMore();
    }
  }

  Future<void> _fetchFirstPage() async {
    setState(() {
      _page = 1;
      _hasMore = true;
      _loading = true;
      _loadingMore = false;
      _errorText = null;
    });

    try {
      final pageItems = await _fetchPage(page: 1);
      setState(() {
        _items
          ..clear()
          ..addAll(pageItems);
        _hasMore = pageItems.length >= _pageSize;
      });
    } catch (e) {
      setState(() {
        _errorText = '加载失败，请重试';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _fetchMore() async {
    if (!_hasMore) return;
    setState(() {
      _loadingMore = true;
      _errorText = null;
    });

    final nextPage = _page + 1;
    try {
      final pageItems = await _fetchPage(page: nextPage);
      if (!mounted) return;
      setState(() {
        _page = nextPage;
        _items.addAll(pageItems);
        _hasMore = pageItems.length >= _pageSize;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = '加载失败，请重试';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingMore = false;
        });
      }
    }
  }

  Future<List<_NewsItem>> _fetchPage({required int page}) async {
    final uri = Uri.parse(
      '$_endpoint?page=$page&size=$_pageSize&type=0',
    );
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('http ${response.statusCode}');
    }

    final decoded = _tryDecodeJson(response.bodyBytes);
    final data = decoded is Map ? decoded['data'] : null;
    final result = data is Map ? (data['results'] ?? data['result']) : null;
    if (result is! List) return const [];

    final List<_NewsItem> items = [];
    for (final raw in result) {
      if (raw is! Map) continue;
      final title = (raw['title'] ?? '').toString();
      if (title.trim().isEmpty) continue;
      final cover = _sanitizeUrl(raw['cover']);
      final dateText = _formatEpoch(raw['created_at'] ?? raw['createdAt']);
      items.add(
        _NewsItem(
          id: (raw['id'] ?? '').toString(),
          title: title,
          cover: cover,
          h5Url: _sanitizeUrl(raw['h5_url']),
          body:
              (raw['content'] ?? raw['body'] ?? raw['intro'] ?? '').toString(),
          dateText: dateText,
        ),
      );
    }
    return items;
  }

  String _sanitizeUrl(dynamic value) {
    final raw = (value ?? '').toString();
    final cleaned = raw.replaceAll('`', '').trim();
    return cleaned;
  }

  String _formatEpoch(dynamic value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return '';
    final seconds = int.tryParse(raw);
    if (seconds == null || seconds <= 0) return raw;
    final dt = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
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
    return Stack(
      children: [
        const _NewsBackground(),
        SafeArea(
          child: Column(
            children: [
              Expanded(
                child: _buildBody(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_items.isEmpty) {
      if (_errorText != null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _errorText!,
                  style: TextStyle(color: Colors.white.withOpacity(0.75)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 44,
                  child: ElevatedButton(
                    onPressed: _fetchFirstPage,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.10),
                      foregroundColor: Colors.white.withOpacity(0.9),
                      elevation: 0,
                      shape: const StadiumBorder(),
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
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
      return RefreshIndicator(
        onRefresh: _fetchFirstPage,
        color: const Color(0xFF00E676),
        backgroundColor: const Color(0xFF0B1E16),
        child: ListView(
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.7,
              child: const NoDataPlaceholder(message: 'No news available'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchFirstPage,
      color: const Color(0xFF00E676),
      backgroundColor: const Color(0xFF0B1E16),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: _items.length + (_loadingMore || _hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _items.length) {
            if (_loadingMore) {
              return Padding(
                padding: const EdgeInsets.only(top: 18),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                ),
              );
            }
            if (_errorText != null) {
              return Padding(
                padding: const EdgeInsets.only(top: 18),
                child: Center(
                  child: TextButton(
                    onPressed: _fetchMore,
                    child: Text(
                      '加载失败，点此重试',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              );
            }
            return const SizedBox(height: 60);
          }

          final item = _items[index];
          return Padding(
            padding: EdgeInsets.only(top: index == 0 ? 0 : 18),
            child: _NewsCard(
              title: item.title,
              coverUrl: item.cover,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => NewsDetailsPage(
                      id: int.tryParse(item.id) ?? 0,
                      content: item.body,
                      h5Url: item.h5Url,
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _NewsItem {
  const _NewsItem({
    required this.id,
    required this.title,
    required this.dateText,
    required this.cover,
    required this.h5Url,
    required this.body,
  });

  final String id;
  final String title;
  final String dateText;
  final String cover;
  final String h5Url;
  final String body;
}

class _NewsBackground extends StatelessWidget {
  const _NewsBackground();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF0F2B20),
            Color(0xFF071813),
          ],
        ),
      ),
    );
  }
}

class _NewsCard extends StatelessWidget {
  const _NewsCard({
    required this.title,
    required this.coverUrl,
    required this.onTap,
  });

  final String title;
  final String coverUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.22),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(
                  height: 210,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (coverUrl.trim().isNotEmpty)
                        Image.network(
                          coverUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const _CoverFallback();
                          },
                        )
                      else
                        const _CoverFallback(),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withOpacity(0.05),
                                Colors.black.withOpacity(0.42),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                height: 1.18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF8BC34A),
            Color(0xFF009688),
            Color(0xFF1565C0),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.image_outlined,
          size: 46,
          color: Colors.white70,
        ),
      ),
    );
  }
}
