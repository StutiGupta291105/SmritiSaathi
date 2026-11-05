import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti_assist/core/theme.dart';
import 'package:smriti_assist/data/app_database.dart';
import 'package:smriti_assist/features/games/number_order_game.dart';
import 'package:smriti_assist/features/games/puzzle_fix_game.dart';
import 'package:smriti_assist/features/games/word_recall_game.dart';
import 'package:smriti_assist/services/voice.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late AppDatabase db;
  late Database raw;
  late String pid;

  setUp(() async {
    sqfliteFfiInit();
    raw = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(
            singleInstance: false,
            version: AppDatabase.schemaVersion,
            onCreate: (d, _) => AppDatabase.createSchema(d)));
    db = AppDatabase.forTesting(raw);
    final a = await db.createAccount(phone: '+919876543210', role: 'patient', name: 'A');
    pid = await db.createPatient(
        accountId: a, phone: '+919876543210', displayName: 'A',
        baselineLevel: 2, language: 'en', createdBy: 'x');
    await db.recordConsent(
        patientId: pid, purposes: {'gameplay': true},
        givenByName: 'A', givenByRelation: 'self', noticeVersion: 'v2');
  });

  tearDown(() => raw.close());

  Future<void> open(WidgetTester t, Widget Function() game) async {
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Builder(
        builder: (c) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => game())),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  Future<List<Map<String, Object?>>> sessions() async {
    // The game saves from inside the test's fake clock; give the database time.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    return raw.query('sessions');
  }

  testWidgets('Number Order: tapping in order completes five rounds and saves them', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await open(t, () => NumberOrderGame(
        db: db, patientId: pid, baselineLevel: 2, startLevel: 1, language: 'en',
        voice: Voice(), voiceOn: false));
    for (var round = 0; round < 5; round++) {
      // Level 1-3 are ascending: tap 1, 2, 3 ... as far as the grid goes.
      for (var n = 1; n <= 9; n++) {
        final f = find.text('$n');
        if (f.evaluate().isEmpty) break;
        await t.tap(f.first);
        await t.pump(const Duration(milliseconds: 50));
      }
      await t.pump(const Duration(milliseconds: 1500));
    }
    await t.pumpAndSettle();
    final rows = await t.runAsync(sessions);
    expect(rows!.single['game'], 'number_order');
    expect(rows.single['trials'], 5);
    expect(rows.single['correct'], 5);
  });

  testWidgets('Number Order: a wrong tap makes the round count as not correct', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await open(t, () => NumberOrderGame(
        db: db, patientId: pid, baselineLevel: 1, startLevel: 1, language: 'en',
        voice: Voice(), voiceOn: false));
    await t.tap(find.text('3').first); // not the first number
    await t.pump(const Duration(milliseconds: 100));
    for (var n = 1; n <= 4; n++) {
      await t.tap(find.text('$n').first);
      await t.pump(const Duration(milliseconds: 50));
    }
    await t.pump(const Duration(milliseconds: 1500));
    await t.tap(find.byIcon(Icons.arrow_back_rounded));
    await t.pumpAndSettle();
    final rows = await t.runAsync(sessions);
    expect(rows!.single['trials'], 1);
    expect(rows.single['correct'], 0);
  });

  testWidgets('Puzzle Fix: six rounds are played and saved', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await open(t, () => PuzzleFixGame(
        db: db, patientId: pid, baselineLevel: 2, startLevel: 2, language: 'en',
        voice: Voice(), voiceOn: false));
    for (var round = 0; round < 6; round++) {
      // Options are the InkWells in the lower grid; tap the first one.
      final options = find.descendant(of: find.byType(GridView), matching: find.byType(InkWell));
      await t.tap(options.first);
      await t.pump(const Duration(milliseconds: 2000));
    }
    await t.pumpAndSettle();
    final rows = await t.runAsync(sessions);
    expect(rows!.single['game'], 'puzzle_fix');
    expect(rows.single['trials'], 6);
  });

  testWidgets('Word Recall: remember, pick, four rounds saved', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await open(t, () => WordRecallGame(
        db: db, patientId: pid, baselineLevel: 2, startLevel: 1, language: 'en',
        voice: Voice(), voiceOn: false));
    for (var round = 0; round < 4; round++) {
      expect(find.text('Remember these. They will disappear.'), findsOneWidget);
      await t.pump(const Duration(seconds: 9)); // memorize time passes
      expect(find.text('Which ones did you see?'), findsOneWidget);
      // Pick three options (level 1 asks for three).
      final opts = find.byWidgetPredicate((w) => w is Semantics && w.properties.button == true && w.properties.selected != null);
      for (var i = 0; i < 3; i++) {
        await t.tap(opts.at(i));
        await t.pump(const Duration(milliseconds: 50));
      }
      await t.pump(const Duration(milliseconds: 2500));
    }
    await t.pumpAndSettle();
    final rows = await t.runAsync(sessions);
    expect(rows!.single['game'], 'word_recall');
    expect(rows.single['trials'], 4);
  });
}
