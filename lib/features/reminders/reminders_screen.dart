import 'package:flutter/material.dart';

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
  });
  final AppDatabase db;
  final ReminderNotifier notifier;
  final String patientId;
  final String language;

  /// Embedded in another screen (the profile flow): no app bar of its own.
  final bool embedded;

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  List<Reminder> _items = [];
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
    if (mounted) {
      setState(() {
        _consented = consented;
        _items = items;
      });
    }
  }

  Future<void> _changed() async {
    await widget.notifier
        .resync(patientId: widget.patientId, lang: widget.language);
    await _load();
  }

  Future<void> _add() async {
    final result = await showDialog<_NewReminder>(
      context: context,
      builder: (_) => _AddReminderDialog(language: widget.language),
    );
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
                    style: const TextStyle(fontSize: 18)),
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
                        ScreenTitle(t('reminders')),
                        const SizedBox(height: 12),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
        child: Row(
          children: [
            IconBadge(
                icon: style.icon,
                fg: style.fg,
                bg: style.bg,
                size: 50,
                circle: true),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t('kind_${r.kind.name}'),
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700)),
                  Text(_when(r),
                      style: const TextStyle(fontSize: 14, color: Palette.muted)),
                  if (r.label.isNotEmpty)
                    Text(r.label,
                        style: const TextStyle(
                            fontSize: 14, color: Palette.muted)),
                ],
              ),
            ),
            Switch(
              value: r.active,
              activeThumbColor: Palette.action,
              onChanged: (v) async {
                await widget.db
                    .setReminderActive(widget.patientId, r.id, v, 'caregiver');
                await _changed();
              },
            ),
            IconButton(
              tooltip: t('delete'),
              icon: const Icon(Icons.delete_outline_rounded, color: Palette.muted),
              onPressed: () async {
                await widget.db
                    .deleteReminder(widget.patientId, r.id, 'caregiver');
                await _changed();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _NewReminder {
  _NewReminder(this.kind, this.label, this.time, this.date, this.by);
  final ReminderKind kind;
  final String label;
  final TimeOfDay time;
  final DateTime? date;
  final String by;
}

class _AddReminderDialog extends StatefulWidget {
  const _AddReminderDialog({required this.language});
  final String language;

  @override
  State<_AddReminderDialog> createState() => _AddReminderDialogState();
}

class _AddReminderDialogState extends State<_AddReminderDialog> {
  ReminderKind _kind = ReminderKind.medicine;
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 0);
  DateTime? _date;
  final _label = TextEditingController();
  final _by = TextEditingController();

  String t(String k) => tr(widget.language, k);

  @override
  void dispose() {
    _label.dispose();
    _by.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAppointment = _kind == ReminderKind.appointment;
    return AlertDialog(
      title: Text(t('addReminder')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButton<ReminderKind>(
              value: _kind,
              isExpanded: true,
              items: [
                for (final k in ReminderKind.values)
                  DropdownMenuItem(value: k, child: Text(t('kind_${k.name}'))),
              ],
              onChanged: (k) => setState(() {
                _kind = k!;
                if (k != ReminderKind.appointment) _date = null;
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
            if (isAppointment)
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today),
                label: Text(_date == null
                    ? t('pickDate')
                    : MaterialLocalizations.of(context).formatMediumDate(_date!)),
                onPressed: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: now,
                    firstDate: now,
                    lastDate: now.add(const Duration(days: 730)),
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
          onPressed: (_by.text.trim().isEmpty || (isAppointment && _date == null))
              ? null
              : () => Navigator.pop(
                  context,
                  _NewReminder(_kind, _label.text.trim(), _time, _date,
                      _by.text.trim())),
          child: Text(t('save')),
        ),
      ],
    );
  }
}
