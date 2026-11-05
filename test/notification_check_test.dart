import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti_assist/core/reminder_schedule.dart';
import 'package:smriti_assist/data/app_database.dart';
import 'package:smriti_assist/features/shell/notification_check.dart';
import 'package:smriti_assist/services/push_service.dart';
import 'package:smriti_assist/services/reminder_notifier.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeNotifier extends ReminderNotifier {
  _FakeNotifier(super.db, {this.accessIs = NotifyAccess.ok, this.pending = 3});
  NotifyAccess accessIs;
  int? pending;
  final log = <String>[];
  @override
  Future<NotifyAccess> access() async => accessIs;
  @override
  Future<NotifyAccess> requestAccess() async {
    log.add('request');
    accessIs = NotifyAccess.ok;
    return accessIs;
  }

  @override
  Future<int?> pendingCount() async => pending;
  @override
  Future<String?> showTest(String t, String b) async {
    log.add('show');
    return null;
  }

  @override
  Future<String?> scheduleTest(String t, String b) async {
    log.add('schedule');
    return 'exact_alarms_not_permitted';
  }

  @override
  Future<void> resync({required String patientId, required String lang}) async => log.add('resync');
}

class _Token implements PushTokenSource {
  const _Token(this.value);
  final String? value;
  @override
  Future<String?> token() async => value;
}

void main() {
  late AppDatabase db;
  late String pid;

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
  });

  Future<void> open(WidgetTester t, _FakeNotifier n, {String? token}) async {
    t.view.physicalSize = const Size(800, 2400);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
        home: NotificationCheckScreen(
            notifier: n, db: db, patientId: pid, lang: 'en', pushSource: _Token(token))));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pump();
    await t.pump();
  }

  testWidgets('it says what is wrong: blocked notifications, no consent, no push', (t) async {
    await open(t, _FakeNotifier(db, accessIs: NotifyAccess.blocked, pending: 0));
    expect(find.textContaining('Android is blocking notifications'), findsOneWidget);
    expect(find.textContaining('nothing is scheduled until you allow reminders'), findsOneWidget);
    expect(find.textContaining('no Firebase project'), findsOneWidget);
    expect(find.textContaining('Auto-start'), findsOneWidget);
  });

  testWidgets('saved reminders but no alert scheduled is called out', (t) async {
    await t.runAsync(() => db.recordConsent(
        patientId: pid, purposes: {'gameplay': true, 'reminders': true},
        givenByName: 'Asha', givenByRelation: 'self', noticeVersion: 'v2'));
    await t.runAsync(() => db.addReminder(
        patientId: pid, kind: ReminderKind.activity, label: 'Walk', hour: 7, minute: 0, createdBy: 'x'));
    await open(t, _FakeNotifier(db, pending: 0));
    expect(find.textContaining('no alert is scheduled'), findsOneWidget);
  });

  testWidgets('buttons: fix permissions, test now, test in a minute (shows the error), rebuild', (t) async {
    final n = _FakeNotifier(db, accessIs: NotifyAccess.blocked);
    await open(t, n, token: 'a-token-longer-than-twenty-chars');
    expect(find.textContaining('registered for push'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('notifyFix')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pump();
    await t.pump();
    expect(n.log, contains('request'));
    expect(find.textContaining('Android is blocking notifications'), findsNothing);
    await t.tap(find.byKey(const ValueKey('notifyNow')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pump();
    expect(n.log, contains('show'));
    expect(find.textContaining('Did a notification appear?', skipOffstage: false), findsOneWidget);
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.byKey(const ValueKey('notifySoon')), 200,
        scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('notifySoon')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pump();
    expect(find.textContaining('Failed: exact_alarms_not_permitted', skipOffstage: false), findsOneWidget);
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.byKey(const ValueKey('notifyRebuild')), 200,
        scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('notifyRebuild')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pump();
    expect(n.log, contains('resync'));
  });
}
