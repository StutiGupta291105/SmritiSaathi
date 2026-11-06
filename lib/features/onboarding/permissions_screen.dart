import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../services/app_permissions.dart';
import '../../services/reminder_notifier.dart';

/// Shown once, right after an account is created: every phone permission the app needs,
/// asked together. Opening the app the first time shows no prompt at all; after this screen
/// no other prompt is shown, ever.
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({
    super.key,
    required this.lang,
    required this.asker,
    required this.notifier,
    required this.onDone,
  });
  final String lang;
  final PermissionAsker asker;
  final ReminderNotifier notifier;
  final VoidCallback onDone;

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  bool _busy = false;

  String t(String k) => tr(widget.lang, k);

  Future<void> _allow() async {
    setState(() => _busy = true);
    try {
      await widget.asker.askAll(widget.notifier);
    } catch (_) {}
    if (mounted) widget.onDone();
  }

  Widget _row(IconData icon, Color fg, Color bg, String title, String detail) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: AppCard(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            IconBadge(icon: icon, fg: fg, bg: bg, size: 48, circle: true),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700, color: Palette.brandDeep)),
                const SizedBox(height: 2),
                Text(detail, style: const TextStyle(fontSize: 14, color: Palette.muted)),
              ]),
            ),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              children: [
                Text(t('osPermTitle'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 25, fontWeight: FontWeight.w700, color: Palette.brandDeep)),
                const SizedBox(height: 8),
                Text(t('osPermIntro'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15, color: Palette.muted)),
                const SizedBox(height: 20),
                _row(Icons.notifications_active_rounded, Palette.orange, Palette.tileOrange,
                    t('osPermNotif'), t('osPermNotifDetail')),
                _row(Icons.alarm_on_rounded, Palette.red, Palette.tileRed, t('osPermAlarm'),
                    t('osPermAlarmDetail')),
                _row(Icons.mic_rounded, Palette.purple, Palette.tilePurple, t('osPermMic'),
                    t('osPermMicDetail')),
                _row(Icons.location_on_rounded, Palette.sky, Palette.tileSky, t('osPermLoc'),
                    t('osPermLocDetail')),
                const SizedBox(height: 4),
                Text(t('osPermNoMore'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12.5, color: Palette.muted)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              FilledButton(
                key: const ValueKey('allowPermissions'),
                onPressed: _busy ? null : _allow,
                child: Text(t('osPermAllow')),
              ),
              TextButton(
                key: const ValueKey('permissionsNotNow'),
                onPressed: _busy ? null : widget.onDone,
                child: Text(t('osPermNotNow'), style: const TextStyle(fontSize: 16)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
