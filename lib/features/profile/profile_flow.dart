import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/languages.dart';
import '../../core/profile.dart';
import '../../core/reminder_schedule.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/app_database.dart';
import '../../services/reminder_notifier.dart';
import '../reminders/reminder_style.dart';
import '../reminders/reminders_screen.dart';
import 'consent_gate.dart';
import 'photo_picker.dart';

/// States and union territories of India, as shown in the State list.
const kIndianStates = [
  'Andaman and Nicobar Islands', 'Andhra Pradesh', 'Arunachal Pradesh', 'Assam',
  'Bihar', 'Chandigarh', 'Chhattisgarh',
  'Dadra and Nagar Haveli and Daman and Diu', 'Delhi', 'Goa', 'Gujarat',
  'Haryana', 'Himachal Pradesh', 'Jammu and Kashmir', 'Jharkhand', 'Karnataka',
  'Kerala', 'Ladakh', 'Lakshadweep', 'Madhya Pradesh', 'Maharashtra', 'Manipur',
  'Meghalaya', 'Mizoram', 'Nagaland', 'Odisha', 'Puducherry', 'Punjab',
  'Rajasthan', 'Sikkim', 'Tamil Nadu', 'Telangana', 'Tripura', 'Uttar Pradesh',
  'Uttarakhand', 'West Bengal',
];

bool looksLikeEmail(String v) =>
    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(v.trim());

/// Profile completion after the first login, in five pages. The page reached is
/// saved so the flow resumes if the app is closed:
/// 0 about you (one form), 1 family members, 2 doctor, 3 caregiver, 4 routine
/// and reminders, then Save.
class ProfileFlow extends StatefulWidget {
  const ProfileFlow({
    super.key,
    required this.db,
    required this.notifier,
    required this.patient,
    required this.onDone,
  });
  final AppDatabase db;
  final ReminderNotifier notifier;
  final Map<String, Object?> patient;
  final VoidCallback onDone;

  @override
  State<ProfileFlow> createState() => _ProfileFlowState();
}

class _ProfileFlowState extends State<ProfileFlow> {
  static const _steps = 5;

  late int _stage = (widget.patient['setup_stage'] as int).clamp(0, _steps - 1);
  late String _lang = widget.patient['language'] as String;
  late DateTime? _dob = widget.patient['dob'] == null
      ? null
      : DateTime.parse(widget.patient['dob'] as String);
  late List<int>? _photo = widget.patient['photo'] as List<int>?;
  bool _photoChanged = false;
  bool _photoRemoved = false;

  late final _nameCtl = TextEditingController(
      text: widget.patient['display_name'] as String);
  late final _emailCtl =
      TextEditingController(text: widget.patient['email'] as String? ?? '');
  late final _cityCtl =
      TextEditingController(text: widget.patient['city'] as String? ?? '');
  late final _phoneCtl = TextEditingController(text: widget.patient['phone'] as String? ?? '');
  late String? _state = kIndianStates.contains(widget.patient['state'])
      ? widget.patient['state'] as String
      : null;

  String get _id => widget.patient['id'] as String;
  String get _name => _nameCtl.text.trim().isEmpty
      ? widget.patient['display_name'] as String
      : _nameCtl.text.trim();
  String t(String k) => tr(_lang, k);

  @override
  void dispose() {
    _nameCtl.dispose();
    _emailCtl.dispose();
    _cityCtl.dispose();
    _phoneCtl.dispose();
    super.dispose();
  }

  bool get _emailOk =>
      _emailCtl.text.trim().isEmpty || looksLikeEmail(_emailCtl.text);

  bool get _canNext =>
      _stage != 0 ||
      (_dob != null && _nameCtl.text.trim().isNotEmpty && _emailOk);

  Future<void> _go(int stage) async {
    await widget.db.setSetupStage(_id, stage);
    if (mounted) setState(() => _stage = stage);
  }

  Future<void> _next() async {
    if (_stage == 0) {
      await widget.db.updateProfileBasics(
        patientId: _id,
        displayName: _nameCtl.text,
        email: _emailCtl.text,
        city: _cityCtl.text,
        state: _state ?? '',
        dob: _dob,
        photo: _photoChanged ? _photo : null,
        clearPhoto: _photoRemoved,
        language: _lang,
        by: _name,
      );
    }
    if (_stage == _steps - 1) {
      await widget.db.setSetupStage(_id, _steps);
      await widget.notifier.resync(patientId: _id, lang: _lang);
      widget.onDone();
      return;
    }
    await _go(_stage + 1);
  }

  @override
  Widget build(BuildContext context) {
    final last = _stage == _steps - 1;
    final pages = [_aboutYou(), _family(), _doctor(), _caregiver(), _routine()];
    final titles = [
      'aboutYou', 'family', 'doctorDetails', 'caregiverDetails', 'routineTitle'
    ];
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          // Little room (small phone or very large text): drop the big title
          // and keep the step line and progress bar.
          final tight =
              box.maxHeight / MediaQuery.textScalerOf(context).scale(1) < 600;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!tight) ...[
                      ScreenTitle(t('profileTitle')),
                      const SizedBox(height: 4),
                    ],
                    Text(
                        tight
                            ? '${t('profileTitle')}  ·  ${_stage + 1}/$_steps  ·  ${t(titles[_stage])}'
                            : '${_stage + 1}/$_steps  ·  ${t(titles[_stage])}',
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Palette.muted)),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: (_stage + 1) / _steps,
                        minHeight: 8,
                        backgroundColor: Palette.line,
                        color: Palette.action,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: pages[_stage]),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Row(
                  children: [
                    if (_stage > 0)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _go(_stage - 1),
                          child: Text(t('back')),
                        ),
                      ),
                    if (_stage > 0) const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        key: const ValueKey('profileNext'),
                        onPressed: _canNext ? _next : null,
                        child: Text(last ? t('save') : t('next')),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  // ---- page 0: about you (one form) -------------------------------------

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Text(text, style: kTitleMedium),
      );

  Widget _aboutYou() {
    final age = _dob == null ? null : ageFromDob(_dob!, DateTime.now());
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(child: Avatar(photo: _photo, radius: 56)),
        const SizedBox(height: 8),
        Center(
          child: Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.add_a_photo_rounded),
                label: Text('${t('addPhoto')} ${t('optional')}'),
                onPressed: () async {
                  final bytes = await pickPhoto(context, _lang);
                  if (bytes != null) {
                    setState(() {
                      _photo = bytes;
                      _photoChanged = true;
                      _photoRemoved = false;
                    });
                  }
                },
              ),
              if (_photo != null)
                TextButton(
                  onPressed: () => setState(() {
                    _photo = null;
                    _photoChanged = false;
                    _photoRemoved = true;
                  }),
                  child: Text(t('removePhoto')),
                ),
            ],
          ),
        ),
        _label(t('yourName')),
        TextField(
          key: const ValueKey('profileName'),
          controller: _nameCtl,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => setState(() {}),
        ),
        _label(t('phoneNumber')),
        TextField(
          key: const ValueKey('profilePhone'),
          controller: _phoneCtl,
          readOnly: true,
          enabled: false,
        ),
        _label('${t('email')} ${t('optional')}'),
        TextField(
          key: const ValueKey('profileEmail'),
          controller: _emailCtl,
          keyboardType: TextInputType.emailAddress,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
              errorText: _emailOk ? null : t('invalidEmail')),
        ),
        _label(t('dob')),
        OutlinedButton.icon(
          icon: const Icon(Icons.cake_rounded),
          label: Text(_dob == null
              ? t('pickDob')
              : MaterialLocalizations.of(context).formatMediumDate(_dob!)),
          onPressed: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: _dob ?? DateTime(now.year - 70, 1, 1),
              firstDate: DateTime(1900),
              lastDate: now,
            );
            if (picked != null) setState(() => _dob = picked);
          },
        ),
        if (age != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('${t('age')}: $age ${t('years')}',
                style: kHeadlineSmall.copyWith(color: Palette.brand)),
          ),
        _label('${t('cityTown')} ${t('optional')}'),
        TextField(
          key: const ValueKey('profileCity'),
          controller: _cityCtl,
          textCapitalization: TextCapitalization.words,
        ),
        _label('${t('stateLabel')} ${t('optional')}'),
        DropdownButtonFormField<String>(
          key: const ValueKey('profileState'),
          initialValue: _state,
          isExpanded: true,
          borderRadius: BorderRadius.circular(16),
          items: [
            for (final s in kIndianStates)
              DropdownMenuItem(
                  value: s, child: Text(s, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() => _state = v),
        ),
        _label(t('preferredLanguage')),
        DropdownButtonFormField<String>(
          key: const ValueKey('profileLanguage'),
          initialValue: _lang,
          isExpanded: true,
          borderRadius: BorderRadius.circular(16),
          items: [
            for (final c in kLanguageOrder)
              DropdownMenuItem(
                value: c,
                child: Text(
                    kLanguages[c] == kLanguageEnglish[c]
                        ? kLanguages[c]!
                        : '${kLanguages[c]}  ·  ${kLanguageEnglish[c]}',
                    overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => setState(() => _lang = v ?? _lang),
        ),
      ],
    );
  }

  // ---- page 1: family ---------------------------------------------------

  Widget _family() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(t('familyHelp'),
              style: const TextStyle(fontSize: 15, color: Palette.muted)),
          const SizedBox(height: 12),
          ConsentGate(
            db: widget.db,
            patientId: _id,
            purpose: 'family_contacts',
            purposeTextKey: 'purposeFamily',
            lang: _lang,
            byName: _name,
            child: _FamilyList(
                db: widget.db, patientId: _id, lang: _lang, by: _name),
          ),
        ],
      );

  // ---- pages 2 and 3: doctor and caregiver ------------------------------

  Widget _invitePage(String kind) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(t('careTeamHelp'),
              style: const TextStyle(fontSize: 15, color: Palette.muted)),
          const SizedBox(height: 12),
          ConsentGate(
            db: widget.db,
            patientId: _id,
            purpose: kind == 'doctor' ? 'doctor_share' : 'caregiver_share',
            purposeTextKey:
                kind == 'doctor' ? 'purposeDoctor' : 'purposeCaregiverShare',
            lang: _lang,
            byName: _name,
            child: _CareInvite(
                db: widget.db,
                patientId: _id,
                kind: kind,
                lang: _lang,
                by: _name),
          ),
          const SizedBox(height: 12),
          Text(t('inviteNote'),
              style: const TextStyle(fontSize: 13.5, color: Palette.muted)),
        ],
      );

  Widget _doctor() => _invitePage('doctor');
  Widget _caregiver() => _invitePage('caregiver');

  // ---- page 4: routine and reminders ------------------------------------

  Widget _routine() => ConsentGate(
        db: widget.db,
        patientId: _id,
        purpose: 'reminders',
        purposeTextKey: 'purposeReminders',
        lang: _lang,
        byName: _name,
        child: _RoutineSetup(
            db: widget.db,
            notifier: widget.notifier,
            patientId: _id,
            lang: _lang,
            by: _name),
      );
}

// ---- family list ----------------------------------------------------------

class _FamilyList extends StatefulWidget {
  const _FamilyList(
      {required this.db,
      required this.patientId,
      required this.lang,
      required this.by});
  final AppDatabase db;
  final String patientId, lang, by;

  @override
  State<_FamilyList> createState() => _FamilyListState();
}

class _FamilyListState extends State<_FamilyList> {
  List<Map<String, Object?>> _members = [];

  String t(String k) => tr(widget.lang, k);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final m = await widget.db.listFamily(widget.patientId);
    if (mounted) setState(() => _members = m);
  }

  Future<void> _add() async {
    final r = await showDialog<_NewMember>(
        context: context, builder: (_) => _FamilyDialog(lang: widget.lang));
    if (r == null) return;
    await widget.db.addFamilyMember(
      patientId: widget.patientId,
      name: r.name,
      phone: r.phone,
      relation: r.relation,
      photo: r.photo,
      by: widget.by,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final m in _members)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AppCard(
              padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
              child: Row(children: [
                Avatar(photo: m['photo'] as List<int>?, radius: 24),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m['name'] as String,
                          style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: Palette.brandDeep)),
                      Text('${t('rel_${m['relation']}')} · ${m['phone']}',
                          style: const TextStyle(
                              fontSize: 13.5, color: Palette.muted)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: t('delete'),
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: Palette.muted),
                  onPressed: () async {
                    await widget.db.deleteFamilyMember(
                        widget.patientId, m['id'] as String, widget.by);
                    await _load();
                  },
                ),
              ]),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.person_add_rounded),
          label: Text(t('addFamily')),
          onPressed: _add,
        ),
      ],
    );
  }
}

class _NewMember {
  _NewMember(this.name, this.phone, this.relation, this.photo);
  final String name, phone, relation;
  final Uint8List? photo;
}

class _FamilyDialog extends StatefulWidget {
  const _FamilyDialog({required this.lang});
  final String lang;

  @override
  State<_FamilyDialog> createState() => _FamilyDialogState();
}

class _FamilyDialogState extends State<_FamilyDialog> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  String _relation = kRelations.first;
  Uint8List? _photo;
  String? _error;

  String t(String k) => tr(widget.lang, k);

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _save() {
    final phone = normalizePhone(_phone.text);
    if (_name.text.trim().isEmpty) {
      setState(() => _error = t('errName'));
    } else if (phone == null) {
      setState(() => _error = t('errPhone'));
    } else {
      Navigator.pop(
          context, _NewMember(_name.text.trim(), phone, _relation, _photo));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t('addFamily')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () async {
                final b = await pickPhoto(context, widget.lang);
                if (b != null) setState(() => _photo = b);
              },
              child: Avatar(photo: _photo, radius: 40, icon: Icons.add_a_photo),
            ),
            Text(t('optional')),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: t('yourName')),
            ),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                  labelText: t('phoneNumber'), prefixText: '+91 '),
            ),
            const SizedBox(height: 8),
            DropdownButton<String>(
              value: _relation,
              isExpanded: true,
              items: [
                for (final r in kRelations)
                  DropdownMenuItem(value: r, child: Text(t('rel_$r'))),
              ],
              onChanged: (v) => setState(() => _relation = v!),
            ),
            if (_error != null)
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(t('cancel'))),
        FilledButton(onPressed: _save, child: Text(t('save'))),
      ],
    );
  }
}

// ---- care team invite -----------------------------------------------------

class _CareInvite extends StatefulWidget {
  const _CareInvite(
      {required this.db,
      required this.patientId,
      required this.kind,
      required this.lang,
      required this.by});
  final AppDatabase db;
  final String patientId, kind, lang, by;

  @override
  State<_CareInvite> createState() => _CareInviteState();
}

class _CareInviteState extends State<_CareInvite> {
  Map<String, Object?>? _link;
  final _name = TextEditingController();
  final _proId = TextEditingController();
  final _phone = TextEditingController();

  String t(String k) => tr(widget.lang, k);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _proId.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final all = await widget.db.listCareLinks(widget.patientId);
    final mine = all.where((l) => l['kind'] == widget.kind).toList();
    if (mounted) setState(() => _link = mine.isEmpty ? null : mine.last);
  }

  bool get _valid =>
      _name.text.trim().isNotEmpty &&
      _proId.text.trim().isNotEmpty &&
      normalizePhone(_phone.text) != null;

  Future<void> _save() async {
    await widget.db.addCareInvite(
      patientId: widget.patientId,
      kind: widget.kind,
      name: _name.text.trim(),
      professionalId: _proId.text.trim(),
      phone: normalizePhone(_phone.text),
      by: widget.by,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final isDoctor = widget.kind == 'doctor';
    final link = _link;
    return AppCard(
      child: Padding(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              IconBadge(
                  icon: isDoctor
                      ? Icons.medical_services_rounded
                      : Icons.volunteer_activism_rounded,
                  fg: isDoctor ? Palette.purple : Palette.green,
                  bg: isDoctor ? Palette.tilePurple : Palette.tileGreen,
                  size: 44,
                  circle: true),
              const SizedBox(width: 12),
              Expanded(
                child: Text(t(isDoctor ? 'roleDoctor' : 'roleCaretaker'),
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Palette.brandDeep)),
              ),
            ]),
            const SizedBox(height: 12),
            if (link != null) ...[
              Text('${link['name']}  ·  ${link['professional_id']}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                Chip(
                  avatar: const Icon(Icons.schedule, size: 20),
                  label: Text(link['status'] == 'pending'
                      ? t('invitePending')
                      : t('status${'${link['status']}'[0].toUpperCase()}${'${link['status']}'.substring(1)}')),
                ),
                if (isDoctor && link['verified'] == 1)
                  Chip(
                    avatar: const Icon(Icons.verified_rounded,
                        size: 20, color: Palette.green),
                    label: Text(t('doctorVerified')),
                  ),
              ]),
            ] else ...[
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                    labelText: t(isDoctor ? 'doctorName' : 'caregiverName')),
              ),
              TextField(
                controller: _proId,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                    labelText: t(isDoctor ? 'doctorId' : 'caregiverId')),
              ),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                    labelText: t('invitePhone'), prefixText: '+91 '),
              ),
              const SizedBox(height: 12),
              FilledButton(
                  onPressed: _valid ? _save : null, child: Text(t('saveInvite'))),
            ],
          ],
        ),
      ),
    );
  }
}


// ---- routine and reminders ------------------------------------------------

/// Daily routine (repeats every day) and reminders for dates (birthdays,
/// appointments, events). Both can be changed later under Reminders.
class _RoutineSetup extends StatefulWidget {
  const _RoutineSetup({
    required this.db,
    required this.notifier,
    required this.patientId,
    required this.lang,
    required this.by,
  });
  final AppDatabase db;
  final ReminderNotifier notifier;
  final String patientId, lang, by;

  @override
  State<_RoutineSetup> createState() => _RoutineSetupState();
}

class _RoutineSetupState extends State<_RoutineSetup> {
  List<Reminder> _items = [];

  String t(String k) => tr(widget.lang, k);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await widget.db.listReminders(widget.patientId);
    if (mounted) setState(() => _items = items);
  }

  Future<void> _add(List<ReminderKind> kinds, String titleKey) async {
    final r = await showAddReminderDialog(context,
        language: widget.lang,
        kinds: kinds,
        title: t(titleKey),
        defaultBy: widget.by);
    if (r == null) return;
    await widget.db.addReminder(
      patientId: widget.patientId,
      kind: r.kind,
      label: r.label,
      hour: r.time.hour,
      minute: r.time.minute,
      onDate: r.date,
      createdBy: r.by,
    );
    await widget.notifier
        .resync(patientId: widget.patientId, lang: widget.lang);
    await _load();
  }

  Future<void> _delete(Reminder r) async {
    await widget.db.deleteReminder(widget.patientId, r.id, widget.by);
    await widget.notifier
        .resync(patientId: widget.patientId, lang: widget.lang);
    await _load();
  }

  Widget _row(Reminder r) {
    final style = kindStyle(r.kind);
    final time = TimeOfDay(hour: r.hour, minute: r.minute).format(context);
    final when = r.onDate == null
        ? '$time · ${t('everyDay')}'
        : '${MaterialLocalizations.of(context).formatMediumDate(r.onDate!)} · $time';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(children: [
          IconBadge(
              icon: style.icon, fg: style.fg, bg: style.bg, size: 44, circle: true),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.label.isEmpty ? t('kind_${r.kind.name}') : r.label,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Palette.brandDeep)),
                Text(
                    r.label.isEmpty
                        ? when
                        : '${t('kind_${r.kind.name}')} · $when',
                    style: const TextStyle(
                        fontSize: 13.5, color: Palette.muted)),
              ],
            ),
          ),
          IconButton(
            tooltip: t('delete'),
            icon: const Icon(Icons.delete_outline_rounded, color: Palette.muted),
            onPressed: () => _delete(r),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final daily = _items.where((r) => !kDatedKinds.contains(r.kind)).toList();
    final dated = _items.where((r) => kDatedKinds.contains(r.kind)).toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(t('dailyRoutine'), style: kTitleLarge),
        const SizedBox(height: 4),
        Text(t('routineHelp'),
            style: const TextStyle(fontSize: 14, color: Palette.muted)),
        const SizedBox(height: 10),
        for (final r in daily) _row(r),
        OutlinedButton.icon(
          key: const ValueKey('addRoutine'),
          icon: const Icon(Icons.add_rounded),
          label: Text(t('addDailyRoutine')),
          onPressed: () => _add(const [
            ReminderKind.medicine,
            ReminderKind.hydration,
            ReminderKind.activity,
          ], 'addDailyRoutine'),
        ),
        const SizedBox(height: 24),
        Text(t('datesReminders'), style: kTitleLarge),
        const SizedBox(height: 4),
        Text(t('datesHelp'),
            style: const TextStyle(fontSize: 14, color: Palette.muted)),
        const SizedBox(height: 10),
        for (final r in dated) _row(r),
        OutlinedButton.icon(
          key: const ValueKey('addDateReminder'),
          icon: const Icon(Icons.add_rounded),
          label: Text(t('addDateReminder')),
          onPressed: () => _add(const [
            ReminderKind.birthday,
            ReminderKind.appointment,
            ReminderKind.event,
          ], 'addDateReminder'),
        ),
        const SizedBox(height: 16),
        Text(t('routineLaterNote'),
            style: const TextStyle(fontSize: 13.5, color: Palette.muted)),
      ],
    );
  }
}
