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
  });

  Future<void> boot(WidgetTester t, ReminderNotifier n) async {
    await t.pumpWidget(MaterialApp(
        home: Root(
            db: db, notifier: n, voice: Voice(), otp: defaultOtpService(null),
            session: _MemorySession(accountId))));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pump(const Duration(milliseconds: 500));
  }

  testWidgets('if setting up reminders fails at start, the person sees why and can retry (no endless spinner)', (t) async {
    await boot(t, _BrokenNotifier(db));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Something went wrong while opening the app.'), findsOneWidget);
    expect(find.textContaining('exact_alarms_not_permitted'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('a working start opens the patient home', (t) async {
    await boot(t, _NoopNotifier(db));
    expect(find.text('Something went wrong while opening the app.'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}

class _NoopNotifier extends ReminderNotifier {
  _NoopNotifier(super.db);
  @override
  Future<void> resync({required String patientId, required String lang}) async {}
}
