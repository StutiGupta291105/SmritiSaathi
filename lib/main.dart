import 'package:flutter/material.dart';

import 'core/language_picker.dart';
import 'core/languages.dart';
import 'core/responsive.dart';
import 'core/strings.dart';
import 'core/theme.dart';
import 'data/app_database.dart';
import 'data/session_store.dart';
import 'features/auth/auth_screen.dart';
import 'features/auth/welcome_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/onboarding/restore_screen.dart';
import 'features/profile/profile_flow.dart';
import 'features/remote/remote_home.dart';
import 'features/shell/patient_shell.dart';
import 'features/splash/splash_screen.dart';
import 'core/config.dart';
import 'services/api_client.dart';
import 'services/otp_service.dart';
import 'services/push_service.dart';
import 'services/reminder_notifier.dart';
import 'services/sync_service.dart';
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
      builder: (context, child) => ValueListenableBuilder<String>(
        valueListenable: kActiveLanguage,
        builder: (context, lang, _) => Directionality(
          textDirection: isRtl(lang) ? TextDirection.rtl : TextDirection.ltr,
          child: ResponsiveScope(child: child!),
        ),
      ),
      home: const _Boot(),
    );
  }
}

class _Services {
  _Services(this.db, this.notifier);
  final AppDatabase db;
  final ReminderNotifier notifier;
  final Voice voice = Voice();
  /// Null when this build has no API address (offline test build).
  final ApiClient? api = kOnlineConfigured ? ApiClient(baseUrl: kApiBaseUrl) : null;
  // Without an API address the offline TEST MODE code is used.
  late final OtpService otp = defaultOtpService(api);
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
              api: s.api,
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
    this.api,
  });
  final AppDatabase db;
  final ReminderNotifier notifier;
  final Voice voice;
  final OtpService otp;
  final SessionStore session;
  final ApiClient? api;

  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> with WidgetsBindingObserver {
  ServerUser? _serverUser;
  late final PushRegistrar? _push =
      widget.api == null ? null : PushRegistrar(widget.api!, const NoPush());
  Map<String, dynamic>? _restoreOffer; // server already has this person's data
  bool _skipRestore = false;
  bool _syncing = false;
  Map<String, Object?>? _account;
  Map<String, Object?>? _patient;
  String _lang = 'en'; // UI language before a patient profile exists
  bool _loading = true;
  bool _started = false; // past the welcome screen
  bool _signUp = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.api?.wake(); // a sleeping test server needs a head start
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _sync();
  }

  /// Uploads what the patient agreed to share. Silent when offline: the data
  /// stays queued on the phone and goes out next time.
  Future<void> _sync() async {
    final api = widget.api;
    final patient = _patient;
    if (api == null || patient == null || _syncing) return;
    if ((patient['setup_stage'] as int) < 5 || !await api.hasSession) return;
    _syncing = true;
    try {
      final outcome = await SyncService(widget.db, api).run(patient['id'] as String);
      if (outcome == SyncOutcome.signedOut) await _logout();
    } finally {
      _syncing = false;
    }
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
    final serverUser = await widget.api?.currentUser();
    Map<String, dynamic>? offer;
    if (account != null &&
        account['role'] == 'patient' &&
        patient == null &&
        serverUser != null &&
        !_skipRestore) {
      try {
        offer = await widget.api!.myPatient();
      } on ApiException {
        offer = null; // none on the server, or not reachable: start normally
      }
    }
    if (mounted) {
      setState(() {
        _account = account;
        _patient = patient;
        _serverUser = serverUser;
        _restoreOffer = offer;
        _loading = false;
      });
      _sync();
      if (serverUser != null) _push?.register();
    }
  }

  Future<bool> _restore(Map<String, Object?> account, String serverPatientId) async {
    try {
      final snap = await widget.api!.snapshot(serverPatientId);
      await widget.db.restoreFromSnapshot(
          accountId: account['id'] as String,
          phone: account['phone'] as String,
          snapshot: snap);
    } on ApiException {
      return false;
    }
    await _load();
    return true;
  }

  Future<void> _logout() async {
    final id = _account?['id'] as String?;
    if (id != null) await widget.db.recordLogout(id);
    await widget.notifier.clear();
    await _push?.unregister(); // while still signed in
    await widget.api?.logout();
    await widget.session.clear();
    _started = false;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final active = (_patient?['language'] as String?) ?? _lang;
    if (kActiveLanguage.value != active) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => kActiveLanguage.value = active);
    }
    final account = _account;
    if (account == null && !_started) {
      return WelcomeScreen(
        lang: _lang,
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
      final api = widget.api;
      final user = _serverUser;
      if (api != null && user != null) {
        return RemoteHome(
            api: api,
            user: user,
            lang: _lang,
            onLogout: _logout,
            onLangChanged: (l) => setState(() => _lang = l),
            onSignedOut: _logout);
      }
      return _RoleComingSoon(
          lang: _lang, name: account['name'] as String, onLogout: _logout);
    }
    final patient = _patient;
    final offer = _restoreOffer;
    if (patient == null && offer != null) {
      return RestoreScreen(
        name: offer['display_name'] as String,
        lang: offer['language'] as String,
        onRestore: () => _restore(account, offer['id'] as String),
        onStartFresh: () {
          _skipRestore = true;
          _load();
        },
      );
    }
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
    final api = widget.api;
    return PatientShell(
      api: api,
      hooks: api == null ? null : serverHooks(widget.db, api, _sync),
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
