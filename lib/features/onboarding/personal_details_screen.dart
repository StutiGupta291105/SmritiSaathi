import 'package:flutter/material.dart';

import '../../core/language_picker.dart';
import '../../core/profile.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/app_database.dart';
import '../profile/profile_flow.dart' show kIndianStates, looksLikeEmail;
import 'onboarding_screen.dart' show kDefaultStartLevel, kNoticeVersion;

/// The last step of creating a patient account (after the mobile number and the code):
/// email, date of birth, city, state and the language to use, plus the one consent the app
/// needs to work on this phone. Then straight to the dashboard. The rest of the profile
/// (family, doctor, caregiver, routine) is completed later in Settings.
class PersonalDetailsScreen extends StatefulWidget {
  const PersonalDetailsScreen({
    super.key,
    required this.db,
    required this.account,
    required this.lang,
    required this.onDone,
    this.existing,
  });
  final AppDatabase db;
  final Map<String, Object?> account;
  final String lang;
  final VoidCallback onDone;

  /// A person who started on an older version and has a profile but no date of birth yet:
  /// no new consent is asked, their earlier answers stand.
  final Map<String, Object?>? existing;

  @override
  State<PersonalDetailsScreen> createState() => _PersonalDetailsScreenState();
}

class _PersonalDetailsScreenState extends State<PersonalDetailsScreen> {
  late String _lang = (widget.existing?['language'] as String?) ?? widget.lang;
  final _email = TextEditingController();
  final _city = TextEditingController();
  String? _state;
  DateTime? _dob;
  bool _core = false; // keep results and reminders on this phone (required)
  bool _care = false; // let the invited caregiver and doctor see them (optional)
  bool _saving = false;

  String t(String k) => tr(_lang, k);
  bool get _existing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _email.text = (e['email'] as String?) ?? '';
      _city.text = (e['city'] as String?) ?? '';
      _state = kIndianStates.contains(e['state']) ? e['state'] as String : null;
      _dob = e['dob'] == null ? null : DateTime.tryParse(e['dob'] as String);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _city.dispose();
    super.dispose();
  }

  bool get _emailOk => _email.text.trim().isEmpty || looksLikeEmail(_email.text);
  bool get _valid => _dob != null && _emailOk && (_existing || _core);

  Future<void> _submit() async {
    setState(() => _saving = true);
    final by = widget.account['name'] as String;
    String id;
    if (_existing) {
      id = widget.existing!['id'] as String;
    } else {
      id = await widget.db.createPatient(
        accountId: widget.account['id'] as String,
        phone: widget.account['phone'] as String,
        displayName: by,
        baselineLevel: kDefaultStartLevel,
        language: _lang,
        createdBy: by,
      );
      await widget.db.recordConsent(
        patientId: id,
        purposes: {
          'gameplay': _core,
          'reminders': _core,
          'family_contacts': false,
          'doctor_share': _care,
          'caregiver_share': _care,
          'sync': _care,
        },
        givenByName: by,
        givenByRelation: 'self',
        noticeVersion: kNoticeVersion,
      );
    }
    await widget.db.updateProfileBasics(
      patientId: id,
      email: _email.text,
      city: _city.text,
      state: _state ?? '',
      dob: _dob,
      language: _lang,
      by: by,
    );
    // Everything else in the profile is optional and is completed from Settings.
    await widget.db.setSetupStage(id, 5);
    if (mounted) widget.onDone();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 70, 1, 1),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Text(text, style: kTitleMedium),
      );

  @override
  Widget build(BuildContext context) {
    final age = _dob == null ? null : ageFromDob(_dob!, DateTime.now());
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              children: [
                Text(t('detailsTitle'), style: kHeadlineMedium),
                const SizedBox(height: 4),
                Text(t('detailsSub'),
                    style: const TextStyle(fontSize: 14.5, color: Palette.muted)),
                _label(t('dob')),
                OutlinedButton.icon(
                  key: const ValueKey('detailsDob'),
                  icon: const Icon(Icons.cake_rounded),
                  label: Text(_dob == null
                      ? t('pickDob')
                      : '${MaterialLocalizations.of(context).formatMediumDate(_dob!)}  ·  $age ${t('years')}'),
                  onPressed: _pickDob,
                ),
                _label('${t('email')} ${t('optional')}'),
                TextField(
                  key: const ValueKey('detailsEmail'),
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(errorText: _emailOk ? null : t('invalidEmail')),
                ),
                _label('${t('cityTown')} ${t('optional')}'),
                TextField(
                  key: const ValueKey('detailsCity'),
                  controller: _city,
                  textCapitalization: TextCapitalization.words,
                ),
                _label('${t('stateLabel')} ${t('optional')}'),
                DropdownButtonFormField<String>(
                  key: const ValueKey('detailsState'),
                  initialValue: _state,
                  isExpanded: true,
                  borderRadius: BorderRadius.circular(16),
                  items: [
                    for (final s in kIndianStates) DropdownMenuItem(value: s, child: Text(s))
                  ],
                  onChanged: (v) => setState(() => _state = v),
                ),
                _label(t('language')),
                LanguageRow(lang: _lang, onChanged: (l) => setState(() => _lang = l)),
                if (!_existing) ...[
                  const SizedBox(height: 14),
                  CheckboxListTile(
                    key: const ValueKey('consentCore'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _core,
                    onChanged: (v) => setState(() => _core = v ?? false),
                    title: Text(t('consentCore'), style: const TextStyle(fontSize: 14.5)),
                  ),
                  CheckboxListTile(
                    key: const ValueKey('consentCare'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _care,
                    onChanged: (v) => setState(() => _care = v ?? false),
                    title: Text(t('consentCare'), style: const TextStyle(fontSize: 14.5)),
                  ),
                ],
                const SizedBox(height: 6),
                Text(t('completeLater'),
                    style: const TextStyle(fontSize: 12.5, color: Palette.muted)),
                Text(t('notAMedicalDevice'),
                    style: const TextStyle(fontSize: 12.5, color: Palette.muted)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: FilledButton(
              key: const ValueKey('detailsContinue'),
              onPressed: _valid && !_saving ? _submit : null,
              child: Text(t('goDashboard')),
            ),
          ),
        ]),
      ),
    );
  }
}
