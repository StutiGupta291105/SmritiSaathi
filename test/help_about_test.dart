import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti_assist/features/shell/settings_pages.dart';

void main() {
  Future<void> show(WidgetTester t, Widget w) async {
    t.view.physicalSize = const Size(800, 2400);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: w));
    await t.pumpAndSettle();
  }

  testWidgets('help shows emergency, steps and expandable FAQ', (t) async {
    await show(t, const HelpSupportScreen(lang: 'en'));
    expect(find.byKey(const ValueKey('helpCall112')), findsOneWidget);
    expect(find.text('Common questions'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Do I need internet to use the app?'), 300,
        scrollable: find.byType(Scrollable).first);
    await t.tap(find.text('Do I need internet to use the app?'));
    await t.pumpAndSettle();
    expect(find.textContaining('work offline'), findsOneWidget);
  });

  testWidgets('help and about render in Hindi and fall back for other languages', (t) async {
    await show(t, const HelpSupportScreen(lang: 'hi'));
    expect(find.text('आम सवाल'), findsOneWidget);
    await show(t, const AboutAppScreen(lang: 'ta'));
    expect(find.text('What Smriti Sathi does'), findsOneWidget); // English fallback
  });

  testWidgets('about states it is not a medical device and shows credits', (t) async {
    await show(t, const AboutAppScreen(lang: 'en'));
    expect(find.textContaining('not a medical device', skipOffstage: false), findsOneWidget);
    expect(find.text('Version 0.1.0', skipOffstage: false), findsOneWidget);
    await t.scrollUntilVisible(find.byKey(const ValueKey('aboutLicences')), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('NIET', skipOffstage: false), findsOneWidget);
  });
}
