import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti_assist/core/theme.dart';
import 'package:smriti_assist/data/app_database.dart';
import 'package:smriti_assist/features/games/change_game.dart';
import 'package:smriti_assist/features/games/echo_game.dart';
import 'package:smriti_assist/features/games/faces_game.dart';
import 'package:smriti_assist/features/games/round_game.dart';
import 'package:smriti_assist/features/games/sort_game.dart';
import 'package:smriti_assist/features/games/tile_game.dart';
import 'package:smriti_assist/features/games/where_game.dart';
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
        patientId: pid,
        purposes: {'gameplay': true, 'family_contacts': true},
        givenByName: 'A', givenByRelation: 'self', noticeVersion: 'v2');
  });

  tearDown(() => raw.close());

  Future<void> open(WidgetTester t, RoundGame Function() game) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Builder(
        builder: (c) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(c)
                  .push(MaterialPageRoute<void>(builder: (_) => game())),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pump();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump();
  }

  Future<List<Map<String, Object?>>> sessions(WidgetTester t) async {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    return (await t.runAsync(() => raw.query('sessions')))!;
  }

  Future<void> wait(WidgetTester t, int ms) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> closeResult(WidgetTester t) async {
    // The game saves, then reads the progress: two database round trips.
    for (var i = 0; i < 3; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Continue'), findsOneWidget);
    expect(find.textContaining('of 3 clears'), findsOneWidget);
    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();
    expect(find.text('open'), findsOneWidget); // back on the previous screen
  }

  testWidgets('Who Is This: five rounds are played and saved, with a closing card', (t) async {
    await open(t, () => FacesGame(db: db, patientId: pid, baselineLevel: 1, startLevel: 1,
        language: 'en', voice: Voice(), voiceOn: false));
    for (var i = 0; i < 5; i++) {
      expect(find.text('I am ready'), findsOneWidget);
      await t.tap(find.text('I am ready'));
      await wait(t, 200);
      await t.tap(find.byType(GameTile).first);
      await wait(t, 1700);
    }
    final rows = await sessions(t);
    expect(rows.single['game'], 'faces');
    expect(rows.single['trials'], 5);
    expect(rows.single['start_level'], 1);
    expect(rows.single['end_level'], 1); // the level never moves inside a play
    await closeResult(t);
  });

  testWidgets('Where Did It Go: study time ends by itself, then a square is chosen', (t) async {
    await open(t, () => WhereGame(db: db, patientId: pid, baselineLevel: 1, startLevel: 1,
        language: 'en', voice: Voice(), voiceOn: false));
    for (var i = 0; i < 5; i++) {
      await wait(t, 6200); // the pictures hide on their own
      expect(find.text('Where was this picture?'), findsOneWidget);
      await t.tap(find.byType(GameTile).at(1));
      await wait(t, 1700);
    }
    expect((await sessions(t)).single['trials'], 5);
    await closeResult(t);
  });

  testWidgets('Spot the Change: look, blink, then find', (t) async {
    await open(t, () => ChangeGame(db: db, patientId: pid, baselineLevel: 1, startLevel: 1,
        language: 'en', voice: Voice(), voiceOn: false));
    for (var i = 0; i < 5; i++) {
      await t.tap(find.text('I am ready'));
      await wait(t, 1100);
      expect(find.text('Something changed. Tap it!'), findsOneWidget);
      await t.tap(find.byType(GameTile).first);
      await wait(t, 1700);
    }
    expect((await sessions(t)).single['trials'], 5);
    await closeResult(t);
  });

  testWidgets('Sort the Day: six choices are saved', (t) async {
    await open(t, () => SortGame(db: db, patientId: pid, baselineLevel: 1, startLevel: 1,
        language: 'en', voice: Voice(), voiceOn: false));
    for (var i = 0; i < 6; i++) {
      await t.tap(find.byType(GameTile).at(1));
      await wait(t, 1700);
    }
    expect((await sessions(t)).single['trials'], 6);
    await closeResult(t);
  });

  testWidgets('Sort the Day at a high level asks for the morning order every other round',
      (t) async {
    await open(t, () => SortGame(db: db, patientId: pid, baselineLevel: 5, startLevel: 5,
        language: 'en', voice: Voice(), voiceOn: false));
    expect(find.text('Where does this belong?'), findsOneWidget);
    await t.tap(find.byType(GameTile).at(1));
    await wait(t, 1700);
    expect(find.text('Tap the steps in the order of your morning'), findsWidgets);
  });

  testWidgets('Sequence Echo: watch, then tap; every round is recorded', (t) async {
    await open(t, () => EchoGame(db: db, patientId: pid, baselineLevel: 1, startLevel: 1,
        language: 'en', voice: Voice(), voiceOn: false));
    for (var i = 0; i < 5; i++) {
      expect(find.text('Watch the order'), findsWidgets);
      await wait(t, 3600); // three tiles light up
      expect(find.text('Now tap them in the same order'), findsWidgets);
      for (var k = 0; k < 3; k++) {
        await t.tap(find.byType(GameTile).first);
        await wait(t, 300);
      }
      await wait(t, 1700);
    }
    expect((await sessions(t)).single['trials'], 5);
    await closeResult(t);
  });

  testWidgets('Match the Tile: all tiles are matched in each of three boards', (t) async {
    await open(t, () => TileGame(db: db, patientId: pid, baselineLevel: 1, startLevel: 1,
        language: 'en', voice: Voice(), voiceOn: false));
    for (var board = 0; board < 3; board++) {
      await wait(t, 4200); // the board is shown face up first
      // Try every pair; matched tiles ignore further taps.
      for (var i = 0; i < 6; i++) {
        for (var j = i + 1; j < 6; j++) {
          await t.tap(find.byType(GameTile).at(i));
          await t.tap(find.byType(GameTile).at(j));
          await wait(t, 1000);
        }
      }
      await wait(t, 1800);
    }
    expect((await sessions(t)).single['trials'], 3);
    await closeResult(t);
  });

  testWidgets('leaving early saves what was played and shows no closing card', (t) async {
    await open(t, () => SortGame(db: db, patientId: pid, baselineLevel: 1, startLevel: 1,
        language: 'en', voice: Voice(), voiceOn: false));
    await t.tap(find.byType(GameTile).at(1));
    await wait(t, 1700);
    await t.tap(find.text('Finish'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pumpAndSettle();
    expect(find.text('Continue'), findsNothing);
    expect(find.text('open'), findsOneWidget);
    expect((await sessions(t)).single['trials'], 1);
  });
}
