import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti_assist/data/app_database.dart';
import 'package:smriti_assist/features/companion/chat_screen.dart';
import 'package:smriti_assist/services/companion_service.dart';
import 'package:smriti_assist/services/voice.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database raw;
  late AppDatabase db;

  setUp(() async {
    sqfliteFfiInit();
    raw = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(
            singleInstance: false,
            version: AppDatabase.schemaVersion,
            onCreate: (d, _) => AppDatabase.createSchema(d)));
    db = AppDatabase.forTesting(raw);
  });

  Widget app() => MaterialApp(
          home: ChatScreen(
        service: CompanionService(db: db, clock: () => DateTime(2026, 3, 10, 10, 30)),
        voice: Voice(),
        db: db,
        patientId: 'p',
        name: 'Asha Devi',
        lang: 'en',
        voiceEnabled: false,
      ));

  testWidgets('greets, answers the day button, and shows the helper note', (t) async {
    await t.pumpWidget(app());
    await t.pump();
    expect(find.textContaining('not a person or a doctor'), findsOneWidget);
    expect(find.textContaining('I am Smriti'), findsOneWidget);
    await t.tap(find.text('What day is it?'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Today is Tuesday, 10 March 2026'), findsOneWidget);
  });

  testWidgets('an emergency message shows the call button and no network is needed',
      (t) async {
    await t.pumpWidget(app());
    await t.enterText(find.byType(TextField), 'I have chest pain');
    await t.tap(find.byIcon(Icons.send_rounded));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('call 112'), findsOneWidget);
    expect(find.text('Call 112 (emergency)'), findsOneWidget);
  });
}
