import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/progress.dart';
import '../../core/reminder_schedule.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/app_database.dart';
import '../../services/reminder_notifier.dart';
import '../../services/voice.dart';
import '../caregiver/caregiver_area.dart';
import '../games/attention_game.dart';
import '../games/memory_match_game.dart';
import '../games/routine_game.dart';
import '../profile/photo_picker.dart' show Avatar;
import '../privacy/privacy_screen.dart';
import '../reminders/reminders_screen.dart';

/// Elderly user's app: Home, Games, Reminders, Progress (as in the mockups).
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
  final VoidCallback onLogout;

  /// Reload the patient row (language change, or erasure -> back to onboarding).
  final VoidCallback onPatientChanged;

  @override
  State<PatientShell> createState() => _PatientShellState();
}

class _PatientShellState extends State<PatientShell> {
  int _tab = 0;

  String get _lang => widget.patient['language'] as String;
  String get _id => widget.patient['id'] as String;
  int get _baseline => widget.patient['baseline_level'] as int;
  String t(String k) => tr(_lang, k);

  bool get _voiceOn => widget.patient['voice_enabled'] == 1;

  /// Starts a game at the level the learned model recommends (always inside
  /// the caregiver's band), then refreshes the tabs when it ends.
  Future<void> _play(String game, Widget Function(int startLevel) build) async {
    final level = await widget.db.recommendedStartLevel(_id, game, _baseline);
    if (!mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => build(level)));
    if (mounted) setState(() {});
  }

  void _openSettings() => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SettingsScreen(
          db: widget.db,
          notifier: widget.notifier,
          patientId: _id,
          language: _lang,
          voiceOn: _voiceOn,
          onChanged: widget.onPatientChanged,
          onLogout: widget.onLogout,
        ),
      ));

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _HomeTab(
        db: widget.db,
        patientId: _id,
        name: widget.patient['display_name'] as String,
        photo: widget.patient['photo'] as List<int>?,
        lang: _lang,
        onPlay: () => setState(() => _tab = 1),
        onSettings: _openSettings,
      ),
      _GamesTab(
        lang: _lang,
        onMemory: () => _play('memory_match', (lvl) => MemoryMatchGame(
            db: widget.db,
            patientId: _id,
            baselineLevel: _baseline,
            language: _lang,
            voice: widget.voice,
            startLevel: lvl,
            voiceOn: _voiceOn)),
        onAttention: () => _play('attention', (lvl) => AttentionGame(
            db: widget.db,
            patientId: _id,
            baselineLevel: _baseline,
            language: _lang,
            voice: widget.voice,
            startLevel: lvl,
            voiceOn: _voiceOn)),
        onRoutine: () => _play('routine', (lvl) => RoutineGame(
            db: widget.db,
            patientId: _id,
            baselineLevel: _baseline,
            language: _lang,
            voice: widget.voice,
            startLevel: lvl,
            voiceOn: _voiceOn)),
      ),
      RemindersScreen(
        db: widget.db,
        notifier: widget.notifier,
        patientId: _id,
        language: _lang,
      ),
      _ProgressTab(db: widget.db, patientId: _id, baseline: _baseline, lang: _lang),
    ];
    return Scaffold(
      body: SafeArea(child: pages[_tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
              icon: const Icon(Icons.home_outlined, size: 30),
              selectedIcon: const Icon(Icons.home, size: 30),
              label: t('tabHome')),
          NavigationDestination(
              icon: const Icon(Icons.extension_outlined, size: 30),
              selectedIcon: const Icon(Icons.extension, size: 30),
              label: t('tabGames')),
          NavigationDestination(
              icon: const Icon(Icons.alarm_outlined, size: 30),
              selectedIcon: const Icon(Icons.alarm, size: 30),
              label: t('reminders')),
          NavigationDestination(
              icon: const Icon(Icons.bar_chart_outlined, size: 30),
              selectedIcon: const Icon(Icons.bar_chart, size: 30),
              label: t('tabProgress')),
        ],
      ),
    );
  }
}

// ---- Home ------------------------------------------------------------------

class _HomeTab extends StatelessWidget {
  const _HomeTab({
    required this.db,
    required this.patientId,
    required this.name,
    required this.photo,
    required this.lang,
    required this.onPlay,
    required this.onSettings,
  });
  final AppDatabase db;
  final String patientId, name, lang;
  final List<int>? photo;
  final VoidCallback onPlay, onSettings;

  String _greeting() {
    final h = DateTime.now().hour;
    return tr(lang, h < 12 ? 'goodMorning' : h < 17 ? 'goodAfternoon' : 'goodEvening');
  }

  Future<List<(DateTime, Reminder)>> _today() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final out = <(DateTime, Reminder)>[];
    for (final r in await db.listReminders(patientId)) {
      final next = nextOccurrences(
          r, startOfDay.subtract(const Duration(seconds: 1)));
      if (next.isNotEmpty &&
          next.first.year == now.year &&
          next.first.month == now.month &&
          next.first.day == now.day) {
        out.add((next.first, r));
      }
    }
    out.sort((a, b) => a.$1.compareTo(b.$1));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Avatar(photo: photo, radius: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Text('${_greeting()},\n$name',
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            IconButton(
              tooltip: tr(lang, 'settings'),
              iconSize: 34,
              icon: const Icon(Icons.settings),
              onPressed: onSettings,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(tr(lang, 'keepGoing'), style: theme.textTheme.titleMedium),
        const SizedBox(height: 20),
        FilledButton.icon(
          icon: const Icon(Icons.extension, size: 32),
          label: Text(tr(lang, 'playGames')),
          onPressed: onPlay,
        ),
        FutureBuilder(
          future: db.listFamily(patientId),
          builder: (context, snap) {
            final family = snap.data ?? const <Map<String, Object?>>[];
            if (family.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                Text(tr(lang, 'callFamily'),
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                for (final m in family)
                  Card(
                    color: Palette.tileGreen,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      leading: Avatar(photo: m['photo'] as List<int>?, radius: 28),
                      title: Text(m['name'] as String,
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w700)),
                      subtitle: Text(tr(lang, 'rel_${m['relation']}'),
                          style: const TextStyle(fontSize: 16)),
                      trailing: const Icon(Icons.call, size: 36, color: Palette.brand),
                      // Opens the phone dialer with the number filled in.
                      onTap: () => launchUrl(
                          Uri(scheme: 'tel', path: m['phone'] as String)),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        Text(tr(lang, 'todaysTasks'),
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        FutureBuilder(
          future: _today(),
          builder: (context, snap) {
            final items = snap.data ?? const <(DateTime, Reminder)>[];
            if (items.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(tr(lang, 'noTasksToday'),
                    style: theme.textTheme.titleMedium),
              );
            }
            return Column(
              children: [
                for (final (at, r) in items)
                  Card(
                    color: Colors.white,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      leading: Icon(kindIcon(r.kind),
                          size: 36, color: Palette.brand),
                      title: Text(
                          r.label.isEmpty
                              ? tr(lang, 'kind_${r.kind.name}')
                              : r.label,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(TimeOfDay.fromDateTime(at).format(context)),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

IconData kindIcon(ReminderKind k) => switch (k) {
      ReminderKind.medicine => Icons.medication,
      ReminderKind.hydration => Icons.water_drop,
      ReminderKind.activity => Icons.directions_walk,
      ReminderKind.appointment => Icons.event,
    };

// ---- Games -----------------------------------------------------------------

class _GamesTab extends StatelessWidget {
  const _GamesTab({
    required this.lang,
    required this.onMemory,
    required this.onAttention,
    required this.onRoutine,
  });
  final String lang;
  final VoidCallback onMemory, onAttention, onRoutine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget tile(Color color, IconData icon, String title, String desc,
        VoidCallback? onTap) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Card(
          color: onTap == null ? color.withAlpha(128) : color,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Icon(icon, size: 48, color: Palette.brand),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: theme.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        Text(onTap == null ? tr(lang, 'comingSoon') : desc,
                            style: theme.textTheme.bodyLarge),
                      ],
                    ),
                  ),
                  if (onTap != null) const Icon(Icons.chevron_right, size: 32),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(tr(lang, 'chooseGame'),
            style: theme.textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        tile(Palette.tileBlue, Icons.extension, tr(lang, 'memoryGame'),
            tr(lang, 'memoryGameDesc'), onMemory),
        tile(Palette.tileOrange, Icons.center_focus_strong,
            tr(lang, 'gameAttention'), tr(lang, 'gameAttentionDesc'), onAttention),
        tile(Palette.tileGreen, Icons.wb_sunny, tr(lang, 'gameRoutine'),
            tr(lang, 'gameRoutineDesc'), onRoutine),
      ],
    );
  }
}

// ---- Progress --------------------------------------------------------------

/// Engagement only: how often the person plays. Deliberately no "cognitive
/// score" or health label (non-diagnostic positioning, see README).
class _ProgressTab extends StatelessWidget {
  const _ProgressTab({
    required this.db,
    required this.patientId,
    required this.baseline,
    required this.lang,
  });
  final AppDatabase db;
  final String patientId;
  final int baseline;
  final String lang;

  Future<(List<DateTime>, int)> _load() async {
    final times = await db.sessionTimes(patientId);
    final levels = await db.recentEndLevels(patientId, limit: 1);
    return (times, levels.isEmpty ? baseline : levels.last);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder(
      future: _load(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final (times, level) = snap.data!;
        final today = DateTime.now();
        final week = sessionsLast7Days(times, today);
        final maxCount = week.fold<int>(1, (m, c) => c > m ? c : m);
        Widget stat(String label, String value, Color color) => Expanded(
              child: Card(
                color: color,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Column(
                    children: [
                      Text(value,
                          style: theme.textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      Text(label,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
              ),
            );
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(tr(lang, 'myProgress'),
                style: theme.textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            Row(children: [
              stat(tr(lang, 'gamesPlayed'), '${times.length}', Palette.tileBlue),
              stat(tr(lang, 'dayStreak'), '${currentStreak(times, today)}',
                  Palette.tileOrange),
              stat(tr(lang, 'currentLevel'), '$level', Palette.tileGreen),
            ]),
            const SizedBox(height: 20),
            Text(tr(lang, 'thisWeek'),
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            SizedBox(
              height: 140,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < 7; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Container(
                              height: 8 + 100.0 * week[i] / maxCount,
                              decoration: BoxDecoration(
                                color: week[i] == 0
                                    ? Colors.black12
                                    : Palette.brand,
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(_dayLetter(
                                today.subtract(Duration(days: 6 - i)))),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(tr(lang, 'progressNote'), style: theme.textTheme.bodyMedium),
          ],
        );
      },
    );
  }

  String _dayLetter(DateTime d) => 'MTWTFSS'[d.weekday - 1];
}

// ---- Settings --------------------------------------------------------------

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.db,
    required this.notifier,
    required this.patientId,
    required this.language,
    required this.voiceOn,
    required this.onChanged,
    required this.onLogout,
  });
  final AppDatabase db;
  final ReminderNotifier notifier;
  final String patientId, language;
  final bool voiceOn;
  final VoidCallback onChanged;
  final VoidCallback onLogout;

  // Assamese and Bengali are in the design; they need translated strings first.
  static const _languages = {'en': 'English', 'hi': 'हिन्दी'};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(language, 'settings'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(tr(language, 'language'),
              style: Theme.of(context).textTheme.titleLarge),
          RadioGroupCompat(
            value: language,
            options: _languages,
            onSelected: (code) async {
              await db.setLanguage(patientId, code, 'user');
              await notifier.resync(patientId: patientId, lang: code);
              onChanged();
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
          const Divider(height: 32),
          SwitchListTile(
            secondary: const Icon(Icons.record_voice_over, size: 32),
            title: Text(tr(language, 'voiceOn'),
                style: const TextStyle(fontSize: 20)),
            value: voiceOn,
            onChanged: (v) async {
              await db.setVoiceEnabled(patientId, v, 'user');
              onChanged();
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.supervisor_account, size: 32),
            title: Text(tr(language, 'caregiverArea'),
                style: const TextStyle(fontSize: 20)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openCaregiverArea(
              context,
              db: db,
              notifier: notifier,
              patientId: patientId,
              lang: language,
              onChanged: onChanged,
            ),
          ),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.lock_outline, size: 32),
            title: Text(tr(language, 'privacy'),
                style: const TextStyle(fontSize: 20)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => PrivacyScreen(
                db: db,
                notifier: notifier,
                patientId: patientId,
                language: language,
                onErased: () {
                  Navigator.of(context).popUntil((r) => r.isFirst);
                  onChanged();
                },
              ),
            )),
          ),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.logout, size: 32),
            title: Text(tr(language, 'logout'),
                style: const TextStyle(fontSize: 20)),
            onTap: () {
              Navigator.of(context).popUntil((r) => r.isFirst);
              onLogout();
            },
          ),
        ],
      ),
    );
  }
}

/// Simple tappable language list (avoids Radio API differences across Flutter versions).
class RadioGroupCompat extends StatelessWidget {
  const RadioGroupCompat(
      {super.key,
      required this.value,
      required this.options,
      required this.onSelected});
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final e in options.entries)
            ListTile(
              leading: Icon(
                  e.key == value
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: Palette.brand,
                  size: 32),
              title: Text(e.value, style: const TextStyle(fontSize: 22)),
              onTap: () => onSelected(e.key),
            ),
        ],
      );
}
