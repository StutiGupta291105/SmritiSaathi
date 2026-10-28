import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../data/app_database.dart';

const String kNoticeVersion = 'v2';

/// First step after a patient account is created: notice and per-purpose
/// consent (DPDP), given by the patient or a guardian, plus the starting game
/// level. Only gameplay storage is required; every other purpose starts
/// unticked so that consent is an active choice.
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

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final TextEditingController _givenByName =
      TextEditingController(text: widget.account['name'] as String);
  final _givenByRelation = TextEditingController(text: 'self');
  int _level = 2;
  final Map<String, bool> _purposes = {
    'gameplay': true,
    'reminders': false,
    'family_contacts': false,
    'doctor_share': false,
    'caregiver_share': false,
    'sync': false,
  };
  bool _saving = false;

  String t(String k) => tr(widget.lang, k);

  @override
  void dispose() {
    _givenByName.dispose();
    _givenByRelation.dispose();
    super.dispose();
  }

  bool get _valid =>
      _givenByName.text.trim().isNotEmpty &&
      _givenByRelation.text.trim().isNotEmpty &&
      _purposes['gameplay'] == true;

  Future<void> _submit() async {
    setState(() => _saving = true);
    final by = _givenByName.text.trim();
    final id = await widget.db.createPatient(
      accountId: widget.account['id'] as String,
      phone: widget.account['phone'] as String,
      displayName: widget.account['name'] as String,
      baselineLevel: _level,
      language: widget.lang,
      createdBy: by,
    );
    await widget.db.recordConsent(
      patientId: id,
      purposes: _purposes,
      givenByName: by,
      givenByRelation: _givenByRelation.text.trim(),
      noticeVersion: kNoticeVersion,
    );
    if (mounted) widget.onDone();
  }

  Widget _purposeTile(String key, String stringKey, {bool required = false}) =>
      CheckboxListTile(
        value: _purposes[key],
        onChanged: required
            ? null
            : (v) => setState(() => _purposes[key] = v ?? false),
        title: Text(t(stringKey), style: const TextStyle(fontSize: 18)),
        controlAffinity: ListTileControlAffinity.leading,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('appName'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Colors.amber.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(t('notAMedicalDevice'),
                  style: const TextStyle(fontSize: 18)),
            ),
          ),
          const SizedBox(height: 16),
          Text(t('consentTitle'),
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(t('consentIntro'), style: const TextStyle(fontSize: 18)),
          _purposeTile('gameplay', 'purposeGameplay', required: true),
          _purposeTile('reminders', 'purposeReminders'),
          _purposeTile('family_contacts', 'purposeFamily'),
          _purposeTile('doctor_share', 'purposeDoctor'),
          _purposeTile('caregiver_share', 'purposeCaregiverShare'),
          _purposeTile('sync', 'purposeSync'),
          const SizedBox(height: 8),
          TextField(
            controller: _givenByName,
            decoration: InputDecoration(labelText: t('givenByName')),
            onChanged: (_) => setState(() {}),
          ),
          TextField(
            controller: _givenByRelation,
            decoration: InputDecoration(labelText: t('givenByRelation')),
            onChanged: (_) => setState(() {}),
          ),
          const Divider(height: 40),
          Text(t('setupTitle'),
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Text(t('startLevel'), style: const TextStyle(fontSize: 18)),
          for (var l = 1; l <= 5; l++)
            ListTile(
              leading: Icon(
                  l == _level
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: Theme.of(context).colorScheme.primary,
                  size: 30),
              title: Text(t('level$l'), style: const TextStyle(fontSize: 18)),
              onTap: () => setState(() => _level = l),
            ),
          Text(t('levelHelp')),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _valid && !_saving ? _submit : null,
            child: Text(t('continue')),
          ),
        ],
      ),
    );
  }
}
