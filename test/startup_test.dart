import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti_assist/data/app_database.dart';
import 'package:smriti_assist/data/session_store.dart';
import 'package:smriti_assist/main.dart';
import 'package:smriti_assist/services/otp_service.dart';
import 'package:smriti_assist/services/reminder_notifier.dart';
import 'package:smriti_assist/services/voice.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Stands in for a phone where scheduling a notification fails.
class _BrokenNotifier extends ReminderNotifier {
  _BrokenNotifier(super.db);
  @override
  Future<void> resync({required String patientId, required String lang}) async =>
      throw StateError('exact_alarms_not_permitted');
}

/// A notification plugin that never answers.
class _HangingNotifier extends ReminderNotifier {
  _HangingNotifier(super.db);
  @override
  Future<void> resync({required String patientId, required String lang}) =>
      Completer<void>().future;
}

class _StuckSession extends SessionStore {
  const _StuckSession();
  @override
  Future<String?> read() => Completer<String?>().future; // secure storage that never answers
}

class _MemorySession extends SessionStore {
  _MemorySession(this.id);
  String? id;
  @override
  Future<String?> read() async => id;
  @override
  Future<void> write(String accountId) async => id = accountId;
  @override
  Future<void> clear() async => id = null;
}

void main() {
  late AppDatabase db;
  late String accountId;

  setUp(() async {
    sqfliteFfiInit();
    final raw = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(
            singleInstance: false,
            version: AppDatabase.schemaVersion,
            onCreate: (d, _) => AppDatabase.createSchema(d)));
    db = AppDatabase.forTesting(raw);
    accountId = await db.createAccount(phone: '+919876543210', role: 'patient', name: 'Asha');
    final pid = await db.createPatient(
        accountId: accountId, phone: '+919876543210', displayName: 'Asha',
        baselineLevel: 2, language: 'en', createdBy: 'x');
    await db.setSetupStage(pid, 5);
    await db.setPermissionsAsked(accountId); // already past the one-time permissions screen
  });

  Future<void> boot(WidgetTester t, ReminderNotifier n) async {
    await t.pumpWidget(MaterialApp(
        home: Root(
            db: db, notifier: n, voice: Voice(), otp: defaultOtpService(null),
            session: _MemorySession(accountId))));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pump(const Duration(milliseconds: 500));
  }

  testWidgets('if setting up reminders fails at start, the app still opens (it is not waited for)', (t) async {
    await boot(t, _BrokenNotifier(db));
    expect(find.text('Something went wrong while opening the app.'), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget); // the patient home is showing
  });

  testWidgets('a working start opens the patient home', (t) async {
    await boot(t, _NoopNotifier(db));
    expect(find.text('Something went wrong while opening the app.'), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('reminders that never finish setting up do not hold the app on a spinner', (t) async {
    await boot(t, _HangingNotifier(db));
    expect(find.text('Something went wrong while opening the app.'), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 31)); // lets the background safety timer run out
  });

  testWidgets('a stalled step is named on screen instead of spinning for ever', (t) async {
    final old = RootStateTimeouts.get();
    RootStateTimeouts.set(const Duration(milliseconds: 200));
    addTearDown(() => RootStateTimeouts.set(old));
    await t.pumpWidget(MaterialApp(
        home: Root(
            db: db, notifier: _NoopNotifier(db), voice: Voice(), otp: defaultOtpService(null),
            session: const _StuckSession())));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('stuck while: reading the saved sign-in'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}

class _NoopNotifier extends ReminderNotifier {
  _NoopNotifier(super.db);
  @override
  Future<void> resync({required String patientId, required String lang}) async {}
}
