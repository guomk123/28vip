import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'matches_page.dart';
import 'news_page.dart';
import 'leagues_page.dart';
import 'profile_page.dart';
import 'login_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.name,
    required this.email,
    required this.avatarSeed,
    this.avatarPath,
  });

  final String name;
  final String email;
  final int avatarSeed;
  final String? avatarPath;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  late String _name;
  late String _email;
  late int _avatarSeed;
  String? _avatarPath;

  @override
  void initState() {
    super.initState();
    _name = widget.name;
    _email = widget.email;
    _avatarSeed = widget.avatarSeed;
    _avatarPath = widget.avatarPath;
  }

  Future<void> _updateUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _name = prefs.getString('user_name') ?? 'Z8VIP User';
      _email = prefs.getString('user_email') ?? '';
      _avatarSeed = prefs.getInt('user_avatar_seed') ?? _email.hashCode;
      _avatarPath = prefs.getString('user_avatar_path');
    });
  }

  Future<void> _onTabTapped(int i) async {
    if (i == 3) {
      final prefs = await SharedPreferences.getInstance();
      final isLoggedIn = prefs.getBool('is_logged_in') ?? false;
      if (!isLoggedIn) {
        if (!mounted) return;
        final loggedIn = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => const LoginPage(fromProfile: true),
          ),
        );
        if (loggedIn == true) {
          await _updateUserData();
          setState(() => _index = 3);
        }
        return;
      }
    }
    setState(() => _index = i);
  }

  void _onLogout() {
    setState(() {
      _index = 0;
      _name = 'Z8VIP User';
      _email = '';
      _avatarSeed = 0;
      _avatarPath = null;
    });
  }

  void _onUserInfoChanged({String? name, String? email, String? avatarPath}) {
    setState(() {
      if (name != null) _name = name;
      if (email != null) _email = email;
      if (avatarPath != null) _avatarPath = avatarPath;
      if (email != null) _avatarSeed = email.hashCode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          const MatchesPage(),
          const NewsPage(),
          const LeaguesPage(),
          ProfilePage(
            name: _name,
            email: _email,
            avatarSeed: _avatarSeed,
            avatarPath: _avatarPath,
            onLogout: _onLogout,
            onInfoChanged: _onUserInfoChanged,
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: _onTabTapped,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        backgroundColor: const Color(0xFF0B1E16),
        selectedItemColor: const Color(0xFF00E676),
        unselectedItemColor: Colors.white.withOpacity(0.45),
        selectedFontSize: 12,
        unselectedFontSize: 12,
        items: const [
          BottomNavigationBarItem(
            icon: Image(
              image: AssetImage('assets/images/tab_home_n.png'),
              width: 24,
              height: 24,
            ),
            activeIcon: Image(
              image: AssetImage('assets/images/tab_home_s.png'),
              width: 24,
              height: 24,
            ),
            label: 'Matches',
          ),
          BottomNavigationBarItem(
            icon: Image(
              image: AssetImage('assets/images/tab_news_n.png'),
              width: 24,
              height: 24,
            ),
            activeIcon: Image(
              image: AssetImage('assets/images/tab_news_s.png'),
              width: 24,
              height: 24,
            ),
            label: 'News',
          ),
          BottomNavigationBarItem(
            icon: Image(
              image: AssetImage('assets/images/tab_leagues_n.png'),
              width: 24,
              height: 24,
            ),
            activeIcon: Image(
              image: AssetImage('assets/images/tab_leagues_s.png'),
              width: 24,
              height: 24,
            ),
            label: 'Leagues',
          ),
          BottomNavigationBarItem(
            icon: Image(
              image: AssetImage('assets/images/tab_person_n.png'),
              width: 24,
              height: 24,
            ),
            activeIcon: Image(
              image: AssetImage('assets/images/tab_person_s.png'),
              width: 24,
              height: 24,
            ),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
