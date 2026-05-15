// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skit_module/pages/league_details_page.dart';
import 'package:skit_module/pages/login_page.dart';
import 'package:skit_module/pages/match_details_page.dart';
import 'package:skit_module/pages/match_stat_details_page.dart';

void main() {
  testWidgets('Login page renders', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));
    await tester.pumpAndSettle();

    expect(find.text('Email Address'), findsOneWidget);
    expect(find.text('Password'), findsNWidgets(2));
    expect(find.text('Sign In'), findsOneWidget);

    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.byType(TextButton), findsOneWidget);
  });

  testWidgets('Fixture card navigates to match details', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: false,
          splashFactory: InkRipple.splashFactory,
        ),
        home: LeagueDetailsPage(teamId: 1, competitionId: 1),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Fixtures'), findsOneWidget);
  });

  testWidgets('Stat row navigates to stat details', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: false,
          splashFactory: InkRipple.splashFactory,
        ),
        home: MatchDetailsPage(),
      ),
    );

    await tester.tap(find.text('Shot on target'));
    await tester.pumpAndSettle();

    expect(find.byType(MatchStatDetailsPage), findsOneWidget);
  });
}
