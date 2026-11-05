import 'dart:async';

import 'package:flutter/material.dart';
import 'offline_bar.dart';
import '../chat/doctor_directory_screen.dart';
import '../chat/messages_screen.dart';

import '../../services/api_client.dart';
import '../../services/companion_service.dart';
import '../../services/sync_service.dart';
import '../companion/chat_screen.dart';

import '../../core/games.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/app_database.dart';
import '../../services/push_events.dart';
import '../../services/reminder_notifier.dart';
import '../reminders/notify_banner.dart';
import '../../services/voice.dart';
import '../../services/live_share.dart';
import '../../services/location_service.dart';
import '../../services/sms_sender.dart';
import '../location/live_share_ui.dart';
import '../games/change_game.dart';
import '../games/echo_game.dart';
import '../games/faces_game.dart';
import '../games/sort_game.dart';
import '../games/tile_game.dart';
import '../games/round_game.dart';
import '../games/where_game.dart';
import '../reminders/reminders_screen.dart';
import 'games_tab.dart';
import 'home_tab.dart';
import 'profile_tab.dart';
import 'progress_screen.dart';

/// Elderly user's app: Home, Games, Reminders, Profile (bottom navigation).
class PatientShell extends StatefulWidget {
  const PatientShell({
    super.key,
    required this.db,
    required this.notifier,
    required this.voice,
    required this.patient,
    required this.onPatientChanged,
    required this.onLogout,
    this.hooks,
    this.api,
    this.onConnectOnline,
    this.locationProvider,
  });

  /// Where the phone is; tests pass a fake.
  final LocationProvider? locationProvider;
  final ApiClient? api;
  final ServerHooks? hooks;
  final AppDatabase db;
  final ReminderNotifier notifier;
  final Voice voice;
  final Map<String, Object?> patient;

  /// Reload the patient row (language change, or erasure -> back to welcome).
  final VoidCallback onPatientChanged;
  final VoidCallback onLogout;

  /// Set when the person set up with no internet and still has to check their
  /// phone number; Settings then offers "Connect online services".
  final void Function(BuildContext context)? onConnectOnline;

  @override
  State<PatientShell> createState() => _PatientShellState();
}

class _PatientShellState extends State<PatientShell> {
  int _tab = 0;
  List<Map<String, dynamic>> _threads = const [];
  Timer? _chatTimer;

  var _ticks = 0;
  late final LiveShareController _live;
  final SmsSender _sms = AndroidSmsSender();

  void _remindersChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _live = LiveShareController(
        provider: widget.locationProvider ?? GeolocatorProvider(), api: widget.api);
    // A share that was running when the app was closed carries on.
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => _live.resume(t('liveNotifyTitle'), t('liveNotifyText')));
    kRemindersRevision.addListener(_remindersChanged);
    kPushOpen.addListener(_onPushOpen);
    // A notification tap that started the app is already waiting.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onPushOpen());
    if (widget.api != null) {
      widget.api!.online.addListener(_onlineChanged);
      _loadThreads();
      _chatTimer = Timer.periodic(const Duration(seconds: 20), (_) {
        _loadThreads();
        // About once a minute, pick up routines a caregiver or doctor added.
        if (++_ticks % 3 == 0) widget.hooks?.syncNow();
      });
    }
  }

  /// A tapped notification: the reminders tab for a routine or reminder, the
  /// conversation itself for a message.
  Future<void> _onPushOpen() async {
    final open = kPushOpen.value;
    if (open == null || !mounted) return;
    kPushOpen.value = null;
    Navigator.of(context).popUntil((r) => r.isFirst);
    switch (open.type) {
      case 'routine':
      case 'reminder':
        setState(() => _tab = 2);
      case 'chat':
        final api = widget.api;
        if (api == null) return;
        try {
          final rows = await api.chatThreads();
          if (!mounted) return;
          setState(() => _threads = rows);
          final th = rows.where((x) => x['link_id'] == open.linkId).toList();
          if (th.isNotEmpty) await _pushThread(th.first);
        } on ApiException {
          // Offline: the app is open on the home tab, the chat buttons still work.
        }
    }
  }

  bool? _wasOnline;

  /// Back online after being offline: send what was saved right away instead of
  /// waiting for the next timer.
  void _onlineChanged() {
    final now = widget.api!.online.value;
    if (now == true && _wasOnline == false) widget.hooks?.syncNow();
    _wasOnline = now;
  }

  @override
  void dispose() {
    widget.api?.online.removeListener(_onlineChanged);
    kRemindersRevision.removeListener(_remindersChanged);
    kPushOpen.removeListener(_onPushOpen);
    _chatTimer?.cancel();
    _live.dispose();
    super.dispose();
  }

  int _unreadFor(String role) => _threads
      .where((x) => x['member_role'] == role)
      .fold<int>(0, (n, x) => n + ((x['unread'] as int?) ?? 0));

  /// Refreshes the conversations and their unread counts; tells the person
  /// when something new has arrived while the app is open.
  Future<void> _loadThreads() async {
    try {
      final rows = await widget.api!.chatThreads();
      if (!mounted) return;
      final before = _threads.fold<int>(0, (n, x) => n + ((x['unread'] as int?) ?? 0));
      final after = rows.fold<int>(0, (n, x) => n + ((x['unread'] as int?) ?? 0));
      setState(() => _threads = rows);
      if (after > before && ModalRoute.of(context)?.isCurrent == true) {
        final from = rows.firstWhere((x) => ((x['unread'] as int?) ?? 0) > 0,
            orElse: () => const {});
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(t('newMessageFrom')
                .replaceAll('{a}', '${from['member_name'] ?? ''}'))));
      }
    } on ApiException {
      // Offline or signed out: the buttons still work once it is back.
    }
  }

  Future<void> _openChat(String role) async {
    List<Map<String, dynamic>> rows = _threads;
    try {
      rows = await widget.api!.chatThreads();
      if (mounted) setState(() => _threads = rows);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isNetwork || rows.isEmpty) {
        return _say(t('chatNeedsOnline'));
      }
    }
    final thread = rows.where((x) => x['member_role'] == role).toList();
    if (!mounted) return;
    if (thread.isEmpty) {
      return _say(t(role == 'doctor' ? 'noDoctorYet' : 'noCaregiverYet'));
    }
    // Several caregivers (or doctors): let the person pick who to write to.
    final th = thread.length == 1
        ? thread.first
        : await showModalBottomSheet<Map<String, dynamic>>(
            context: context,
            backgroundColor: Palette.cream,
            builder: (_) => SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (final x in thread)
                  ListTile(
                    key: ValueKey('pick_${x['link_id']}'),
                    leading: const Icon(Icons.chat_bubble_rounded),
                    title: Text('${x['member_name']}',
                        style: const TextStyle(fontSize: 17)),
                    trailing: ((x['unread'] as int?) ?? 0) > 0
                        ? Text('${x['unread']}',
                            style: const TextStyle(
                                color: Palette.red, fontWeight: FontWeight.w700))
                        : null,
                    onTap: () => Navigator.pop(context, x),
                  ),
              ]),
            ),
          );
    if (th == null || !mounted) return;
    await _pushThread(th);
  }

  Future<void> _pushThread(Map<String, dynamic> th) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => MessagesScreen(
        api: widget.api!,
        linkId: th['link_id'] as String,
        title: '${th['member_name']}',
        lang: _lang,
        accent: th['member_role'] == 'doctor' ? Palette.purple : Palette.action,
        callPhone: th['member_phone'] as String?,
        onActivity: _loadThreads,
      ),
    ));
    _loadThreads();
  }

  /// Talk to Doctor: the patient's own doctor pinned on top, then every other
  /// doctor on the app.
  Future<void> _openDoctors() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => DoctorDirectoryScreen(
        api: widget.api!,
        lang: _lang,
        onActivity: _loadThreads,
      ),
    ));
    _loadThreads();
  }

  Future<void> _say(String message) => showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          content: Text(message, style: const TextStyle(fontSize: 16)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(t('finish'))),
          ],
        ),
      );

  String get _lang => widget.patient['language'] as String;
  String get _id => widget.patient['id'] as String;
  int get _baseline => widget.patient['baseline_level'] as int;
  bool get _voiceOn => widget.patient['voice_enabled'] == 1;
  String t(String k) => tr(_lang, k);

  /// Starts a game at the level the learned model recommends (always inside
  /// the caregiver's band), then refreshes the tabs when it ends.
  Future<void> _play(String game, Widget Function(int startLevel) build) async {
    final level = await widget.db.recommendedStartLevel(_id, game, _baseline);
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => build(level)));
    if (mounted) setState(() {});
  }

  void _playGame(String id) {
    switch (id) {
      case 'faces':
        return _start(id, FacesGame.new);
      case 'echo':
        return _start(id, EchoGame.new);
      case 'where':
        return _start(id, WhereGame.new);
      case 'change':
        return _start(id, ChangeGame.new);
      case 'sort':
        return _start(id, SortGame.new);
      default:
        return _start('tile', TileGame.new);
    }
  }

  void _start(
    String id,
    RoundGame Function({
      Key? key,
      required AppDatabase db,
      required String patientId,
      required int baselineLevel,
      required int startLevel,
      required String language,
      required Voice voice,
      required bool voiceOn,
    }) make,
  ) => _play(
    id,
    (lvl) => make(
      db: widget.db,
      patientId: _id,
      baselineLevel: _baseline,
      language: _lang,
      voice: widget.voice,
      startLevel: lvl,
      voiceOn: _voiceOn,
    ),
  );

  void _openProgress() => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) =>
          ProgressScreen(db: widget.db, patientId: _id, lang: _lang),
    ),
  );

  void _openTalk() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ChatScreen(
        service: CompanionService(db: widget.db, api: widget.api),
        voice: widget.voice,
        db: widget.db,
        patientId: _id,
        name: widget.patient['display_name'] as String,
        lang: _lang,
        voiceEnabled: widget.patient['voice_enabled'] == 1,
        syncNow: widget.hooks?.syncNow,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomeTab(
        db: widget.db,
        patientId: _id,
        name: widget.patient['display_name'] as String,
        photo: widget.patient['photo'] as List<int>?,
        lang: _lang,
        topCard: LiveLocationCard(
          controller: _live,
          lang: _lang,
          // One tap shares at once; the slider icon lets the person choose.
          onShare: () => quickShareLiveLocation(context,
              db: widget.db,
              patientId: _id,
              name: widget.patient['display_name'] as String,
              lang: _lang,
              controller: _live,
              api: widget.api,
              sms: _sms),
          onOptions: () => showLiveShareSheet(context,
              db: widget.db,
              patientId: _id,
              name: widget.patient['display_name'] as String,
              lang: _lang,
              controller: _live,
              api: widget.api,
              sms: _sms),
        ),
        onPlay: () => _playGame(kGames.first.id),
        onGames: () => setState(() => _tab = 1),
        onReminders: () => setState(() => _tab = 2),
        onProgress: _openProgress,
        onTalk: _openTalk,
        onChatCaregiver:
            widget.api == null ? null : () => _openChat('caretaker'),
        onChatDoctor: widget.api == null ? null : _openDoctors,
        unreadCaregiver: _unreadFor('caretaker'),
        unreadDoctor: _unreadFor('doctor'),
      ),
      GamesTab(lang: _lang, onPlay: _playGame),
      RemindersScreen(
        db: widget.db,
        notifier: widget.notifier,
        patientId: _id,
        language: _lang,
        embedded: true,
        onBack: () => setState(() => _tab = 0),
      ),
      ProfileTab(
        hooks: widget.hooks,
        db: widget.db,
        notifier: widget.notifier,
        patient: widget.patient,
        onChanged: widget.onPatientChanged,
        onLogout: widget.onLogout,
        onConnectOnline: widget.onConnectOnline,
      ),
    ];
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          if (widget.api != null)
            OfflineBar(
                api: widget.api!, lang: _lang, db: widget.db, patientId: _id),
          NotifyAccessBanner(notifier: widget.notifier, lang: _lang),
          Expanded(child: pages[_tab]),
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
                offset: Offset(0, 4),
              ),
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
                  selectedIcon: const Icon(Icons.home_rounded),
                  label: t('tabHome'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.sports_esports_outlined),
                  selectedIcon: const Icon(Icons.sports_esports_rounded),
                  label: t('tabGames'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.notifications_none_rounded),
                  selectedIcon: const Icon(Icons.notifications_rounded),
                  label: t('reminders'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.person_outline_rounded),
                  selectedIcon: const Icon(Icons.person_rounded),
                  label: t('tabProfile'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
