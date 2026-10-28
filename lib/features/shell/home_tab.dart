import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/reminder_schedule.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/app_database.dart';
import '../profile/photo_picker.dart' show Avatar;
import '../reminders/reminder_style.dart';

class _HomeData {
  _HomeData(this.playedToday, this.tasks);
  final bool playedToday;
  final List<(DateTime, Reminder)> tasks;
}

/// Home: greeting, Today's Goal, four shortcut tiles and today's tasks.
class HomeTab extends StatelessWidget {
  const HomeTab({
    super.key,
    required this.db,
    required this.patientId,
    required this.name,
    required this.photo,
    required this.lang,
    required this.onPlay,
    required this.onGames,
    required this.onReminders,
    required this.onProgress,
  });
  final AppDatabase db;
  final String patientId, name, lang;
  final List<int>? photo;
  final VoidCallback onPlay, onGames, onReminders, onProgress;

  String t(String k) => tr(lang, k);

  String _greeting() {
    final h = DateTime.now().hour;
    return t(h < 12 ? 'goodMorning' : h < 17 ? 'goodAfternoon' : 'goodEvening');
  }

  Future<_HomeData> _load() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final played = (await db.sessionTimes(patientId))
        .any((d) => !d.isBefore(startOfDay));
    final tasks = <(DateTime, Reminder)>[];
    for (final r in await db.listReminders(patientId)) {
      final next =
          nextOccurrences(r, startOfDay.subtract(const Duration(seconds: 1)));
      if (next.isNotEmpty &&
          next.first.year == now.year &&
          next.first.month == now.month &&
          next.first.day == now.day) {
        tasks.add((next.first, r));
      }
    }
    tasks.sort((a, b) => a.$1.compareTo(b.$1));
    return _HomeData(played, tasks);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_HomeData>(
      future: _load(),
      builder: (context, snap) {
        final data = snap.data;
        final done = data?.playedToday ?? false;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Row(
              children: [
                Avatar(photo: photo, radius: 28),
                const SizedBox(width: 14),
                Expanded(
                  child: Text('${_greeting()},\n$name',
                      style: const TextStyle(
                          fontSize: 24,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                          color: Palette.brandDeep)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(t('greeting'),
                style: const TextStyle(fontSize: 15, color: Palette.muted)),
            const SizedBox(height: 18),

            // Today's Goal
            AppCard(
              child: Row(
                children: [
                  const IconBadge(
                      icon: Icons.extension_rounded,
                      fg: Palette.blue,
                      bg: Palette.tileBlue,
                      size: 58),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t('todaysGoal'),
                            style: const TextStyle(
                                fontSize: 14, color: Palette.muted)),
                        Text(t(done ? 'goalDone' : 'goalPlay'),
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (done)
                    const Icon(Icons.check_circle_rounded,
                        color: Palette.action, size: 40)
                  else
                    SizedBox(
                      width: 120,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(46),
                            textStyle: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 16, fontWeight: FontWeight.w600)),
                        onPressed: onPlay,
                        child: Text(t('playNow')),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Tiles
            Row(children: [
              Expanded(
                  child: _tile(Icons.sports_esports_rounded, t('tileGames'),
                      Palette.tileBlue, Palette.blue, onGames)),
              const SizedBox(width: 14),
              Expanded(
                  child: _tile(Icons.notifications_rounded, t('tileReminders'),
                      Palette.tileOrange, Palette.orange, onReminders)),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                  child: _tile(Icons.bar_chart_rounded, t('tileProgress'),
                      Palette.tileGreen, Palette.green, onProgress)),
              const SizedBox(width: 14),
              Expanded(
                  child: _tile(Icons.call_rounded, t('callFamily'),
                      Palette.tileSky, Palette.sky,
                      () => _showFamily(context))),
            ]),

            // Today's tasks
            const SizedBox(height: 24),
            Text(t('todaysTasks'),
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Palette.brandDeep)),
            const SizedBox(height: 10),
            if (data == null)
              const SizedBox.shrink()
            else if (data.tasks.isEmpty)
              Text(t('noTasksToday'),
                  style: const TextStyle(fontSize: 16, color: Palette.muted))
            else
              for (final (at, r) in data.tasks)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      IconBadge(
                          icon: kindStyle(r.kind).icon,
                          fg: kindStyle(r.kind).fg,
                          bg: kindStyle(r.kind).bg,
                          size: 46,
                          circle: true),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                r.label.isEmpty
                                    ? t('kind_${r.kind.name}')
                                    : r.label,
                                style: const TextStyle(
                                    fontSize: 17, fontWeight: FontWeight.w600)),
                            Text(TimeOfDay.fromDateTime(at).format(context),
                                style: const TextStyle(
                                    fontSize: 14, color: Palette.muted)),
                          ],
                        ),
                      ),
                    ]),
                  ),
                ),
          ],
        );
      },
    );
  }

  Widget _tile(IconData icon, String label, Color bg, Color fg, VoidCallback onTap) =>
      AppCard(
        color: bg,
        onTap: onTap,
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
        child: Column(
          children: [
            Icon(icon, size: 44, color: fg),
            const SizedBox(height: 10),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Future<void> _showFamily(BuildContext context) async {
    final family = await db.listFamily(patientId);
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Palette.cream,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t('callFamily'),
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Palette.brandDeep)),
              const SizedBox(height: 12),
              if (family.isEmpty)
                Text(t('noneAdded'), style: const TextStyle(fontSize: 17)),
              for (final m in family)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    // Opens the phone dialer with the number filled in.
                    onTap: () => launchUrl(
                        Uri(scheme: 'tel', path: m['phone'] as String)),
                    child: Row(children: [
                      Avatar(photo: m['photo'] as List<int>?, radius: 26),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m['name'] as String,
                                style: const TextStyle(
                                    fontSize: 19, fontWeight: FontWeight.w700)),
                            Text(t('rel_${m['relation']}'),
                                style: const TextStyle(
                                    fontSize: 14, color: Palette.muted)),
                          ],
                        ),
                      ),
                      const IconBadge(
                          icon: Icons.call_rounded,
                          fg: Colors.white,
                          bg: Palette.action,
                          size: 48,
                          circle: true),
                    ]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
