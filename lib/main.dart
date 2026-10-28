import 'package:flutter/material.dart';

import 'core/strings.dart';
import 'data/app_database.dart';
import 'features/games/memory_match_game.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/privacy/privacy_screen.dart';
import 'features/reminders/reminders_screen.dart';
import 'services/reminder_notifier.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDatabase.open();
  final notifier = ReminderNotifier(db);
  await notifier.init();
  runApp(SmritiAssistApp(db: db, notifier: notifier));
}

class SmritiAssistApp extends StatelessWidget {
  const SmritiAssistApp({super.key, required this.db, required this.notifier});
  final AppDatabase db;
  final ReminderNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmritiAssist',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
        // Elderly-friendly defaults: large text, large touch targets.
        textTheme: Typography.blackMountainView.apply(fontSizeFactor: 1.2),
        visualDensity: VisualDensity.standard,
        materialTapTargetSize: MaterialTapTargetSize.padded,
      ),
      home: Root(db: db, notifier: notifier),
    );
  }
}

class Root extends StatefulWidget {
  const Root({super.key, required this.db, required this.notifier});
  final AppDatabase db;
  final ReminderNotifier notifier;

  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  Map<String, Object?>? _patient;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await widget.db.firstPatient();
    if (p != null) {
      await widget.notifier
          .resync(patientId: p['id'] as String, lang: p['language'] as String);
    }
    if (mounted) {
      setState(() {
        _patient = p;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_patient == null) {
      return OnboardingScreen(db: widget.db, onDone: _load);
    }
    return HomeScreen(
        db: widget.db,
        notifier: widget.notifier,
        patient: _patient!,
        onErased: _load);
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.db,
    required this.notifier,
    required this.patient,
    required this.onErased,
  });
  final AppDatabase db;
  final ReminderNotifier notifier;
  final Map<String, Object?> patient;
  final VoidCallback onErased;

  @override
  Widget build(BuildContext context) {
    final lang = patient['language'] as String;
    final name = patient['display_name'] as String;
    return Scaffold(
      appBar: AppBar(title: Text(tr(lang, 'appName'))),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name, style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 96,
                child: FilledButton.icon(
                  icon: const Icon(Icons.extension, size: 36),
                  label: Text(tr(lang, 'memoryGame'),
                      style: const TextStyle(fontSize: 28)),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MemoryMatchGame(
                        db: db,
                        patientId: patient['id'] as String,
                        baselineLevel: patient['baseline_level'] as int,
                        language: lang,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 96,
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.alarm, size: 36),
                  label: Text(tr(lang, 'reminders'),
                      style: const TextStyle(fontSize: 28)),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RemindersScreen(
                        db: db,
                        notifier: notifier,
                        patientId: patient['id'] as String,
                        language: lang,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                icon: const Icon(Icons.lock_outline),
                label: Text(tr(lang, 'privacy'),
                    style: const TextStyle(fontSize: 20)),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PrivacyScreen(
                      db: db,
                      notifier: notifier,
                      patientId: patient['id'] as String,
                      language: lang,
                      onErased: () {
                        Navigator.of(context).pop();
                        onErased();
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
