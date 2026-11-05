import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/games.dart';
import '../../core/reminder_schedule.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../services/api_client.dart';
import '../../services/push_events.dart';
import '../chat/messages_screen.dart';
import '../reminders/reminder_style.dart';
import '../shell/offline_bar.dart';
import '../reminders/reminders_screen.dart' show showAddReminderDialog, NewReminder;
import '../shell/garden.dart' show GardenHeader;
import 'care_timeline.dart';
import '../shell/settings_pages.dart';

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
  late String? _careId = widget.user.careId;
  List<Map<String, dynamic>> _threads = const [];
  Timer? _chatTimer;
  late int _tab = widget.initialTab;

  /// Today's routines across this caregiver's patients (for the garden home).
  List<TodayItem> _today = const [];

  String t(String k) => tr(widget.lang, k);
  Color get _accent => accentFor(widget.user.role);

  @override
  void initState() {
    super.initState();
    _load();
    _chatTimer = Timer.periodic(const Duration(seconds: 20), (_) => _loadThreads());
    kPushOpen.addListener(_onPushOpen);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onPushOpen());
  }

  /// A tapped message notification opens that conversation.
  Future<void> _onPushOpen() async {
    final open = kPushOpen.value;
    if (open == null || !mounted || open.type != 'chat') return;
    kPushOpen.value = null;
    Navigator.of(context).popUntil((r) => r.isFirst);
    try {
      final rows = await widget.api.chatThreads();
      if (!mounted) return;
      setState(() => _threads = rows);
      final th = rows.where((x) => x['link_id'] == open.linkId).toList();
      if (th.isNotEmpty) await _openChat(th.first);
    } on ApiException {
      // Offline: stay on the home screen.
    }
  }

  @override
  void dispose() {
    kPushOpen.removeListener(_onPushOpen);
    _chatTimer?.cancel();
    super.dispose();
  }

  bool get _doctor => widget.user.role == 'doctor';

  /// Where the bell goes: the alerts page.
  int get _alertsIndex => 5;

  int get _unreadTotal =>
      _threads.fold<int>(0, (n, x) => n + ((x['unread'] as int?) ?? 0));

  Future<void> _loadThreads() async {
    try {
      final rows = await widget.api.chatThreads();
      if (!mounted) return;
      final before = _unreadTotal;
      setState(() => _threads = rows);
      if (_unreadTotal > before && ModalRoute.of(context)?.isCurrent == true) {
        final from = rows.firstWhere((x) => ((x['unread'] as int?) ?? 0) > 0,
            orElse: () => const {});
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(t('newMessageFrom')
                .replaceAll('{a}', '${from['patient_name'] ?? ''}'))));
      }
    } on ApiException catch (e) {
      if (e.isUnauthorized) widget.onSignedOut?.call();
    }
  }

  /// Who the conversation is with: the patient for a care or opinion chat, the
  /// other professional for a care-team chat.
  String _threadTitle(Map<String, dynamic> th) =>
      th['kind'] == 'pro' ? '${th['peer_name']}' : '${th['patient_name']}';

  String _threadSubtitle(Map<String, dynamic> th, String lastText) {
    switch (th['kind']) {
      case 'pro':
        return '${t('chatKindTeam')} · ${th['patient_name']}';
      case 'opinion':
        return t('chatKindOpinion');
      default:
        return lastText;
    }
  }

  Future<void> _openChat(Map<String, dynamic> th) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => MessagesScreen(
              api: widget.api,
              linkId: th['link_id'] as String,
              title: _threadTitle(th),
              lang: widget.lang,
              accent: _accent,
              onActivity: _loadThreads,
            )));
    _loadThreads();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorKey = null;
    });
    try {
      final invites = await widget.api.myInvites();
      final patients = await widget.api.myPatients();
      await _loadThreads();
      if (_careId == null) {
        try {
          _careId = (await widget.api.me()).careId;
        } catch (_) {
          // The ID shows once the next refresh works.
        }
      }
      if (!mounted) return;
      setState(() {
        _invites = invites;
        _patients = patients;
        _loading = false;
      });
      if (!_doctor) unawaited(_loadToday(patients));
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) return widget.onSignedOut?.call();
      setState(() {
        _errorKey = e.isNetwork ? 'errOffline' : 'errOtpFailed';
        _loading = false;
      });
    }
  }

  /// The routines set for today for up to ten patients, soonest first. A patient
  /// whose list cannot be fetched is skipped; the rest still show.
  Future<void> _loadToday(List<Map<String, dynamic>> patients) async {
    final now = DateTime.now();
    final lists = await Future.wait([
      for (final p in patients.take(10))
        widget.api
            .careReminders(p['patient_id'] as String, cached: true)
            .then((c) => todayItems(c, now, patient: '${p['display_name']}'))
            .catchError((Object _) => <TodayItem>[]),
    ]);
    if (!mounted) return;
    setState(() => _today = [for (final l in lists) ...l]
      ..sort((a, b) => a.at.compareTo(b.at)));
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
              canPrescribe: widget.user.role == 'doctor',
              accent: _accent,
              lang: widget.lang,
              byName: widget.user.name,
              onMessage: _threadFor(p['patient_id'] as String) == null
                  ? null
                  : () => _openChat(_threadFor(p['patient_id'] as String)!),
              onMessageDoctor: _doctor || _teamThreadFor(p['patient_id'] as String) == null
                  ? null
                  : () => _openChat(_teamThreadFor(p['patient_id'] as String)!),
              onSignedOut: widget.onSignedOut)));

  /// The care-team chat (caregiver and doctor) about this patient, if there is one.
  Map<String, dynamic>? _teamThreadFor(String patientId) {
    for (final th in _threads) {
      if (th['kind'] == 'pro' && th['patient_id'] == patientId) return th;
    }
    return null;
  }

  /// The care chat with this patient (never the caregiver-doctor chat about them).
  Map<String, dynamic>? _threadFor(String patientId) {
    for (final th in _threads) {
      if (th['patient_id'] == patientId && (th['kind'] ?? 'care') == 'care') return th;
    }
    return null;
  }

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
    // Both roles: Home, Patients, Consult, Requests, Profile. The alerts page is
    // reached from the bell (tab 5), so five tabs fit on a small phone.
    final pages = [
      _dashboard(),
      _patientsTab(),
      _consultTab(),
      _requestsTab(),
      _settings(),
      _alertsTab(),
    ];
    return Theme(
      // Buttons and tabs take the role's colour.
      data: base.copyWith(
        navigationBarTheme: base.navigationBarTheme.copyWith(
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final on = states.contains(WidgetState.selected);
            return TextStyle(
                fontSize: 12,
                fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                color: on ? _accent : Palette.muted);
          }),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: (base.filledButtonTheme.style ?? const ButtonStyle())
              .copyWith(backgroundColor: WidgetStatePropertyAll(_accent)),
        ),
      ),
      child: Scaffold(
        body: SafeArea(
          child: Column(children: [
            OfflineBar(api: widget.api, lang: widget.lang),
            Expanded(
                child: RefreshIndicator(onRefresh: _load, child: pages[_tab])),
          ]),
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
                selectedIndex: _tab == 5 ? 0 : _tab,
                onDestinationSelected: (i) => setState(() => _tab = i),
                destinations: _destinations(),
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
        backgroundColor: widget.user.role == 'doctor' ? Palette.tileBlue : Palette.tileGreen,
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

  Widget _threadRow(Map<String, dynamic> th) {
    final unread = (th['unread'] as int?) ?? 0;
    final kind = th['last_kind'] as String?;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        key: ValueKey('thread_${th['link_id']}'),
        padding: const EdgeInsets.all(12),
        onTap: () => _openChat(th),
        child: Row(children: [
          _avatar(_threadTitle(th)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_threadTitle(th),
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Palette.brandDeep)),
                Text(
                    _threadSubtitle(
                        th,
                        kind == null
                            ? t('noMessagesYet')
                            : kind == 'image'
                                ? t('photoMsg')
                                : kind == 'voice'
                                    ? t('voiceNote')
                                    : t('chatMessages')),
                    style: const TextStyle(fontSize: 12.5, color: Palette.muted)),
              ],
            ),
          ),
          if (unread > 0)
            Container(
              margin: const EdgeInsetsDirectional.only(end: 6),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                  color: Palette.red, borderRadius: BorderRadius.circular(12)),
              child: Text('$unread',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          Icon(Icons.chat_bubble_outline_rounded, color: _accent),
        ]),
      ),
    );
  }

  /// Warm header card, tinted with the role's colour so a doctor and a
  /// caregiver can tell at a glance which app they are in.
  Widget _hero() {
    final doctor = widget.user.role == 'doctor';
    final tint = doctor ? Palette.tileBlue : Palette.tileGreen;
    return Container(
      key: const ValueKey('roleHero'),
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tint, Colors.white],
        ),
        border: Border.all(color: _accent.withValues(alpha: .18)),
      ),
      child: Row(children: [
        _avatar(widget.user.name, radius: 28),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${_greeting()},',
                  style: const TextStyle(fontSize: 14, color: Palette.muted)),
              Text(widget.user.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Palette.brandDeep)),
              const SizedBox(height: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                    color: _accent.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(12)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                      doctor
                          ? Icons.medical_services_rounded
                          : Icons.volunteer_activism_rounded,
                      size: 14,
                      color: _accent),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(t(doctor ? 'roleDoctor' : 'roleCaretaker'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _accent)),
                  ),
                ]),
              ),
              const SizedBox(height: 8),
              Text(t(doctor ? 'rmGlanceDoctor' : 'rmGlanceCaretaker'),
                  style: const TextStyle(fontSize: 13, color: Palette.muted)),
            ],
          ),
        ),
        IconButton(
          tooltip: t('rmStatAlerts'),
          onPressed: () => setState(() => _tab = _alertsIndex),
          icon: Badge(
              isLabelVisible: _alertTotal > 0,
              label: Text('$_alertTotal'),
              child: const Icon(Icons.notifications_none_rounded)),
        ),
      ]),
    );
  }

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
    final active = _patients.where(_activeToday).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        if (_doctor) _hero() else _gardenHome(active),
        const SizedBox(height: 16),
        _errorLine(),
        if (_loading)
          const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()))
        else ...[
          if (_doctor) ...[
            Row(children: [
              _stat(Icons.groups_rounded, Palette.green, Palette.tileGreen,
                  '${_patients.length}', t('rmStatPeople')),
              const SizedBox(width: 10),
              _stat(Icons.bolt_rounded, Palette.orange, Palette.tileOrange,
                  '$active', t('rmActiveToday')),
              const SizedBox(width: 10),
              _stat(Icons.notifications_active_rounded, Palette.red,
                  Palette.tileRed, '$_alertTotal', t('rmStatAlerts')),
            ]),
            const SizedBox(height: 18),
          ] else ...[
            // Today as a line through the day, like the patient's own home.
            CareTimeline(
              title: t('routinesToday'),
              empty: t('noRoutinesToday'),
              items: _today,
              lang: widget.lang,
              now: DateTime.now(),
            ),
            const SizedBox(height: 18),
          ],
          if (_threads.isNotEmpty) ...[
            _heading(t('chatMessages')),
            const SizedBox(height: 8),
            for (final th in ([..._threads]
              ..sort((a, b) => '${b['last_at'] ?? ''}'.compareTo('${a['last_at'] ?? ''}'))))
              _threadRow(th),
            const SizedBox(height: 10),
          ],
          if (recent.any((p) => _alertCount(p) > 0)) ...[
            // Who to look at first.
            _heading(t('rmStatusAttention')),
            const SizedBox(height: 8),
            for (final p in recent.where((p) => _alertCount(p) > 0))
              _patientRow(p, chip: true),
            const SizedBox(height: 10),
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

  /// The caregiver's home: a garden whose plant grows with how many of their loved
  /// ones have played today (no score, an empty day is just a young plant).
  Widget _gardenHome(int active) {
    final total = _patients.length;
    return GardenHeader(
      key: const ValueKey('caregiverGarden'),
      greeting: _greeting(),
      name: widget.user.name,
      photo: null,
      now: DateTime.now(),
      progress: total == 0 ? 0 : active / total,
      progressText: t('careActiveToday')
          .replaceAll('{a}', '$active')
          .replaceAll('{b}', '$total'),
      trailing: Material(
        color: Colors.white.withValues(alpha: .85),
        shape: const CircleBorder(),
        child: IconButton(
          key: const ValueKey('gardenBell'),
          tooltip: t('rmStatAlerts'),
          onPressed: () => setState(() => _tab = _alertsIndex),
          icon: Badge(
              isLabelVisible: _alertTotal > 0,
              label: Text('$_alertTotal'),
              child: const Icon(Icons.notifications_none_rounded)),
        ),
      ),
    );
  }

  Widget _inviteCard(Map<String, dynamic> i) {
    final since = DateTime.tryParse('${i['created_at'] ?? ''}');
    final asDoctor = i['member_role'] == 'doctor';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        key: ValueKey('invite_${i['id']}'),
        color: Palette.tileOrange,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              _avatar('${i['patient_display_name']}', radius: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${i['patient_display_name']}',
                          style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: Palette.brandDeep)),
                      const SizedBox(height: 2),
                      Text(
                          '${t('rmInvitedAs')} ${t(asDoctor ? 'roleDoctor' : 'roleCaretaker')}'
                          '${since == null ? '' : ' · ${agoText(widget.lang, since, DateTime.now())}'}',
                          style: const TextStyle(
                              fontSize: 13, color: Palette.muted)),
                    ]),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: FilledButton(
                    key: ValueKey('accept_${i['id']}'),
                    onPressed: () => _answer(i['id'] as String, true),
                    child: Text(t('rmAccept'))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                    key: ValueKey('decline_${i['id']}'),
                    style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: _accent,
                        side: BorderSide(color: _accent.withValues(alpha: .4))),
                    onPressed: () => _answer(i['id'] as String, false),
                    child: Text(t('rmDecline'))),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  /// Three short steps, so a new doctor or caregiver knows how a patient
  /// comes to appear in the app.
  Widget _howLinking() => AppCard(
        key: const ValueKey('howLinking'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t('rqHowTitle'),
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Palette.brandDeep)),
          const SizedBox(height: 10),
          for (final (n, k) in [(1, 'rqHow1'), (2, 'rqHow2'), (3, 'rqHow3')])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                        radius: 12,
                        backgroundColor: _accent.withValues(alpha: .12),
                        child: Text('$n',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: _accent))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(t(k),
                            style: const TextStyle(fontSize: 14, height: 1.35))),
                  ]),
            ),
        ]),
      );

  // ---- tab 2: requests (invitations from patients) -------------------------

  List<NavigationDestination> _destinations() => [
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
                isLabelVisible: _unreadTotal > 0,
                label: Text('$_unreadTotal'),
                child: const Icon(Icons.forum_outlined)),
            selectedIcon: Icon(Icons.forum_rounded, color: _accent),
            label: t('consultTab')),
        NavigationDestination(
            icon: Badge(
                isLabelVisible: _invites.isNotEmpty,
                label: Text('${_invites.length}'),
                child: const Icon(Icons.mail_outline_rounded)),
            selectedIcon: Icon(Icons.mail_rounded, color: _accent),
            label: t('rmRequests')),
        NavigationDestination(
            icon: const Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded, color: _accent),
            label: t('tabProfile')),
      ];

  // ---- consult (doctor) ----------------------------------------------------

  int _consultSeg = 0; // 0 patients, 1 caregivers

  int _unreadOf(Iterable<Map<String, dynamic>> rows) =>
      rows.fold<int>(0, (n, x) => n + ((x['unread'] as int?) ?? 0));

  List<Map<String, dynamic>> _byRecent(Iterable<Map<String, dynamic>> rows) =>
      [...rows]..sort((a, b) => '${b['last_at'] ?? ''}'.compareTo('${a['last_at'] ?? ''}'));

  Widget _segment(Key key, String label, int index, int unread) {
    final on = _consultSeg == index;
    return Expanded(
      child: GestureDetector(
        key: key,
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _consultSeg = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
              color: on ? _accent : Colors.transparent,
              borderRadius: BorderRadius.circular(22)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: on ? Colors.white : Palette.muted)),
            ),
            if (unread > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                    color: Palette.red, borderRadius: BorderRadius.circular(10)),
                child: Text('$unread',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  /// Conversations in one place. A doctor: their own patients, then questions from
  /// other patients who asked for an opinion, and the caregivers of their own
  /// patients. A caregiver: their patients, and the doctors of those patients. The
  /// server never creates a chat outside these (see `test_conversations.py`).
  Widget _consultTab() {
    final mine = _byRecent(_threads.where((x) => x['kind'] == 'care'));
    // Opinion requests are a doctor's; a caregiver never has any (the server sends none).
    final others = _doctor ? _byRecent(_threads.where((x) => x['kind'] == 'opinion')) : <Map<String, dynamic>>[];
    final team = _byRecent(_threads.where((x) => x['kind'] == 'pro'));
    final patientsUnread = _unreadOf(mine) + _unreadOf(others);
    Widget empty(String key) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Text(t(key),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14.5, color: Palette.muted, height: 1.4)),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      children: [
        ScreenTitle(t('consultTab')),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: Palette.line)),
          child: Row(children: [
            _segment(const ValueKey('consultSegPatients'), t('consultPatients'), 0,
                patientsUnread),
            _segment(const ValueKey('consultSegCaregivers'),
                t(_doctor ? 'consultCaregivers' : 'consultDoctors'), 1, _unreadOf(team)),
          ]),
        ),
        const SizedBox(height: 16),
        if (_consultSeg == 0) ...[
          if (mine.isEmpty && others.isEmpty) empty('noPatientChats'),
          if (mine.isNotEmpty) ...[
            _heading(t('yourPatientsChat')),
            const SizedBox(height: 8),
            for (final th in mine) _threadRow(th),
            const SizedBox(height: 8),
          ],
          if (others.isNotEmpty) ...[
            _heading(t('otherQueries')),
            const SizedBox(height: 8),
            for (final th in others) _threadRow(th),
          ],
        ] else ...[
          if (team.isEmpty) empty(_doctor ? 'noCaregiverChats' : 'noDoctorChats'),
          for (final th in team) _threadRow(th),
        ],
      ],
    );
  }

  Widget _requestsTab() => ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          ScreenTitle(t('rmRequests')),
          const SizedBox(height: 12),
          CareIdCard(careId: _careId, lang: widget.lang, accent: _accent),
          const SizedBox(height: 16),
          _errorLine(),
          if (_loading)
            const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()))
          else if (_invites.isEmpty) ...[
            AppCard(
              color: Palette.tileGreen,
              child: Row(children: [
                const Icon(Icons.mark_email_read_outlined,
                    size: 28, color: Palette.green),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(t('rmNoRequests'),
                      key: const ValueKey('noRequests'),
                      style: const TextStyle(fontSize: 14, height: 1.35)),
                ),
              ]),
            ),
          ] else
            for (final i in _invites) _inviteCard(i),
          const SizedBox(height: 4),
          _howLinking(),
        ],
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

  Widget _alertRow(Map<String, dynamic> p, Map<String, dynamic> a) {
    final attention = a['severity'] == 'attention';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        onTap: () => _open(p),
        child: Row(children: [
          IconBadge(
              icon: attention
                  ? Icons.notifications_active_rounded
                  : Icons.lightbulb_outline_rounded,
              fg: attention ? Palette.red : Palette.orange,
              bg: attention ? Palette.tileRed : Palette.tileOrange,
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
                        fontWeight: FontWeight.w700,
                        color: Palette.brandDeep)),
                Text(
                    trf(widget.lang, 'alert_${a['kind']}',
                        a: (a['a'] as int?) ?? 0, b: (a['b'] as int?) ?? 0),
                    style: const TextStyle(fontSize: 13, color: Palette.muted)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Palette.muted),
        ]),
      ),
    );
  }

  /// Alerts about how the app is being used, most urgent first. A doctor reaches
  /// this page from the bell on Home, so it has a way back.
  Widget _alertsTab() {
    final items = <(Map<String, dynamic>, Map<String, dynamic>)>[
      for (final p in _patients)
        for (final a in ((p['alerts'] as List?) ?? const [])
            .cast<Map<String, dynamic>>())
          (p, a)
    ];
    final urgent = [for (final x in items) if (x.$2['severity'] == 'attention') x];
    final gentle = [for (final x in items) if (x.$2['severity'] != 'attention') x];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Row(children: [
          Padding(
              padding: const EdgeInsets.only(right: 10),
              child: InkWell(
                key: const ValueKey('alertsBack'),
                borderRadius: BorderRadius.circular(20),
                onTap: () => setState(() => _tab = 0),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.arrow_back_rounded, color: Palette.brandDeep),
                ),
              ),
            ),
          Expanded(child: ScreenTitle(t('rmStatAlerts'))),
          if (items.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                  color: urgent.isEmpty ? Palette.tileOrange : Palette.tileRed,
                  borderRadius: BorderRadius.circular(14)),
              child: Text('${items.length}',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: urgent.isEmpty ? Palette.orange : Palette.red)),
            ),
        ]),
        const SizedBox(height: 12),
        if (items.isEmpty)
          AppCard(
            color: Palette.tileGreen,
            child: Row(children: [
              const Icon(Icons.check_circle_rounded, size: 30, color: Palette.green),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(t('rmNoAlertsAll'),
                      style: const TextStyle(fontSize: 15, height: 1.35))),
            ]),
          ),
        if (urgent.isNotEmpty) ...[
          _heading(t('rmStatusAttention')),
          const SizedBox(height: 8),
          for (final (p, a) in urgent) _alertRow(p, a),
          const SizedBox(height: 6),
        ],
        if (gentle.isNotEmpty) ...[
          _heading(t('alertsGentle')),
          const SizedBox(height: 8),
          for (final (p, a) in gentle) _alertRow(p, a),
        ],
        if (items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(t('alertHelp'),
                style: const TextStyle(fontSize: 12, color: Palette.muted)),
          ),
      ],
    );
  }

  // ---- tab 3: settings ----------------------------------------------------------

  Widget _settings() {
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
          key: const ValueKey('settingsProfileCard'),
          color: widget.user.role == 'doctor' ? Palette.tileBlue : Palette.tileGreen,
          child: Row(children: [
            _avatar(widget.user.name, radius: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.user.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Palette.brandDeep)),
                    Text(t(widget.user.role == 'doctor' ? 'roleDoctor' : 'roleCaretaker'),
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _accent)),
                    if (_careId != null && _careId!.isNotEmpty)
                      Text(_careId!,
                          style: const TextStyle(
                              fontSize: 13, color: Palette.muted)),
                  ]),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Column(children: [
            row(const ValueKey('rowProfile'), Icons.person_outline_rounded,
                Palette.green, Palette.tileGreen, t('tabProfile'),
                () => open(AccountProfileScreen(
                      name: widget.user.name,
                      careId: _careId,
                      api: widget.api,
                      role: widget.user.role,
                      lang: widget.lang,
                      accent: _accent,
                      onLangChanged: widget.onLangChanged,
                    ))),
            row(const ValueKey('rowHelp'), Icons.help_outline_rounded,
                Palette.blue, Palette.tileBlue, t('helpSupport'),
                () => open(HelpSupportScreen(lang: widget.lang))),
            row(const ValueKey('rowAbout'), Icons.info_outline_rounded,
                Palette.purple, Palette.tilePurple, t('aboutApp'),
                () => open(AboutAppScreen(lang: widget.lang))),
            row(const ValueKey('rowSos'), Icons.phone_in_talk_outlined,
                Palette.red, Palette.tileRed, t('emergencySos'),
                () => open(SosScreen(lang: widget.lang))),
          ]),
        ),
        const SizedBox(height: 16),
        AppCard(
          color: Palette.tileRed,
          onTap: widget.onLogout,
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
    this.canPrescribe = false,
    this.accent = Palette.action,
    this.onSignedOut,
    this.onMessage,
    this.onMessageDoctor,
    this.byName = '',
  });

  /// The signed-in caregiver's or doctor's name, recorded on what they add.
  final String byName;

  /// For a caregiver: opens the care-team chat with this patient's doctor; null
  /// when there is no doctor yet (or for a doctor).
  final VoidCallback? onMessageDoctor;

  /// Opens the conversation with this patient; null when there is none.
  final VoidCallback? onMessage;
  final ApiClient api;
  final String patientId, name, lang;
  final bool canSetBaseline;

  /// Only a doctor prescribes medicines; a caregiver adds every other routine.
  final bool canPrescribe;
  final Color accent;
  final VoidCallback? onSignedOut;

  @override
  State<RemotePatientScreen> createState() => _RemotePatientScreenState();
}

enum _Sec { overview, games, reminders, notes }

class _RemotePatientScreenState extends State<RemotePatientScreen> {
  /// A doctor reads results first; a caregiver works with the routine first.
  List<_Sec> get _secs => widget.canPrescribe
      ? const [_Sec.overview, _Sec.games, _Sec.reminders, _Sec.notes]
      : const [_Sec.overview, _Sec.reminders, _Sec.notes, _Sec.games];
  _Sec _sec = _Sec.overview;
  List<Map<String, dynamic>>? _notes;
  final _noteCtl = TextEditingController();
  Map<String, dynamic>? _report;
  List<Map<String, dynamic>>? _reminders;
  List<Map<String, dynamic>> _careItems = const [];
  String? _errorKey;
  bool _loading = true;

  String t(String k) => tr(widget.lang, k);

  @override
  void initState() {
    super.initState();
    _load();
    if (!widget.canPrescribe) _reloadCare(); // the caregiver's overview shows today's routine
  }

  @override
  void dispose() {
    _noteCtl.dispose();
    super.dispose();
  }

  void _go(_Sec s) {
    setState(() => _sec = s);
    if (s == _Sec.reminders) _loadReminders();
    if (s == _Sec.notes) _loadNotes();
  }

  Future<void> _loadNotes() async {
    try {
      final n = await widget.api.careNotes(widget.patientId);
      if (mounted) setState(() => _notes = n);
    } on ApiException catch (e) {
      if (mounted) _fail(e);
    }
  }

  Future<void> _addNote() async {
    final text = _noteCtl.text.trim();
    if (text.isEmpty) return;
    try {
      await widget.api.addCareNote(widget.patientId, text);
      _noteCtl.clear();
    } on ApiException catch (e) {
      if (mounted) _fail(e);
      return;
    }
    await _loadNotes();
  }

  Future<void> _deleteNote(String id) async {
    try {
      await widget.api.deleteCareNote(widget.patientId, id);
    } on ApiException catch (e) {
      if (mounted) _fail(e);
      return;
    }
    await _loadNotes();
  }

  String _secLabel(_Sec s) => switch (s) {
        _Sec.overview => t('overviewTitle'),
        _Sec.games => t('tabGames'),
        _Sec.reminders => t(widget.canPrescribe ? 'reminders' : 'tabRoutine'),
        _Sec.notes => t('notesTab'),
      };

  /// Shared by the caregiver and the doctor: short notes only they can read.
  List<Widget> _notesTab() {
    final notes = _notes;
    return [
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            key: const ValueKey('noteField'),
            controller: _noteCtl,
            minLines: 2,
            maxLines: 4,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: t('notesHint'), counterText: ''),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: const ValueKey('addNote'),
              style: FilledButton.styleFrom(backgroundColor: widget.accent),
              onPressed: _addNote,
              icon: const Icon(Icons.add_rounded),
              label: Text(t('notesAdd')),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      if (notes == null)
        (_errorKey != null
            ? const SizedBox.shrink()
            : const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator())))
      else if (notes.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Text(t('notesEmpty'),
              key: const ValueKey('noNotes'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Palette.muted, height: 1.4)),
        )
      else
        for (final n in notes)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppCard(
              key: ValueKey('note_${n['id']}'),
              color: n['mine'] == true ? Colors.white : Palette.tilePurple,
              padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${n['body']}', style: const TextStyle(fontSize: 15.5, height: 1.4)),
                    const SizedBox(height: 6),
                    Text(
                        [
                          '${n['author_name']}',
                          t(n['author_role'] == 'doctor' ? 'roleDoctor' : 'roleCaretaker'),
                          if (DateTime.tryParse('${n['created_at']}') case final d?)
                            agoText(widget.lang, d.toLocal(), DateTime.now()),
                        ].join(' · '),
                        style: const TextStyle(fontSize: 12.5, color: Palette.muted)),
                  ]),
                ),
                if (n['mine'] == true)
                  IconButton(
                    key: ValueKey('deleteNote_${n['id']}'),
                    tooltip: t('delete'),
                    icon: const Icon(Icons.delete_outline_rounded, color: Palette.muted),
                    onPressed: () => _deleteNote('${n['id']}'),
                  ),
              ]),
            ),
          ),
    ];
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
      final c = await widget.api.careReminders(widget.patientId, cached: true);
      if (mounted) {
        setState(() {
          _reminders = r;
          _careItems = c;
        });
      }
    } on ApiException catch (e) {
      if (mounted) _fail(e);
    }
  }

  Future<void> _reloadCare() async {
    try {
      final c = await widget.api.careReminders(widget.patientId, cached: true);
      if (mounted) setState(() => _careItems = c);
    } on ApiException catch (e) {
      if (mounted) _fail(e);
    }
  }

  /// A caregiver or doctor adds a routine or reminder; the patient's phone picks
  /// it up the next time it syncs and sets up its notification.
  Future<void> _addCare() async {
    final r = await showAddReminderDialog(context,
        language: widget.lang,
        kinds: [
          for (final k in ReminderKind.values)
            if (widget.canPrescribe || k != ReminderKind.medicine) k
        ],
        defaultBy: widget.byName);
    if (r == null) return;
    final d = r.date;
    try {
      // A medicine taken several times a day becomes one reminder per time.
      for (final at in r.allTimes) {
        await widget.api.addCareReminder(widget.patientId,
            kind: r.kind.name,
            label: r.label,
            hour: at.hour,
            minute: at.minute,
            daysMask: r.daysMask,
            onDate: d == null
                ? null
                : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
      }
    } on ApiException catch (e) {
      if (mounted) _fail(e);
      return;
    }
    await _reloadCare();
  }

  Future<void> _editCare(Map<String, dynamic> x) async {
    final kind = ReminderKind.values.firstWhere((k) => k.name == x['kind'],
        orElse: () => ReminderKind.activity);
    final d = x['on_date'] == null ? null : DateTime.tryParse('${x['on_date']}');
    final r = await showAddReminderDialog(context,
        language: widget.lang,
        title: t('editDetails'),
        kinds: [
          for (final k in ReminderKind.values)
            if (widget.canPrescribe || k != ReminderKind.medicine) k
        ],
        initial: NewReminder(kind, '${x['label']}',
            TimeOfDay(hour: x['hour'] as int, minute: x['minute'] as int), d, '',
            daysMask: (x['days_mask'] as int?) ?? 127));
    if (r == null) return;
    final nd = r.date;
    try {
      await widget.api.editCareReminder(widget.patientId, '${x['id']}',
          kind: r.kind.name,
          label: r.label,
          hour: r.time.hour,
          minute: r.time.minute,
          daysMask: r.daysMask,
          onDate: nd == null
              ? null
              : '${nd.year.toString().padLeft(4, '0')}-${nd.month.toString().padLeft(2, '0')}-${nd.day.toString().padLeft(2, '0')}');
    } on ApiException catch (e) {
      if (mounted) _fail(e);
      return;
    }
    await _reloadCare();
  }

  Future<void> _deleteCare(String id) async {
    try {
      await widget.api.deleteCareReminder(widget.patientId, id);
    } on ApiException catch (e) {
      if (mounted) _fail(e);
      return;
    }
    await _reloadCare();
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

  void _openReport() => Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => RemoteReportScreen(
          api: widget.api,
          patientId: widget.patientId,
          name: widget.name,
          lang: widget.lang,
          accent: widget.accent,
          onSignedOut: widget.onSignedOut)));

  /// Who this is at a glance, and the three things a doctor or caregiver does
  /// most from here: message, read the report, add to the routine.
  Widget _patientHero(Map<String, dynamic>? r) {
    final alerts = r == null
        ? const <Map<String, dynamic>>[]
        : (r['alerts'] as List).cast<Map<String, dynamic>>();
    final attention = alerts.any((a) => a['severity'] == 'attention');
    final last = r == null ? null : r['last_played'] as String?;
    final lastDt = last == null ? null : DateTime.tryParse(last);
    final tint = widget.canPrescribe ? Palette.tileBlue : Palette.tileGreen;
    Widget action(Key key, IconData icon, String label, VoidCallback? onTap) =>
        Expanded(
          child: OutlinedButton(
            key: key,
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: widget.accent,
              side: BorderSide(color: widget.accent.withValues(alpha: .25)),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 22),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
        );
    return Container(
      key: const ValueKey('patientHero'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [tint, Colors.white]),
        border: Border.all(color: widget.accent.withValues(alpha: .18)),
      ),
      child: Column(children: [
        Row(children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: Colors.white,
            child: Text(
                widget.name.trim().isEmpty ? '?' : widget.name.trim()[0].toUpperCase(),
                style: const TextStyle(
                    fontSize: 26, fontWeight: FontWeight.w800, color: Palette.brandDeep)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800, color: Palette.brandDeep)),
              const SizedBox(height: 6),
              if (r != null)
                Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                        color: attention ? Palette.tileRed : Palette.tileGreen,
                        borderRadius: BorderRadius.circular(12)),
                    child: Text(t(attention ? 'rmStatusAttention' : 'rmStatusOk'),
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700,
                            color: attention ? Palette.red : Palette.green)),
                  ),
                  Text(
                      lastDt == null
                          ? t('rmNoGamesYet')
                          : agoText(widget.lang, lastDt, DateTime.now()),
                      style: const TextStyle(fontSize: 12.5, color: Palette.muted)),
                ]),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          action(const ValueKey('heroMessage'), Icons.chat_rounded, t('chatMessages'),
              widget.onMessage),
          if (!widget.canPrescribe) ...[
            const SizedBox(width: 8),
            action(const ValueKey('heroDoctor'), Icons.medical_services_rounded,
                t('roleDoctor'), widget.onMessageDoctor),
          ],
          const SizedBox(width: 8),
          action(const ValueKey('heroReport'), Icons.insights_rounded, t('rmReportTitle'),
              r == null ? null : _openReport),
          const SizedBox(width: 8),
          action(const ValueKey('heroRoutine'), Icons.add_alarm_rounded,
              t(widget.canPrescribe ? 'addReminder' : 'tabRoutine'),
              () => _go(_Sec.reminders)),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;
    return Scaffold(
      appBar: AppBar(
        actions: [
          if (widget.onMessage != null)
            IconButton(
              key: const ValueKey('messagePatient'),
              tooltip: t('chatMessages'),
              icon: Icon(Icons.chat_rounded, color: widget.accent),
              onPressed: widget.onMessage,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          _patientHero(r),
          const SizedBox(height: 14),
          _UnderlineTabs(
            color: widget.accent,
            labels: [for (final x in _secs) _secLabel(x)],
            selected: _secs.indexOf(_sec),
            onSelected: (i) => _go(_secs[i]),
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
          if (_sec == _Sec.reminders)
            ..._remindersTab()
          else if (_sec == _Sec.notes)
            ..._notesTab()
          else if (_loading)
            const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()))
          else if (r != null)
            ...(_sec == _Sec.overview
                ? [
                    if (!widget.canPrescribe) ...[
                      CareTimeline(
                        title: t('routinesToday'),
                        empty: t('noRoutinesToday'),
                        items: todayItems(_careItems, DateTime.now()),
                        lang: widget.lang,
                        now: DateTime.now(),
                      ),
                      const SizedBox(height: 16),
                    ],
                    ..._overview(r),
                  ]
                : _gamesTab(r)),
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
          const SizedBox(width: 12),
          Flexible(
            child: Text(
                lastDt == null
                    ? t('never')
                    : agoText(widget.lang, lastDt, DateTime.now()),
                textAlign: TextAlign.end,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Palette.brandDeep)),
          ),
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
    final addButton = Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FilledButton.icon(
        key: const ValueKey('addCareReminder'),
        icon: const Icon(Icons.add_rounded),
        label: Text(t('addReminder')),
        onPressed: _addCare,
      ),
    );
    if (items.isEmpty && _careItems.isEmpty) {
      return [
        addButton,
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(t('rmNoReminders'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Palette.muted)),
        ),
      ];
    }
    return [
      addButton,
      for (final x in _careItems)
        Builder(builder: (_) {
          final kind = ReminderKind.values.firstWhere((k) => k.name == x['kind'],
              orElse: () => ReminderKind.activity);
          final style = kindStyle(kind);
          final hh = (x['hour'] as int).toString().padLeft(2, '0');
          final mm = (x['minute'] as int).toString().padLeft(2, '0');
          final date = x['on_date'] as String?;
          final label = '${x['label']}';
          return Padding(
            key: ValueKey('care_${x['id']}'),
            padding: const EdgeInsets.only(bottom: 10),
            child: AppCard(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
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
                        Text(label.isEmpty ? t('kind_${kind.name}') : label,
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Palette.brandDeep)),
                        Text(
                            date == null
                                ? '$hh:$mm · ${daysText(widget.lang, (x['days_mask'] as int?) ?? 127)}'
                                : '$date · $hh:$mm',
                            style: const TextStyle(
                                fontSize: 13, color: Palette.ink)),
                        Text(
                            t('addedBy').replaceAll('{a}', '${x['created_by_name']}'),
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: widget.accent)),
                      ]),
                ),
                if (x['mine'] == true)
                  IconButton(
                    key: ValueKey('editCare_${x['id']}'),
                    tooltip: t('editDetails'),
                    icon: Icon(Icons.edit_outlined, color: widget.accent),
                    onPressed: () => _editCare(x),
                  ),
                if (x['mine'] == true)
                  IconButton(
                    key: ValueKey('deleteCare_${x['id']}'),
                    tooltip: t('delete'),
                    icon: const Icon(Icons.delete_outline_rounded,
                        color: Palette.red),
                    onPressed: () => _deleteCare('${x['id']}'),
                  ),
              ]),
            ),
          );
        }),
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
              height: 190,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final g in perGame)
                    Expanded(
                      child: Builder(builder: (_) {
                        final info = kGames.firstWhere((x) => x.id == g['game'],
                            orElse: () => kGames.first);
                        final pct = ((g['accuracy'] as num) * 100).round();
                        return Column(
                          children: [
                            // The bar takes whatever height the labels leave.
                            Expanded(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: FractionallySizedBox(
                                  heightFactor: (0.08 + 0.92 * pct / 100),
                                  child: Container(
                                    width: 26,
                                    decoration: BoxDecoration(
                                      color: info.color,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('$pct%',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600)),
                            ),
                            const SizedBox(height: 2),
                            Text(t(info.titleKey),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 10, color: Palette.muted)),
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
