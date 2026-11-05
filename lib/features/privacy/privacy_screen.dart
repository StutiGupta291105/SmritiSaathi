import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../data/app_database.dart';
import '../../services/reminder_notifier.dart';
import '../../services/sync_service.dart';
import '../onboarding/onboarding_screen.dart' show kNoticeVersion;

/// DPDP rights in one place: change or withdraw consent per purpose, see all
/// data held (access), erase it (erasure). Every action is attributed to a
/// named person and written to the audit log.
class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({
    super.key,
    required this.db,
    required this.notifier,
    required this.patientId,
    required this.language,
    required this.onErased,
    this.hooks,
  });
  final ServerHooks? hooks;
  final AppDatabase db;
  final ReminderNotifier notifier;
  final String patientId;
  final String language;
  final VoidCallback onErased;

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  Map<String, bool> _state = {};
  final _by = TextEditingController();

  String t(String k) => tr(widget.language, k);

  static const _labels = {
    'gameplay': 'purposeGameplay',
    'reminders': 'purposeReminders',
    'family_contacts': 'purposeFamily',
    'doctor_share': 'purposeDoctor',
    'caregiver_share': 'purposeCaregiverShare',
    'location': 'purposeLocation',
    'sync': 'purposeSync',
    'companion': 'purposeCompanion',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _by.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = await widget.db.consentState(widget.patientId);
    if (mounted) setState(() => _state = s);
  }

  String get _actor => _by.text.trim();

  Future<void> _toggle(String purpose, bool value) async {
    if (_actor.isEmpty) return;
    if (value) {
      await widget.db.recordConsent(
        patientId: widget.patientId,
        purposes: {purpose: true},
        givenByName: _actor,
        givenByRelation: 'caregiver_or_self',
        noticeVersion: kNoticeVersion,
      );
    } else {
      await widget.db.withdrawConsent(
        patientId: widget.patientId,
        purpose: purpose,
        byName: _actor,
        byRelation: 'caregiver_or_self',
        noticeVersion: kNoticeVersion,
      );
    }
    await widget.notifier
        .resync(patientId: widget.patientId, lang: widget.language);
    await _load();
    // Tell the server now, so sharing stops there as well.
    await widget.hooks?.syncNow();
  }

  Future<void> _export() async {
    if (_actor.isEmpty) return;
    final data = await widget.db.exportPatient(widget.patientId, _actor);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        content: SingleChildScrollView(
          child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(data)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t('finish'))),
        ],
      ),
    );
  }

  Future<void> _erase() async {
    if (_actor.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        content: Text(t('eraseConfirm')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('delete'))),
        ],
      ),
    );
    if (ok != true) return;
    final remote = widget.hooks;
    if (remote != null && !await remote.eraseRemote(widget.patientId)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t('eraseNeedsInternet'))));
      return;
    }
    await widget.db.erasePatient(widget.patientId, _actor);
    await widget.notifier.resync(patientId: widget.patientId, lang: widget.language);
    if (mounted) widget.onErased();
  }

  @override
  Widget build(BuildContext context) {
    final blocked = _actor.isEmpty;
    return Scaffold(
      appBar: AppBar(title: Text(t('privacy'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(t('privacyIntro')),
          const SizedBox(height: 12),
          TextField(
            controller: _by,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: t('whoIsActing')),
          ),
          const SizedBox(height: 12),
          for (final e in _labels.entries)
            SwitchListTile(
              title: Text(t(e.value)),
              value: _state[e.key] ?? false,
              onChanged: blocked ? null : (v) => _toggle(e.key, v),
            ),
          const Divider(height: 32),
          OutlinedButton.icon(
            icon: const Icon(Icons.visibility),
            label: Text(t('exportData')),
            onPressed: blocked ? null : _export,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.delete_forever),
            label: Text(t('eraseData')),
            onPressed: blocked ? null : _erase,
          ),
        ],
      ),
    );
  }
}
