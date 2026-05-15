import 'dart:math' as math;

import 'package:flutter/material.dart';

extension _ColorWithValuesCompat on Color {
  Color withValues({double? alpha}) {
    if (alpha == null) return this;
    final a = alpha.clamp(0.0, 1.0);
    return withOpacity(a);
  }
}

class MatchStatDetailsPage extends StatelessWidget {
  const MatchStatDetailsPage({
    super.key,
    required this.title,
    required this.leftValue,
    required this.rightValue,
    required this.isPercent,
  });

  final String title;
  final int leftValue;
  final int rightValue;
  final bool isPercent;

  @override
  Widget build(BuildContext context) {
    final leftText = isPercent ? '$leftValue%' : '$leftValue';
    final rightText = isPercent ? '$rightValue%' : '$rightValue';

    return Scaffold(
      body: Stack(
        children: [
          const _Background(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                  child: Row(
                    children: [
                      _BackIconButton(
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                      const Spacer(),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      const SizedBox(width: 38, height: 38),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                    children: [
                      _StatHeroCard(
                        title: title,
                        leftText: leftText,
                        rightText: rightText,
                        leftValue: leftValue,
                        rightValue: rightValue,
                      ),
                      const SizedBox(height: 14),
                      const _BreakdownCard(),
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

class _Background extends StatelessWidget {
  const _Background();

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

class _StatHeroCard extends StatelessWidget {
  const _StatHeroCard({
    required this.title,
    required this.leftText,
    required this.rightText,
    required this.leftValue,
    required this.rightValue,
  });

  final String title;
  final String leftText;
  final String rightText;
  final int leftValue;
  final int rightValue;

  @override
  Widget build(BuildContext context) {
    final total = math.max(1, leftValue + rightValue);
    final ratio = leftValue / total;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withValues(alpha: 0.06),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
        child: Column(
          children: [
            Text(
              title,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _ValuePill(
                  text: leftText,
                  bg: const Color(0xFF00E676).withValues(alpha: 0.22),
                  fg: const Color(0xFF00E676),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: SizedBox(
                      height: 12,
                      child: Row(
                        children: [
                          Expanded(
                            flex: (ratio * 1000).round(),
                            child: Container(color: const Color(0xFF00E676)),
                          ),
                          Expanded(
                            flex: ((1 - ratio) * 1000).round(),
                            child: Container(color: const Color(0xFFFFC107)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _ValuePill(
                  text: rightText,
                  bg: const Color(0xFFFFC107).withValues(alpha: 0.20),
                  fg: const Color(0xFFFFC107),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ValuePill extends StatelessWidget {
  const _ValuePill({required this.text, required this.bg, required this.fg});

  final String text;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 32,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            color: fg,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withValues(alpha: 0.06),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          children: const [
            _BreakdownRow(title: '1st half', left: '—', right: '—'),
            SizedBox(height: 12),
            _BreakdownRow(title: '2nd half', left: '—', right: '—'),
          ],
        ),
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.title,
    required this.left,
    required this.right,
  });

  final String title;
  final String left;
  final String right;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            title,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            left,
            textAlign: TextAlign.left,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            right,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
