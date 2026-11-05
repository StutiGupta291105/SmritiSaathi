import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smriti_assist/data/app_database.dart';
import 'package:smriti_assist/features/chat/doctor_directory_screen.dart';
import 'package:smriti_assist/features/shell/patient_shell.dart';
import 'package:smriti_assist/services/api_client.dart';
import 'package:smriti_assist/services/reminder_notifier.dart';
import 'package:smriti_assist/services/voice.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _NoopNotifier extends ReminderNotifier {
  _NoopNotifier(super.db);
  @override
  Future<void> resync({required String patientId, required String lang}) async {}
}

http.Response _j(Object b) =>
    http.Response(jsonEncode(b), 200, headers: {'content-type': 'application/json'});

void main() {
  late AppDatabase db;
  late String pid;
  late Map<String, Object?> patient;

  setUp(() async {
    sqfliteFfiInit();
    final raw = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(
            singleInstance: false,
            version: AppDatabase.schemaVersion,
            onCreate: (d, _) => AppDatabase.createSchema(d)));
    db = AppDatabase.forTesting(raw);
    final a = await db.createAccount(phone: '+919876543210', role: 'patient', name: 'Asha');
    pid = await db.createPatient(
        accountId: a, phone: '+919876543210', displayName: 'Asha',
        baselineLevel: 2, language: 'en', createdBy: 'x');
    await db.recordConsent(
        patientId: pid,
        purposes: {'gameplay': true, 'reminders': true, 'sync': true},
        givenByName: 'Asha', givenByRelation: 'self', noticeVersion: 'v2');
    patient = {
      'id': pid, 'display_name': 'Asha', 'language': 'en', 'phone': '+919876543210',
      'dob': '1948-03-02', 'voice_enabled': 0, 'photo': null, 'baseline_level': 2, 'setup_stage': 5,
    };
  });

  ApiClient api(List<Map<String, Object?>> doctors) => ApiClient(
      baseUrl: 'https://api.example.com',
      tokens: MemoryTokenStore(),
      client: MockClient((r) async {
        if (r.url.path == '/v1/chat/doctors') return _j(doctors);
        if (r.url.path == '/v1/chat/threads') return _j(<Object>[]);
        return _j(<Object>[]);
      }));

  Future<void> pump(WidgetTester t, ApiClient a) async {
    t.view.physicalSize = const Size(800, 2200);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
        home: PatientShell(
            db: db, notifier: _NoopNotifier(db), voice: Voice(), patient: patient,
            api: a, onPatientChanged: () {}, onLogout: () {})));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pump(const Duration(milliseconds: 400));
  }

  testWidgets('Talk to Doctor opens the directory with the patient\'s doctor pinned', (t) async {
    await pump(t, api([
      {'doctor_id': 'd1', 'name': 'Dr Rao', 'verified': true, 'pinned': true, 'thread_id': 'L1'},
      {'doctor_id': 'd2', 'name': 'Dr Sen', 'verified': false, 'pinned': false, 'thread_id': null},
    ]));
    await t.scrollUntilVisible(find.byKey(const ValueKey('talkDoctor')), 200,
        scrollable: find.byType(Scrollable).first);
    await t.tap(find.byKey(const ValueKey('talkDoctor')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pump();
    await t.pump();
    expect(find.byType(DoctorDirectoryScreen), findsOneWidget);
    expect(find.text('Your doctor'), findsOneWidget);
    expect(find.text('Dr Rao'), findsOneWidget);
    expect(find.text('Dr Sen'), findsOneWidget);
  });

  testWidgets('every bottom tab and home tile opens without an error', (t) async {
    await pump(t, api(const []));
    for (final label in ['Games', 'Reminders', 'Profile', 'Home']) {
      await t.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
      await t.pump(const Duration(milliseconds: 400));
      expect(t.takeException(), isNull, reason: label);
    }
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 10));
  });
}
