import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/language_picker.dart';
import '../../core/profile.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/app_database.dart';
import '../../services/reminder_notifier.dart';
import '../../services/sync_service.dart';
import '../caregiver/caregiver_area.dart';
import '../privacy/privacy_screen.dart';
import '../profile/photo_picker.dart' show Avatar;

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
      {super.key, required this.db, required this.patientId, required this.lang});
  final AppDatabase db;
  final String patientId, lang;

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
        const SizedBox(height: 20),
        Text(tr(lang, 'callFamily'),
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Palette.brandDeep)),
        const SizedBox(height: 8),
        FutureBuilder<List<Map<String, Object?>>>(
          future: db.listFamily(patientId),
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
      ]);
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await widget.db.patientById(widget.patientId);
    final f = await widget.db.listFamily(widget.patientId);
    if (mounted) setState(() {
      _p = p;
      _family = f;
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
