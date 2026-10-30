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
    _loadWater();
    kRemindersRevision.addListener(_load);
  }

  @override
  void dispose() {
    kRemindersRevision.removeListener(_load);
    super.dispose();
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
    final by = ((await widget.db.patientById(widget.patientId))?['display_name']
            as String?) ??
        '';
    if (!mounted) return;
    final result = await showAddReminderDialog(context,
        language: widget.language,
        kinds: _tabKinds[_tab],
        defaultBy: by);
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

  /// 0 medicines, 1 water tracker, 2 routine, 3 reminders (appointments, events,
  /// important dates).
  int _tab = 0;
  int _glasses = 0;

  static const _tabKinds = <int, List<ReminderKind>>{
    0: [ReminderKind.medicine],
    1: [ReminderKind.hydration],
    2: [ReminderKind.activity],
    3: [
      ReminderKind.appointment,
      ReminderKind.event,
      ReminderKind.birthday,
    ],
  };

  bool _runsToday(Reminder r) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final next = nextOccurrences(r, start.subtract(const Duration(seconds: 1)));
    return next.isNotEmpty &&
        next.first.year == now.year &&
        next.first.month == now.month &&
        next.first.day == now.day;
  }

  String _when(Reminder r) {
    final time = TimeOfDay(hour: r.hour, minute: r.minute).format(context);
    if (r.onDate != null) {
      return '${MaterialLocalizations.of(context).formatMediumDate(r.onDate!)} · $time';
    }
    return '$time · ${t('everyDay')}';
  }

  Future<void> _loadWater() async {
    final n = await widget.db.waterToday(widget.patientId);
    if (mounted) setState(() => _glasses = n);
  }

  Future<void> _glass(int by) async {
    final n = await widget.db.addWater(widget.patientId, by: by);
    if (mounted) setState(() => _glasses = n);
  }

  /// The reminders shown in the current tab. The last tab lists only what is
  /// still to come, soonest first.
  List<Reminder> get _shown {
    final kinds = _tabKinds[_tab]!;
    final of = _items.where((r) => kinds.contains(r.kind)).toList();
    if (_tab == 3) {
      final now = DateTime.now();
      final withNext = [
        for (final r in of)
          if (r.active && nextOccurrences(r, now).isNotEmpty)
            (nextOccurrences(r, now).first, r)
      ]..sort((a, b) => a.$1.compareTo(b.$1));
      return [for (final x in withNext) x.$2];
    }
    of.sort((a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));
    return of;
  }

  Widget _tabs() {
    const icons = [
      Icons.medication_outlined,
      Icons.water_drop_outlined,
      Icons.checklist_rounded,
      Icons.notifications_none_rounded,
    ];
    final labels = [
      t('tabMedicines'),
      t('tabWater'),
      t('tabRoutine'),
      t('reminders'),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Palette.line),
      ),
      child: Row(children: [
        for (var i = 0; i < 4; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : 2),
              child: GestureDetector(
                key: ValueKey('remTab$i'),
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  setState(() => _tab = i);
                  if (i == 1) _loadWater();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
                  decoration: BoxDecoration(
                    color: i == _tab ? Palette.action : Colors.transparent,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icons[i],
                        size: 20,
                        color: i == _tab ? Colors.white : Palette.muted),
                    const SizedBox(height: 3),
                    Text(labels[i],
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11.5,
                            height: 1.15,
                            fontWeight: FontWeight.w700,
                            color: i == _tab ? Colors.white : Palette.muted)),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _water() {
    const goal = AppDatabase.waterGoal;
    final shown = _shown;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      children: [
        AppCard(
          padding: const EdgeInsets.all(18),
          child: Column(children: [
            const IconBadge(
                icon: Icons.water_drop_outlined,
                fg: Palette.blue,
                bg: Palette.tileBlue,
                size: 64),
            const SizedBox(height: 12),
            Text(
                t('waterOfGlasses')
                    .replaceAll('{a}', '$_glasses')
                    .replaceAll('{b}', '$goal'),
                key: const ValueKey('waterCount'),
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Palette.brandDeep)),
            const SizedBox(height: 4),
            Text(t('waterHint'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Palette.muted)),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < goal; i++)
                  GestureDetector(
                    key: ValueKey('glass$i'),
                    // Tapping the last full glass takes one back, if it was a slip.
                    onTap: i == _glasses - 1 ? () => _glass(-1) : null,
                    child: Container(
                      width: 40,
                      height: 52,
                      decoration: BoxDecoration(
                        color: i < _glasses
                            ? Palette.tileBlue
                            : const Color(0xFFFBF3E7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: i < _glasses
                                ? Palette.blue.withValues(alpha: .5)
                                : Palette.line),
                      ),
                      child: Icon(Icons.local_drink_outlined,
                          size: 22,
                          color: i < _glasses ? Palette.blue : Palette.muted),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey('drinkGlass'),
                style: FilledButton.styleFrom(backgroundColor: Palette.blue),
                onPressed: () => _glass(1),
                icon: const Icon(Icons.water_drop_outlined, size: 20),
                label: Text(t('drinkGlass')),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        for (final r in shown) _row(r),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
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
                      _tabs(),
                    ],
                  ),
                ),
                Expanded(
                  child: _tab == 1
                      ? _water()
                      : shown.isEmpty
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
                    key: const ValueKey('addReminder'),
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
    final title = r.label.isNotEmpty ? r.label : t('kind_${r.kind.name}');
    final note = parts.skip(1).join(' · ');
    final canMark = r.kind == ReminderKind.medicine && r.active && _runsToday(r);
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
                    Text(title,
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
                    if (r.addedBy != null && r.addedBy!.isNotEmpty)
                      Text(t('addedBy').replaceAll('{a}', r.addedBy!),
                          style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Palette.brand)),
                    if (note.isNotEmpty)
                      Text(note,
                          style: const TextStyle(
                              fontSize: 12.5, color: Palette.muted)),
                    if (canMark)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: OutlinedButton.icon(
                          key: ValueKey('taken_${r.id}'),
                          style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 36),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              foregroundColor:
                                  isDone ? Palette.action : Palette.red),
                          onPressed: () async {
                            final d = DateTime.now();
                            await widget.db.setReminderDone(
                                patientId: widget.patientId,
                                reminderId: r.id,
                                day: DateTime(d.year, d.month, d.day),
                                done: !isDone,
                                by: 'self');
                            await _load();
                          },
                          icon: Icon(
                              isDone
                                  ? Icons.check_circle_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              size: 18),
                          label: Text(t(isDone ? 'takenToday' : 'markTaken')),
                        ),
                      ),
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
  NewReminder? initial,
}) =>
    showDialog<NewReminder>(
      context: context,
      builder: (_) => _AddReminderDialog(
          language: language,
          kinds: kinds ?? ReminderKind.values,
          title: title,
          defaultBy: defaultBy,
          initial: initial),
    );

class _AddReminderDialog extends StatefulWidget {
  const _AddReminderDialog({
    required this.language,
    required this.kinds,
    this.title,
    this.defaultBy = '',
    this.initial,
  });
  final NewReminder? initial;
  final String language;
  final List<ReminderKind> kinds;
  final String? title;
  final String defaultBy;

  @override
  State<_AddReminderDialog> createState() => _AddReminderDialogState();
}

class _AddReminderDialogState extends State<_AddReminderDialog> {
  late ReminderKind _kind = widget.initial?.kind ?? widget.kinds.first;
  late TimeOfDay _time =
      widget.initial?.time ?? const TimeOfDay(hour: 9, minute: 0);
  late DateTime? _date = widget.initial?.date;
  late final _label = TextEditingController(text: widget.initial?.label ?? '');

  String t(String k) => tr(widget.language, k);

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dated = kDatedKinds.contains(_kind);
    Widget field(String label, Widget child) => Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: kTitleMedium.copyWith(fontSize: 15, height: 1.25)),
              const SizedBox(height: 6),
              child,
            ],
          ),
        );
    return AlertDialog(
      title: Text(widget.title ?? t('addReminder'), style: kTitleLarge),
      scrollable: true,
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.kinds.length > 1)
              DropdownButtonFormField<ReminderKind>(
                initialValue: _kind,
                isExpanded: true,
                borderRadius: BorderRadius.circular(16),
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
            field(
                t('reminderLabel'),
                TextField(
                    controller: _label,
                    textCapitalization: TextCapitalization.sentences)),
            field(
              t('pickTime'),
              OutlinedButton.icon(
                icon: const Icon(Icons.access_time),
                label: Text(_time.format(context)),
                onPressed: () async {
                  final picked = await showTimePicker(
                      context: context, initialTime: _time);
                  if (picked != null) setState(() => _time = picked);
                },
              ),
            ),
            if (dated)
              field(
                t('pickDate'),
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today),
                  label: Text(_date == null
                      ? t('pickDate')
                      : MaterialLocalizations.of(context)
                          .formatMediumDate(_date!)),
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
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(children: [
                  const Icon(Icons.repeat_rounded,
                      size: 18, color: Palette.muted),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(t('everyDay'),
                          style: const TextStyle(
                              fontSize: 15, color: Palette.muted))),
                ]),
              ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      actions: [
        Row(children: [
          Expanded(
            child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: Text(t('cancel'))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: (dated && _date == null)
                  ? null
                  : () => Navigator.pop(
                      context,
                      NewReminder(_kind, _label.text.trim(), _time, _date,
                          widget.defaultBy.trim().isEmpty
                              ? 'self'
                              : widget.defaultBy.trim())),
              child: Text(t('save')),
            ),
          ),
        ]),
      ],
    );
  }
}
