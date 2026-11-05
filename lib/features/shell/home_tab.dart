import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/adherence.dart';
import '../../core/reminder_schedule.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/app_database.dart';
import '../profile/photo_picker.dart' show Avatar;
import '../reminders/reminder_style.dart';
import 'garden.dart';

class _HomeData {
  _HomeData(this.playedToday, this.tasks, this.done);
  final bool playedToday;
  final List<(DateTime, Reminder)> tasks;
  final Set<String> done; // reminder ids marked done today
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
    required this.onTalk,
    this.onChatCaregiver,
    this.onChatDoctor,
    this.unreadCaregiver = 0,
    this.unreadDoctor = 0,
    this.topCard,
  });

  /// Shown above everything else (the live location button).
  final Widget? topCard;
  final AppDatabase db;
  final String patientId, name, lang;
  final List<int>? photo;
  final VoidCallback onPlay, onGames, onReminders, onProgress, onTalk;

  /// Messages with the linked caregiver and doctor; null hides the buttons
  /// (builds without an online service).
  final VoidCallback? onChatCaregiver, onChatDoctor;
  final int unreadCaregiver, unreadDoctor;

  String t(String k) => tr(lang, k);

  String _greeting() {
    final h = DateTime.now().hour;
    return t(h < 12 ? 'goodMorning' : h < 17 ? 'goodAfternoon' : 'goodEvening');
  }

  // Today's progress for the garden: every task, plus playing a game.
  int _total(_HomeData? d) => (d?.tasks.length ?? 0) + 1;
  int _doneCount(_HomeData? d) =>
      d == null ? 0 : d.done.length + (d.playedToday ? 1 : 0);
  double _progress(_HomeData? d) => _doneCount(d) / _total(d);

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
    final keys = await db.doneKeys(patientId, days: 2);
    final done = {
      for (final (_, r) in tasks)
        if (keys.contains(doneKey(r.id, startOfDay))) r.id
    };
    return _HomeData(played, tasks, done);
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
            if (topCard != null) ...[topCard!, const SizedBox(height: 14)],
            GardenHeader(
              greeting: _greeting(),
              name: name,
              photo: photo,
              now: DateTime.now(),
              progress: _progress(data),
              progressText: t('doneOfTotal')
                  .replaceAll('{a}', '${_doneCount(data)}')
                  .replaceAll('{b}', '${_total(data)}'),
            ),
            const SizedBox(height: 18),

            // Today as a line through the day: "now" glows, a tap ticks it off.
            if (data != null) _Timeline(
              title: t('todaysTasks'),
              empty: t('noTasksToday'),
              tasks: data.tasks,
              done: data.done,
              lang: lang,
              onToggle: (r, v) => db.setReminderDone(
                patientId: patientId,
                reminderId: r.id,
                day: DateTime.now(),
                done: v,
                by: 'patient',
              ),
            ),
            const SizedBox(height: 18),

            // Today's Goal
            AppCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    children: [
                      const IconBadge(
                          icon: Icons.extension_rounded,
                          fg: Palette.blue,
                          bg: Palette.tileBlue,
                          size: 52),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t('todaysGoal'),
                                style: const TextStyle(
                                    fontSize: 12.5, color: Palette.muted)),
                            Text(t(done ? 'goalDone' : 'goalPlay'),
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Palette.brandDeep)),
                          ],
                        ),
                      ),
                      if (done)
                        const Icon(Icons.check_circle_rounded,
                            color: Palette.action, size: 34),
                    ],
                  ),
                  if (!done) ...[
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(46)),
                        onPressed: onPlay,
                        child: Text(t('playNow')),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

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
                  child: _tile(Icons.chat_bubble_rounded, t('chatTitle'),
                      Palette.tilePurple, Palette.purple, onTalk)),
            ]),

            if (onChatCaregiver != null && onChatDoctor != null) ...[
              const SizedBox(height: 14),
              _chatCard('talkCaregiver', Icons.volunteer_activism_rounded,
                  t('talkToCaregiver'), Palette.green, Palette.tileGreen,
                  unreadCaregiver, onChatCaregiver!),
              const SizedBox(height: 10),
              _chatCard('talkDoctor', Icons.medical_services_rounded,
                  t('talkToDoctor'), Palette.purple, Palette.tilePurple,
                  unreadDoctor, onChatDoctor!),
            ],
            const SizedBox(height: 14),
            AppCard(
              onTap: () => _showFamily(context),
              color: Palette.tileSky,
              child: Row(children: [
                const IconBadge(
                    icon: Icons.call_rounded,
                    fg: Palette.sky,
                    bg: Colors.white,
                    circle: true),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(t('callFamily'),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                const Icon(Icons.chevron_right_rounded),
              ]),
            ),

          ],
        );
      },
    );
  }

  Widget _tile(IconData icon, String label, Color bg, Color fg, VoidCallback onTap) =>
      Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 128),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
            decoration: BoxDecoration(
              color: bg.withAlpha(150),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: bg, width: 1.6),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 48, color: fg),
                const SizedBox(height: 8),
                Text(label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Palette.brandDeep)),
              ],
            ),
          ),
        ),
      );

  Widget _chatCard(String key, IconData icon, String label, Color fg, Color bg,
          int unread, VoidCallback onTap) =>
      AppCard(
        key: ValueKey(key),
        onTap: onTap,
        color: bg,
        child: Row(children: [
          IconBadge(icon: icon, fg: fg, bg: Colors.white, circle: true),
          const SizedBox(width: 14),
          Expanded(
            child: Text(label,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          if (unread > 0)
            Container(
              margin: const EdgeInsetsDirectional.only(end: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: Palette.red, borderRadius: BorderRadius.circular(14)),
              child: Text('$unread',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14)),
            ),
          const Icon(Icons.chevron_right_rounded),
        ]),
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

/// Today's tasks on one vertical line. The next task that is not done is marked
/// "now" with a glowing ring; tapping the circle on the right ticks a task off.
class _Timeline extends StatelessWidget {
  const _Timeline({
    required this.title,
    required this.empty,
    required this.tasks,
    required this.done,
    required this.lang,
    required this.onToggle,
  });
  final String title, empty, lang;
  final List<(DateTime, Reminder)> tasks;
  final Set<String> done;
  final Future<void> Function(Reminder r, bool done) onToggle;

  @override
  Widget build(BuildContext context) {
    final nowIndex = tasks.indexWhere((x) => !done.contains(x.$2.id));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title,
          style: const TextStyle(
              fontSize: 20, fontWeight: FontWeight.w700, color: Palette.brandDeep)),
      const SizedBox(height: 10),
      if (tasks.isEmpty)
        Text(empty, style: const TextStyle(fontSize: 16, color: Palette.muted))
      else
        for (var i = 0; i < tasks.length; i++)
          _TimelineItem(
            key: ValueKey(tasks[i].$2.id),
            reminder: tasks[i].$2,
            at: tasks[i].$1,
            lang: lang,
            first: i == 0,
            last: i == tasks.length - 1,
            isNow: i == nowIndex,
            initiallyDone: done.contains(tasks[i].$2.id),
            onToggle: (v) => onToggle(tasks[i].$2, v),
          ),
    ]);
  }
}

class _TimelineItem extends StatefulWidget {
  const _TimelineItem({
    super.key,
    required this.reminder,
    required this.at,
    required this.lang,
    required this.first,
    required this.last,
    required this.isNow,
    required this.initiallyDone,
    required this.onToggle,
  });
  final Reminder reminder;
  final DateTime at;
  final String lang;
  final bool first, last, isNow, initiallyDone;
  final Future<void> Function(bool done) onToggle;

  @override
  State<_TimelineItem> createState() => _TimelineItemState();
}

class _TimelineItemState extends State<_TimelineItem> {
  late bool _done = widget.initiallyDone;

  @override
  Widget build(BuildContext context) {
    final r = widget.reminder;
    final style = kindStyle(r.kind);
    final label = r.label.isEmpty ? tr(widget.lang, 'kind_${r.kind.name}') : r.label;
    final by = r.addedBy;
    final now = widget.isNow && !_done;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 66,
          child: Stack(alignment: Alignment.topCenter, children: [
            Positioned.fill(
              child: Align(
                alignment: Alignment.center,
                child: Container(
                  width: 4,
                  margin: EdgeInsets.only(
                      top: widget.first ? 36 : 0, bottom: widget.last ? 36 : 0),
                  decoration: BoxDecoration(
                      color: const Color(0xFFE1D6C4),
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                key: now ? const ValueKey('timelineNow') : null,
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _done ? Palette.tileGreen : style.bg,
                  border: Border.all(
                      color: _done ? Palette.action : Colors.white, width: 3),
                  boxShadow: [
                    if (now)
                      BoxShadow(
                          color: Palette.action.withValues(alpha: 0.35),
                          blurRadius: 0,
                          spreadRadius: 6),
                    const BoxShadow(
                        color: Color(0x26000000), blurRadius: 8, offset: Offset(0, 3)),
                  ],
                ),
                child: Icon(_done ? Icons.check_rounded : style.icon,
                    size: 26, color: _done ? Palette.action : style.fg),
              ),
            ),
          ]),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppCard(
              color: _done ? Palette.tileGreen : Colors.white,
              padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            decoration: _done ? TextDecoration.lineThrough : null)),
                    Text(TimeOfDay.fromDateTime(widget.at).format(context),
                        style: const TextStyle(fontSize: 14, color: Palette.muted)),
                    if (by != null && by.isNotEmpty)
                      Text(tr(widget.lang, 'addedBy').replaceAll('{a}', by),
                          style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Palette.brand)),
                  ]),
                ),
                IconButton(
                  tooltip: tr(widget.lang, 'markDone'),
                  iconSize: 38,
                  icon: Icon(
                      _done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      color: _done ? Palette.action : Palette.muted),
                  onPressed: () async {
                    final next = !_done;
                    setState(() => _done = next);
                    try {
                      await widget.onToggle(next);
                    } catch (_) {
                      if (mounted) setState(() => _done = !next);
                    }
                  },
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
