import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../services/api_client.dart';

/// Home for a caretaker or doctor signed in to the server: invitations from
/// patients and the people who currently share their progress with them.
class RemoteHome extends StatefulWidget {
  const RemoteHome({
    super.key,
    required this.api,
    required this.user,
    required this.lang,
    required this.onLogout,
    this.onSignedOut,
  });
  final ApiClient api;
  final ServerUser user;
  final String lang;
  final VoidCallback onLogout;

  /// Called when the server no longer accepts this login.
  final VoidCallback? onSignedOut;

  @override
  State<RemoteHome> createState() => _RemoteHomeState();
}

class _RemoteHomeState extends State<RemoteHome> {
  List<Map<String, dynamic>> _invites = const [];
  List<Map<String, dynamic>> _patients = const [];
  bool _loading = true;
  String? _errorKey;

  String t(String k) => tr(widget.lang, k);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorKey = null;
    });
    try {
      final invites = await widget.api.myInvites();
      final patients = await widget.api.myPatients();
      if (!mounted) return;
      setState(() {
        _invites = invites;
        _patients = patients;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) return widget.onSignedOut?.call();
      setState(() {
        _errorKey = e.isNetwork ? 'errOffline' : 'errOtpFailed';
        _loading = false;
      });
    }
  }

  Future<void> _answer(String id, bool accept) async {
    try {
      accept
          ? await widget.api.acceptInvite(id)
          : await widget.api.declineInvite(id);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) return widget.onSignedOut?.call();
      setState(() => _errorKey = e.isNetwork ? 'errOffline' : 'errOtpFailed');
      return;
    }
    await _load();
  }

  String _roleLabel(String role) => t(role == 'doctor' ? 'roleDoctor' : 'roleCaretaker');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.user.name),
        actions: [
          IconButton(
              tooltip: t('logout'),
              icon: const Icon(Icons.logout_rounded),
              onPressed: widget.onLogout),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ScreenTitle(t('rmPeople')),
            const SizedBox(height: 12),
            if (_errorKey != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(t(_errorKey!),
                    style: const TextStyle(
                        color: Palette.red, fontSize: 18, fontWeight: FontWeight.w600)),
              ),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else ...[
              if (_invites.isNotEmpty) ...[
                Text(t('rmInvites'),
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                for (final i in _invites)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: AppCard(
                      color: Palette.tileOrange,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${i['patient_display_name']}',
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w700)),
                          Text('${t('rmInvitedAs')} ${_roleLabel('${i['member_role']}')}',
                              style: const TextStyle(fontSize: 16)),
                          const SizedBox(height: 10),
                          Row(children: [
                            Expanded(
                              child: FilledButton(
                                  onPressed: () => _answer(i['id'] as String, true),
                                  child: Text(t('rmAccept'))),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton(
                                  onPressed: () => _answer(i['id'] as String, false),
                                  child: Text(t('rmDecline'))),
                            ),
                          ]),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
              ],
              if (_patients.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(t('rmNoPatients'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 18, color: Palette.muted)),
                ),
              for (final p in _patients)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AppCard(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => RemotePatientScreen(
                            api: widget.api,
                            patientId: p['patient_id'] as String,
                            name: '${p['display_name']}',
                            canSetBaseline: widget.user.role == 'caretaker',
                            lang: widget.lang,
                            onSignedOut: widget.onSignedOut))),
                    child: Row(children: [
                      const IconBadge(
                          icon: Icons.person_rounded,
                          fg: Palette.green,
                          bg: Palette.tileGreen),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text('${p['display_name']}',
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w700)),
                      ),
                      if ((p['alerts_needing_attention'] as int? ?? 0) > 0)
                        Chip(
                            backgroundColor: Palette.tileRed,
                            label: Text('${p['alerts_needing_attention']}')),
                      const Icon(Icons.chevron_right_rounded),
                    ]),
                  ),
                ),
              const SizedBox(height: 8),
              Text(t('rmPrivacyNote'),
                  style: const TextStyle(fontSize: 14, color: Palette.muted)),
            ],
          ],
        ),
      ),
    );
  }
}

/// One patient's shared progress over 7, 30 or 90 days. Describes how the app
/// is used; it is not a medical assessment.
class RemotePatientScreen extends StatefulWidget {
  const RemotePatientScreen({
    super.key,
    required this.api,
    required this.patientId,
    required this.name,
    required this.lang,
    this.canSetBaseline = false,
    this.onSignedOut,
  });
  final ApiClient api;
  final String patientId, name, lang;
  final bool canSetBaseline;
  final VoidCallback? onSignedOut;

  @override
  State<RemotePatientScreen> createState() => _RemotePatientScreenState();
}

class _RemotePatientScreenState extends State<RemotePatientScreen> {
  static const _ranges = [7, 30, 90];
  int _range = 0;
  Map<String, dynamic>? _report;
  String? _errorKey;
  bool _loading = true;

  String t(String k) => tr(widget.lang, k);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorKey = null;
    });
    try {
      final r = await widget.api.report(widget.patientId, _ranges[_range]);
      if (!mounted) return;
      setState(() {
        _report = r;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        Navigator.of(context).pop();
        return widget.onSignedOut?.call();
      }
      setState(() {
        // 404: sharing was switched off or the link ended.
        _errorKey = e.isNetwork
            ? 'errOffline'
            : (e.status == 404 ? 'rmNoLongerShared' : 'errOtpFailed');
        _report = null;
        _loading = false;
      });
    }
  }

  Future<void> _setBaseline(int level) async {
    try {
      await widget.api.setBaseline(widget.patientId, level);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _errorKey = e.isNetwork ? 'errOffline' : 'errOtpFailed');
      return;
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;
    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          PillTabs(
            labels: [for (final d in _ranges) trf(widget.lang, 'rmDays', a: d)],
            selected: _range,
            onSelected: (i) {
              setState(() => _range = i);
              _load();
            },
          ),
          const SizedBox(height: 16),
          if (_errorKey != null)
            Text(t(_errorKey!),
                style: const TextStyle(
                    color: Palette.red, fontSize: 18, fontWeight: FontWeight.w600)),
          if (_loading)
            const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()))
          else if (r != null) ..._content(r),
        ],
      ),
    );
  }

  List<Widget> _content(Map<String, dynamic> r) {
    final daily = (r['daily'] as List).cast<int>();
    final maxBar = daily.fold<int>(1, (m, v) => v > m ? v : m);
    final perGame = (r['per_game'] as List).cast<Map<String, dynamic>>();
    final alerts = (r['alerts'] as List).cast<Map<String, dynamic>>();
    final adherence = r['adherence'] as Map<String, dynamic>;
    final baseline = (r['patient'] as Map<String, dynamic>)['baseline_level'] as int;
    final last = r['last_played'] as String?;
    const gameKeys = {
      'memory_match': 'memoryGame',
      'attention': 'gameAttention',
      'routine': 'gameRoutine',
    };
    return [
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t('alertsTitle'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (alerts.isEmpty)
            Text(t('noAlerts'), style: const TextStyle(fontSize: 16))
          else
            for (final a in alerts)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                    trf(widget.lang, 'alert_${a['kind']}',
                        a: a['a'] as int, b: a['b'] as int),
                    style: const TextStyle(fontSize: 16)),
              ),
          const SizedBox(height: 4),
          Text(t('alertHelp'),
              style: const TextStyle(fontSize: 13, color: Palette.muted)),
        ]),
      ),
      const SizedBox(height: 12),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t('overviewTitle'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('${t('rmGames')}: ${r['games_played']}',
              style: const TextStyle(fontSize: 16)),
          Text('${t('rmStreak')}: ${r['streak']}', style: const TextStyle(fontSize: 16)),
          Text('${t('lastPlayed')}: ${last == null ? '-' : last.substring(0, 10)}',
              style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 12),
          SizedBox(
            height: 80,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final v in daily)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: Container(
                        height: 4 + 76 * v / maxBar,
                        decoration: BoxDecoration(
                          color: v == 0 ? Palette.line : Palette.action,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ]),
      ),
      if (perGame.isNotEmpty) ...[
        const SizedBox(height: 12),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final g in perGame)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                    '${t(gameKeys[g['game']] ?? 'memoryGame')}: ${g['sessions']} · '
                    '${((g['accuracy'] as num) * 100).round()}%',
                    style: const TextStyle(fontSize: 16)),
              ),
          ]),
        ),
      ],
      const SizedBox(height: 12),
      AppCard(
        child: Text(
            '${t('adherenceTitle')}: ${trf(widget.lang, 'adherenceLine', a: adherence['done'] as int, b: adherence['expected'] as int)}\n\n${t('adherenceNote')}',
            style: const TextStyle(fontSize: 16)),
      ),
      if (widget.canSetBaseline) ...[
        const SizedBox(height: 12),
        AppCard(
          child: Row(children: [
            Expanded(
              child: Text('${t('startingLevel')}: $baseline',
                  style: const TextStyle(fontSize: 16)),
            ),
            IconButton(
                onPressed: baseline > 1 ? () => _setBaseline(baseline - 1) : null,
                icon: const Icon(Icons.remove_circle_outline_rounded)),
            IconButton(
                onPressed: baseline < 5 ? () => _setBaseline(baseline + 1) : null,
                icon: const Icon(Icons.add_circle_outline_rounded)),
          ]),
        ),
      ],
    ];
  }
}
