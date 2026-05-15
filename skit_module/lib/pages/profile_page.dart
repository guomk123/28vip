import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'favorite_manager.dart';
import 'match_details_page.dart';
import 'basketball_match_details_page.dart';
import 'login_page.dart';
import 'common_widgets.dart';
import 'webview_page.dart';

extension _ColorWithValuesCompat on Color {
  Color withValues({double? alpha}) {
    if (alpha == null) return this;
    final a = alpha.clamp(0.0, 1.0);
    return withOpacity(a);
  }
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    this.name = 'Peter Brian',
    this.email = '12345678@123.com',
    this.avatarSeed = 0,
    this.avatarPath,
    this.onLogout,
    this.onInfoChanged,
  });

  final String name;
  final String email;
  final int avatarSeed;
  final String? avatarPath;
  final VoidCallback? onLogout;
  final Function({String? name, String? email, String? avatarPath})?
      onInfoChanged;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _picker = ImagePicker();
  late String _name;
  late String _email;
  late int _avatarSeed;
  String? _avatarPath;
  bool _isLoadingInfo = false;

  @override
  void initState() {
    super.initState();
    _name = widget.name;
    _email = widget.email;
    _avatarSeed = widget.avatarSeed;
    _avatarPath = widget.avatarPath;
    _fetchUserInfo();
  }

  Future<void> _fetchUserInfo() async {
    debugPrint('>>> _fetchUserInfo START');
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('is_logged_in') ?? false;
    final token = prefs.getString('user_token');

    debugPrint(
        '>>> Status - isLoggedIn: $isLoggedIn, hasToken: ${token != null}');
    if (!isLoggedIn) {
      debugPrint('>>> Not logged in, skipping request');
      return;
    }

    setState(() => _isLoadingInfo = true);

    try {
      debugPrint('>>> Requesting: https://api.z8vips.com/api/v1/member');
      debugPrint('>>> Header Token: $token');

      final response = await http.get(
        Uri.parse('https://api.z8vips.com/api/v1/member'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'authorization': token,
        },
      );

      debugPrint('>>> HTTP Status: ${response.statusCode}');
      final responseBody = utf8.decode(response.bodyBytes);
      debugPrint('>>> HTTP Response Body: $responseBody');

      if (response.statusCode == 200) {
        final decoded = jsonDecode(responseBody);
        if (decoded['code'] == 0 && decoded['data'] != null) {
          final data = decoded['data'];
          final nickname = data['nickname']?.toString() ?? 'Z8VIP User';
          final email = data['email']?.toString() ?? '';
          final avatar = data['avatar']?.toString().trim();

          final hasChanges = nickname != _name ||
              email != _email ||
              (avatar != null && avatar != _avatarPath);

          if (hasChanges) {
            debugPrint(
                '>>> Setting state with: name=$nickname, email=$email, avatar=$avatar');
            setState(() {
              _name = nickname;
              _email = email;
              if (avatar != null && avatar.isNotEmpty) {
                _avatarPath = avatar;
              }
              _avatarSeed = _email.hashCode;
            });

            // 仅在数据确实变化时通知父组件，防止无限循环
            widget.onInfoChanged
                ?.call(name: _name, email: _email, avatarPath: _avatarPath);
          }

          await prefs.setString('user_name', _name);
          await prefs.setString('user_email', _email);
          if (_avatarPath != null && _avatarPath!.isNotEmpty) {
            await prefs.setString('user_avatar_path', _avatarPath!);
          }
          debugPrint('>>> User info process finished. Changed: $hasChanges');
        } else {
          debugPrint('>>> Business Error: ${decoded['message']}');
        }
      } else {
        debugPrint('>>> Server Error Status: ${response.statusCode}');
      }
    } catch (e, stack) {
      debugPrint('>>> Exception: $e');
      debugPrint('>>> Stack: $stack');
    } finally {
      debugPrint('>>> _fetchUserInfo END');
      if (mounted) setState(() => _isLoadingInfo = false);
    }
  }

  @override
  void didUpdateWidget(ProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    debugPrint('>>> didUpdateWidget called');

    bool loginStatusChanged =
        (oldWidget.email.isEmpty || oldWidget.email == '12345678@123.com') &&
            widget.email.isNotEmpty &&
            widget.email != '12345678@123.com';

    // 仅在父组件传入的数据与当前显示的数据确实不一致时才同步到内部状态
    if (widget.name != _name ||
        widget.email != _email ||
        widget.avatarPath != _avatarPath) {
      debugPrint('>>> Widget data changed, updating internal state');
      setState(() {
        _name = widget.name;
        _email = widget.email;
        _avatarSeed = widget.avatarSeed;
        _avatarPath = widget.avatarPath;
      });
    }

    // 如果检测到登录状态变化（从无到有），或者邮箱发生了实质性变化，触发一次个人信息刷新
    if (loginStatusChanged ||
        (widget.email != oldWidget.email && widget.email.isNotEmpty)) {
      debugPrint('>>> Login detected or email changed, fetching server info');
      _fetchUserInfo();
    }
  }

  Future<void> _openEdit() async {
    final result = await Navigator.of(context).push<_EditProfileResult>(
      MaterialPageRoute(
        builder: (_) => EditProfilePage(
          name: _name,
          email: _email,
          avatarSeed: _avatarSeed,
          avatarPath: _avatarPath,
        ),
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      _name = result.name;
      _avatarPath = result.avatarPath;
    });

    // 同步给父组件
    widget.onInfoChanged?.call(name: _name, avatarPath: _avatarPath);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', _name);
    if (_avatarPath == null || _avatarPath!.trim().isEmpty) {
      await prefs.remove('user_avatar_path');
    } else {
      await prefs.setString('user_avatar_path', _avatarPath!);
    }
  }

  Future<void> _pickAvatarFromProfile() async {
    try {
      final file = await _picker.pickImage(source: ImageSource.gallery);
      if (!mounted || file == null) return;
      setState(() {
        _avatarPath = file.path;
      });

      // 同步给父组件
      widget.onInfoChanged?.call(avatarPath: file.path);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_avatar_path', file.path);
    } catch (_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: const Text(
            '无法打开相册，请检查权限',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          backgroundColor: Colors.black.withValues(alpha: 0.78),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const _ProfileBackground(),
        SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(10, 18, 10, 24),
            children: [
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  'Profile',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              const SizedBox(height: 26),
              _ProfileHeader(
                name: _name,
                email: _email,
                avatarSeed: _avatarSeed,
                avatarPath: _avatarPath,
                onAvatarTap: _pickAvatarFromProfile,
              ),
              const SizedBox(height: 28),
              _MenuCard(
                items: [
                  _MenuItem(
                    icon: Icons.edit_rounded,
                    label: 'Edit info',
                    iconBg: Colors.white.withValues(alpha: 0.06),
                    iconColor: const Color(0xFF00E676),
                    onTap: _openEdit,
                  ),
                  _MenuItem(
                    icon: Icons.favorite_rounded,
                    label: 'My Favorites',
                    iconBg: Colors.white.withValues(alpha: 0.06),
                    iconColor: const Color(0xFF00E676),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const MyFavoritesPage()),
                      );
                    },
                  ),
                  _MenuItem(
                    icon: Icons.description_rounded,
                    label: 'Privacy Agreement',
                    iconBg: Colors.white.withValues(alpha: 0.06),
                    iconColor: const Color(0xFF00E676),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const WebViewPage(
                            url: 'https://www.z8vips.com/privacy-agreement?platform=IOS',
                            title: 'Privacy Agreement',
                          ),
                        ),
                      );
                    },
                  ),
                  _MenuItem(
                    icon: Icons.info_outline_rounded,
                    label: 'About Us',
                    iconBg: Colors.white.withValues(alpha: 0.06),
                    iconColor: const Color(0xFF00E676),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AboutUsPage()),
                      );
                    },
                  ),
                  _MenuItem(
                    icon: Icons.logout_rounded,
                    label: 'Log out',
                    iconBg: Colors.white.withValues(alpha: 0.06),
                    iconColor: const Color(0xFFFF5252),
                    onTap: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: const Color(0xFF0B1E16),
                          title: const Text('Log out'),
                          content: const Text('Are you sure you want to log out?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              child: const Text('Log out', style: TextStyle(color: Color(0xFFFF5252))),
                            ),
                          ],
                        ),
                      );

                      if (confirmed == true) {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.clear();
                        if (!mounted) return;
                        widget.onLogout?.call();
                      }
                    },
                  ),
                  _MenuItem(
                    icon: Icons.person_off_rounded,
                    label: 'Delete Account',
                    iconBg: Colors.white.withValues(alpha: 0.06),
                    iconColor: const Color(0xFFFF5252),
                    onTap: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: const Color(0xFF0B1E16),
                          title: const Text('Delete Account', style: TextStyle(color: Color(0xFFFF5252))),
                          content: const Text(
                            'Your account and all data will be permanently deleted. This action cannot be undone.',
                            style: TextStyle(color: Colors.white70),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              child: const Text('Delete', style: TextStyle(color: Color(0xFFFF5252))),
                            ),
                          ],
                        ),
                      );

                      if (confirmed == true) {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.clear();
                        if (!mounted) return;
                        widget.onLogout?.call();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Account deleted successfully')),
                        );
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class MyFavoritesPage extends StatefulWidget {
  const MyFavoritesPage({super.key});

  @override
  State<MyFavoritesPage> createState() => _MyFavoritesPageState();
}

class _MyFavoritesPageState extends State<MyFavoritesPage> {
  List<FavoriteItem> _favorites = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final list = await FavoriteManager.getFavorites();
    if (mounted) {
      setState(() {
        _favorites = list;
        _loading = false;
      });
    }
  }

  Future<void> _toggleFavorite(FavoriteItem item) async {
    await FavoriteManager.toggleFavorite(item);
    _loadFavorites();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const _ProfileBackground(),
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
                        'My Favorites',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const Spacer(),
                      const SizedBox(width: 38, height: 38),
                    ],
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _favorites.isEmpty
                          ? const NoDataPlaceholder(
                              message: 'No favorites yet',
                              icon: Icons.favorite_border_rounded,
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              itemCount: _favorites.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final item = _favorites[index];
                                return _FavoriteCard(
                                  item: item,
                                  onTap: () async {
                                    if (item.type == FavoriteType.football) {
                                      await Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => MatchDetailsPage(
                                            matchId: item.matchId,
                                            initialHomeTeamName:
                                                item.homeTeamName,
                                            initialAwayTeamName:
                                                item.awayTeamName,
                                            initialHomeTeamLogoUrl:
                                                item.homeTeamLogoUrl,
                                            initialAwayTeamLogoUrl:
                                                item.awayTeamLogoUrl,
                                            initialCompetitionName:
                                                item.competitionName,
                                            initialHomeScore: item.homeScore,
                                            initialAwayScore: item.awayScore,
                                          ),
                                        ),
                                      );
                                    } else {
                                      await Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              BasketballMatchDetailsPage(
                                            matchId: item.matchId,
                                            initialHomeTeamName:
                                                item.homeTeamName,
                                            initialAwayTeamName:
                                                item.awayTeamName,
                                            initialHomeTeamLogoUrl:
                                                item.homeTeamLogoUrl,
                                            initialAwayTeamLogoUrl:
                                                item.awayTeamLogoUrl,
                                            initialCompetitionName:
                                                item.competitionName,
                                            initialHomeScore: item.homeScore,
                                            initialAwayScore: item.awayScore,
                                            initialTimeText: item.timeText,
                                            initialPeriodText: item.periodText,
                                          ),
                                        ),
                                      );
                                    }
                                    _loadFavorites();
                                  },
                                  onDelete: () => _toggleFavorite(item),
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

class _FavoriteCard extends StatelessWidget {
  const _FavoriteCard({
    required this.item,
    required this.onTap,
    required this.onDelete,
  });

  final FavoriteItem item;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E676).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        item.type == FavoriteType.football
                            ? 'Football'
                            : 'Basketball',
                        style: const TextStyle(
                          color: Color(0xFF00E676),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (item.competitionName != null)
                      Text(
                        item.competitionName!,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: onDelete,
                      child: Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.white.withValues(alpha: 0.3),
                        size: 20,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          _TeamLogo(url: item.homeTeamLogoUrl),
                          const SizedBox(height: 8),
                          Text(
                            item.homeTeamName,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      children: [
                        Text(
                          'VS',
                          style: TextStyle(
                            color: Color(0xFF00E676),
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        children: [
                          _TeamLogo(url: item.awayTeamLogoUrl),
                          const SizedBox(height: 8),
                          Text(
                            item.awayTeamName,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TeamLogo extends StatelessWidget {
  const _TeamLogo({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        shape: BoxShape.circle,
      ),
      child: url != null && url!.isNotEmpty
          ? Image.network(
              url!,
              errorBuilder: (_, __, ___) => _LogoPlaceholder(),
            )
          : _LogoPlaceholder(),
    );
  }
}

class _LogoPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.sports_soccer_rounded,
      color: Colors.white.withValues(alpha: 0.2),
      size: 24,
    );
  }
}

class AboutUsPage extends StatelessWidget {
  const AboutUsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const _ProfileBackground(),
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
                        'About Us',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const Spacer(),
                      const SizedBox(width: 38, height: 38),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.06),
                          ),
                        ),
                        child: Column(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.asset(
                                'assets/images/app_logo.png',
                                width: 82,
                                height: 82,
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'Z8VIP',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Live scores, match details, and lineups.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.65),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Email: service@z8vips.com',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.65),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Container(
                              height: 1,
                              color: Colors.white.withValues(alpha: 0.10),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              '© ${DateTime.now().year} Z8VIP',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.45),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
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

class _ProfileBackground extends StatelessWidget {
  const _ProfileBackground();

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

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.name,
    required this.email,
    required this.avatarSeed,
    required this.avatarPath,
    required this.onAvatarTap,
  });

  final String name;
  final String email;
  final int avatarSeed;
  final String? avatarPath;
  final VoidCallback onAvatarTap;

  @override
  Widget build(BuildContext context) {
    debugPrint(
        '>>> Building ProfileHeader with name: $name, email: $email, avatarPath: $avatarPath');
    final palettes = [
      const [Color(0xFF5C6BC0), Color(0xFFE57373), Color(0xFFFFB74D)],
      const [Color(0xFF26A69A), Color(0xFF42A5F5), Color(0xFFAB47BC)],
      const [Color(0xFF00E676), Color(0xFF1DE9B6), Color(0xFF2D63FF)],
      const [Color(0xFFFFC107), Color(0xFFEF5350), Color(0xFF7E57C2)],
    ];
    final colors = palettes[avatarSeed.abs() % palettes.length];

    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onAvatarTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 110,
              height: 110,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipOval(
                      child: (avatarPath != null &&
                              avatarPath!.trim().isNotEmpty)
                          ? (avatarPath!.startsWith('http')
                              ? Image.network(
                                  avatarPath!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return _AvatarFallback(colors: colors);
                                  },
                                )
                              : Image.file(
                                  File(avatarPath!),
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return _AvatarFallback(colors: colors);
                                  },
                                ))
                          : _AvatarFallback(colors: colors),
                    ),
                  ),
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B1E16),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Icon(
                        Icons.photo_camera_rounded,
                        size: 18,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
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
          email,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({required this.colors});

  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.person_rounded,
          size: 52,
          color: Colors.white.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}

class _EditProfileResult {
  const _EditProfileResult({required this.name, required this.avatarPath});

  final String name;
  final String? avatarPath;
}

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({
    super.key,
    required this.name,
    required this.email,
    required this.avatarSeed,
    required this.avatarPath,
  });

  final String name;
  final String email;
  final int avatarSeed;
  final String? avatarPath;

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _picker = ImagePicker();
  late final TextEditingController _nameController;
  late String? _avatarPath;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.name);
    if (_nameController.text.trim().length > 12) {
      final text = _nameController.text.trim();
      final limited = text.substring(0, 12);
      _nameController.value = TextEditingValue(
        text: limited,
        selection: TextSelection.collapsed(offset: limited.length),
      );
    }
    _avatarPath = widget.avatarPath;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (!mounted || file == null) return;
    setState(() {
      _avatarPath = file.path;
    });
  }

  void _save() {
    final newName = _nameController.text.trim();
    if (newName.isEmpty) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: const Text(
            '请输入昵称',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          backgroundColor: Colors.black.withValues(alpha: 0.78),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    if (newName.length > 12) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: const Text(
            '昵称最多12个字',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          backgroundColor: Colors.black.withValues(alpha: 0.78),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    Navigator.of(
      context,
    ).pop(_EditProfileResult(name: newName, avatarPath: _avatarPath));
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _nameController.text.trim().isNotEmpty;

    return Scaffold(
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Stack(
          children: [
            const _ProfileBackground(),
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
                        const Expanded(
                          child: Text(
                            'Edit info',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: canSave ? _save : null,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                            foregroundColor: const Color(0xFF00E676),
                            disabledForegroundColor: Colors.white.withValues(
                              alpha: 0.35,
                            ),
                          ),
                          child: const Text(
                            'Save',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                      children: [
                        Center(
                          child: GestureDetector(
                            onTap: _pickAvatar,
                            child: SizedBox(
                              width: 120,
                              height: 120,
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: ClipOval(
                                      child: (_avatarPath != null &&
                                              _avatarPath!.trim().isNotEmpty)
                                          ? (_avatarPath!.startsWith('http')
                                              ? Image.network(
                                                  _avatarPath!,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, error,
                                                      stackTrace) {
                                                    return _AvatarFallback(
                                                      colors: const [
                                                        Color(0xFF00E676),
                                                        Color(0xFF1DE9B6),
                                                        Color(0xFF2D63FF),
                                                      ],
                                                    );
                                                  },
                                                )
                                              : Image.file(
                                                  File(_avatarPath!),
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, error,
                                                      stackTrace) {
                                                    return _AvatarFallback(
                                                      colors: const [
                                                        Color(0xFF00E676),
                                                        Color(0xFF1DE9B6),
                                                        Color(0xFF2D63FF),
                                                      ],
                                                    );
                                                  },
                                                ))
                                          : _AvatarFallback(
                                              colors: const [
                                                Color(0xFF00E676),
                                                Color(0xFF1DE9B6),
                                                Color(0xFF2D63FF),
                                              ],
                                            ),
                                    ),
                                  ),
                                  Positioned(
                                    right: 8,
                                    bottom: 8,
                                    child: Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0B1E16),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white.withValues(
                                            alpha: 0.10,
                                          ),
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.photo_library_outlined,
                                        size: 18,
                                        color: Colors.white.withValues(
                                          alpha: 0.85,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Tap avatar to choose a photo',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Nickname',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 4,
                          ),
                          child: TextField(
                            controller: _nameController,
                            onChanged: (_) => setState(() {}),
                            maxLength: 12,
                            maxLengthEnforcement: MaxLengthEnforcement.enforced,
                            inputFormatters: [
                              LengthLimitingTextInputFormatter(12)
                            ],
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            cursorColor: const Color(0xFF00E676),
                            decoration: InputDecoration(
                              hintText: '请输入昵称',
                              hintStyle: TextStyle(
                                color: Colors.white.withValues(alpha: 0.30),
                                fontWeight: FontWeight.w600,
                              ),
                              counterText: '',
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                      ],
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

class _MenuItem {
  _MenuItem({
    required this.icon,
    required this.label,
    required this.iconBg,
    required this.iconColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color iconBg;
  final Color iconColor;
  final FutureOr<void> Function() onTap;
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.items});

  final List<_MenuItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (int i = 0; i < items.length; i++) ...[
          _MenuRow(item: items[i]),
          if (i != items.length - 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Divider(
                height: 1,
                thickness: 1,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
        ],
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.item});

  final _MenuItem item;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => item.onTap(),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: item.iconBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                child: Icon(item.icon, color: item.iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  item.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.35),
              ),
            ],
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
