import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/dates.dart';

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
    final done = consented
        ? await widget.db.doneKeys(widget.patientId, days: 2)
        : <String>{};
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
        language: widget.language, kinds: _tabKinds[_tab], defaultBy: by);
    if (result == null) return;
    for (final at in result.allTimes) {
      await widget.db.addReminder(
        patientId: widget.patientId,
        kind: result.kind,
        label: result.label,
        hour: at.hour,
        minute: at.minute,
        daysMask: result.daysMask,
        onDate: result.date,
        createdBy: result.by,
      );
    }
    await _changed();
  }

  /// 0 medicines, 1 routine (activities and any water/hydration reminders),
  /// 2 reminders (appointments, events, important dates).
  int _tab = 0;

  static const _tabKinds = <int, List<ReminderKind>>{
    0: [ReminderKind.medicine],
    1: [ReminderKind.activity, ReminderKind.hydration],
    2: [
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
    return '$time · ${daysText(widget.language, r.daysMask)}';
  }

  /// The reminders shown in the current tab. The last tab lists only what is
  /// still to come, soonest first.
  List<Reminder> get _shown {
    final kinds = _tabKinds[_tab]!;
    final of = _items.where((r) => kinds.contains(r.kind)).toList();
    if (_tab == 2) {
      final now = DateTime.now();
      final withNext = [
        for (final r in of)
          if (r.active && nextOccurrences(r, now).isNotEmpty)
            (nextOccurrences(r, now).first, r)
      ]..sort((a, b) => a.$1.compareTo(b.$1));
      return [for (final x in withNext) x.$2];
    }
    of.sort(
        (a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));
    return of;
  }

  Widget _tabs() {
    const icons = [
      Icons.medication_outlined,
      Icons.checklist_rounded,
      Icons.notifications_none_rounded,
    ];
    final labels = [
      t('tabMedicines'),
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
        for (var i = 0; i < 3; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : 2),
              child: GestureDetector(
                key: ValueKey('remTab$i'),
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _tab = i),
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
    final isDone = _doneKeys
        .contains(doneKey(r.id, DateTime(today.year, today.month, today.day)));
    final parts = _when(r).split(' · ');
    final title = r.label.isNotEmpty ? r.label : t('kind_${r.kind.name}');
    final note = parts.skip(1).join(' · ');
    final canMark =
        r.kind == ReminderKind.medicine && r.active && _runsToday(r);
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
                        Text(
                            t(r.active ? 'reminderTurnOff' : 'reminderTurnOn')),
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
  NewReminder(this.kind, this.label, this.time, this.date, this.by,
      {this.extraTimes = const [], this.daysMask = 127});
  final ReminderKind kind;
  final String label;
  final TimeOfDay time;
  final DateTime? date;
  final String by;

  /// A medicine taken more than once a day: its other times (one reminder is
  /// created for each of [time] and these).
  final List<TimeOfDay> extraTimes;

  /// The days of the week it runs on (bit 0 = Monday ... bit 6 = Sunday); 127 is
  /// every day. Dated reminders (appointments, events) ignore it.
  final int daysMask;

  List<TimeOfDay> get allTimes => [time, ...extraTimes];
}

/// "Metformin · 500 mg · After food": how a prescription is written in the
/// reminder's label, so it reads the same on the patient's phone.
String medicineLabel(String lang, String name, String dose, String? food) => [
      name.trim(),
      if (dose.trim().isNotEmpty) dose.trim(),
      if (food != null)
        tr(lang, 'food${food[0].toUpperCase()}${food.substring(1)}'),
    ].join(' · ');

const _kFoods = ['before', 'after', 'with', 'any'];

/// Everyday routines to add with one tap: label key, kind, and a sensible time.
const kRoutineTemplates = <(String, ReminderKind, int, int)>[
  ('tplWalk', ReminderKind.activity, 7, 0),
  ('tplWater', ReminderKind.hydration, 10, 0),
  ('tplBreakfast', ReminderKind.activity, 8, 30),
  ('tplLunch', ReminderKind.activity, 13, 0),
  ('tplDinner', ReminderKind.activity, 20, 0),
  ('tplExercise', ReminderKind.activity, 17, 0),
  ('tplCallFamily', ReminderKind.activity, 18, 30),
  ('tplSleep', ReminderKind.activity, 22, 0),
];

/// Reads a label written by [medicineLabel] back into its parts (for editing).
({String name, String dose, String? food}) parseMedicineLabel(
    String lang, String label) {
  final parts = label.split(' · ').map((x) => x.trim()).toList();
  String? food;
  if (parts.length > 1) {
    for (final f in _kFoods) {
      if (parts.last ==
          tr(lang, 'food${f[0].toUpperCase()}${f.substring(1)}')) {
        food = f;
        parts.removeLast();
        break;
      }
    }
  }
  return (
    name: parts.isEmpty ? '' : parts.first,
    dose: parts.length > 1 ? parts.sublist(1).join(' · ') : '',
    food: food,
  );
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
  late final _rx = widget.initial?.kind == ReminderKind.medicine
      ? parseMedicineLabel(widget.language, widget.initial!.label)
      : (name: '', dose: '', food: null as String?);
  late final _name = TextEditingController(text: _rx.name);
  late final _dose = TextEditingController(text: _rx.dose);
  late String? _food = _rx.food;
  late int _days = (widget.initial?.daysMask ?? 127) & 127;
  bool _nameMissing = false; // shown after Save is tapped with no medicine name
  late List<TimeOfDay> _times = [
    widget.initial?.time ?? const TimeOfDay(hour: 8, minute: 0)
  ];

  bool get _editing => widget.initial != null;
  bool get _medicine => _kind == ReminderKind.medicine;

  String t(String k) => tr(widget.language, k);

  @override
  void dispose() {
    _label.dispose();
    _name.dispose();
    _dose.dispose();
    super.dispose();
  }

  Future<void> _pickTime(int i) async {
    final picked =
        await showTimePicker(context: context, initialTime: _times[i]);
    if (picked != null) setState(() => _times[i] = picked);
  }

  void _preset(int n) => setState(() => _times = switch (n) {
        1 => const [TimeOfDay(hour: 8, minute: 0)],
        2 => const [
            TimeOfDay(hour: 8, minute: 0),
            TimeOfDay(hour: 20, minute: 0)
          ],
        _ => const [
            TimeOfDay(hour: 8, minute: 0),
            TimeOfDay(hour: 14, minute: 0),
            TimeOfDay(hour: 20, minute: 0)
          ],
      });

  /// The common routines this form may offer, in order through the day.
  List<(String, ReminderKind, int, int)> get _templates => [
        for (final x in kRoutineTemplates)
          if (widget.kinds.contains(x.$2)) x
      ]..sort((a, b) => (a.$3 * 60 + a.$4).compareTo(b.$3 * 60 + b.$4));

  Future<void> _pickTemplate() async {
    final picked = await showModalBottomSheet<(String, ReminderKind, int, int)>(
      context: context,
      backgroundColor: Palette.cream,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(sheet).size.height * 0.8),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                child: Text(t('tplTitle'),
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800, color: Palette.brandDeep)),
              ),
              for (final x in _templates)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    key: ValueKey('tpl_${x.$1}'),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    onTap: () => Navigator.pop(sheet, x),
                    child: Row(children: [
                      IconBadge(
                          icon: _templateIcon(x.$1),
                          fg: kindStyle(x.$2).fg,
                          bg: kindStyle(x.$2).bg,
                          size: 42,
                          circle: true),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(t(x.$1),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                      Text(TimeOfDay(hour: x.$3, minute: x.$4).format(sheet),
                          style: const TextStyle(fontSize: 14, color: Palette.muted)),
                    ]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _kind = picked.$2;
      _label.text = t(picked.$1);
      _time = TimeOfDay(hour: picked.$3, minute: picked.$4);
    });
  }

  static IconData _templateIcon(String key) => switch (key) {
        'tplWalk' => Icons.directions_walk_rounded,
        'tplWater' => Icons.water_drop_rounded,
        'tplBreakfast' => Icons.free_breakfast_rounded,
        'tplLunch' => Icons.lunch_dining_rounded,
        'tplDinner' => Icons.dinner_dining_rounded,
        'tplExercise' => Icons.self_improvement_rounded,
        'tplCallFamily' => Icons.call_rounded,
        'tplSleep' => Icons.bedtime_rounded,
        _ => Icons.alarm_rounded,
      };

  /// S M T W T F S: tap the days it should run; "Every day" selects all.
  Widget _daysPicker() {
    const order = [6, 0, 1, 2, 3, 4, 5]; // Sunday first, as on a calendar
    final all = _days == 127;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(t('repeatOn'),
                style: kTitleMedium.copyWith(fontSize: 15, height: 1.25)),
          ),
          FilterChip(
            key: const ValueKey('daysAll'),
            visualDensity: VisualDensity.compact,
            label: Text(t('everyDay')),
            selected: all,
            onSelected: (_) => setState(() => _days = 127),
          ),
        ]),
        const SizedBox(height: 8),
        // Seven equal circles that shrink to fit a narrow dialog (a small phone).
        Row(children: [
          for (final bit in order)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 40),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Semantics(
                        label: weekdayShort(widget.language, bit + 1),
                        selected: (_days >> bit) & 1 == 1,
                        button: true,
                        child: GestureDetector(
                          key: ValueKey('day$bit'),
                          onTap: () => setState(() {
                            final next = _days ^ (1 << bit);
                            if (next != 0)
                              _days = next; // at least one day stays on
                          }),
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: (_days >> bit) & 1 == 1
                                  ? Palette.action
                                  : Colors.white,
                              border: Border.all(
                                  color: (_days >> bit) & 1 == 1
                                      ? Palette.action
                                      : Palette.line,
                                  width: 1.5),
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Padding(
                                padding: const EdgeInsets.all(3),
                                child: Text(_dayLetter(bit),
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: (_days >> bit) & 1 == 1
                                            ? Colors.white
                                            : Palette.ink)),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 6),
        Text(daysText(widget.language, _days),
            key: const ValueKey('daysSummary'),
            style: const TextStyle(fontSize: 13, color: Palette.muted)),
      ]),
    );
  }

  /// One letter in English (S M T W T F S); other languages use their short name.
  String _dayLetter(int bit) {
    final name = weekdayShort(widget.language, bit + 1);
    return widget.language == 'en' ? name.substring(0, 1) : name;
  }

  /// Name, dose, when to take it and the times of day: what a prescription needs.
  List<Widget> _medicineFields(Widget Function(String, Widget) field) => [
        field(
            t('rxName'),
            TextField(
                key: const ValueKey('rxName'),
                controller: _name,
                inputFormatters: [LengthLimitingTextInputFormatter(50)],
                onChanged: (_) => setState(() => _nameMissing = false),
                decoration: InputDecoration(
                    errorText: _nameMissing ? t('rxNameNeeded') : null),
                textCapitalization: TextCapitalization.words)),
        field(
            t('rxDose'),
            TextField(
                key: const ValueKey('rxDose'),
                controller: _dose,
                inputFormatters: [LengthLimitingTextInputFormatter(30)])),
        field(
          t('rxWhen'),
          // Two even rows of two: nothing wraps unevenly.
          Column(children: [
            for (var r = 0; r < _kFoods.length; r += 2)
              Padding(
                padding: EdgeInsets.only(bottom: r + 2 < _kFoods.length ? 10 : 0),
                child: Row(children: [
                  for (final f in _kFoods.sublist(r, r + 2)) ...[
                    if (f != _kFoods[r]) const SizedBox(width: 10),
                    Expanded(
                      child: OptionTile(
                        key: ValueKey('food_$f'),
                        label: t('food${f[0].toUpperCase()}${f.substring(1)}'),
                        selected: _food == f,
                        onTap: () => setState(() => _food = _food == f ? null : f),
                      ),
                    ),
                  ],
                ]),
              ),
          ]),
        ),
        field(
          t('rxTimes'),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // One row of three equal tiles with the number big: 1, 2, 3.
            if (!_editing)
              IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final (n, k) in [
                  (1, 'rxOnce'),
                  (2, 'rxTwice'),
                  (3, 'rxThrice')
                ]) ...[
                  if (n > 1) const SizedBox(width: 10),
                  Expanded(
                    child: OptionTile(
                      key: ValueKey('rxPreset$n'),
                      big: '$n',
                      minHeight: 76,
                      label: t(k),
                      selected: _times.length == n,
                      onTap: () => _preset(n),
                    ),
                  ),
                ],
              ]),
              ),
            const SizedBox(height: 8),
            for (var i = 0; i < _times.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: ValueKey('rxTime$i'),
                      icon: const Icon(Icons.access_time),
                      label: Text(_times[i].format(context)),
                      onPressed: () => _pickTime(i),
                    ),
                  ),
                  if (!_editing && _times.length > 1)
                    IconButton(
                      key: ValueKey('rxRemoveTime$i'),
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() => _times.removeAt(i)),
                    ),
                ]),
              ),
            if (!_editing && _times.length < 4)
              TextButton.icon(
                key: const ValueKey('rxAddTime'),
                icon: const Icon(Icons.add_rounded),
                label: Text(t('rxAddTime')),
                onPressed: () => setState(() {
                  final last = _times.last;
                  _times.add(TimeOfDay(
                      hour: (last.hour + 4) % 24, minute: last.minute));
                }),
              ),
          ]),
        ),
      ];

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
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
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
                key:
                    ValueKey(_kind), // follows a template that changes the kind
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
            if (_medicine)
              ..._medicineFields(field)
            else ...[
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(t('reminderLabel'),
                          style: kTitleMedium.copyWith(fontSize: 15, height: 1.25)),
                    ),
                    // Common routines in one tidy list, instead of a row of chips.
                    if (!dated && !_editing && _templates.isNotEmpty)
                      TextButton.icon(
                        key: const ValueKey('quickAdd'),
                        style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8)),
                        icon: const Icon(Icons.bolt_rounded, size: 18),
                        label: Text(t('tplTitle')),
                        onPressed: _pickTemplate,
                      ),
                  ]),
                  const SizedBox(height: 6),
                  TextField(
                      controller: _label,
                      textCapitalization: TextCapitalization.sentences),
                ]),
              ),
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
            ],
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
              _daysPicker(),
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
                  : () {
                      if (_medicine && _name.text.trim().isEmpty) {
                        // Say what is missing instead of a button that does nothing.
                        setState(() => _nameMissing = true);
                        return;
                      }
                      final by = widget.defaultBy.trim().isEmpty
                          ? 'self'
                          : widget.defaultBy.trim();
                      if (_medicine) {
                        final times = [..._times]..sort((a, b) =>
                            (a.hour * 60 + a.minute)
                                .compareTo(b.hour * 60 + b.minute));
                        Navigator.pop(
                            context,
                            NewReminder(
                                _kind,
                                medicineLabel(widget.language, _name.text,
                                    _dose.text, _food),
                                times.first,
                                null,
                                by,
                                extraTimes: times.sublist(1),
                                daysMask: _days));
                      } else {
                        Navigator.pop(
                            context,
                            NewReminder(
                                _kind, _label.text.trim(), _time, _date, by,
                                daysMask: dated ? 127 : _days));
                      }
                    },
              child: Text(t('save')),
            ),
          ),
        ]),
      ],
    );
  }
}
