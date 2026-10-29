import 'package:flutter/material.dart';

import '../../core/adherence.dart';
import '../../core/reminder_schedule.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/app_database.dart';
import '../../services/reminder_notifier.dart';
import 'reminder_style.dart';

/// Caregiver-managed reminders for medicine, water, activities, appointments.
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({
    super.key,
    required this.db,
    required this.notifier,
    required this.patientId,
    required this.language,
    this.embedded = false,
    this.onBack,
  });
  final AppDatabase db;
  final ReminderNotifier notifier;
  final String patientId;
  final String language;

  /// Embedded in another screen (the profile flow): no app bar of its own.
  final bool embedded;

  /// Shows a back arrow beside the title (used when this is a tab).
  final VoidCallback? onBack;

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  List<Reminder> _items = [];
  Set<String> _doneKeys = {};
  bool _consented = false;

  String t(String k) => tr(widget.language, k);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final consented = await widget.db.hasConsent(widget.patientId, 'reminders');
    final items = await widget.db.listReminders(widget.patientId);
    final done = consented ? await widget.db.doneKeys(widget.patientId, days: 2) : <String>{};
    if (mounted) {
      setState(() {
        _consented = consented;
        _items = items;
        _doneKeys = done;
      });
    }
  }

  Future<void> _changed() async {
    await widget.notifier
        .resync(patientId: widget.patientId, lang: widget.language);
    await _load();
  }

  Future<void> _add() async {
    final result =
        await showAddReminderDialog(context, language: widget.language);
    if (result == null) return;
    await widget.db.addReminder(
      patientId: widget.patientId,
      kind: result.kind,
      label: result.label,
      hour: result.time.hour,
      minute: result.time.minute,
      onDate: result.date,
      createdBy: result.by,
    );
    await _changed();
  }

  int _tab = 0; // 0 today, 1 upcoming, 2 all

  bool _runsToday(Reminder r) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final next = nextOccurrences(r, start.subtract(const Duration(seconds: 1)));
    return next.isNotEmpty &&
        next.first.year == now.year &&
        next.first.month == now.month &&
        next.first.day == now.day;
  }

  bool _upcoming(Reminder r) {
    if (!r.active || _runsToday(r)) return false;
    return nextOccurrences(r, DateTime.now()).isNotEmpty;
  }

  String _when(Reminder r) {
    final time = TimeOfDay(hour: r.hour, minute: r.minute).format(context);
    if (r.onDate != null) {
      return '${MaterialLocalizations.of(context).formatMediumDate(r.onDate!)} · $time';
    }
    return '$time · ${t('everyDay')}';
  }

  @override
  Widget build(BuildContext context) {
    final shown = switch (_tab) {
      0 => _items.where(_runsToday).toList(),
      1 => _items.where(_upcoming).toList(),
      _ => _items,
    };
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: Text(t('reminders'))),
      body: !_consented
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(t('remindersOff'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16)),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!widget.embedded) const SizedBox(height: 0),
                      if (widget.embedded) ...[
                        Row(children: [
                          if (widget.onBack != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: InkWell(
                                onTap: widget.onBack,
                                borderRadius: BorderRadius.circular(20),
                                child: const Padding(
                                  padding: EdgeInsets.all(4),
                                  child: Icon(Icons.arrow_back_rounded,
                                      color: Palette.brandDeep),
                                ),
                              ),
                            ),
                          Expanded(child: ScreenTitle(t('reminders'))),
                        ]),
                        const SizedBox(height: 14),
                      ],
                      PillTabs(
                        labels: [t('today'), t('upcoming'), t('all')],
                        selected: _tab,
                        onSelected: (i) => setState(() => _tab = i),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: shown.isEmpty
                      ? Center(
                          child: Text(t('nothingHere'),
                              style: const TextStyle(
                                  fontSize: 17, color: Palette.muted)))
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                          children: [for (final r in shown) _row(r)],
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  child: FilledButton.icon(
                    onPressed: _add,
                    icon: const Icon(Icons.add_rounded, size: 28),
                    label: Text(t('addReminder')),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _row(Reminder r) {
    final style = kindStyle(r.kind);
    final today = DateTime.now();
    final isDone = _doneKeys.contains(doneKey(r.id, DateTime(today.year, today.month, today.day)));
    final parts = _when(r).split(' · ');
    final note = r.label.isNotEmpty ? r.label : parts.skip(1).join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Opacity(
        opacity: r.active ? 1 : 0.55,
        child: AppCard(
          padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
          child: Row(
            children: [
              IconBadge(
                  icon: style.icon,
                  fg: style.fg,
                  bg: style.bg,
                  size: 52,
                  circle: true),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('kind_${r.kind.name}'),
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Palette.brandDeep)),
                    Text(
                        r.active
                            ? parts.first
                            : '${parts.first} · ${t('reminderOff')}',
                        style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                            color: Palette.ink)),
                    if (note.isNotEmpty)
                      Text(note,
                          style: const TextStyle(
                              fontSize: 12.5, color: Palette.muted)),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: t('reminders'),
                icon: Icon(
                    isDone
                        ? Icons.check_circle_rounded
                        : Icons.chevron_right_rounded,
                    color: isDone ? Palette.action : Palette.muted),
                onSelected: (v) async {
                  if (v == 'delete') {
                    await widget.db
                        .deleteReminder(widget.patientId, r.id, 'caregiver');
                  } else {
                    await widget.db.setReminderActive(
                        widget.patientId, r.id, !r.active, 'caregiver');
                  }
                  await _changed();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                      value: 'toggle',
                      child: Row(children: [
                        Icon(
                            r.active
                                ? Icons.notifications_off_outlined
                                : Icons.notifications_active_outlined,
                            color: Palette.muted),
                        const SizedBox(width: 8),
                        Text(t(r.active ? 'reminderTurnOff' : 'reminderTurnOn')),
                      ])),
                  PopupMenuItem(
                      value: 'delete',
                      child: Row(children: [
                        const Icon(Icons.delete_outline_rounded,
                            color: Palette.red),
                        const SizedBox(width: 8),
                        Text(t('delete')),
                      ])),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NewReminder {
  NewReminder(this.kind, this.label, this.time, this.date, this.by);
  final ReminderKind kind;
  final String label;
  final TimeOfDay time;
  final DateTime? date;
  final String by;
}

/// Kinds that happen on a particular date rather than every day.
const kDatedKinds = {
  ReminderKind.appointment,
  ReminderKind.birthday,
  ReminderKind.event,
};

/// Asks for one reminder. [kinds] limits the choices (the profile flow shows
/// daily routines and dated reminders separately); [defaultBy] pre-fills who is
/// making the change.
Future<NewReminder?> showAddReminderDialog(
  BuildContext context, {
  required String language,
  List<ReminderKind>? kinds,
  String? title,
  String defaultBy = '',
}) =>
    showDialog<NewReminder>(
      context: context,
      builder: (_) => _AddReminderDialog(
          language: language,
          kinds: kinds ?? ReminderKind.values,
          title: title,
          defaultBy: defaultBy),
    );

class _AddReminderDialog extends StatefulWidget {
  const _AddReminderDialog({
    required this.language,
    required this.kinds,
    this.title,
    this.defaultBy = '',
  });
  final String language;
  final List<ReminderKind> kinds;
  final String? title;
  final String defaultBy;

  @override
  State<_AddReminderDialog> createState() => _AddReminderDialogState();
}

class _AddReminderDialogState extends State<_AddReminderDialog> {
  late ReminderKind _kind = widget.kinds.first;
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 0);
  DateTime? _date;
  final _label = TextEditingController();
  late final _by = TextEditingController(text: widget.defaultBy);

  String t(String k) => tr(widget.language, k);

  @override
  void dispose() {
    _label.dispose();
    _by.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dated = kDatedKinds.contains(_kind);
    return AlertDialog(
      title: Text(widget.title ?? t('addReminder')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.kinds.length > 1)
              DropdownButton<ReminderKind>(
                value: _kind,
                isExpanded: true,
                items: [
                  for (final k in widget.kinds)
                    DropdownMenuItem(
                        value: k, child: Text(t('kind_${k.name}'))),
                ],
                onChanged: (k) => setState(() {
                  _kind = k!;
                  if (!kDatedKinds.contains(k)) _date = null;
                }),
              ),
            TextField(
                controller: _label,
                decoration: InputDecoration(labelText: t('reminderLabel'))),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.access_time),
              label: Text('${t('pickTime')}: ${_time.format(context)}'),
              onPressed: () async {
                final picked =
                    await showTimePicker(context: context, initialTime: _time);
                if (picked != null) setState(() => _time = picked);
              },
            ),
            if (dated)
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today),
                label: Text(_date == null
                    ? t('pickDate')
                    : MaterialLocalizations.of(context).formatMediumDate(_date!)),
                onPressed: () async {
                  final now = DateTime.now();
                  final birthday = _kind == ReminderKind.birthday;
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: now,
                    // A birthday is a date in the past that comes round each year.
                    firstDate: birthday ? DateTime(1900) : now,
                    lastDate:
                        birthday ? now : now.add(const Duration(days: 1095)),
                  );
                  if (picked != null) setState(() => _date = picked);
                },
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(t('everyDay')),
              ),
            TextField(
                controller: _by,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: t('whoIsActing'))),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(t('cancel'))),
        FilledButton(
          onPressed: (_by.text.trim().isEmpty || (dated && _date == null))
              ? null
              : () => Navigator.pop(
                  context,
                  NewReminder(_kind, _label.text.trim(), _time, _date,
                      _by.text.trim())),
          child: Text(t('save')),
        ),
      ],
    );
  }
}
