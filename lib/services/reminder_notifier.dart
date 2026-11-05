import 'package:flutter/foundation.dart';
import 'dart:io' show Platform;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/reminder_schedule.dart';
import '../core/strings.dart';
import '../data/app_database.dart';
import 'push_events.dart';

/// Whether this phone will actually show the reminders.
enum NotifyAccess {
  /// Notifications are allowed and alarms are exact.
  ok,

  /// The person said "Don't allow" (or switched notifications off): nothing shows.
  blocked,

  /// Notifications show, but Android has not allowed exact alarms, so they may
  /// arrive a few minutes late.
  inexactOnly,
}

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

  /// Android keeps a notification's sound on its *channel* and a channel cannot be
  /// changed once the phone has created it, so reminders use a channel made on
  /// purpose with sound and vibration (the first version of the app made one that
  /// could end up silent). Chat push uses its own.
  static const kReminderChannel = 'reminder_alerts';
  static const kMessageChannel = 'messages';

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      kReminderChannel,
      'Reminder alerts',
      channelDescription: 'Sounds and pops up when it is time for a medicine, a routine or an appointment',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.reminder,
      // Rings like an alarm so a reminder is heard even when the ringer is low.
      audioAttributesUsage: AudioAttributesUsage.alarm,
      visibility: NotificationVisibility.private,
    ),
    iOS: DarwinNotificationDetails(presentSound: true, presentAlert: true),
  );

  @visibleForTesting
  static NotificationDetails get reminderDetails => _details;

  static bool _tzReady = false;

  /// Sets up the time zone so repeating alarms keep the right wall-clock time
  /// (and survive a daylight-saving change).
  static Future<void> _initTimeZone() async {
    if (_tzReady) return;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation(await FlutterTimezone.getLocalTimezone()));
    } catch (_) {
      // Unknown zone name: fall back to a fixed offset (Java and iOS both
      // understand "GMT+05:30"). Reminders are rebuilt on every app start.
      final off = DateTime.now().timeZoneOffset;
      final m = off.inMinutes.abs();
      final name = 'GMT${off.isNegative ? '-' : '+'}'
          '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
      tz.setLocalLocation(tz.Location(name, [-8640000000000000], [0],
          [tz.TimeZone(off.inMilliseconds, isDst: false, abbreviation: name)]));
    }
    _tzReady = true;
  }

  void _tapped(NotificationResponse r) {
    final open = PushOpen.fromPayload(r.payload);
    if (open != null) kPushOpen.value = open;
  }

  Future<void> _initPlugin() async {
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: _tapped,
    );
    await _createChannels();
    await _initTimeZone();
  }

  /// Makes the Android notification channels (safe to repeat). Chat push names the
  /// `messages` channel, so it must exist before the first push arrives.
  Future<void> _createChannels() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    try {
      await android.deleteNotificationChannel('reminders'); // the old, possibly silent one
    } catch (_) {}
    await android.createNotificationChannel(const AndroidNotificationChannel(
      kReminderChannel,
      'Reminder alerts',
      description: 'Sounds and pops up when it is time for a medicine, a routine or an appointment',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      audioAttributesUsage: AudioAttributesUsage.alarm,
    ));
    await android.createNotificationChannel(const AndroidNotificationChannel(
      kMessageChannel,
      'Messages',
      description: 'New chat messages and routine updates',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    ));
  }

  /// Whether Android will make a sound for reminder alerts: the importance and
  /// sound setting of the reminder channel as the phone has it now (the person can
  /// switch a channel to silent in the phone's settings). Null if unknown.
  Future<({bool playsSound, bool loudEnough})?> soundStatus() async {
    try {
      final android = _android;
      if (android == null) return null;
      final channels = await android.getNotificationChannels() ?? const [];
      for (final c in channels) {
        if (c.id == kReminderChannel) {
          return (
            playsSound: c.playSound,
            loudEnough: c.importance.value >= Importance.high.value,
          );
        }
      }
    } catch (e) {
      lastProblem = 'sound: $e';
    }
    return null;
  }

  /// Why the last notification step failed (null when all went well). A failed
  /// notification must never stop the app from opening or a routine from being
  /// saved, so problems are recorded here instead of thrown.
  String? lastProblem;

  Future<void> init() async {
    try {
      await _init();
    } catch (e) {
      lastProblem = 'init: $e';
    }
  }

  Future<void> _init() async {
    await _initPlugin();
    // The app was started by tapping a notification.
    try {
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        final open = PushOpen.fromPayload(launch!.notificationResponse?.payload);
        if (open != null) kPushOpen.value = open;
      }
    } catch (_) {}
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
      await android?.requestExactAlarmsPermission();
    }
  }

  /// For the background push handler: no permission prompts, nothing to show.
  Future<void> initBackground() => _initPlugin();

  AndroidFlutterLocalNotificationsPlugin? get _android => Platform.isAndroid
      ? _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      : null;

  /// Can this phone show reminders right now? Never throws (tests and desktop
  /// have no notification plugin).
  Future<NotifyAccess> access() async {
    try {
      final android = _android;
      if (android == null) return NotifyAccess.ok;
      if (await android.areNotificationsEnabled() == false) return NotifyAccess.blocked;
      if (await android.canScheduleExactNotifications() == false) {
        return NotifyAccess.inexactOnly;
      }
    } catch (_) {}
    return NotifyAccess.ok;
  }

  /// Asks for what is missing. Android stops showing the notification prompt
  /// after "Don't allow" a couple of times, so when asking does nothing the
  /// phone's settings page for this app opens. Exact alarms are granted on a
  /// system settings page, which opens directly.
  Future<NotifyAccess> requestAccess() async {
    try {
      final android = _android;
      if (android != null) {
        if (await android.areNotificationsEnabled() == false) {
          await android.requestNotificationsPermission();
          if (await android.areNotificationsEnabled() == false) {
            await ph.openAppSettings();
            return NotifyAccess.blocked;
          }
        }
        if (await android.canScheduleExactNotifications() == false) {
          await android.requestExactAlarmsPermission();
        }
      }
    } catch (_) {}
    return access();
  }

  /// How many reminder alerts the phone currently holds (null if it cannot say).
  Future<int?> pendingCount() async {
    try {
      return (await _plugin.pendingNotificationRequests()).length;
    } catch (e) {
      lastProblem = 'pending: $e';
      return null;
    }
  }

  /// For the Notification check screen: asks for an alert one minute from now,
  /// the same way real reminders are scheduled. Returns the error text, or null.
  Future<String?> scheduleTest(String title, String body) async {
    try {
      await _initTimeZone();
      final exact = await access() != NotifyAccess.inexactOnly;
      await _plugin.zonedSchedule(
        0x7e57,
        title,
        body,
        tz.TZDateTime.now(tz.local).add(const Duration(minutes: 1)),
        _details,
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: 'reminder',
      );
      return null;
    } catch (e) {
      return '$e';
    }
  }

  /// Shows a notification straight away; returns the error text, or null.
  Future<String?> showTest(String title, String body) async {
    try {
      await _plugin.show(0x7e58, title, body, _details, payload: 'reminder');
      return null;
    } catch (e) {
      return '$e';
    }
  }

  /// Shows a notification now (used by the background push handler).
  Future<void> showNow(String title, String body, {String? payload}) =>
      _plugin.show(0x5ee0, title, body, _details, payload: payload);

  /// Cancels every pending reminder (used on logout, so nothing fires for a
  /// signed-out account on a shared phone).
  Future<void> clear() async {
    try {
      await _plugin.cancelAll();
    } catch (e) {
      lastProblem = 'clear: $e';
    }
  }

  static DateTimeComponents? _match(AlertRepeat r) {
    switch (r) {
      case AlertRepeat.daily:
        return DateTimeComponents.time;
      case AlertRepeat.weekly:
        return DateTimeComponents.dayOfWeekAndTime;
      case AlertRepeat.yearly:
        return DateTimeComponents.dateAndTime;
      case AlertRepeat.none:
        return null;
    }
  }

  /// Rebuilds the pending notifications from the database. Call after any
  /// reminder or consent change and on every app start. Daily, weekly and
  /// yearly reminders are handed to the OS as *repeating* notifications, so
  /// they keep ringing for as long as the phone is on, even if the app is not
  /// opened again.
  Future<void> resync({required String patientId, required String lang}) async {
    try {
      await _resync(patientId, lang);
    } catch (e) {
      // Never let a notification problem break saving a routine or opening the app.
      lastProblem = 'resync: $e';
      debugPrint('Reminders could not be rebuilt: $e');
    }
  }

  Future<void> _resync(String patientId, String lang) async {
    await _plugin.cancelAll();
    if (!await _db.hasConsent(patientId, 'reminders')) return;
    await _initTimeZone();
    // Without the exact-alarm permission Android refuses exact alarms; an
    // inexact one still rings (a few minutes late at worst).
    final exact = await access() != NotifyAccess.inexactOnly;
    var id = 0;
    for (final a in repeatingAlerts(await _db.listReminders(patientId), DateTime.now(),
        limit: _maxPending)) {
      final text = tr(lang, 'notif_${a.kind.name}');
      final body = a.headsUp ? '${tr(lang, 'notifSoon')}: $text' : text;
      // Built from the wall-clock fields in the local zone, so the repeat
      // stays at the same local time all year.
      final f = a.first;
      final when = tz.TZDateTime(tz.local, f.year, f.month, f.day, f.hour, f.minute);
      try {
        await _plugin.zonedSchedule(
          id++,
          tr(lang, 'appName'),
          body,
          when,
          _details,
          androidScheduleMode: exact
              ? AndroidScheduleMode.exactAllowWhileIdle
              : AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: _match(a.repeat),
          payload: 'reminder',
        );
      } catch (e) {
        debugPrint('Could not schedule a reminder: $e');
      }
    }
  }
}
