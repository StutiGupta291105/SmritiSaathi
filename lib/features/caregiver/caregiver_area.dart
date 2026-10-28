import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/ability_model.dart';
import '../../core/adaptive_engine.dart';
import '../../core/adherence.dart';
import '../../core/engagement_alerts.dart';
import '../../core/profile.dart';
import '../../core/progress.dart';
import '../../core/reporting.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/app_database.dart';
import '../../services/reminder_notifier.dart';
import '../profile/consent_gate.dart';
import '../profile/photo_picker.dart' show Avatar;
import '../reminders/reminders_screen.dart';

const _games = {
  'memory_match': 'memoryGame',
  'attention': 'gameAttention',
  'routine': 'gameRoutine',
};

/// Opens the caregiver area: PIN first, then the dashboard.
Future<void> openCaregiverArea(
  BuildContext context, {
  required AppDatabase db,
  required ReminderNotifier notifier,
  required String patientId,
  required String lang,
  required VoidCallback onChanged,
}) =>
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _PinScreen(
        db: db,
        notifier: notifier,
        patientId: patientId,
        lang: lang,
        onChanged: onChanged,
      ),
    ));

// ---- PIN --------------------------------------------------------------------

class _PinScreen extends StatefulWidget {
  const _PinScreen({
    required this.db,
    required this.notifier,
    required this.patientId,
    required this.lang,
    required this.onChanged,
  });
  final AppDatabase db;
  final ReminderNotifier notifier;
  final String patientId, lang;
  final VoidCallback onChanged;

  @override
  State<_PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<_PinScreen> {
  bool? _hasPin;
  final _pin = TextEditingController();
  final _repeat = TextEditingController();
  String? _errorKey;
  bool _busy = false;

  String t(String k) => tr(widget.lang, k);

  @override
  void initState() {
    super.initState();
    widget.db.hasCaregiverPin(widget.patientId).then((v) {
      if (mounted) setState(() => _hasPin = v);
    });
  }

  @override
  void dispose() {
    _pin.dispose();
    _repeat.dispose();
    super.dispose();
  }

  void _openDashboard() {
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => CaregiverDashboard(
        db: widget.db,
        notifier: widget.notifier,
        patientId: widget.patientId,
        lang: widget.lang,
        onChanged: widget.onChanged,
      ),
    ));
  }

  Future<void> _submit() async {
    final pin = _pin.text;
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      return setState(() => _errorKey = 'pinShort');
    }
    setState(() {
      _busy = true;
      _errorKey = null;
    });
    if (_hasPin == false) {
      if (_repeat.text != pin) {
        return setState(() {
          _errorKey = 'pinMismatch';
          _busy = false;
        });
      }
      await widget.db.setCaregiverPin(widget.patientId, pin, 'caregiver');
      await widget.db.verifyCaregiverPin(widget.patientId, pin, 'caregiver');
      if (mounted) _openDashboard();
      return;
    }
    final r = await widget.db.verifyCaregiverPin(widget.patientId, pin, 'caregiver');
    if (!mounted) return;
    if (r == PinResult.ok) return _openDashboard();
    setState(() {
      _errorKey = r == PinResult.locked ? 'pinLocked' : 'pinWrong';
      _busy = false;
      _pin.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final creating = _hasPin == false;
    return Scaffold(
      appBar: AppBar(title: Text(t('caregiverArea'))),
      body: _hasPin == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Icon(Icons.lock, size: 56, color: Palette.brand),
                const SizedBox(height: 12),
                Text(creating ? t('pinCreateTitle') : t('pinEnter'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                if (creating)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(t('pinCreateHelp'),
                        style: const TextStyle(fontSize: 18)),
                  ),
                const SizedBox(height: 12),
                _pinField(_pin, creating ? t('pinCreateTitle') : t('pinEnter')),
                if (creating) ...[
                  const SizedBox(height: 12),
                  _pinField(_repeat, t('pinRepeat')),
                ],
                if (_errorKey != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(t(_errorKey!),
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 18,
                            fontWeight: FontWeight.w600)),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: Text(t('continue')),
                ),
              ],
            ),
    );
  }

  Widget _pinField(TextEditingController c, String label) => TextField(
        controller: c,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: 6,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(fontSize: 24, letterSpacing: 8),
        decoration: InputDecoration(
            labelText: label, border: const OutlineInputBorder()),
      );
}

// ---- Dashboard ----------------------------------------------------------------

class _DashData {
  _DashData(this.patient, this.sessions, this.alerts, this.models, this.family,
      this.links, this.week);
  final Map<String, Object?> patient;
  final List<SessionRecord> sessions;
  final List<EngagementAlert> alerts;
  final Map<String, AbilityModel> models;
  final List<Map<String, Object?>> family;
  final List<Map<String, Object?>> links;
  final AdherenceSummary week; // reminders marked done, last 7 days
}

/// What a caregiver sees: engagement trends over 7 days, 30 days or 3 months,
/// alerts, how many reminders were marked done, difficulty control, a summary
/// to share, and shortcuts to reminders. Shown only while 'caregiver_share'
/// is consented. Everything is computed from the history on this phone;
/// nothing is sent anywhere. The wording is deliberately about use of the app,
/// not health.
class CaregiverDashboard extends StatefulWidget {
  const CaregiverDashboard({
    super.key,
    required this.db,
    required this.notifier,
    required this.patientId,
    required this.lang,
    required this.onChanged,
  });
  final AppDatabase db;
  final ReminderNotifier notifier;
  final String patientId, lang;
  final VoidCallback onChanged;

  @override
  State<CaregiverDashboard> createState() => _CaregiverDashboardState();
}

class _CaregiverDashboardState extends State<CaregiverDashboard> {
  late Future<_DashData> _data = _load();
  ReportRange _range = ReportRange.days7;

  String t(String k) => tr(widget.lang, k);

  Future<_DashData> _load() async {
    final patient = (await widget.db.patientById(widget.patientId))!;
    final baseline = patient['baseline_level'] as int;
    final sessions = await widget.db.sessionRecords(widget.patientId);
    final reminders = await widget.db.listReminders(widget.patientId);
    final done = await widget.db.doneKeys(widget.patientId);
    final now = DateTime.now();
    final week = adherence(reminders, done, now);
    return _DashData(
      patient,
      sessions,
      computeAlerts(
        sessions: sessions,
        now: now,
        baseline: baseline,
        overdueMedicines: overdueMedicines(reminders, done, now).length,
        weekAdherence: week,
      ),
      {
        for (final g in _games.keys)
          g: await widget.db.abilityModel(widget.patientId, g, baseline)
      },
      await widget.db.listFamily(widget.patientId),
      await widget.db.listCareLinks(widget.patientId),
      week,
    );
  }

  void _reload() => setState(() => _data = _load());

  /// [suggested] pre-selects the level an alert recommended; accepting it is
  /// recorded as such, anything else as the caregiver's own judgement.
  Future<void> _changeLevel(int current, {int? suggested}) async {
    final result = await showDialog<(int, String)>(
      context: context,
      builder: (_) => _LevelDialog(
          lang: widget.lang, current: current, initial: suggested ?? current),
    );
    if (result == null) return;
    await widget.db.setBaseline(
      patientId: widget.patientId,
      newLevel: result.$1,
      caregiverName: result.$2,
      reason: result.$1 == suggested ? 'accepted_suggestion' : 'caregiver_judgement',
    );
    widget.onChanged();
    _reload();
  }

  Future<void> _copySummary(_DashData d, List<SessionRecord> inRange) async {
    final text = buildSummary(
      lang: widget.lang,
      name: '${d.patient['display_name']}',
      range: _range,
      sessionsInRange: inRange,
      adherence: d.week,
      alerts: d.alerts,
      gameNames: {for (final e in _games.entries) e.key: t(e.value)},
    );
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t('summaryCopied'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('dashTitle'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ConsentGate(
              db: widget.db,
              patientId: widget.patientId,
              purpose: 'caregiver_share',
              purposeTextKey: 'purposeCaregiverShare',
              lang: widget.lang,
              byName: 'caregiver',
              onChanged: _reload,
              child: FutureBuilder<_DashData>(
                future: _data,
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return _body(snap.data!);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(_DashData d) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final allTimes = d.sessions.map((s) => s.endedAt).toList();
    final inRange = sessionsInRange(d.sessions, now, _range);
    final buckets = sessionBuckets(allTimes, now, _range);
    final maxCount = buckets.fold<int>(1, (m, c) => c > m ? c : m);
    final baseline = d.patient['baseline_level'] as int;
    final dob = d.patient['dob'] == null
        ? null
        : DateTime.parse(d.patient['dob'] as String);
    final summaries = summarizeByGame(inRange);
    final dayLetters = _range == ReportRange.days7;

    Widget section(String key) => Padding(
          padding: const EdgeInsets.only(top: 24, bottom: 8),
          child: Text(t(key),
              style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700, color: Palette.brandDeep)),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Avatar(photo: d.patient['photo'] as List<int>?, radius: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${d.patient['display_name']}'
              '${dob == null ? '' : ', ${ageFromDob(dob, now)} ${t('years')}'}',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Text(t('dashNote'), style: const TextStyle(fontSize: 16)),

        section('alertsTitle'),
        if (d.alerts.isEmpty)
          Card(
            color: Palette.tileGreen,
            child: ListTile(
              leading: const Icon(Icons.check_circle, color: Palette.brand),
              title: Text(t('noAlerts'), style: const TextStyle(fontSize: 18)),
            ),
          )
        else ...[
          for (final a in d.alerts)
            Card(
              color: a.severity == AlertSeverity.attention
                  ? Colors.amber.shade100
                  : Palette.tileBlue,
              child: ListTile(
                leading: Icon(
                    a.severity == AlertSeverity.attention
                        ? Icons.notifications_active
                        : Icons.lightbulb,
                    color: Palette.brand),
                title: Text(
                    trf(widget.lang, 'alert_${a.kind.name}', a: a.a, b: a.b),
                    style: const TextStyle(fontSize: 18)),
                trailing: switch (a.kind) {
                  AlertKind.suggestRaiseBaseline => TextButton(
                      onPressed: () => _changeLevel(baseline,
                          suggested: (baseline + 1).clamp(1, 5)),
                      child: Text(t('reviewLevel'))),
                  AlertKind.suggestLowerBaseline => TextButton(
                      onPressed: () => _changeLevel(baseline,
                          suggested: (baseline - 1).clamp(1, 5)),
                      child: Text(t('reviewLevel'))),
                  _ => null,
                },
              ),
            ),
          Text(t('alertHelp'), style: const TextStyle(fontSize: 15)),
        ],

        section('overviewTitle'),
        PillTabs(
          labels: [t('range7'), t('range30'), t('range90')],
          selected: _range.index,
          onSelected: (i) => setState(() => _range = ReportRange.values[i]),
        ),
        const SizedBox(height: 12),
        Row(children: [
          _stat(t('gamesPlayed'), '${inRange.length}', Palette.tileBlue),
          _stat(t('dayStreak'), '${currentStreak(allTimes, now)}',
              Palette.tileOrange),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
              '${t('lastPlayed')}: ${d.sessions.isEmpty ? t('never') : MaterialLocalizations.of(context).formatMediumDate(d.sessions.last.endedAt)}',
              style: const TextStyle(fontSize: 18)),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 110,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < buckets.length; i++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: buckets.length > 14 ? 1 : 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          height: 6 + 70.0 * buckets[i] / maxCount,
                          decoration: BoxDecoration(
                            color: buckets[i] == 0
                                ? Colors.black12
                                : Palette.brand,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        if (dayLetters) ...[
                          const SizedBox(height: 4),
                          Text('MTWTFSS'[
                              now.subtract(Duration(days: 6 - i)).weekday - 1]),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),

        if (summaries.isNotEmpty) ...[
          section('accuracyByGame'),
          for (final g in summaries)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      '${t(_games[g.game] ?? g.game)} · ${trf(widget.lang, 'sessionsCount', a: g.sessions)} · ${(g.accuracy * 100).round()}%',
                      style: const TextStyle(fontSize: 18)),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                        value: g.accuracy, minHeight: 12),
                  ),
                ],
              ),
            ),
        ],

        section('adherenceTitle'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (d.week.expected == 0)
                  Text(t('noneAdded'), style: const TextStyle(fontSize: 18))
                else ...[
                  Text(
                      trf(widget.lang, 'adherenceLine',
                          a: d.week.done, b: d.week.expected),
                      style: const TextStyle(fontSize: 18)),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                        value: d.week.rate, minHeight: 12),
                  ),
                ],
                const SizedBox(height: 8),
                Text(t('adherenceNote'), style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ),

        section('difficultyTitle'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${t('startingLevel')}: ${trf(widget.lang, 'levelWord', a: baseline)}',
                    style: const TextStyle(fontSize: 18)),
                const SizedBox(height: 8),
                OutlinedButton(
                    onPressed: () => _changeLevel(baseline),
                    child: Text(t('changeLevel'))),
                const Divider(height: 28),
                Text(t('modelTitle'),
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                for (final e in _games.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(_modelLine(e.value, d.models[e.key]!, baseline),
                        style: const TextStyle(fontSize: 17)),
                  ),
                const SizedBox(height: 6),
                Text(t('modelBody'), style: const TextStyle(fontSize: 15)),
              ],
            ),
          ),
        ),

        section('manageReminders'),
        FilledButton.icon(
          icon: const Icon(Icons.alarm),
          label: Text(t('manageReminders')),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => RemindersScreen(
              db: widget.db,
              notifier: widget.notifier,
              patientId: widget.patientId,
              language: widget.lang,
            ),
          )),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.copy_rounded),
          label: Text(t('copySummary')),
          onPressed: () => _copySummary(d, inRange),
        ),

        section('familyAndTeam'),
        if (d.family.isEmpty && d.links.isEmpty)
          Text(t('noneAdded'), style: const TextStyle(fontSize: 18)),
        for (final m in d.family)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Avatar(photo: m['photo'] as List<int>?),
            title: Text(m['name'] as String,
                style: const TextStyle(fontSize: 18)),
            subtitle: Text(t('rel_${m['relation']}')),
          ),
        for (final l in d.links)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(l['kind'] == 'doctor'
                ? Icons.medical_services
                : Icons.volunteer_activism),
            title: Text('${l['name']}', style: const TextStyle(fontSize: 18)),
            subtitle: Text(
                '${t(l['kind'] == 'doctor' ? 'roleDoctor' : 'roleCaretaker')} · ${t(_statusKey('${l['status']}'))}'),
          ),
      ],
    );
  }

  String _statusKey(String status) =>
      'status${status[0].toUpperCase()}${status.substring(1)}';

  String _modelLine(String nameKey, AbilityModel m, int baseline) {
    final level = m.recommend(DifficultyBand(baseline));
    final basis = m.trials == 0
        ? t('modelNoData')
        : trf(widget.lang, 'modelBasedOn', a: m.trials);
    return '${t(nameKey)}: ${trf(widget.lang, 'levelWord', a: level)} ($basis)';
  }

  Widget _stat(String label, String value, Color color) => Expanded(
        child: Card(
          color: color,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(children: [
              Text(value,
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
              Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15)),
            ]),
          ),
        ),
      );
}

class _LevelDialog extends StatefulWidget {
  const _LevelDialog(
      {required this.lang, required this.current, required this.initial});
  final String lang;
  final int current, initial;

  @override
  State<_LevelDialog> createState() => _LevelDialogState();
}

class _LevelDialogState extends State<_LevelDialog> {
  late int _level = widget.initial;
  final _name = TextEditingController();

  String t(String k) => tr(widget.lang, k);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t('changeLevel')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var l = 1; l <= 5; l++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                    l == _level
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: Palette.brand),
                title: Text(t('level$l')),
                onTap: () => setState(() => _level = l),
              ),
            TextField(
              controller: _name,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: t('whoIsActing')),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(t('cancel'))),
        FilledButton(
          onPressed: _name.text.trim().isEmpty || _level == widget.current
              ? null
              : () => Navigator.pop(context, (_level, _name.text.trim())),
          child: Text(t('save')),
        ),
      ],
    );
  }
}
