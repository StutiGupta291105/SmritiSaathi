import 'package:permission_handler/permission_handler.dart' as ph;

import 'reminder_notifier.dart';

/// Asks the phone for everything the app needs, in one go. It is called once, right after
/// an account is created, and never again: nothing else in the app shows a permission
/// prompt (a feature whose permission was refused just says how to turn it on).
///
/// What is needed, and what is not:
///  * alerts and notifications, and exact alarms (reminders ring on time)
///  * microphone (voice notes)
///  * location, only used while the person shares it
///  * NOT needed: camera and photos (the phone's own camera and gallery are opened and hand
///    back the one picture), calls (the dialer opens with the number filled in), storage,
///    contacts, SMS.
abstract class PermissionAsker {
  Future<void> askAll(ReminderNotifier notifier);
}

class DevicePermissionAsker implements PermissionAsker {
  const DevicePermissionAsker();

  @override
  Future<void> askAll(ReminderNotifier notifier) async {
    // Each one is awaited so the phone's dialogs come one after another, not on top of each other.
    try {
      await ph.Permission.microphone.request();
    } catch (_) {}
    try {
      await ph.Permission.locationWhenInUse.request();
    } catch (_) {}
    // Notifications and exact alarms last: the exact-alarm switch is a phone settings page.
    await notifier.requestSystemAccess();
  }
}

/// For tests and builds without a phone.
class NoPermissionAsker implements PermissionAsker {
  const NoPermissionAsker();
  @override
  Future<void> askAll(ReminderNotifier notifier) async {}
}
