import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/games.dart';
import '../../core/languages.dart';
import '../../core/reminder_schedule.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../services/api_client.dart';
import '../reminders/reminder_style.dart';

/// Blue for doctors, green for caretakers, as on the design sheet.
Color accentFor(String role) =>
    role == 'doctor' ? const Color(0xFF2F6FE0) : Palette.action;

/// The app for a caretaker or doctor signed in to the server: a dashboard of
/// the people who share with them, a patient list, alerts and settings. They
/// see only what each person has agreed to share.
class RemoteHome extends StatefulWidget {
  const RemoteHome({
    super.key,
    required this.api,
    required this.user,
    required this.lang,
    required this.onLogout,
    this.onSignedOut,
    this.onLangChanged,
    this.initialTab = 0,
  });
  final int initialTab;
  final ApiClient api;
  final ServerUser user;
  final String lang;
  final VoidCallback onLogout;
  final ValueChanged<String>? onLangChanged;

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
  late int _tab = widget.initialTab;

  String t(String k) => tr(widget.lang, k);
  Color get _accent => accentFor(widget.user.role);

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

  void _open(Map<String, dynamic> p) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => RemotePatientScreen(
              api: widget.api,
              patientId: p['patient_id'] as String,
              name: '${p['display_name']}',
              canSetBaseline: widget.user.role == 'caretaker',
              accent: _accent,
              lang: widget.lang,
              onSignedOut: widget.onSignedOut)));

  int _alertCount(Map<String, dynamic> p) =>
      (p['alerts_needing_attention'] as int?) ?? 0;

  DateTime? _lastPlayed(Map<String, dynamic> p) {
    final s = p['last_played'] as String?;
    return s == null ? null : DateTime.tryParse(s);
  }

  bool _activeToday(Map<String, dynamic> p) {
    final d = _lastPlayed(p);
    final n = DateTime.now();
    return d != null && d.year == n.year && d.month == n.month && d.day == n.day;
  }

  String _greeting() {
    final h = DateTime.now().hour;
    return t(h < 12 ? 'goodMorning' : h < 17 ? 'goodAfternoon' : 'goodEvening');
  }

  int get _alertTotal => _patients.fold<int>(0, (n, p) => n + _alertCount(p));

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final pages = [_dashboard(), _patientsTab(), _alertsTab(), _settings()];
    return Theme(
      // Buttons and tabs take the role's colour.
      data: base.copyWith(
        filledButtonTheme: FilledButtonThemeData(
          style: (base.filledButtonTheme.style ?? const ButtonStyle())
              .copyWith(backgroundColor: WidgetStatePropertyAll(_accent)),
        ),
      ),
      child: Scaffold(
        body: SafeArea(
          child: RefreshIndicator(onRefresh: _load, child: pages[_tab]),
        ),
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x1F000000),
                    blurRadius: 16,
                    offset: Offset(0, 4)),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: NavigationBar(
                selectedIndex: _tab,
                onDestinationSelected: (i) => setState(() => _tab = i),
                destinations: [
                  NavigationDestination(
                      icon: const Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home_rounded, color: _accent),
                      label: t('tabHome')),
                  NavigationDestination(
                      icon: const Icon(Icons.groups_outlined),
                      selectedIcon: Icon(Icons.groups_rounded, color: _accent),
                      label: t('rmStatPeople')),
                  NavigationDestination(
                      icon: Badge(
                          isLabelVisible: _alertTotal > 0,
                          label: Text('$_alertTotal'),
                          child: const Icon(Icons.notifications_none_rounded)),
                      selectedIcon:
                          Icon(Icons.notifications_rounded, color: _accent),
                      label: t('rmStatAlerts')),
                  NavigationDestination(
                      icon: const Icon(Icons.person_outline_rounded),
                      selectedIcon: Icon(Icons.person_rounded, color: _accent),
                      label: t('tabProfile')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---- shared bits ---------------------------------------------------------

  Widget _avatar(String name, {double radius = 24}) => CircleAvatar(
        radius: radius,
        backgroundColor: Palette.tileGreen,
        child: Text(name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
            style: TextStyle(
                fontSize: radius * 0.85,
                fontWeight: FontWeight.w700,
                color: Palette.brandDeep)),
      );

  Widget _stat(IconData icon, Color fg, Color bg, String value, String label) =>
      Expanded(
        child: AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
          child: Column(children: [
            IconBadge(icon: icon, fg: fg, bg: bg, size: 38, circle: true),
            const SizedBox(height: 6),
            Text(value,
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Palette.brandDeep)),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11.5, color: Palette.muted)),
          ]),
        ),
      );

  Widget _heading(String text) => Text(text,
      style: const TextStyle(
          fontSize: 17, fontWeight: FontWeight.w700, color: Palette.brandDeep));

  Widget _errorLine() => _errorKey == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(t(_errorKey!),
              style: const TextStyle(
                  color: Palette.red, fontSize: 15, fontWeight: FontWeight.w600)),
        );

  String _activityLine(Map<String, dynamic> p) {
    final d = _lastPlayed(p);
    if (d == null) return t('rmNoGamesYet');
    return '${t('rmPlayedGame')} · ${agoText(widget.lang, d, DateTime.now())}';
  }

  Widget _statusChip(Map<String, dynamic> p) {
    final attention = _alertCount(p) > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: attention ? Palette.tileRed : Palette.tileGreen,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(t(attention ? 'rmStatusAttention' : 'rmStatusOk'),
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: attention ? Palette.red : Palette.green)),
    );
  }

  Widget _patientRow(Map<String, dynamic> p, {bool chip = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: AppCard(
          padding: const EdgeInsets.all(12),
          onTap: () => _open(p),
          child: Row(children: [
            _avatar('${p['display_name']}'),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${p['display_name']}',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Palette.brandDeep)),
                  Text(_activityLine(p),
                      style:
                          const TextStyle(fontSize: 12.5, color: Palette.muted)),
                  if (chip) ...[
                    const SizedBox(height: 6),
                    _statusChip(p),
                  ],
                ],
              ),
            ),
            if (!chip && _alertCount(p) > 0)
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                    color: Palette.tileRed,
                    borderRadius: BorderRadius.circular(12)),
                child: Text('${_alertCount(p)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: Palette.red)),
              ),
            const Icon(Icons.chevron_right_rounded, color: Palette.muted),
          ]),
        ),
      );

  // ---- tab 0: dashboard ------------------------------------------------------

  Widget _dashboard() {
    final recent = [..._patients]
      ..sort((a, b) {
        final x = _lastPlayed(a), y = _lastPlayed(b);
        if (x == null && y == null) return 0;
        if (x == null) return 1;
        if (y == null) return -1;
        return y.compareTo(x);
      });
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Row(children: [
          _avatar(widget.user.name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_greeting()},',
                    style: const TextStyle(fontSize: 14, color: Palette.muted)),
                Text(widget.user.name,
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Palette.brandDeep)),
              ],
            ),
          ),
          IconButton(
            tooltip: t('rmStatAlerts'),
            onPressed: () => setState(() => _tab = 2),
            icon: Badge(
                isLabelVisible: _alertTotal > 0,
                label: Text('$_alertTotal'),
                child: const Icon(Icons.notifications_none_rounded)),
          ),
        ]),
        const SizedBox(height: 4),
        Text(
            t(widget.user.role == 'doctor'
                ? 'rmGlanceDoctor'
                : 'rmGlanceCaretaker'),
            style: const TextStyle(fontSize: 13, color: Palette.muted)),
        const SizedBox(height: 14),
        _errorLine(),
        if (_loading)
          const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()))
        else ...[
          Row(children: [
            _stat(Icons.groups_rounded, Palette.green, Palette.tileGreen,
                '${_patients.length}', t('rmStatPeople')),
            const SizedBox(width: 10),
            _stat(Icons.bolt_rounded, Palette.orange, Palette.tileOrange,
                '${_patients.where(_activeToday).length}', t('rmActiveToday')),
            const SizedBox(width: 10),
            _stat(Icons.notifications_active_rounded, Palette.red,
                Palette.tileRed, '$_alertTotal', t('rmStatAlerts')),
          ]),
          const SizedBox(height: 18),
          if (_invites.isNotEmpty) ...[
            _heading(t('rmInvites')),
            const SizedBox(height: 8),
            for (final i in _invites) _inviteCard(i),
            const SizedBox(height: 8),
          ],
          _heading(t('rmRecent')),
          const SizedBox(height: 10),
          if (recent.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(t('rmNoPatients'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: Palette.muted)),
            ),
          for (final p in recent) _patientRow(p),
          const SizedBox(height: 6),
          Text(t('rmPrivacyNote'),
              style: const TextStyle(fontSize: 12, color: Palette.muted)),
        ],
      ],
    );
  }

  Widget _inviteCard(Map<String, dynamic> i) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: AppCard(
          color: Palette.tileOrange,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${i['patient_display_name']}',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700)),
              Text(
                  '${t('rmInvitedAs')} ${t(i['member_role'] == 'doctor' ? 'roleDoctor' : 'roleCaretaker')}',
                  style: const TextStyle(fontSize: 13.5)),
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
      );

  // ---- tab 1: patients -------------------------------------------------------

  String _query = '';

  Widget _patientsTab() {
    final shown = _patients
        .where((p) =>
            '${p['display_name']}'.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        ScreenTitle(t('rmStatPeople')),
        const SizedBox(height: 12),
        TextField(
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: t('rmSearch'),
            prefixIcon: const Icon(Icons.search_rounded),
          ),
        ),
        const SizedBox(height: 14),
        _errorLine(),
        if (_loading)
          const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()))
        else if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(t(_patients.isEmpty ? 'rmNoPatients' : 'nothingHere'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Palette.muted)),
          ),
        for (final p in shown) _patientRow(p, chip: true),
      ],
    );
  }

  // ---- tab 2: alerts -----------------------------------------------------------

  Widget _alertsTab() {
    final items = <(Map<String, dynamic>, Map<String, dynamic>)>[
      for (final p in _patients)
        for (final a in ((p['alerts'] as List?) ?? const [])
            .cast<Map<String, dynamic>>())
          (p, a)
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        ScreenTitle(t('rmStatAlerts')),
        const SizedBox(height: 12),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(t('rmNoAlertsAll'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: Palette.muted)),
          ),
        for (final (p, a) in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppCard(
              padding: const EdgeInsets.all(12),
              onTap: () => _open(p),
              child: Row(children: [
                IconBadge(
                    icon: a['severity'] == 'attention'
                        ? Icons.notifications_active_rounded
                        : Icons.lightbulb_outline_rounded,
                    fg: a['severity'] == 'attention'
                        ? Palette.red
                        : Palette.orange,
                    bg: a['severity'] == 'attention'
                        ? Palette.tileRed
                        : Palette.tileOrange,
                    size: 44,
                    circle: true),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${p['display_name']}',
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Palette.brandDeep)),
                      Text(
                          trf(widget.lang, 'alert_${a['kind']}',
                              a: (a['a'] as int?) ?? 0,
                              b: (a['b'] as int?) ?? 0),
                          style: const TextStyle(
                              fontSize: 12.5, color: Palette.muted)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Palette.muted),
              ]),
            ),
          ),
        if (items.isNotEmpty)
          Text(t('alertHelp'),
              style: const TextStyle(fontSize: 12, color: Palette.muted)),
      ],
    );
  }

  // ---- tab 3: settings ----------------------------------------------------------

  Widget _settings() => ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          ScreenTitle(t('settings')),
          const SizedBox(height: 12),
          AppCard(
            child: Row(children: [
              _avatar(widget.user.name, radius: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.user.name,
                        style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Palette.brandDeep)),
                    Text(
                        '${t('rmSignedInAs')} ${t(widget.user.role == 'doctor' ? 'roleDoctor' : 'roleCaretaker')}',
                        style: const TextStyle(
                            fontSize: 12.5, color: Palette.muted)),
                  ],
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          Text(t('language'),
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Palette.brandDeep)),
          const SizedBox(height: 8),
          AppCard(
            padding: const EdgeInsets.all(6),
            child: Column(children: [
              for (final e in kLanguages.entries)
                ListTile(
                  dense: true,
                  leading: Icon(
                      widget.lang == e.key
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      color: widget.lang == e.key ? _accent : Palette.muted),
                  title: Text(e.value, style: const TextStyle(fontSize: 15)),
                  onTap: () => widget.onLangChanged?.call(e.key),
                ),
            ]),
          ),
          const SizedBox(height: 12),
          AppCard(
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => AlertDialog(
                title: Text(t('appName')),
                content: Text(t('notAMedicalDevice')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(t('finish'))),
                ],
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              const IconBadge(
                  icon: Icons.info_outline_rounded,
                  fg: Palette.sky,
                  bg: Palette.tileSky,
                  size: 40,
                  circle: true),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(t('rmAbout'),
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600))),
              const Icon(Icons.chevron_right_rounded, color: Palette.muted),
            ]),
          ),
          const SizedBox(height: 12),
          AppCard(
            color: Palette.tileRed,
            onTap: widget.onLogout,
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.logout_rounded, color: Palette.red),
                const SizedBox(width: 8),
                Text(t('logout'),
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Palette.red)),
              ],
            ),
          ),
        ],
      );
}

// =====================================================================================
// One patient: Overview / Games / Reminders
// =====================================================================================

/// One patient's shared progress. Describes how the app is used; it is not a
/// medical assessment.
class RemotePatientScreen extends StatefulWidget {
  const RemotePatientScreen({
    super.key,
    required this.api,
    required this.patientId,
    required this.name,
    required this.lang,
    this.canSetBaseline = false,
    this.accent = Palette.action,
    this.onSignedOut,
  });
  final ApiClient api;
  final String patientId, name, lang;
  final bool canSetBaseline;
  final Color accent;
  final VoidCallback? onSignedOut;

  @override
  State<RemotePatientScreen> createState() => _RemotePatientScreenState();
}

class _RemotePatientScreenState extends State<RemotePatientScreen> {
  int _tab = 0; // 0 overview, 1 games, 2 reminders
  Map<String, dynamic>? _report;
  List<Map<String, dynamic>>? _reminders;
  String? _errorKey;
  bool _loading = true;

  String t(String k) => tr(widget.lang, k);

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _fail(ApiException e) {
    if (e.isUnauthorized) {
      Navigator.of(context).pop();
      widget.onSignedOut?.call();
      return;
    }
    setState(() {
      // 404: sharing was switched off or the link ended.
      _errorKey = e.isNetwork
          ? 'errOffline'
          : (e.status == 404 ? 'rmNoLongerShared' : 'errOtpFailed');
      _loading = false;
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorKey = null;
    });
    try {
      final r = await widget.api.report(widget.patientId, 7);
      if (!mounted) return;
      setState(() {
        _report = r;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      _report = null;
      _fail(e);
    }
  }

  Future<void> _loadReminders() async {
    if (_reminders != null) return;
    try {
      final r = await widget.api.patientReminders(widget.patientId);
      if (mounted) setState(() => _reminders = r);
    } on ApiException catch (e) {
      if (mounted) _fail(e);
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
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Palette.tileGreen,
            child: Text(
                widget.name.trim().isEmpty
                    ? '?'
                    : widget.name.trim()[0].toUpperCase(),
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: Palette.brandDeep)),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(widget.name,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          _UnderlineTabs(
            color: widget.accent,
            labels: [t('overviewTitle'), t('tabGames'), t('reminders')],
            selected: _tab,
            onSelected: (i) {
              setState(() => _tab = i);
              if (i == 2) _loadReminders();
            },
          ),
          const SizedBox(height: 14),
          if (_errorKey != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(t(_errorKey!),
                  style: const TextStyle(
                      color: Palette.red,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
            ),
          if (_tab == 2)
            ..._remindersTab()
          else if (_loading)
            const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()))
          else if (r != null)
            ...(_tab == 0 ? _overview(r) : _gamesTab(r)),
        ],
      ),
    );
  }

  // ---- overview ------------------------------------------------------------------

  Widget _stat(String value, String label) => Expanded(
        child: AppCard(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: const TextStyle(fontSize: 12.5, color: Palette.muted)),
            const SizedBox(height: 4),
            Text(value,
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Palette.brandDeep)),
          ]),
        ),
      );

  List<Widget> _overview(Map<String, dynamic> r) {
    final alerts = (r['alerts'] as List).cast<Map<String, dynamic>>();
    final attention = alerts.any((a) => a['severity'] == 'attention');
    final baseline =
        (r['patient'] as Map<String, dynamic>)['baseline_level'] as int;
    final last = r['last_played'] as String?;
    final lastDt = last == null ? null : DateTime.tryParse(last);
    final streak = r['streak'] as int;
    return [
      AppCard(
        child: Row(children: [
          IconBadge(
              icon: attention
                  ? Icons.notifications_active_rounded
                  : Icons.sentiment_satisfied_alt_rounded,
              fg: attention ? Palette.red : Palette.green,
              bg: attention ? Palette.tileRed : Palette.tileGreen,
              size: 46,
              circle: true),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('rmRecent'),
                  style: const TextStyle(fontSize: 12.5, color: Palette.muted)),
              Text(t(attention ? 'rmStatusAttention' : 'rmStatusOk'),
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: attention ? Palette.red : Palette.green)),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      Row(children: [
        _stat(trf(widget.lang, streak == 1 ? 'dayUnit' : 'daysUnit', a: streak),
            t('rmStreak')),
        const SizedBox(width: 12),
        _stat('${r['games_played']}', t('rmGames')),
      ]),
      const SizedBox(height: 12),
      AppCard(
        child: Row(children: [
          Expanded(
              child: Text(t('lastPlayed'),
                  style: const TextStyle(fontSize: 13, color: Palette.muted))),
          Text(
              lastDt == null
                  ? t('never')
                  : agoText(widget.lang, lastDt, DateTime.now()),
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Palette.brandDeep)),
        ]),
      ),
      const SizedBox(height: 12),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t('alertsTitle'),
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Palette.brandDeep)),
          const SizedBox(height: 8),
          if (alerts.isEmpty)
            Text(t('noAlerts'), style: const TextStyle(fontSize: 14))
          else
            for (final a in alerts)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                    trf(widget.lang, 'alert_${a['kind']}',
                        a: a['a'] as int, b: a['b'] as int),
                    style: const TextStyle(fontSize: 14)),
              ),
          const SizedBox(height: 4),
          Text(t('alertHelp'),
              style: const TextStyle(fontSize: 12, color: Palette.muted)),
        ]),
      ),
      if (widget.canSetBaseline) ...[
        const SizedBox(height: 12),
        AppCard(
          child: Row(children: [
            Expanded(
              child: Text('${t('startingLevel')}: $baseline',
                  style: const TextStyle(fontSize: 14)),
            ),
            IconButton(
                onPressed:
                    baseline > 1 ? () => _setBaseline(baseline - 1) : null,
                icon: const Icon(Icons.remove_circle_outline_rounded)),
            IconButton(
                onPressed:
                    baseline < 5 ? () => _setBaseline(baseline + 1) : null,
                icon: const Icon(Icons.add_circle_outline_rounded)),
          ]),
        ),
      ],
      const SizedBox(height: 16),
      FilledButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => RemoteReportScreen(
                api: widget.api,
                patientId: widget.patientId,
                name: widget.name,
                lang: widget.lang,
                accent: widget.accent,
                onSignedOut: widget.onSignedOut))),
        style: FilledButton.styleFrom(backgroundColor: widget.accent),
        child: Text(t('rmViewReport')),
      ),
    ];
  }

  // ---- games ---------------------------------------------------------------------

  List<Widget> _gamesTab(Map<String, dynamic> r) {
    final perGame = (r['per_game'] as List).cast<Map<String, dynamic>>();
    if (perGame.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(t('rmNoGamesYet'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Palette.muted)),
        ),
      ];
    }
    return [
      Text(t('accuracyByGame'),
          style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Palette.brandDeep)),
      const SizedBox(height: 10),
      for (final g in perGame) _gameBar(g),
    ];
  }

  Widget _gameBar(Map<String, dynamic> g) {
    final info =
        kGames.firstWhere((x) => x.id == g['game'], orElse: () => kGames.first);
    final pct = ((g['accuracy'] as num) * 100).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: info.color, borderRadius: BorderRadius.circular(12)),
            child: Icon(info.icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Text(t(info.titleKey),
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600))),
                Text('$pct%',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                    value: pct / 100,
                    minHeight: 7,
                    backgroundColor: const Color(0xFFE9ECEF),
                    color: info.color),
              ),
              const SizedBox(height: 4),
              Text(trf(widget.lang, 'sessionsCount', a: g['sessions'] as int),
                  style: const TextStyle(fontSize: 12, color: Palette.muted)),
            ]),
          ),
        ]),
      ),
    );
  }

  // ---- reminders -------------------------------------------------------------------

  List<Widget> _remindersTab() {
    final items = _reminders;
    if (items == null) {
      return _errorKey != null
          ? const []
          : const [
              Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()))
            ];
    }
    if (items.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(t('rmNoReminders'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Palette.muted)),
        ),
      ];
    }
    return [
      for (final x in items)
        Builder(builder: (_) {
          final kind = ReminderKind.values.firstWhere(
              (k) => k.name == x['kind'],
              orElse: () => ReminderKind.activity);
          final style = kindStyle(kind);
          final hh = (x['hour'] as int).toString().padLeft(2, '0');
          final mm = (x['minute'] as int).toString().padLeft(2, '0');
          final active = x['active'] == true;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Opacity(
              opacity: active ? 1 : 0.55,
              child: AppCard(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Row(children: [
                  IconBadge(
                      icon: style.icon,
                      fg: style.fg,
                      bg: style.bg,
                      size: 44,
                      circle: true),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t('kind_${kind.name}'),
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Palette.brandDeep)),
                          Text(
                              '$hh:$mm${active ? '' : ' · ${t('reminderOff')}'}',
                              style: const TextStyle(
                                  fontSize: 13, color: Palette.ink)),
                        ]),
                  ),
                  if (x['done_today'] == true)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.check_circle_rounded,
                          color: Palette.action),
                      const SizedBox(width: 4),
                      Text(t('rmDone'),
                          style: const TextStyle(
                              fontSize: 12, color: Palette.green)),
                    ]),
                ]),
              ),
            ),
          );
        }),
      const SizedBox(height: 4),
      Text(t('adherenceNote'),
          style: const TextStyle(fontSize: 12, color: Palette.muted)),
    ];
  }
}

// =====================================================================================
// Detailed report
// =====================================================================================

class RemoteReportScreen extends StatefulWidget {
  const RemoteReportScreen({
    super.key,
    required this.api,
    required this.patientId,
    required this.name,
    required this.lang,
    this.accent = Palette.action,
    this.onSignedOut,
  });
  final ApiClient api;
  final String patientId, name, lang;
  final Color accent;
  final VoidCallback? onSignedOut;

  @override
  State<RemoteReportScreen> createState() => _RemoteReportScreenState();
}

class _RemoteReportScreenState extends State<RemoteReportScreen> {
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
        _errorKey = e.isNetwork
            ? 'errOffline'
            : (e.status == 404 ? 'rmNoLongerShared' : 'errOtpFailed');
        _report = null;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;
    return Scaffold(
      appBar: AppBar(title: Text('${t('rmReportTitle')} · ${widget.name}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          PillTabs(
            color: widget.accent,
            labels: [for (final d in _ranges) trf(widget.lang, 'rmDays', a: d)],
            selected: _range,
            onSelected: (i) {
              setState(() => _range = i);
              _load();
            },
          ),
          const SizedBox(height: 14),
          if (_errorKey != null)
            Text(t(_errorKey!),
                style: const TextStyle(
                    color: Palette.red,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
          if (_loading)
            const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()))
          else if (r != null)
            ..._content(r),
        ],
      ),
    );
  }

  List<Widget> _content(Map<String, dynamic> r) {
    final daily = (r['daily'] as List).cast<int>();
    final maxBar = daily.fold<int>(1, (m, v) => v > m ? v : m);
    final perGame = (r['per_game'] as List).cast<Map<String, dynamic>>();
    final adherence = r['adherence'] as Map<String, dynamic>;
    return [
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t('rmGames'),
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Palette.brandDeep)),
          const SizedBox(height: 10),
          SizedBox(
            height: 90,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final v in daily)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: Container(
                        height: 4 + 80 * v / maxBar,
                        decoration: BoxDecoration(
                          color: v == 0 ? Palette.line : widget.accent,
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
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('accuracyByGame'),
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Palette.brandDeep)),
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final g in perGame)
                    Expanded(
                      child: Builder(builder: (_) {
                        final info = kGames.firstWhere((x) => x.id == g['game'],
                            orElse: () => kGames.first);
                        final pct = ((g['accuracy'] as num) * 100).round();
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text('$pct%',
                                style: const TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Container(
                              width: 26,
                              height: 6 + 64.0 * pct / 100,
                              decoration: BoxDecoration(
                                color: info.color,
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            const SizedBox(height: 6),
                            SizedBox(
                              height: 30,
                              child: Text(t(info.titleKey),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 10, color: Palette.muted)),
                            ),
                          ],
                        );
                      }),
                    ),
                ],
              ),
            ),
          ]),
        ),
      ],
      const SizedBox(height: 12),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t('rmActivitySummary'),
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Palette.brandDeep)),
          const SizedBox(height: 10),
          Row(children: [
            _mini(Icons.sports_esports_rounded, Palette.blue, Palette.tileBlue,
                '${r['games_played']}', t('rmGames')),
            _mini(
                Icons.notifications_rounded,
                Palette.orange,
                Palette.tileOrange,
                '${adherence['done']} / ${adherence['expected']}',
                t('adherenceTitle')),
            _mini(Icons.local_fire_department_rounded, Palette.red,
                Palette.tileRed, '${r['streak']}', t('rmStreak')),
          ]),
          const SizedBox(height: 10),
          Text(t('adherenceNote'),
              style: const TextStyle(fontSize: 12, color: Palette.muted)),
        ]),
      ),
    ];
  }

  Widget _mini(IconData icon, Color fg, Color bg, String value, String label) =>
      Expanded(
        child: Column(children: [
          IconBadge(icon: icon, fg: fg, bg: bg, size: 38, circle: true),
          const SizedBox(height: 4),
          Text(value,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Palette.muted)),
        ]),
      );
}

/// Text tabs with a coloured underline under the selected one, as on the sheet.
class _UnderlineTabs extends StatelessWidget {
  const _UnderlineTabs({
    required this.labels,
    required this.selected,
    required this.onSelected,
    required this.color,
  });
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: InkWell(
                onTap: () => onSelected(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                          color: i == selected ? color : Colors.transparent,
                          width: 2.5),
                    ),
                  ),
                  child: Text(labels[i],
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: i == selected ? color : Palette.muted)),
                ),
              ),
            ),
        ]),
      );
}
