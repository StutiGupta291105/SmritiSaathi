import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/app_database.dart';
import '../../services/reminder_notifier.dart';
import '../../services/sync_service.dart';
import 'settings_pages.dart';

/// Settings tab: Profile (all details, language, voice, caregiver area,
/// privacy), Help and Support, About, Emergency SOS, and Log out.
class ProfileTab extends StatelessWidget {
  const ProfileTab({
    super.key,
    required this.db,
    required this.notifier,
    required this.patient,
    required this.onChanged,
    required this.onLogout,
    this.hooks,
  });
  final ServerHooks? hooks;
  final AppDatabase db;
  final ReminderNotifier notifier;
  final Map<String, Object?> patient;
  final VoidCallback onChanged, onLogout;

  String get _id => patient['id'] as String;
  String get _lang => patient['language'] as String;
  String t(String k) => tr(_lang, k);

  @override
  Widget build(BuildContext context) {
    void open(Widget screen) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

    Widget row(Key key, IconData icon, Color fg, Color bg, String label,
            VoidCallback onTap) =>
        InkWell(
          key: key,
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(children: [
              IconBadge(icon: icon, fg: fg, bg: bg, size: 44, circle: true),
              const SizedBox(width: 14),
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600)),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 28, color: Palette.muted),
            ]),
          ),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      children: [
        ScreenTitle(t('settings')),
        const SizedBox(height: 16),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Column(children: [
            row(const ValueKey('rowProfile'), Icons.person_outline_rounded,
                Palette.green, Palette.tileGreen, t('tabProfile'),
                () => open(ProfileDetailsScreen(
                      hooks: hooks,
                      db: db,
                      notifier: notifier,
                      patientId: _id,
                      onChanged: onChanged,
                    ))),
            row(const ValueKey('rowHelp'), Icons.help_outline_rounded,
                Palette.blue, Palette.tileBlue, t('helpSupport'),
                () => open(HelpSupportScreen(lang: _lang))),
            row(const ValueKey('rowAbout'), Icons.info_outline_rounded,
                Palette.purple, Palette.tilePurple, t('aboutApp'),
                () => open(AboutAppScreen(lang: _lang))),
            row(const ValueKey('rowSos'), Icons.phone_in_talk_outlined,
                Palette.red, Palette.tileRed, t('emergencySos'),
                () => open(SosScreen(db: db, patientId: _id, lang: _lang))),
          ]),
        ),
        const SizedBox(height: 16),
        AppCard(
          color: Palette.tileRed,
          onTap: onLogout,
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.logout_rounded, color: Palette.red),
              const SizedBox(width: 10),
              Text(t('logout'),
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Palette.red)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text('${t('appName')} • ${t('tagline')} • $kFooterLine',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Palette.muted)),
      ],
    );
  }
}
