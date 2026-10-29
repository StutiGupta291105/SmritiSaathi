import 'dart:async';

import 'package:flutter/material.dart';
import '../chat/messages_screen.dart';

import '../../services/api_client.dart';
import '../../services/companion_service.dart';
import '../../services/sync_service.dart';
import '../companion/chat_screen.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/app_database.dart';
import '../../services/reminder_notifier.dart';
import '../../services/voice.dart';
import '../games/attention_game.dart';
import '../games/memory_match_game.dart';
import '../games/number_order_game.dart';
import '../games/puzzle_fix_game.dart';
import '../games/word_recall_game.dart';
import '../games/routine_game.dart';
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
  });
  final ApiClient? api;
  final ServerHooks? hooks;
  final AppDatabase db;
  final ReminderNotifier notifier;
  final Voice voice;
  final Map<String, Object?> patient;

  /// Reload the patient row (language change, or erasure -> back to welcome).
  final VoidCallback onPatientChanged;
  final VoidCallback onLogout;

  @override
  State<PatientShell> createState() => _PatientShellState();
}

class _PatientShellState extends State<PatientShell> {
  int _tab = 0;
  List<Map<String, dynamic>> _threads = const [];
  Timer? _chatTimer;

  @override
  void initState() {
    super.initState();
    if (widget.api != null) {
      _loadThreads();
      _chatTimer = Timer.periodic(const Duration(seconds: 20), (_) => _loadThreads());
    }
  }

  @override
  void dispose() {
    _chatTimer?.cancel();
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
    final th = thread.first;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => MessagesScreen(
        api: widget.api!,
        linkId: th['link_id'] as String,
        title: '${th['member_name']}',
        lang: _lang,
        accent: role == 'doctor' ? Palette.purple : Palette.action,
        callPhone: th['member_phone'] as String?,
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

  void _playMemory() => _play(
    'memory_match',
    (lvl) => MemoryMatchGame(
      db: widget.db,
      patientId: _id,
      baselineLevel: _baseline,
      language: _lang,
      voice: widget.voice,
      startLevel: lvl,
      voiceOn: _voiceOn,
    ),
  );

  void _playAttention() => _play(
    'attention',
    (lvl) => AttentionGame(
      db: widget.db,
      patientId: _id,
      baselineLevel: _baseline,
      language: _lang,
      voice: widget.voice,
      startLevel: lvl,
      voiceOn: _voiceOn,
    ),
  );

  void _playRoutine() => _play(
    'routine',
    (lvl) => RoutineGame(
      db: widget.db,
      patientId: _id,
      baselineLevel: _baseline,
      language: _lang,
      voice: widget.voice,
      startLevel: lvl,
      voiceOn: _voiceOn,
    ),
  );

  void _playWordRecall() => _play(
    'word_recall',
    (lvl) => WordRecallGame(
      db: widget.db,
      patientId: _id,
      baselineLevel: _baseline,
      language: _lang,
      voice: widget.voice,
      startLevel: lvl,
      voiceOn: _voiceOn,
    ),
  );

  void _playPuzzleFix() => _play(
    'puzzle_fix',
    (lvl) => PuzzleFixGame(
      db: widget.db,
      patientId: _id,
      baselineLevel: _baseline,
      language: _lang,
      voice: widget.voice,
      startLevel: lvl,
      voiceOn: _voiceOn,
    ),
  );

  void _playNumberOrder() => _play(
    'number_order',
    (lvl) => NumberOrderGame(
      db: widget.db,
      patientId: _id,
      baselineLevel: _baseline,
      language: _lang,
      voice: widget.voice,
      startLevel: lvl,
      voiceOn: _voiceOn,
    ),
  );

  void _playGame(String id) {
    switch (id) {
      case 'memory_match':
        return _playMemory();
      case 'word_recall':
        return _playWordRecall();
      case 'puzzle_fix':
        return _playPuzzleFix();
      case 'number_order':
        return _playNumberOrder();
      case 'attention':
        return _playAttention();
      default:
        return _playRoutine();
    }
  }

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
        onPlay: _playMemory,
        onGames: () => setState(() => _tab = 1),
        onReminders: () => setState(() => _tab = 2),
        onProgress: _openProgress,
        onTalk: _openTalk,
        onChatCaregiver:
            widget.api == null ? null : () => _openChat('caretaker'),
        onChatDoctor: widget.api == null ? null : () => _openChat('doctor'),
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
      ),
    ];
    return Scaffold(
      body: SafeArea(child: pages[_tab]),
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
