import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/language_picker.dart';
import '../../core/profile.dart';
import '../../services/api_client.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/app_database.dart';
import '../../services/reminder_notifier.dart';
import '../../services/sync_service.dart';
import '../caregiver/caregiver_area.dart';
import '../privacy/privacy_screen.dart';
import '../profile/photo_picker.dart' show Avatar;
import '../profile/profile_flow.dart';

const String kFooterLine = 'MDoNER Digital Health';
const String kAppVersion = '0.1.0';

Widget _page(String title, List<Widget> children) => Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SafeArea(
          child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: children),
        ),
      ),
    );

Widget _textCard(IconData icon, Color fg, Color bg, String text) => AppCard(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        IconBadge(icon: icon, fg: fg, bg: bg, size: 44, circle: true),
        const SizedBox(width: 14),
        Expanded(
            child: Text(text, style: const TextStyle(fontSize: 16, height: 1.45))),
      ]),
    );

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key, required this.lang});
  final String lang;

  @override
  Widget build(BuildContext context) => _page(tr(lang, 'helpSupport'), [
        _textCard(Icons.help_outline_rounded, Palette.blue, Palette.tileBlue,
            tr(lang, 'helpBody')),
      ]);
}

class AboutAppScreen extends StatelessWidget {
  const AboutAppScreen({super.key, required this.lang});
  final String lang;

  @override
  Widget build(BuildContext context) => _page(tr(lang, 'aboutApp'), [
        AppCard(
          child: Column(children: [
            Text(tr(lang, 'appName'), style: kHeadlineMedium),
            const SizedBox(height: 4),
            Text(tr(lang, 'tagline'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: Palette.muted)),
            const SizedBox(height: 4),
            Text('v$kAppVersion',
                style: const TextStyle(fontSize: 13, color: Palette.muted)),
          ]),
        ),
        const SizedBox(height: 12),
        _textCard(Icons.info_outline_rounded, Palette.purple,
            Palette.tilePurple, tr(lang, 'aboutBody')),
        const SizedBox(height: 16),
        Center(
            child: Text(kFooterLine,
                style: const TextStyle(fontSize: 13, color: Palette.muted))),
      ]);
}

class SosScreen extends StatelessWidget {
  const SosScreen(
      {super.key, this.db, this.patientId, required this.lang});

  /// Without a local patient (a caregiver or doctor account) only the 112
  /// button is shown.
  final AppDatabase? db;
  final String? patientId;
  final String lang;

  @override
  Widget build(BuildContext context) => _page(tr(lang, 'emergencySos'), [
        _textCard(Icons.emergency_rounded, Palette.red, Palette.tileRed,
            tr(lang, 'sosBody')),
        const SizedBox(height: 14),
        FilledButton.icon(
          key: const ValueKey('sosCall112'),
          style: FilledButton.styleFrom(backgroundColor: Palette.red),
          onPressed: () => launchUrl(Uri(scheme: 'tel', path: '112')),
          icon: const Icon(Icons.call_rounded),
          label: Text(tr(lang, 'chatCall112')),
        ),
        if (db != null && patientId != null) ..._familyCalls(),
      ]);

  List<Widget> _familyCalls() => [
        const SizedBox(height: 20),
        Text(tr(lang, 'callFamily'),
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Palette.brandDeep)),
        const SizedBox(height: 8),
        FutureBuilder<List<Map<String, Object?>>>(
          future: db!.listFamily(patientId!),
          builder: (context, snap) {
            final family = snap.data ?? const <Map<String, Object?>>[];
            if (family.isEmpty) {
              return Text(tr(lang, 'noneAdded'),
                  style: const TextStyle(fontSize: 16, color: Palette.muted));
            }
            return Column(children: [
              for (final m in family)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    onTap: () => launchUrl(
                        Uri(scheme: 'tel', path: m['phone'] as String)),
                    child: Row(children: [
                      Avatar(photo: m['photo'] as List<int>?, radius: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(m['name'] as String,
                                  style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700)),
                              Text(
                                  '${tr(lang, 'rel_${m['relation']}')} · ${m['phone']}',
                                  style: const TextStyle(
                                      fontSize: 14, color: Palette.muted)),
                            ]),
                      ),
                      const Icon(Icons.call_rounded, color: Palette.green),
                    ]),
                  ),
                ),
            ]);
          },
        ),
      ];
}

/// Everything held about the person, with language and spoken instructions
/// editable, and the caregiver area and privacy a tap away.
class ProfileDetailsScreen extends StatefulWidget {
  const ProfileDetailsScreen({
    super.key,
    required this.db,
    required this.notifier,
    required this.patientId,
    required this.onChanged,
    this.hooks,
  });
  final AppDatabase db;
  final ReminderNotifier notifier;
  final String patientId;
  final VoidCallback onChanged;
  final ServerHooks? hooks;

  @override
  State<ProfileDetailsScreen> createState() => _ProfileDetailsScreenState();
}

class _ProfileDetailsScreenState extends State<ProfileDetailsScreen> {
  Map<String, Object?>? _p;
  List<Map<String, Object?>> _family = const [];
  List<Map<String, Object?>> _links = const [];
  int _reminders = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await widget.db.patientById(widget.patientId);
    final f = await widget.db.listFamily(widget.patientId);
    final l = await widget.db.listCareLinks(widget.patientId);
    final r = await widget.db.listReminders(widget.patientId);
    if (mounted) setState(() {
      _p = p;
      _family = f;
      _links = l.where((x) => x['status'] != 'revoked').toList();
      _reminders = r.length;
    });
  }

  Future<void> _changed() async {
    await _load();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    if (p == null) {
      return Scaffold(
          appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    final lang = p['language'] as String;
    String t(String k) => tr(lang, k);
    final dob = p['dob'] == null ? null : DateTime.parse(p['dob'] as String);
    String? text(String k) {
      final v = p[k] as String?;
      return v == null || v.trim().isEmpty ? null : v;
    }

    Widget item(String label, String? value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
                flex: 4,
                child: Text(label,
                    style: const TextStyle(fontSize: 14, color: Palette.muted))),
            const SizedBox(width: 12),
            Expanded(
                flex: 6,
                child: Text(value ?? '—',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600))),
          ]),
        );
    const divider = Divider(height: 1, color: Palette.line);

    Widget navRow(IconData icon, Color fg, Color bg, String label,
            VoidCallback onTap) =>
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(children: [
              IconBadge(icon: icon, fg: fg, bg: bg, size: 44, circle: true),
              const SizedBox(width: 14),
              Expanded(
                  child: Text(label,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600))),
              const Icon(Icons.chevron_right_rounded,
                  size: 28, color: Palette.muted),
            ]),
          ),
        );

    String linkSummary(String kind) {
      final mine = _links.where((x) => x['kind'] == kind).toList();
      if (mine.isEmpty) return t('notAddedYet');
      return mine.map((x) => '${x['name']}').join(', ');
    }

    Widget editRow(int stage, IconData icon, Color fg, Color bg, String label,
            String summary) =>
        InkWell(
          key: ValueKey('edit_$stage'),
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => ProfileFlow(
                db: widget.db,
                notifier: widget.notifier,
                hooks: widget.hooks,
                patient: p,
                editStage: stage,
                onDone: () {},
              ),
            ));
            await _changed();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(children: [
              IconBadge(icon: icon, fg: fg, bg: bg, size: 44, circle: true),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                      Text(summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13.5, color: Palette.muted)),
                    ]),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 28, color: Palette.muted),
            ]),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text(t('tabProfile'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Center(child: Avatar(photo: p['photo'] as List<int>?, radius: 52)),
            const SizedBox(height: 10),
            Center(
                child: Text('${p['display_name']}',
                    textAlign: TextAlign.center, style: kHeadlineMedium)),
            const SizedBox(height: 16),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(children: [
                item(t('phoneNumber'), text('phone')),
                divider,
                item(t('email'), text('email')),
                divider,
                item(
                    t('dob'),
                    dob == null
                        ? null
                        : MaterialLocalizations.of(context).formatMediumDate(dob)),
                divider,
                item(
                    t('age'),
                    dob == null
                        ? null
                        : '${ageFromDob(dob, DateTime.now())} ${t('years')}'),
                divider,
                item(t('cityTown'), text('city')),
                divider,
                item(t('stateLabel'), text('state')),
              ]),
            ),
            const SizedBox(height: 16),
            Text(t('manageProfile'),
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Palette.brandDeep)),
            const SizedBox(height: 8),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Column(children: [
                editRow(0, Icons.badge_outlined, Palette.green, Palette.tileGreen,
                    t('aboutYou'), t('editDetails')),
                divider,
                editRow(1, Icons.groups_rounded, Palette.orange, Palette.tileOrange,
                    t('family'), _family.isEmpty ? t('notAddedYet') : '${_family.length}'),
                divider,
                editRow(2, Icons.medical_services_rounded, Palette.purple,
                    Palette.tilePurple, t('doctorDetails'), linkSummary('doctor')),
                divider,
                editRow(3, Icons.volunteer_activism_rounded, Palette.green,
                    Palette.tileGreen, t('caregiverDetails'), linkSummary('caregiver')),
                divider,
                editRow(4, Icons.checklist_rounded, Palette.blue, Palette.tileBlue,
                    t('routineTitle'),
                    _reminders == 0 ? t('notAddedYet') : '$_reminders'),
              ]),
            ),
            const SizedBox(height: 16),
            Text(t('language'),
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Palette.brandDeep)),
            const SizedBox(height: 8),
            LanguageRow(
              lang: lang,
              onChanged: (code) async {
                await widget.db.setLanguage(widget.patientId, code, 'user');
                await widget.notifier
                    .resync(patientId: widget.patientId, lang: code);
                await _changed();
              },
            ),
            const SizedBox(height: 12),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Row(children: [
                IconBadge(
                    icon: Icons.record_voice_over_rounded,
                    fg: Palette.sky,
                    bg: Palette.tileSky,
                    size: 44,
                    circle: true),
                const SizedBox(width: 14),
                Expanded(
                    child: Text(t('voiceOn'),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600))),
                Switch(
                  value: p['voice_enabled'] == 1,
                  activeThumbColor: Palette.action,
                  onChanged: (v) async {
                    await widget.db
                        .setVoiceEnabled(widget.patientId, v, 'user');
                    await _changed();
                  },
                ),
              ]),
            ),
            const SizedBox(height: 16),
            Text(t('family'),
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Palette.brandDeep)),
            const SizedBox(height: 8),
            if (_family.isEmpty)
              Text(t('noneAdded'),
                  style: const TextStyle(fontSize: 16, color: Palette.muted))
            else
              AppCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Column(children: [
                  for (var i = 0; i < _family.length; i++) ...[
                    if (i > 0) divider,
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(children: [
                        Avatar(
                            photo: _family[i]['photo'] as List<int>?,
                            radius: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_family[i]['name'] as String,
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700)),
                                Text(
                                    '${t('rel_${_family[i]['relation']}')} · ${_family[i]['phone']}',
                                    style: const TextStyle(
                                        fontSize: 14, color: Palette.muted)),
                              ]),
                        ),
                      ]),
                    ),
                  ],
                ]),
              ),
            const SizedBox(height: 16),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Column(children: [
                navRow(Icons.supervisor_account_rounded, Palette.green,
                    Palette.tileGreen, t('caregiverArea'), () {
                  openCaregiverArea(
                    context,
                    db: widget.db,
                    notifier: widget.notifier,
                    patientId: widget.patientId,
                    lang: lang,
                    onChanged: _changed,
                  );
                }),
                divider,
                navRow(Icons.lock_rounded, Palette.purple, Palette.tilePurple,
                    t('privacy'), () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => PrivacyScreen(
                      hooks: widget.hooks,
                      db: widget.db,
                      notifier: widget.notifier,
                      patientId: widget.patientId,
                      language: lang,
                      onErased: () {
                        Navigator.of(context).popUntil((r) => r.isFirst);
                        widget.onChanged();
                      },
                    ),
                  ));
                }),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

/// Profile for a caregiver or doctor account: who is signed in, and language.
class AccountProfileScreen extends StatefulWidget {
  const AccountProfileScreen({
    super.key,
    required this.name,
    required this.role,
    required this.lang,
    required this.onLangChanged,
    this.careId,
    this.api,
    this.accent = Palette.brand,
  });
  final String name, role, lang;
  final String? careId;

  /// With the online service: lets the person choose a number their patients
  /// can call from the app.
  final ApiClient? api;
  final ValueChanged<String>? onLangChanged;
  final Color accent;

  @override
  State<AccountProfileScreen> createState() => _AccountProfileScreenState();
}

class _AccountProfileScreenState extends State<AccountProfileScreen> {
  late String _lang = widget.lang;
  late String? _careId = widget.careId;
  final _phone = TextEditingController();
  bool _saving = false;
  String? _saved;
  String t(String k) => tr(_lang, k);

  @override
  void initState() {
    super.initState();
    _loadMe();
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _loadMe() async {
    if (widget.api == null) return;
    try {
      final me = await widget.api!.me();
      if (!mounted) return;
      setState(() {
        _careId = me.careId ?? _careId;
        _phone.text = (me.contactPhone ?? '').replaceFirst('+91', '');
      });
    } catch (_) {}
  }

  bool get _phoneOk => _phone.text.trim().isEmpty || normalizePhone(_phone.text) != null;

  Future<void> _savePhone() async {
    setState(() => _saving = true);
    try {
      final n = _phone.text.trim().isEmpty ? '' : normalizePhone(_phone.text)!;
      await widget.api!.setContactPhone(n);
      if (mounted) setState(() => _saved = t('contactSaved'));
    } on ApiException {
      if (mounted) setState(() => _saved = t('chatSendFailed'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final initial =
        widget.name.trim().isEmpty ? '?' : widget.name.trim()[0].toUpperCase();
    return Scaffold(
      appBar: AppBar(title: Text(t('tabProfile'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Center(
              child: CircleAvatar(
                radius: 52,
                backgroundColor: Palette.tileGreen,
                child: Text(initial,
                    style: kHeadlineMedium.copyWith(color: widget.accent)),
              ),
            ),
            const SizedBox(height: 10),
            Center(
                child: Text(widget.name,
                    textAlign: TextAlign.center, style: kHeadlineMedium)),
            Center(
              child: Text(
                  t(widget.role == 'doctor' ? 'roleDoctor' : 'roleCaretaker'),
                  style: const TextStyle(fontSize: 15, color: Palette.muted)),
            ),
            const SizedBox(height: 20),
            CareIdCard(careId: _careId, lang: _lang, accent: widget.accent),
            if (widget.api != null) ...[
              const SizedBox(height: 20),
              Text(t('contactPhoneLabel'),
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Palette.brandDeep)),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('contactPhone'),
                controller: _phone,
                keyboardType: TextInputType.phone,
                onChanged: (_) => setState(() => _saved = null),
                decoration: InputDecoration(
                    prefixText: '+91 ',
                    helperText: t('contactPhoneHelp'),
                    helperMaxLines: 2),
              ),
              const SizedBox(height: 10),
              FilledButton(
                key: const ValueKey('saveContact'),
                onPressed: _phoneOk && !_saving ? _savePhone : null,
                child: Text(_saved ?? t('save')),
              ),
            ],
            const SizedBox(height: 20),
            Text(t('language'),
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Palette.brandDeep)),
            const SizedBox(height: 8),
            LanguageRow(
              lang: _lang,
              accent: widget.accent,
              onChanged: (code) {
                setState(() => _lang = code);
                widget.onLangChanged?.call(code);
              },
            ),
          ],
        ),
      ),
    );
  }
}


/// A caretaker's or doctor's own Care ID, with a copy button. A patient types
/// it to invite them; nothing is shared until they accept.
class CareIdCard extends StatelessWidget {
  const CareIdCard({super.key, required this.careId, required this.lang, this.accent = Palette.brand});
  final String? careId;
  final String lang;
  final Color accent;

  @override
  Widget build(BuildContext context) => AppCard(
        key: const ValueKey('careIdCard'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr(lang, 'careIdLabel'),
              style: const TextStyle(fontSize: 14, color: Palette.muted)),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(
              child: Text(careId ?? '…',
                  key: const ValueKey('careIdText'),
                  style: kHeadlineMedium.copyWith(color: accent, letterSpacing: 1.5)),
            ),
            if (careId != null)
              IconButton(
                tooltip: tr(lang, 'careIdCopy'),
                icon: const Icon(Icons.copy_rounded),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: careId!));
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(tr(lang, 'careIdCopied'))));
                },
              ),
          ]),
          const SizedBox(height: 6),
          Text(tr(lang, 'careIdShare'),
              style: const TextStyle(fontSize: 14, height: 1.35, color: Palette.muted)),
        ]),
      );
}
