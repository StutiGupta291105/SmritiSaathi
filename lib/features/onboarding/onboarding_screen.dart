import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../data/app_database.dart';

const String kNoticeVersion = 'v1';

/// One-time onboarding done BY THE CAREGIVER/GUARDIAN: consent (DPDP) +
/// starting level. Consent is per purpose; only gameplay storage is required.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.db, required this.onDone});
  final AppDatabase db;
  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  String _lang = 'en';
  final _patientName = TextEditingController();
  final _givenByName = TextEditingController();
  final _givenByRelation = TextEditingController();
  int _level = 2;
  final Map<String, bool> _purposes = {
    'gameplay': true,
    'reminders': true,
    'caregiver_share': false,
    'sync': false,
  };
  bool _saving = false;

  @override
  void dispose() {
    _patientName.dispose();
    _givenByName.dispose();
    _givenByRelation.dispose();
    super.dispose();
  }

  bool get _valid =>
      _patientName.text.trim().isNotEmpty &&
      _givenByName.text.trim().isNotEmpty &&
      _givenByRelation.text.trim().isNotEmpty &&
      _purposes['gameplay'] == true;

  Future<void> _submit() async {
    setState(() => _saving = true);
    final caregiver = _givenByName.text.trim();
    final id = await widget.db.createPatient(
      displayName: _patientName.text.trim(),
      baselineLevel: _level,
      language: _lang,
      caregiverName: caregiver,
    );
    await widget.db.recordConsent(
      patientId: id,
      purposes: _purposes,
      givenByName: caregiver,
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
        title: Text(tr(_lang, stringKey), style: const TextStyle(fontSize: 18)),
        controlAffinity: ListTileControlAffinity.leading,
      );

  @override
  Widget build(BuildContext context) {
    final t = (String k) => tr(_lang, k);
    return Scaffold(
      appBar: AppBar(
        title: Text(t('appName')),
        actions: [
          TextButton(
            onPressed: () => setState(() => _lang = _lang == 'en' ? 'hi' : 'en'),
            child: Text(_lang == 'en' ? 'हिन्दी' : 'English',
                style: const TextStyle(fontSize: 18)),
          ),
        ],
      ),
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
          _purposeTile('caregiver_share', 'purposeCaregiverShare'),
          _purposeTile('sync', 'purposeSync'),
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
          TextField(
            controller: _patientName,
            decoration: InputDecoration(labelText: t('patientName')),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Text(t('startLevel'), style: const TextStyle(fontSize: 18)),
          for (var l = 1; l <= 5; l++)
            RadioListTile<int>(
              value: l,
              groupValue: _level,
              onChanged: (v) => setState(() => _level = v ?? _level),
              title: Text(t('level$l'), style: const TextStyle(fontSize: 18)),
            ),
          Text(t('levelHelp')),
          const SizedBox(height: 24),
          SizedBox(
            height: 64,
            child: FilledButton(
              onPressed: _valid && !_saving ? _submit : null,
              child: Text(t('continue'), style: const TextStyle(fontSize: 22)),
            ),
          ),
        ],
      ),
    );
  }
}
