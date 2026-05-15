import 'dart:async';
import 'dart:convert';

import 'package:captcha_plugin_flutter/captcha_plugin_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'home_shell.dart';

Future<void> _persistLoginSession({
  required String email,
  required String name,
  String? token,
}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('is_logged_in', true);
  await prefs.setString('user_email', email);
  await prefs.setString('user_name', name);
  await prefs.setInt('user_avatar_seed', email.hashCode);
  if (token != null) {
    await prefs.setString('user_token', token);
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.fromProfile = false});

  final bool fromProfile;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const _sendVerifyEndpoint =
      'https://api.z8vips.com/api/v1/auth/send-verify';
  static const _otpLoginEndpoint = 'https://api.z8vips.com/api/v1/auth/login';
  static const _captchaKey = '69d5b2ee3fec46658e01c0b45fc381af';

  final _emailController = TextEditingController();
  final _codeController = TextEditingController();

  final CaptchaPluginFlutter _captchaPlugin = CaptchaPluginFlutter();

  int _countdown = 0;
  Timer? _timer;
  bool _isSendingCode = false;
  bool _isLoggingIn = false;

  @override
  void initState() {
    super.initState();
    _initCaptcha();
  }

  void _initCaptcha() {
    _captchaPlugin.init({
      "captcha_id": _captchaKey,
      "is_debug": false,
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    setState(() => _countdown = 60);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 0) {
        setState(() => _countdown--);
      } else {
        timer.cancel();
      }
    });
  }

  void _showError(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.black.withOpacity(0.78),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _triggerCaptcha() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showError('请输入邮箱');
      return;
    }
    if (_countdown > 0 || _isSendingCode) return;

    _captchaPlugin.showCaptcha(
      onSuccess: (dynamic data) {
        if (data is Map) {
          final validate = data['validate'] as String?;
          if (validate != null && validate.isNotEmpty) {
            _sendCode(validate);
          }
        }
      },
      onError: (dynamic data) {
        _showError('验证出错，请重试');
      },
    );
  }

  Future<void> _sendCode(String validate) async {
    final email = _emailController.text.trim();
    setState(() => _isSendingCode = true);

    try {
      final response = await http.post(
        Uri.parse(_sendVerifyEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'validate': validate,
          'channel': 'email',
          'account': email,
          'scene': 'sms-login',
        }),
      );

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode == 200 && decoded['code'] == 0) {
        _showError('验证码已发送');
        _startCountdown();
      } else {
        _showError(decoded['message'] ?? '发送失败');
      }
    } catch (_) {
      _showError('发送失败，请检查网络');
    } finally {
      if (mounted) setState(() => _isSendingCode = false);
    }
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final code = _codeController.text.trim();

    if (email.isEmpty) {
      _showError('请输入邮箱');
      return;
    }
    if (code.isEmpty) {
      _showError('请输入验证码');
      return;
    }
    if (_isLoggingIn) return;

    setState(() => _isLoggingIn = true);

    try {
      final response = await http.post(
        Uri.parse(_otpLoginEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'account': email,
          'code': code,
          'type': 'email_code',
          'channel': 'email',
        }),
      );

      final responseBody = utf8.decode(response.bodyBytes);
      debugPrint('Login Request: $_otpLoginEndpoint');
      debugPrint('Login Response Status: ${response.statusCode}');
      debugPrint('Login Response Body: $responseBody');

      final decoded = jsonDecode(responseBody);
      if (response.statusCode == 200 && decoded['code'] == 0) {
        final data = decoded['data'] ?? {};
        final token = data['token'] as String?;
        // 使用输入的邮箱作为默认显示，直到个人中心接口返回真实昵称
        final name = 'Z8VIP User';
        final avatarSeed = email.hashCode;
        await _persistLoginSession(
          email: email,
          name: name,
          token: token,
        );

        if (!mounted) return;
        if (widget.fromProfile) {
          Navigator.of(context).pop(true);
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) =>
                  HomeShell(name: name, email: email, avatarSeed: avatarSeed),
            ),
          );
        }
      } else {
        _showError(decoded['message'] ?? '登录失败');
      }
    } catch (_) {
      _showError('登录出错，请重试');
    } finally {
      if (mounted) setState(() => _isLoggingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);

    return Scaffold(
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const _AuthBackground(showTopImage: true),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: EdgeInsets.only(
                      left: 24,
                      right: 24,
                      top: 6,
                      bottom: 24 + viewInsets.bottom,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - 56,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: _BackIconButton(
                              onTap: () => Navigator.of(context).maybePop(),
                            ),
                          ),
                          SizedBox(height: constraints.maxHeight * 0.02),
                          const _Logo(),
                          const SizedBox(height: 34),
                          const _FieldLabel('Email Address'),
                          const SizedBox(height: 10),
                          _Input(
                            controller: _emailController,
                            hintText: 'youremail@1234.com',
                            keyboardType: TextInputType.visiblePassword,
                            prefixIcon: Icons.mail_outline,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9a-zA-Z@._-]'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          const _FieldLabel('Verify Code'),
                          const SizedBox(height: 10),
                          _Input(
                            controller: _codeController,
                            hintText: 'Enter code',
                            keyboardType: TextInputType.number,
                            prefixIcon: Icons.verified_user_outlined,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(6),
                            ],
                            suffix: TextButton(
                              onPressed: (_countdown > 0 || _isSendingCode)
                                  ? null
                                  : _triggerCaptcha,
                              child: Text(
                                _countdown > 0
                                    ? '${_countdown}s'
                                    : (_isSendingCode
                                        ? 'Sending...'
                                        : 'Get Code'),
                                style: TextStyle(
                                  color: (_countdown > 0 || _isSendingCode)
                                      ? Colors.white.withOpacity(0.3)
                                      : _Colors.accent,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          SizedBox(
                            height: 64,
                            child: ElevatedButton(
                              onPressed: _isLoggingIn ? null : _login,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _Colors.accent,
                                foregroundColor: Colors.black,
                                disabledBackgroundColor:
                                    _Colors.accent.withOpacity(0.5),
                                elevation: 0,
                                shape: const StadiumBorder(),
                                textStyle: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              child: Text(_isLoggingIn
                                  ? 'Logging in...'
                                  : 'Sign In / Sign Up'),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Center(
                            child: Text(
                              "Login or register automatically with code",
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.4),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 移除 SignUpPage 类，因为它已经整合到 LoginPage 中

class _AuthTitle extends StatelessWidget {
  const _AuthTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: Colors.white.withOpacity(0.95),
            fontSize: 34,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: 62,
          height: 4,
          decoration: BoxDecoration(
            color: _Colors.accent,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          subtitle,
          style: TextStyle(
            color: Colors.white.withOpacity(0.50),
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _AuthBackground extends StatelessWidget {
  const _AuthBackground({required this.showTopImage});

  final bool showTopImage;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (showTopImage)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Image.asset(
              'assets/images/login_top_v2.png',
              width: MediaQuery.sizeOf(context).width,
              fit: BoxFit.fitWidth,
              alignment: Alignment.topCenter,
              errorBuilder: (context, error, stackTrace) {
                return Image.asset(
                  'assets/images/login_top.png',
                  width: MediaQuery.sizeOf(context).width,
                  fit: BoxFit.fitWidth,
                  alignment: Alignment.topCenter,
                  errorBuilder: (context, error, stackTrace) {
                    return const SizedBox.shrink();
                  },
                );
              },
            ),
          ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                _Colors.greenOverlayTop,
                _Colors.greenOverlayMid,
                _Colors.darkBottom,
              ],
              stops: [0, 0.45, 1],
            ),
          ),
        ),
        Container(color: Colors.black.withOpacity(0.18)),
      ],
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Image.asset(
        'assets/images/login_logo.png',
        width: 260,
        height: 150,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return Image.asset(
            'assets/images/login_logo.png',
            width: 260,
            height: 150,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                width: 260,
                height: 150,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.22),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.20),
                  ),
                ),
                child: const Text(
                  'Z8VIP',
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                    color: Colors.white,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.white.withOpacity(0.9),
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    );
  }
}

class _Input extends StatelessWidget {
  const _Input({
    required this.controller,
    required this.hintText,
    required this.keyboardType,
    required this.prefixIcon,
    this.obscureText = false,
    this.suffix,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String hintText;
  final TextInputType keyboardType;
  final IconData prefixIcon;
  final bool obscureText;
  final Widget? suffix;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        autocorrect: false,
        enableSuggestions: false,
        inputFormatters: inputFormatters,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(
            color: Colors.white.withOpacity(0.35),
            fontWeight: FontWeight.w600,
          ),
          filled: true,
          fillColor: Colors.black.withOpacity(0.22),
          prefixIcon: Icon(
            prefixIcon,
            color: Colors.white.withOpacity(0.65),
          ),
          suffixIcon: suffix == null
              ? null
              : IconTheme(
                  data: IconThemeData(
                    color: Colors.white.withOpacity(0.55),
                  ),
                  child: suffix!,
                ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 18),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.06)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide(
              color: _Colors.accent.withOpacity(0.8),
            ),
          ),
        ),
      ),
    );
  }
}

class _Colors {
  static const accent = Color(0xFF00E676);
  static const greenOverlayTop = Color(0xAA16D163);
  static const greenOverlayMid = Color(0x6610B455);
  static const darkBottom = Color(0xFF14211A);
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
              'assets/images/login_back.png',
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
