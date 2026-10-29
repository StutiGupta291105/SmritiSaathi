import 'dart:io' show Platform;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/profile.dart';
import '../../core/languages.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/app_database.dart';
import '../../services/reminder_notifier.dart';
import '../reminders/reminders_screen.dart';
import 'consent_gate.dart';
import 'photo_picker.dart';

/// Profile completion after the first login. Five steps; the step reached is
/// saved so the flow resumes if the app is closed:
/// 0 about you, 1 family, 2 care team, 3 daily routine, 4 permissions.
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

  String get _id => widget.patient['id'] as String;
  String get _name => widget.patient['display_name'] as String;
  String t(String k) => tr(_lang, k);

  bool get _canNext => _stage != 0 || _dob != null;

  Future<void> _go(int stage) async {
    await widget.db.setSetupStage(_id, stage);
    if (mounted) setState(() => _stage = stage);
  }

  Future<void> _next() async {
    if (_stage == 0) {
      await widget.db.updateProfileBasics(
        patientId: _id,
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
    final theme = Theme.of(context);
    final last = _stage == _steps - 1;
    final pages = [_aboutYou(), _family(), _careTeam(), _routine(), _permissions()];
    final titles = ['aboutYou', 'family', 'careTeam', 'routineTitle', 'permTitle'];
    return Scaffold(
      appBar: AppBar(
        title: Text(t('profileTitle')),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(6),
          child: LinearProgressIndicator(value: (_stage + 1) / _steps),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('${_stage + 1}/$_steps  ${t(titles[_stage])}',
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ),
            Expanded(child: pages[_stage]),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  if (_stage > 0)
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(64)),
                        onPressed: () => _go(_stage - 1),
                        child: Text(t('back'),
                            style: const TextStyle(fontSize: 20)),
                      ),
                    ),
                  if (_stage > 0) const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _canNext ? _next : null,
                      child: Text(last ? t('finishSetup') : t('next')),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- step 0: about you ------------------------------------------------

  Widget _aboutYou() {
    final theme = Theme.of(context);
    final age = _dob == null ? null : ageFromDob(_dob!, DateTime.now());
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(child: Avatar(photo: _photo, radius: 60)),
        const SizedBox(height: 8),
        Center(
          child: Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.add_a_photo),
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
        const SizedBox(height: 24),
        Text(t('dob'), style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.cake),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(60)),
          label: Text(
              _dob == null
                  ? t('pickDob')
                  : MaterialLocalizations.of(context).formatMediumDate(_dob!),
              style: const TextStyle(fontSize: 20)),
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
            padding: const EdgeInsets.only(top: 12),
            child: Text('${t('age')}: $age ${t('years')}',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(color: Palette.brand, fontWeight: FontWeight.w700)),
          ),
        const SizedBox(height: 24),
        Text(t('preferredLanguage'), style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final e in kLanguages.entries)
              ChoiceChip(
                label: Text(e.value, style: const TextStyle(fontSize: 20)),
                selected: _lang == e.key,
                onSelected: (_) => setState(() => _lang = e.key),
              ),
          ],
        ),
      ],
    );
  }

  // ---- step 1: family ---------------------------------------------------

  Widget _family() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(t('familyHelp'), style: const TextStyle(fontSize: 18)),
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

  // ---- step 2: care team ------------------------------------------------

  Widget _careTeam() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(t('careTeamHelp'), style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 12),
          for (final kind in const ['doctor', 'caregiver'])
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: ConsentGate(
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
            ),
          Text(t('inviteNote'), style: const TextStyle(fontSize: 16)),
        ],
      );

  // ---- step 3: daily routine --------------------------------------------

  Widget _routine() => Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(t('routineHelp'), style: const TextStyle(fontSize: 18)),
          ),
          Expanded(
            child: ConsentGate(
              db: widget.db,
              patientId: _id,
              purpose: 'reminders',
              purposeTextKey: 'purposeReminders',
              lang: _lang,
              byName: _name,
              child: RemindersScreen(
                db: widget.db,
                notifier: widget.notifier,
                patientId: _id,
                language: _lang,
                embedded: true,
              ),
            ),
          ),
        ],
      );

  // ---- step 4: permissions ----------------------------------------------

  Widget _permissions() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _PermissionCard(
            icon: Icons.call,
            title: t('permPhone'),
            why: t('permPhoneWhy'),
            lang: _lang,
            permission: Permission.phone,
          ),
          const SizedBox(height: 16),
          _PermissionCard(
            icon: Icons.location_on,
            title: t('permLocation'),
            why: t('permLocationWhy'),
            lang: _lang,
            permission: Permission.locationWhenInUse,
            onGranted: () => widget.db.hasConsent(_id, 'location').then((has) {
              if (!has) {
                return widget.db.recordConsent(
                  patientId: _id,
                  purposes: {'location': true},
                  givenByName: _name,
                  givenByRelation: 'self_or_guardian',
                  noticeVersion: 'v2',
                );
              }
            }),
          ),
        ],
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
          Card(
            child: ListTile(
              leading: Avatar(photo: m['photo'] as List<int>?),
              title: Text(m['name'] as String,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              subtitle: Text(
                  '${t('rel_${m['relation']}')} · ${m['phone']}',
                  style: const TextStyle(fontSize: 16)),
              trailing: IconButton(
                tooltip: t('delete'),
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  await widget.db.deleteFamilyMember(
                      widget.patientId, m['id'] as String, widget.by);
                  await _load();
                },
              ),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(60)),
          icon: const Icon(Icons.person_add),
          label: Text(t('addFamily'), style: const TextStyle(fontSize: 20)),
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
    final theme = Theme.of(context);
    final link = _link;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(isDoctor ? Icons.medical_services : Icons.volunteer_activism,
                  color: Palette.brand),
              const SizedBox(width: 8),
              Text(t(isDoctor ? 'roleDoctor' : 'roleCaretaker'),
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 8),
            if (link != null) ...[
              Text('${link['name']}  ·  ${link['professional_id']}',
                  style: const TextStyle(fontSize: 20)),
              const SizedBox(height: 6),
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

// ---- permission card ------------------------------------------------------

class _PermissionCard extends StatefulWidget {
  const _PermissionCard({
    required this.icon,
    required this.title,
    required this.why,
    required this.lang,
    required this.permission,
    this.onGranted,
  });
  final IconData icon;
  final String title, why, lang;
  final Permission permission;
  final Future<void> Function()? onGranted;

  @override
  State<_PermissionCard> createState() => _PermissionCardState();
}

class _PermissionCardState extends State<_PermissionCard> {
  PermissionStatus? _status;

  String t(String k) => tr(widget.lang, k);

  /// iOS has no 'phone' permission: a tel: link opens the dialer, which asks
  /// the person to confirm the call itself. Showing a button that can never be
  /// granted would only confuse.
  bool get _notNeeded => Platform.isIOS && widget.permission == Permission.phone;

  @override
  void initState() {
    super.initState();
    if (_notNeeded) return;
    widget.permission.status.then((s) {
      if (mounted) setState(() => _status = s);
    });
  }

  Future<void> _ask() async {
    final s = await widget.permission.request();
    if (s.isGranted) await widget.onGranted?.call();
    if (mounted) setState(() => _status = s);
  }

  @override
  Widget build(BuildContext context) {
    final granted = _notNeeded || (_status?.isGranted ?? false);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(widget.icon, size: 32, color: Palette.brand),
              const SizedBox(width: 10),
              Text(widget.title,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 8),
            Text(widget.why, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 12),
            if (granted)
              Chip(
                  avatar: const Icon(Icons.check_circle, color: Colors.green),
                  label: Text(t('allowed')))
            else ...[
              if (_status != null && _status!.isPermanentlyDenied)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(t('notAllowed')),
                ),
              FilledButton(
                onPressed: _status!= null && _status!.isPermanentlyDenied
                    ? openAppSettings
                    : _ask,
                child: Text(t('allow')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
