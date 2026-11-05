import 'package:flutter/material.dart';

import '../../core/notify_text.dart';
import '../../core/theme.dart';
import '../../services/reminder_notifier.dart';

/// Shown above the app when this phone will not ring reminders: the person
/// tapped "Don't allow" on the notification prompt (Android 13+), or Android
/// has not allowed exact alarms. One tap asks again, or opens the phone's
/// settings page for the app when Android no longer shows the prompt.
class NotifyAccessBanner extends StatefulWidget {
  const NotifyAccessBanner({super.key, required this.notifier, required this.lang});
  final ReminderNotifier notifier;
  final String lang;

  @override
  State<NotifyAccessBanner> createState() => _NotifyAccessBannerState();
}

class _NotifyAccessBannerState extends State<NotifyAccessBanner>
    with WidgetsBindingObserver {
  NotifyAccess _access = NotifyAccess.ok;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Coming back from the settings page: look again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check({bool request = false}) async {
    final a =
        request ? await widget.notifier.requestAccess() : await widget.notifier.access();
    if (mounted && a != _access) setState(() => _access = a);
  }

  @override
  Widget build(BuildContext context) {
    if (_access == NotifyAccess.ok) return const SizedBox.shrink();
    final blocked = _access == NotifyAccess.blocked;
    return Material(
      color: blocked ? Palette.tileRed : Palette.tileOrange,
      child: InkWell(
        key: const ValueKey('notifyAccessBanner'),
        onTap: () => _check(request: true),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            Icon(blocked ? Icons.notifications_off_rounded : Icons.alarm_off_rounded,
                color: blocked ? Palette.red : Palette.orange),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                notifyText(widget.lang, blocked ? 'notifBlocked' : 'notifInexact'),
                style: const TextStyle(fontSize: 15, color: Palette.ink),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => _check(request: true),
              child: Text(notifyText(widget.lang, 'notifAllow')),
            ),
          ]),
        ),
      ),
    );
  }
}
