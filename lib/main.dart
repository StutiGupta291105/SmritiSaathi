import 'package:flutter/material.dart';

import 'core/strings.dart';
import 'core/theme.dart';
import 'data/app_database.dart';
import 'data/session_store.dart';
import 'features/auth/auth_screen.dart';
import 'features/auth/welcome_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/profile/profile_flow.dart';
import 'features/shell/patient_shell.dart';
import 'features/splash/splash_screen.dart';
import 'services/otp_service.dart';
import 'services/reminder_notifier.dart';
import 'services/voice.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SmritiSathiApp());
}

class SmritiSathiApp extends StatelessWidget {
  const SmritiSathiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smriti Sathi',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const _Boot(),
    );
  }
}

class _Services {
  _Services(this.db, this.notifier);
  final AppDatabase db;
  final ReminderNotifier notifier;
  final Voice voice = Voice();
  // TEST MODE: replace with a real SMS OTP service before real use.
  final OtpService otp = DevOtpService();
  final SessionStore session = const SessionStore();
}

/// Shows the splash while the encrypted database opens and reminders are set
/// up (kept on screen for at least a moment so it can be read), then the app.
class _Boot extends StatefulWidget {
  const _Boot();

  @override
  State<_Boot> createState() => _BootState();
}

class _BootState extends State<_Boot> {
  static const _minSplash = Duration(milliseconds: 2400);
  late Future<_Services> _init = _initialize();

  Future<_Services> _initialize() async {
    final started = DateTime.now();
    final db = await AppDatabase.open();
    final notifier = ReminderNotifier(db);
    await notifier.init();
    final remaining = _minSplash - DateTime.now().difference(started);
    if (remaining > Duration.zero) await Future<void>.delayed(remaining);
    return _Services(db, notifier);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Services>(
      future: _init,
      builder: (context, snap) {
        final Widget child;
        if (snap.hasError) {
          child = Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 56),
                    const SizedBox(height: 12),
                    const Text('Something went wrong while starting the app.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 18)),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => setState(() => _init = _initialize()),
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            ),
          );
        } else if (snap.hasData) {
          final s = snap.data!;
          child = Root(
              db: s.db,
              notifier: s.notifier,
              voice: s.voice,
              otp: s.otp,
              session: s.session);
        } else {
          child = const SplashScreen();
        }
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: KeyedSubtree(
            key: ValueKey(snap.hasData ? 'app' : (snap.hasError ? 'err' : 'splash')),
            child: child,
          ),
        );
      },
    );
  }
}

class Root extends StatefulWidget {
  const Root({
    super.key,
    required this.db,
    required this.notifier,
    required this.voice,
    required this.otp,
    required this.session,
  });
  final AppDatabase db;
  final ReminderNotifier notifier;
  final Voice voice;
  final OtpService otp;
  final SessionStore session;

  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  Map<String, Object?>? _account;
  Map<String, Object?>? _patient;
  String _lang = 'en'; // UI language before a patient profile exists
  bool _loading = true;
  bool _started = false; // past the welcome screen
  bool _signUp = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    Map<String, Object?>? account;
    Map<String, Object?>? patient;
    final id = await widget.session.read();
    if (id != null) {
      account = await widget.db.accountById(id);
      if (account == null) await widget.session.clear(); // e.g. after erasure
    }
    if (account != null && account['role'] == 'patient') {
      patient = await widget.db.patientForAccount(account['id'] as String);
      if (patient != null && (patient['setup_stage'] as int) >= 5) {
        await widget.notifier.resync(
            patientId: patient['id'] as String,
            lang: patient['language'] as String);
      }
    }
    if (mounted) {
      setState(() {
        _account = account;
        _patient = patient;
        _loading = false;
      });
    }
  }

  Future<void> _logout() async {
    final id = _account?['id'] as String?;
    if (id != null) await widget.db.recordLogout(id);
    await widget.notifier.clear();
    await widget.session.clear();
    _started = false;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final account = _account;
    if (account == null && !_started) {
      return WelcomeScreen(
        lang: _lang,
        onLangChanged: (l) => setState(() => _lang = l),
        onGetStarted: () => setState(() {
          _started = true;
          _signUp = true;
        }),
        onLogin: () => setState(() {
          _started = true;
          _signUp = false;
        }),
      );
    }
    if (account == null) {
      return AuthScreen(
        key: ValueKey(_signUp),
        initialSignUp: _signUp,
        onBack: () => setState(() => _started = false),
        db: widget.db,
        otp: widget.otp,
        session: widget.session,
        lang: _lang,
        onLangChanged: (l) => setState(() => _lang = l),
        onLoggedIn: _load,
      );
    }
    if (account['role'] != 'patient') {
      return _RoleComingSoon(
          lang: _lang, name: account['name'] as String, onLogout: _logout);
    }
    final patient = _patient;
    if (patient == null) {
      return OnboardingScreen(
          db: widget.db, account: account, lang: _lang, onDone: _load);
    }
    if ((patient['setup_stage'] as int) < 5) {
      return ProfileFlow(
        key: ValueKey(patient['id']),
        db: widget.db,
        notifier: widget.notifier,
        patient: patient,
        onDone: _load,
      );
    }
    return PatientShell(
      db: widget.db,
      notifier: widget.notifier,
      voice: widget.voice,
      patient: patient,
      onPatientChanged: _load,
      onLogout: _logout,
    );
  }
}

/// Doctor and caretaker accounts exist, but their screens need the online
/// service (invites, shared reports), which is not built yet.
class _RoleComingSoon extends StatelessWidget {
  const _RoleComingSoon(
      {required this.lang, required this.name, required this.onLogout});
  final String lang, name;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(lang, 'appName'))),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 16),
              Text(tr(lang, 'comingSoon2'),
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(tr(lang, 'rolePlaceholderBody'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 24),
              FilledButton(onPressed: onLogout, child: Text(tr(lang, 'logout'))),
            ],
          ),
        ),
      ),
    );
  }
}
