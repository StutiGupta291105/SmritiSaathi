import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/app_database.dart';

const String kNoticeVersion = 'v2';

/// First step after a patient account is created: "Allow Permissions". Each
/// purpose (DPDP) is allowed with its own button, which turns into a green
/// tick; tapping the tick takes the permission back. Only saving results on
/// the device is required to continue; everything else starts not allowed so
/// that consent stays an active choice. The person signing up gives consent
/// for themselves, so the consent record names them with the relation "self".
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.db,
    required this.account,
    required this.lang,
    required this.onDone,
  });
  final AppDatabase db;
  final Map<String, Object?> account;
  final String lang;
  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

/// Starting game level for a new person; a caregiver can change it later in
/// the caregiver area.
const int kDefaultStartLevel = 2;

class _OnboardingScreenState extends State<OnboardingScreen> {
  final Map<String, bool> _purposes = {
    'gameplay': false,
    'reminders': false,
    'family_contacts': false,
    'doctor_share': false,
    'caregiver_share': false,
    'sync': false,
  };
  bool _saving = false;

  String t(String k) => tr(widget.lang, k);

  bool get _valid => _purposes['gameplay'] == true;

  Future<void> _submit() async {
    setState(() => _saving = true);
    final by = widget.account['name'] as String;
    final id = await widget.db.createPatient(
      accountId: widget.account['id'] as String,
      phone: widget.account['phone'] as String,
      displayName: by,
      baselineLevel: kDefaultStartLevel,
      language: widget.lang,
      createdBy: by,
    );
    await widget.db.recordConsent(
      patientId: id,
      purposes: _purposes,
      givenByName: by,
      givenByRelation: 'self',
      noticeVersion: kNoticeVersion,
    );
    if (mounted) widget.onDone();
  }

  Widget _row(String key, IconData icon, Color fg, Color bg, String title,
      String detail,
      {bool required = false}) {
    final on = _purposes[key] == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Row(children: [
          IconBadge(icon: icon, fg: fg, bg: bg, size: 48, circle: true),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Palette.brandDeep)),
                if (required)
                  Text(t('permRequired'),
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Palette.orange)),
                const SizedBox(height: 2),
                Text(detail,
                    style: const TextStyle(
                        fontSize: 13.5, height: 1.3, color: Palette.muted)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          on
              ? Semantics(
                  button: true,
                  label: '$title: ${t('permAllowed')}',
                  child: InkResponse(
                    key: ValueKey('allowed_$key'),
                    onTap: () => setState(() => _purposes[key] = false),
                    child: const Icon(Icons.check_circle_rounded,
                        size: 44, color: Palette.action),
                  ),
                )
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 104),
                  child: FilledButton(
                    key: ValueKey('allow_$key'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 42),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      textStyle: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 15,
                          fontWeight: FontWeight.w600),
                    ),
                    onPressed: () => setState(() => _purposes[key] = true),
                    child: Text(t('allow'),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              children: [
                Text(t('allowPermsTitle'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w700,
                        color: Palette.brandDeep)),
                const SizedBox(height: 8),
                Text(t('permIntro'),
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(fontSize: 15, color: Palette.muted)),
                const SizedBox(height: 20),
                _row('gameplay', Icons.save_rounded, Palette.green,
                    Palette.tileGreen, t('permGameplay'), t('purposeGameplay'),
                    required: true),
                _row('reminders', Icons.notifications_active_rounded,
                    Palette.orange, Palette.tileOrange, t('permReminders'),
                    t('purposeReminders')),
                _row('family_contacts', Icons.call_rounded, Palette.sky,
                    Palette.tileSky, t('permFamily'), t('purposeFamily')),
                _row('doctor_share', Icons.medical_services_rounded,
                    Palette.purple, Palette.tilePurple, t('permDoctor'),
                    t('purposeDoctor')),
                _row('caregiver_share', Icons.supervisor_account_rounded,
                    Palette.green, Palette.tileGreen, t('permCaregiver'),
                    t('purposeCaregiverShare')),
                _row('sync', Icons.cloud_upload_rounded, Palette.sky,
                    Palette.tileSky, t('permSync'), t('purposeSync')),
                const SizedBox(height: 4),
                Text(t('notAMedicalDevice'),
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(fontSize: 12.5, color: Palette.muted)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: FilledButton(
              onPressed: _valid && !_saving ? _submit : null,
              child: Text(t('continue')),
            ),
          ),
        ]),
      ),
    );
  }
}
