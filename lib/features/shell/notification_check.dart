import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/app_database.dart';
import '../../services/firebase_push.dart';
import '../../services/push_service.dart';
import '../../services/reminder_notifier.dart';

/// A support screen that says, in plain words, why reminders and alerts may not
/// be reaching this phone, and lets the person try one. It is English only on
/// purpose: it is for whoever is helping set the phone up.
class NotificationCheckScreen extends StatefulWidget {
  const NotificationCheckScreen({
    super.key,
    required this.notifier,
    required this.db,
    required this.patientId,
    required this.lang,
    this.pushSource = const FirebasePushSource(),
  });
  final ReminderNotifier notifier;
  final AppDatabase db;
  final String patientId, lang;
  final PushTokenSource pushSource;

  @override
  State<NotificationCheckScreen> createState() => _NotificationCheckScreenState();
}

class _Row {
  const _Row(this.ok, this.title, this.detail);
  final bool? ok; // null = information only
  final String title, detail;
}

class _NotificationCheckScreenState extends State<NotificationCheckScreen>
    with WidgetsBindingObserver {
  List<_Row> _rows = const [];
  String? _message;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _run();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _run(); // back from the phone's settings
  }

  Future<void> _run() async {
    final access = await widget.notifier.access();
    final consent = await widget.db.hasConsent(widget.patientId, 'reminders');
    final reminders = (await widget.db.listReminders(widget.patientId)).length;
    final pending = await widget.notifier.pendingCount();
    final sound = await widget.notifier.soundStatus();
    final token = await widget.pushSource.token();
    if (!mounted) return;
    setState(() => _rows = [
          _Row(
              access != NotifyAccess.blocked,
              'Notifications are allowed',
              access == NotifyAccess.blocked
                  ? 'Android is blocking notifications for this app. Tap "Fix permissions".'
                  : 'Yes.'),
          _Row(
              access != NotifyAccess.inexactOnly,
              'Exact alarms are allowed',
              access == NotifyAccess.inexactOnly
                  ? 'No: reminders may arrive a few minutes late. Tap "Fix permissions" and allow "Alarms & reminders".'
                  : 'Yes.'),
          _Row(
              sound == null ? null : (sound.playsSound && sound.loudEnough),
              'Alert sound',
              sound == null
                  ? 'Could not read the phone\'s sound setting.'
                  : (sound.playsSound && sound.loudEnough
                      ? 'On: reminders ring and pop up.'
                      : 'Off: the phone has this app\'s alerts on silent. Tap "Open phone settings", then Notifications > Reminder alerts, and set Importance to Urgent or High with Sound on. Also check the phone is not on Do Not Disturb.')),
          _Row(consent, 'Reminders are switched on in Privacy and permissions',
              consent ? 'Yes.' : 'No: nothing is scheduled until you allow reminders there.'),
          _Row(reminders > 0, 'Reminders saved on this phone', '$reminders'),
          _Row(
              pending == null ? false : (reminders == 0 || pending > 0),
              'Alerts waiting in the phone',
              pending == null
                  ? 'Could not read them.'
                  : (reminders > 0 && pending == 0
                      ? '0: your reminders are saved but no alert is scheduled. Tap "Rebuild alerts".'
                      : '$pending')),
          _Row(
              token != null,
              'Push (messages when the app is closed)',
              token != null
                  ? 'This phone is registered for push.'
                  : 'Not available in this build (no Firebase project), so chat and "routine updated" alerts arrive only while the app is open.'),
          _Row(null, 'If alerts are late or never come',
              'On Oppo, Realme, OnePlus, Xiaomi and Vivo phones also allow Auto-start for this app and set its Battery use to "Unrestricted"; these phones stop apps that run in the background.'),
          if (widget.notifier.lastProblem != null)
            _Row(false, 'Last problem recorded', widget.notifier.lastProblem!),
        ]);
  }

  Future<void> _do(Future<String?> Function() action, String okText) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final err = await action();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = err == null ? okText : 'Failed: $err';
    });
    await _run();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notification check')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            for (final r in _rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(
                        r.ok == null
                            ? Icons.info_outline_rounded
                            : (r.ok! ? Icons.check_circle_rounded : Icons.error_rounded),
                        color: r.ok == null
                            ? Palette.blue
                            : (r.ok! ? Palette.green : Palette.red)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r.title,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(r.detail,
                            style: const TextStyle(
                                fontSize: 13.5, color: Palette.muted, height: 1.35)),
                      ]),
                    ),
                  ]),
                ),
              ),
            const SizedBox(height: 6),
            FilledButton.icon(
              key: const ValueKey('notifyFix'),
              onPressed: _busy
                  ? null
                  : () => _do(() async {
                        await widget.notifier.requestAccess();
                        return null;
                      }, 'Permissions checked.'),
              icon: const Icon(Icons.verified_user_outlined),
              label: const Text('Fix permissions'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const ValueKey('notifySettings'),
              onPressed: _busy ? null : () => ph.openAppSettings(),
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Open phone settings'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const ValueKey('notifyNow'),
              onPressed: _busy
                  ? null
                  : () => _do(
                      () => widget.notifier.showTest('Smriti Sathi', 'Test: this is an alert shown now.'),
                      'Sent. Did a notification appear? If not, notifications are blocked on this phone.'),
              icon: const Icon(Icons.notifications_active_outlined),
              label: const Text('Show a test alert now'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const ValueKey('notifySoon'),
              onPressed: _busy
                  ? null
                  : () => _do(
                      () => widget.notifier.scheduleTest(
                          'Smriti Sathi', 'Test: this alert was scheduled one minute ago.'),
                      'Scheduled. Lock the phone and wait one minute: an alert should appear.'),
              icon: const Icon(Icons.alarm_add_outlined),
              label: const Text('Schedule a test alert in 1 minute'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const ValueKey('notifyRebuild'),
              onPressed: _busy
                  ? null
                  : () => _do(() async {
                        await widget.notifier
                            .resync(patientId: widget.patientId, lang: widget.lang);
                        return widget.notifier.lastProblem;
                      }, 'Alerts rebuilt from your reminders.'),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Rebuild alerts'),
            ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(_message!,
                    key: const ValueKey('notifyMessage'),
                    style: const TextStyle(fontSize: 14, height: 1.4)),
              ),
          ],
        ),
      ),
    );
  }
}
