import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smriti_assist/data/app_database.dart';
import 'package:smriti_assist/data/session_store.dart';
import 'package:smriti_assist/features/auth/auth_screen.dart';
import 'package:smriti_assist/features/chat/messages_screen.dart';
import 'package:smriti_assist/features/shell/connect_online.dart';
import 'package:smriti_assist/features/shell/offline_bar.dart';
import 'package:smriti_assist/services/api_client.dart';
import 'package:smriti_assist/services/otp_service.dart';
import 'package:smriti_assist/services/voice_notes.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

http.Response _j(Object b, [int s = 200]) =>
    http.Response(jsonEncode(b), s, headers: {'content-type': 'application/json'});

class _Voice implements VoiceRecorder {
  @override
  Future<bool> start() async => true;
  @override
  Future<RecordedNote?> stop() async => null;
  @override
  Future<void> cancel() async {}
}

class _Player implements VoicePlayer {
  @override
  Stream<void> get onFinished => const Stream.empty();
  @override
  Future<void> play(Uint8List bytes, String mime) async {}
  @override
  Future<void> stop() async {}
  @override
  void dispose() {}
}

/// A switchable chat server.
class _Net {
  bool up = true;
  final sent = <String>[];
  final stored = <Map<String, dynamic>>[];
  int id = 1;
  Future<http.Response> handle(http.Request r) async {
    if (!up) throw http.ClientException('no signal');
    final p = r.url.path;
    if (p == '/v1/chat/L1/messages' && r.method == 'GET') {
      final after = int.tryParse(r.url.queryParameters['after'] ?? '') ?? 0;
      return _j([for (final m in stored) if ((m['id'] as int) > after) m]);
    }
    if (p == '/v1/chat/L1/messages' && r.method == 'POST') {
      final b = jsonDecode(r.body) as Map<String, dynamic>;
      sent.add('${b['text']}');
      final m = {'id': id++, 'mine': true, 'kind': b['kind'], 'text': b['text'], 'mime': '', 'duration_ms': 0,
                 'has_media': false, 'created_at': '2026-10-31T10:00:00', 'read': false};
      stored.add(m);
      return _j(m, 201);
    }
    if (p == '/v1/chat/L1/read') return _j({});
    return _j({'detail': 'x'}, 404);
  }
}

void main() {
  late AppDatabase db;
  late _Net net;
  late ApiClient api;

  setUp(() async {
    sqfliteFfiInit();
    final raw = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(
            singleInstance: false,
            version: AppDatabase.schemaVersion,
            onCreate: (d, _) => AppDatabase.createSchema(d)));
    db = AppDatabase.forTesting(raw);
    net = _Net();
    api = ApiClient(
        baseUrl: 'https://api.example.com',
        tokens: MemoryTokenStore(),
        client: MockClient(net.handle),
        store: db);
  });

  /// Database and network answers arrive in real time while the widget clock is
  /// fake, so alternate: let real time pass, then let the widgets catch up.
  Future<void> settle(WidgetTester t, {int rounds = 5}) async {
    for (var i = 0; i < rounds; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Widget chat() => MaterialApp(
      home: MessagesScreen(
          api: api, linkId: 'L1', title: 'Ravi', lang: 'en', recorder: _Voice(), player: _Player(),
          pollEvery: const Duration(milliseconds: 400)));

  testWidgets('a message written offline shows as waiting and goes out by itself when the signal returns', (t) async {
    net.up = false;
    await t.pumpWidget(chat());
    await settle(t);
    await t.enterText(find.byKey(const ValueKey('chatInput')), 'Please call me');
    await t.pump();
    await t.tap(find.byKey(const ValueKey('sendText')));
    await settle(t);
    expect(find.text('Please call me'), findsOneWidget);
    expect(find.text('Waiting to send'), findsOneWidget);
    expect(await t.runAsync(() => db.outboxList()), hasLength(1));
    expect(net.sent, isEmpty);

    net.up = true;
    await t.pump(const Duration(milliseconds: 500)); // next poll
    await settle(t, rounds: 8);
    expect(net.sent, ['Please call me']);
    expect(find.text('Waiting to send'), findsNothing);
    expect(find.text('Please call me'), findsOneWidget); // now the real message, once
    expect(await t.runAsync(() => db.outboxList()), isEmpty);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('an old conversation can still be read with no signal', (t) async {
    net.stored.add({'id': 7, 'mine': false, 'kind': 'text', 'text': 'Take your tablet', 'mime': '',
                    'duration_ms': 0, 'has_media': false, 'created_at': '2026-10-31T09:00:00', 'read': true});
    await t.runAsync(() => api.chatMessages('L1')); // seen while online once
    net.up = false;
    await t.pumpWidget(chat());
    await settle(t);
    expect(find.text('Take your tablet'), findsOneWidget);
    expect(find.byKey(const ValueKey('staleBar')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the offline bar reassures a patient and counts what is waiting', (t) async {
    late String pid;
    await t.runAsync(() async {
      final acc = await db.createAccount(phone: '+919876543210', role: 'patient', name: 'Asha');
      pid = await db.createPatient(accountId: acc, phone: '+919876543210', displayName: 'Asha',
          baselineLevel: 2, language: 'en', createdBy: 'x');
      await db.recordConsent(patientId: pid, purposes: {'gameplay': true, 'sync': true},
          givenByName: 'Asha', givenByRelation: 'self', noticeVersion: 'v2');
      await db.insertSession(patientId: pid, game: 'memory_match', startedAt: DateTime.now(),
          startLevel: 2, endLevel: 2, trials: 3, correct: 3);
    });
    await t.pumpWidget(MaterialApp(
        home: Scaffold(body: OfflineBar(api: api, lang: 'en', db: db, patientId: pid, refresh: const Duration(milliseconds: 200)))));
    expect(find.byKey(const ValueKey('offlineBar')), findsNothing); // unknown yet: say nothing
    net.up = false;
    await t.runAsync(() async {
      try {
        await api.chatMessages('L1');
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('offlineBar')), findsOneWidget);
    expect(find.textContaining('saved on this phone'), findsOneWidget);
    expect(find.textContaining('waiting to send'), findsOneWidget);
    net.up = true;
    await t.runAsync(() async {
      await api.chatMessages('L1');
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('offlineBar')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a new patient with no internet can still set up on the phone', (t) async {
    final off = _OfflineOtp();
    String? loggedInAs;
    await t.binding.setSurfaceSize(const Size(800, 1600));
    await t.pumpWidget(MaterialApp(
        home: AuthScreen(
            db: db, otp: off, session: _MemSession(), lang: 'en', onLangChanged: (_) {},
            onLoggedIn: () => loggedInAs = 'in', initialSignUp: true)));
    await t.enterText(find.byType(TextField).at(0), 'Asha Devi');
    await t.enterText(find.byType(TextField).at(1), '+919876543210');
    await t.tap(find.byType(FilledButton));
    await settle(t);
    expect(find.byKey(const ValueKey('offlineStart')), findsOneWidget);
    expect(find.byKey(const ValueKey('offlineNote')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('offlineStart')));
    await settle(t);
    expect(loggedInAs, 'in');
    final acc = await t.runAsync(() => db.accountByPhoneRole('+919876543210', 'patient'));
    expect(acc, isNotNull);
    expect(acc!['name'], 'Asha Devi');
  });

  testWidgets('connecting online later: new number signs up, then the account is linked', (t) async {
    final acc = (await t.runAsync(() => db.createAccount(phone: '+919876543210', role: 'patient', name: 'Asha')))!;
    final otp = _FakeOtp();
    var connected = false;
    await t.pumpWidget(MaterialApp(
        home: ConnectOnlineScreen(otp: otp, db: db, accountId: acc, phone: '+919876543210',
            name: 'Asha', lang: 'en', onConnected: () => connected = true)));
    await t.tap(find.byKey(const ValueKey('connectGo')));
    await settle(t);
    await t.enterText(find.byKey(const ValueKey('connectCode')), '123456');
    await t.tap(find.byKey(const ValueKey('connectGo')));
    await settle(t);
    expect(connected, isTrue);
    expect((await t.runAsync(() => db.accountById(acc)))!['server_user_id'], 'srv-1');
    expect(otp.modes, ['signup']);
  });

  testWidgets('connecting online later: a number already known online switches to sign-in with a new code', (t) async {
    final acc = (await t.runAsync(() => db.createAccount(phone: '+919876543210', role: 'patient', name: 'Asha')))!;
    final otp = _FakeOtp(existsOnline: true);
    var connected = false;
    await t.pumpWidget(MaterialApp(
        home: ConnectOnlineScreen(otp: otp, db: db, accountId: acc, phone: '+919876543210',
            name: 'Asha', lang: 'en', onConnected: () => connected = true)));
    await t.tap(find.byKey(const ValueKey('connectGo')));
    await settle(t);
    await t.enterText(find.byKey(const ValueKey('connectCode')), '123456');
    await t.tap(find.byKey(const ValueKey('connectGo')));
    await settle(t);
    expect(connected, isFalse);
    expect(find.text('Please get a new code and enter it to finish.'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('connectGo'))); // send again, now to sign in
    await settle(t);
    await t.enterText(find.byKey(const ValueKey('connectCode')), '123456');
    await t.tap(find.byKey(const ValueKey('connectGo')));
    await settle(t);
    expect(connected, isTrue);
    expect(otp.modes, ['signup', 'login']);
  });
}

class _MemSession extends SessionStore {
  _MemSession();
  String? v;
  @override
  Future<String?> read() async => v;
  @override
  Future<void> write(String accountId) async => v = accountId;
  @override
  Future<void> clear() async => v = null;
}

class _OfflineOtp implements OtpService {
  @override
  bool get isTestMode => false;
  @override
  ServerUser? get serverUser => null;
  @override
  Future<OtpResult> send(String phoneE164, {String role = 'patient', bool signUp = false}) async =>
      OtpResult.offline;
  @override
  Future<OtpResult> verify(String phoneE164, String code,
          {String role = 'patient', bool signUp = false, String? name}) async =>
      OtpResult.offline;
}

class _FakeOtp implements OtpService {
  _FakeOtp({this.existsOnline = false});
  final bool existsOnline;
  final modes = <String>[];
  ServerUser? _u;
  @override
  bool get isTestMode => false;
  @override
  ServerUser? get serverUser => _u;
  @override
  Future<OtpResult> send(String phoneE164, {String role = 'patient', bool signUp = false}) async =>
      OtpResult.ok;
  @override
  Future<OtpResult> verify(String phoneE164, String code,
      {String role = 'patient', bool signUp = false, String? name}) async {
    modes.add(signUp ? 'signup' : 'login');
    if (signUp && existsOnline) return OtpResult.accountExists;
    _u = const ServerUser('srv-1', 'patient', 'Asha');
    return OtpResult.ok;
  }
}
