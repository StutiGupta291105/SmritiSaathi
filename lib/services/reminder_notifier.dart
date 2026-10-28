import 'dart:io' show Platform;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/reminder_schedule.dart';
import '../core/strings.dart';
import '../data/app_database.dart';

/// Schedules reminders as on-device notifications, so they fire with no
/// internet. Compliance notes:
///  * Scheduling only happens while the 'reminders' purpose is consented.
///  * Lock-screen text is generic per kind ("Time for your medicine"); the
///    medicine name or appointment details stay inside the encrypted DB and
///    are shown only in the app (DPDP data minimisation, privacy on a shared
///    or lost phone).
///  * No third-party push service and no network call is involved.
class ReminderNotifier {
  ReminderNotifier(this._db);
  final AppDatabase _db;
  final _plugin = FlutterLocalNotificationsPlugin();
  static const _maxPending = 60; // iOS keeps at most 64 pending local notifications

  Future<void> init() async {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(
        tz.getLocation(await FlutterTimezone.getLocalTimezone()));
    await _plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ));
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
      await android?.requestExactAlarmsPermission();
    }
  }

  /// Rebuilds the pending notifications from the database. Call after any
  /// reminder or consent change and on every app start.
  Future<void> resync({required String patientId, required String lang}) async {
    await _plugin.cancelAll();
    if (!await _db.hasConsent(patientId, 'reminders')) return;
    final now = DateTime.now();
    final upcoming = <(DateTime, Reminder)>[];
    for (final r in await _db.listReminders(patientId)) {
      for (final at in nextOccurrences(r, now, count: 14)) {
        upcoming.add((at, r));
      }
    }
    upcoming.sort((a, b) => a.$1.compareTo(b.$1));
    var id = 0;
    for (final (at, r) in upcoming.take(_maxPending)) {
      await _plugin.zonedSchedule(
        id++,
        tr(lang, 'appName'),
        tr(lang, 'notif_${r.kind.name}'),
        tz.TZDateTime.from(at, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'reminders',
            'Reminders',
            importance: Importance.high,
            priority: Priority.high,
            visibility: NotificationVisibility.private,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }
}
