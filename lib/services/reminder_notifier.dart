import 'package:flutter/foundation.dart';
import 'dart:io' show Platform;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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
/// Bumped when reminders change from outside the screens (a caregiver or doctor
/// added or removed one), so open screens reload.
final ValueNotifier<int> kRemindersRevision = ValueNotifier<int>(0);

class ReminderNotifier {
  ReminderNotifier(this._db);
  final AppDatabase _db;
  final _plugin = FlutterLocalNotificationsPlugin();
  static const _maxPending = 60; // iOS keeps at most 64 pending local notifications

  /// Why the last notification could not be scheduled (null when all went well).
  /// A failed notification must never stop the app from starting or a routine
  /// from being saved, so errors are recorded here instead of thrown.
  String? lastProblem;

  Future<void> init() async {
    try {
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
    } catch (e) {
      lastProblem = 'init: $e';
    }
  }

  /// Cancels every pending reminder (used on logout, so nothing fires for a
  /// signed-out account on a shared phone).
  Future<void> clear() async {
    try {
      await _plugin.cancelAll();
    } catch (e) {
      lastProblem = 'clear: $e';
    }
  }

  /// Rebuilds the pending notifications from the database. Call after any
  /// reminder or consent change and on every app start.
  Future<void> resync({required String patientId, required String lang}) async {
    try {
      await _resync(patientId, lang);
    } catch (e) {
      // Never let a notification problem break saving a routine or opening the app.
      lastProblem = 'resync: $e';
    }
  }

  Future<void> _resync(String patientId, String lang) async {
    await _plugin.cancelAll();
    lastProblem = null;
    if (!await _db.hasConsent(patientId, 'reminders')) return;
    // Exact alarms need a permission Android 12+ lets the person refuse. Without
    // it, ask for approximate times instead of failing: a reminder a few minutes
    // late is better than none.
    var exact = true;
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      exact = await android?.canScheduleExactNotifications() ?? true;
    }
    var id = 0;
    for (final a in plannedAlerts(await _db.listReminders(patientId), DateTime.now(),
        limit: _maxPending)) {
      final text = tr(lang, 'notif_${a.kind.name}');
      final body = a.headsUp ? '${tr(lang, 'notifSoon')}: $text' : text;
      final when = tz.TZDateTime.from(a.at, tz.UTC);
      Future<void> schedule(AndroidScheduleMode mode) => _plugin.zonedSchedule(
            id,
            tr(lang, 'appName'),
            body,
            // Each notification is a one-off absolute instant computed from local
            // wall-clock time (DST-correct), so no timezone database is needed.
            when,
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
            androidScheduleMode: mode,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
          );
      try {
        await schedule(exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle);
      } catch (_) {
        try {
          await schedule(AndroidScheduleMode.inexactAllowWhileIdle);
          exact = false; // do not try exact again for the rest
        } catch (e) {
          lastProblem = 'schedule: $e';
          continue; // skip this one, keep the others
        }
      }
      id++;
    }
  }
}
