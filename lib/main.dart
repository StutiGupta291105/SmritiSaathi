import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'data/app_database.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/shell/patient_shell.dart';
import 'services/reminder_notifier.dart';
import 'services/voice.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDatabase.open();
  final notifier = ReminderNotifier(db);
  await notifier.init();
  runApp(SmritiSathiApp(db: db, notifier: notifier, voice: Voice()));
}

class SmritiSathiApp extends StatelessWidget {
  const SmritiSathiApp(
      {super.key,
      required this.db,
      required this.notifier,
      required this.voice});
  final AppDatabase db;
  final ReminderNotifier notifier;
  final Voice voice;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smriti Sathi',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: Root(db: db, notifier: notifier, voice: voice),
    );
  }
}

class Root extends StatefulWidget {
  const Root(
      {super.key,
      required this.db,
      required this.notifier,
      required this.voice});
  final AppDatabase db;
  final ReminderNotifier notifier;
  final Voice voice;

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
    return PatientShell(
      db: widget.db,
      notifier: widget.notifier,
      voice: widget.voice,
      patient: _patient!,
      onPatientChanged: _load,
    );
  }
}
