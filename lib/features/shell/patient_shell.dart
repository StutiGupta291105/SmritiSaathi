import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../data/app_database.dart';
import '../../services/reminder_notifier.dart';
import '../../services/voice.dart';
import '../games/attention_game.dart';
import '../games/memory_match_game.dart';
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
  });
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
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => build(level)));
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
          voiceOn: _voiceOn));

  void _playAttention() => _play(
      'attention',
      (lvl) => AttentionGame(
          db: widget.db,
          patientId: _id,
          baselineLevel: _baseline,
          language: _lang,
          voice: widget.voice,
          startLevel: lvl,
          voiceOn: _voiceOn));

  void _playRoutine() => _play(
      'routine',
      (lvl) => RoutineGame(
          db: widget.db,
          patientId: _id,
          baselineLevel: _baseline,
          language: _lang,
          voice: widget.voice,
          startLevel: lvl,
          voiceOn: _voiceOn));

  void _openProgress() => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            ProgressScreen(db: widget.db, patientId: _id, lang: _lang),
      ));

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
      ),
      GamesTab(
        lang: _lang,
        onMemory: _playMemory,
        onAttention: _playAttention,
        onRoutine: _playRoutine,
      ),
      RemindersScreen(
        db: widget.db,
        notifier: widget.notifier,
        patientId: _id,
        language: _lang,
        embedded: true,
      ),
      ProfileTab(
        db: widget.db,
        notifier: widget.notifier,
        patient: widget.patient,
        onChanged: widget.onPatientChanged,
        onLogout: widget.onLogout,
      ),
    ];
    return Scaffold(
      body: SafeArea(child: pages[_tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home_rounded),
              label: t('tabHome')),
          NavigationDestination(
              icon: const Icon(Icons.sports_esports_outlined),
              selectedIcon: const Icon(Icons.sports_esports_rounded),
              label: t('tabGames')),
          NavigationDestination(
              icon: const Icon(Icons.notifications_none_rounded),
              selectedIcon: const Icon(Icons.notifications_rounded),
              label: t('reminders')),
          NavigationDestination(
              icon: const Icon(Icons.person_outline_rounded),
              selectedIcon: const Icon(Icons.person_rounded),
              label: t('tabProfile')),
        ],
      ),
    );
  }
}
