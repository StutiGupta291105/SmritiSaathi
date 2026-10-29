import 'package:flutter/material.dart';

import '../../core/engagement_alerts.dart';
import '../../core/profile.dart';
import '../../core/language_picker.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/app_database.dart';
import '../../services/reminder_notifier.dart';
import '../../services/sync_service.dart';
import '../caregiver/caregiver_area.dart';
import '../privacy/privacy_screen.dart';
import '../profile/photo_picker.dart' show Avatar;

/// Profile tab: who is signed in, language, spoken instructions, caregiver
/// area, privacy and log out.
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
    final dob =
        patient['dob'] == null ? null : DateTime.parse(patient['dob'] as String);
    final phone = patient['phone'] as String?;
    final voiceOn = patient['voice_enabled'] == 1;

    Widget row(IconData icon, Color fg, Color bg, String label,
            {VoidCallback? onTap, Widget? trailing, Color? labelColor}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AppCard(
            onTap: onTap,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              IconBadge(icon: icon, fg: fg, bg: bg, size: 44, circle: true),
              const SizedBox(width: 14),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: labelColor)),
              ),
              trailing ??
                  (onTap == null
                      ? const SizedBox.shrink()
                      : const Icon(Icons.chevron_right_rounded,
                          size: 28, color: Palette.muted)),
            ]),
          ),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      children: [
        ScreenTitle(t('settings')),
        const SizedBox(height: 16),
        // Language
        Text(t('language'),
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Palette.brandDeep)),
        const SizedBox(height: 8),
        LanguageRow(
          lang: _lang,
          onChanged: (code) async {
            await db.setLanguage(_id, code, 'user');
            await notifier.resync(patientId: _id, lang: code);
            onChanged();
          },
        ),
        const SizedBox(height: 18),

        // Who is signed in
        AppCard(
          child: Row(children: [
            Avatar(photo: patient['photo'] as List<int>?, radius: 36),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${patient['display_name']}',
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w700)),
                  if (dob != null)
                    Text('${t('age')}: ${ageFromDob(dob, DateTime.now())} ${t('years')}',
                        style: const TextStyle(
                            fontSize: 14, color: Palette.muted)),
                  if (phone != null)
                    Text(maskPhone(phone),
                        style: const TextStyle(
                            fontSize: 14, color: Palette.muted)),
                ],
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        row(Icons.record_voice_over_rounded, Palette.sky, Palette.tileSky,
            t('voiceOn'),
            trailing: Switch(
              value: voiceOn,
              activeThumbColor: Palette.action,
              onChanged: (v) async {
                await db.setVoiceEnabled(_id, v, 'user');
                onChanged();
              },
            )),
        row(Icons.supervisor_account_rounded, Palette.green, Palette.tileGreen,
            t('caregiverArea'),
            trailing: FutureBuilder<List<EngagementAlert>>(
              future: db.currentAlerts(_id),
              builder: (context, snap) {
                final n = (snap.data ?? const <EngagementAlert>[])
                    .where((a) => a.severity == AlertSeverity.attention)
                    .length;
                return Row(mainAxisSize: MainAxisSize.min, children: [
                  if (n > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: Palette.red,
                          borderRadius: BorderRadius.circular(14)),
                      child: Text('$n',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14)),
                    ),
                  const Icon(Icons.chevron_right_rounded,
                      size: 28, color: Palette.muted),
                ]);
              },
            ),
            onTap: () => openCaregiverArea(
                  context,
                  db: db,
                  notifier: notifier,
                  patientId: _id,
                  lang: _lang,
                  onChanged: onChanged,
                )),
        row(Icons.lock_rounded, Palette.purple, Palette.tilePurple,
            t('privacy'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PrivacyScreen(
                    hooks: hooks,
                    db: db,
                    notifier: notifier,
                    patientId: _id,
                    language: _lang,
                    onErased: () {
                      Navigator.of(context).popUntil((r) => r.isFirst);
                      onChanged();
                    },
                  ),
                ))),
        const SizedBox(height: 6),
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
      ],
    );
  }
}
