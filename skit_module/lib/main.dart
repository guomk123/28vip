import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pages/home_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'z8vip',
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: false,
        scaffoldBackgroundColor: const Color(0xFF071813),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E676),
          secondary: Color(0xFF1DE9B6),
          surface: Color(0xFF0B1E16),
        ),
        textTheme: ThemeData.dark().textTheme.apply(
              bodyColor: Colors.white,
              displayColor: Colors.white,
            ),
      ),
      home: const _BootPage(),
    );
  }
}

class _BootPage extends StatefulWidget {
  const _BootPage();

  @override
  State<_BootPage> createState() => _BootPageState();
}

class _BootPageState extends State<_BootPage> {
  Future<Widget>? _future;

  @override
  void initState() {
    super.initState();
    _future = _resolveHome();
  }

  Future<Widget> _resolveHome() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('user_email') ?? '';
    final name = prefs.getString('user_name') ?? 'Z8VIP User';
    final avatarSeed = prefs.getInt('user_avatar_seed') ?? email.hashCode;
    final avatarPath = prefs.getString('user_avatar_path');
    return HomeShell(
      name: name,
      email: email,
      avatarSeed: avatarSeed,
      avatarPath: avatarPath,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _future,
      builder: (context, snapshot) {
        final home = snapshot.data;
        if (home != null) return home;
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
    );
  }
}
