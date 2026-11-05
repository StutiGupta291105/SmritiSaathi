import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smriti_assist/core/theme.dart';
import 'package:smriti_assist/data/app_database.dart';
import 'package:smriti_assist/features/location/live_share_ui.dart';
import 'package:smriti_assist/services/api_client.dart';
import 'package:smriti_assist/services/live_share.dart';
import 'package:smriti_assist/services/location_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeLocation implements LocationProvider {
  FakeLocation({this.access = LocationAccess.granted});
  LocationAccess access;
  GeoPoint at = const GeoPoint(12.97, 77.59, 8);
  final updates0 = StreamController<GeoPoint>.broadcast();
  bool failCurrent = false;
  @override
  Future<LocationAccess> ensureAccess() async => access;
  @override
  Future<GeoPoint> current() async {
    if (failCurrent) throw Exception('no fix');
    return at;
  }

  @override
  Stream<GeoPoint> updates({required String title, required String text}) => updates0.stream;
}

class Server {
  final calls = <String>[];
  final bodies = <Map<String, dynamic>>[];
  bool offline = false;
  http.Response handle(http.Request r) {
    if (offline) throw http.ClientException('down');
    calls.add('${r.method} ${r.url.path}');
    if (r.body.isNotEmpty) bodies.add(jsonDecode(r.body) as Map<String, dynamic>);
    if (r.url.path == '/v1/live/start') {
      return http.Response(
          jsonEncode({'active': true, 'url': 'https://api.example.com/live/TOKEN123',
              'expires_at': '2030-01-01T00:00:00Z'}),
          201);
    }
    if (r.url.path.startsWith('/v1/chat/')) return http.Response(jsonEncode({'id': 1}), 201);
    return http.Response('{}', 200);
  }
}

ApiClient apiFor(Server s) => ApiClient(
    baseUrl: 'https://api.example.com',
    tokens: MemoryTokenStore(),
    client: MockClient((r) async => s.handle(r)));

void main() {
  test('messages: live (with a time) and just-now wording, and an SMS link', () {
    final live = liveMessage('en',
        name: 'Asha', link: 'https://x/live/T', until: DateTime(2026, 1, 1, 18, 30));
    expect(live, 'Asha is sharing a live location until 6:30 pm: https://x/live/T');
    expect(liveMessage('en', name: 'Asha', link: 'https://x/m'), 'Asha is here right now: https://x/m');
    final u = smsUri(['+919811111111', '+919822222222'], 'Hi there & you');
    expect(u.toString(), startsWith('sms:+919811111111,+919822222222?body=Hi%20there%20%26%20you'));
  });

  group('controller', () {
    test('a live share starts on the server, keeps it fresh (throttled) and stops', () async {
      final srv = Server();
      final loc = FakeLocation();
      var now = DateTime(2026, 1, 1, 10);
      final c = LiveShareController(
          provider: loc, api: apiFor(srv), clock: () => now, minGap: const Duration(seconds: 20));
      final r = await c.start(minutes: 60, notifyTitle: 't', notifyText: 'x');
      expect(r.outcome, ShareOutcome.ok);
      expect(r.live, isTrue);
      expect(r.link, 'https://api.example.com/live/TOKEN123');
      expect(c.active, isTrue);
      expect(srv.bodies.first, {'lat': 12.97, 'lng': 77.59, 'accuracy': 8.0, 'minutes': 60});
      // a point right away is too soon; one 30 s later is sent
      loc.updates0.add(const GeoPoint(13, 77.6, 5));
      await Future<void>.delayed(Duration.zero);
      expect(srv.calls.where((x) => x == 'PUT /v1/live/update'), isEmpty);
      now = now.add(const Duration(seconds: 30));
      loc.updates0.add(const GeoPoint(13.1, 77.7, 5));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(srv.calls.where((x) => x == 'PUT /v1/live/update').length, 1);
      await c.stop();
      expect(c.active, isFalse);
      expect(srv.calls.last, 'POST /v1/live/stop');
      c.dispose();
    });

    test('"just now" sends one spot and starts nothing on the server', () async {
      final srv = Server();
      final c = LiveShareController(provider: FakeLocation(), api: apiFor(srv));
      final r = await c.start(minutes: 0, notifyTitle: 't', notifyText: 'x');
      expect(r.live, isFalse);
      expect(r.link, 'https://www.google.com/maps?q=12.97,77.59');
      expect(srv.calls, isEmpty);
      expect(c.active, isFalse);
    });

    test('offline: falls back to a plain maps link for this spot', () async {
      final srv = Server()..offline = true;
      final c = LiveShareController(provider: FakeLocation(), api: apiFor(srv));
      final r = await c.start(minutes: 60, notifyTitle: 't', notifyText: 'x');
      expect(r.outcome, ShareOutcome.ok);
      expect(r.live, isFalse);
      expect(r.link, startsWith('https://www.google.com/maps?q='));
      expect(c.active, isFalse);
    });

    test('no permission, location off, or no fix: nothing is shared', () async {
      for (final (a, o) in [
        (LocationAccess.denied, ShareOutcome.denied),
        (LocationAccess.deniedForever, ShareOutcome.deniedForever),
        (LocationAccess.serviceOff, ShareOutcome.serviceOff),
      ]) {
        final c = LiveShareController(provider: FakeLocation(access: a));
        expect((await c.start(minutes: 30, notifyTitle: '', notifyText: '')).outcome, o);
        expect(c.active, isFalse);
      }
      final noFix = FakeLocation()..failCurrent = true;
      final c = LiveShareController(provider: noFix);
      expect((await c.start(minutes: 30, notifyTitle: '', notifyText: '')).outcome,
          ShareOutcome.noPosition);
    });
  });

  group('sending', () {
    test('caregiver by chat, family by one SMS, only the chosen people', () async {
      final srv = Server();
      Uri? opened;
      final report = await sendLiveMessage(
        text: 'hello link',
        api: apiFor(srv),
        launch: (u) async {
          opened = u;
          return true;
        },
        targets: const [
          ShareTarget(name: 'Ravi', chatLinkId: 'L1', chat: true, phone: '+919811111111'),
          ShareTarget(name: 'Meena', phone: '+919822222222', sms: true),
          ShareTarget(name: 'Gopal', phone: '+919833333333', sms: true),
          ShareTarget(name: 'No phone', sms: true),
        ],
      );
      expect(report.chatSent, 1);
      expect(srv.calls, ['POST /v1/chat/L1/messages']);
      expect(report.smsOpened, isTrue);
      // the caregiver is not in the SMS unless "also SMS" was chosen
      expect(opened.toString(), startsWith('sms:+919822222222,+919833333333?body='));
    });

    test('an SMS to the caregiver too when asked', () async {
      Uri? opened;
      await sendLiveMessage(
        text: 'x',
        launch: (u) async {
          opened = u;
          return true;
        },
        targets: const [
          ShareTarget(name: 'Ravi', chatLinkId: 'L1', chat: true, sms: true, phone: '+919811111111'),
        ],
      );
      expect(opened.toString(), startsWith('sms:+919811111111'));
    });
  });

  group('screens', () {
    late Database raw;
    late AppDatabase db;
    late String pid;

    setUp(() async {
      sqfliteFfiInit();
      raw = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
          options: OpenDatabaseOptions(
              singleInstance: false,
              version: AppDatabase.schemaVersion,
              onCreate: (d, _) => AppDatabase.createSchema(d)));
      db = AppDatabase.forTesting(raw);
      final a = await db.createAccount(phone: '+919876543210', role: 'patient', name: 'A');
      pid = await db.createPatient(
          accountId: a, phone: '+919876543210', displayName: 'Asha Devi',
          baselineLevel: 2, language: 'en', createdBy: 'x');
      await db.recordConsent(
          patientId: pid,
          purposes: {'family_contacts': true, 'caregiver_share': true},
          givenByName: 'A', givenByRelation: 'self', noticeVersion: 'v2');
      await db.addFamilyMember(
          patientId: pid, name: 'Meena', phone: '+919822222222', relation: 'daughter',
          shareLocation: true, by: 'x');
      await db.addFamilyMember(
          patientId: pid, name: 'Gopal', phone: '+919833333333', relation: 'son', by: 'x');
    });
    tearDown(() => raw.close());

    test('the family flag is stored, listed, changeable, and the table is upgraded', () async {
      final fam = await db.listFamily(pid);
      expect([for (final m in fam) m['share_location']], [1, 0]);
      await db.setFamilyShareLocation(pid, fam[1]['id'] as String, true);
      expect([for (final m in await db.listFamily(pid)) m['share_location']], [1, 1]);
      // an older phone: family_members without the column gets it
      final old = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
          options: OpenDatabaseOptions(singleInstance: false));
      await old.execute('CREATE TABLE family_members(id TEXT PRIMARY KEY, name TEXT)');
      await old.insert('family_members', {'id': 'a', 'name': 'Old'});
      await AppDatabase.upgradeSchema(old, 12);
      expect((await old.query('family_members')).single['share_location'], 0);
      await old.close();
    });

    test('candidates: flagged family only is ticked, caregivers go by chat', () async {
      await db.addCareInvite(
          patientId: pid, kind: 'caregiver', name: 'Ravi', professionalId: 'CG-AB23XY',
          phone: '+919811111111', by: 'x');
      final links = await db.listCareLinks(pid);
      await raw.update('care_links', {'status': 'accepted', 'server_link_id': 'L9'},
          where: 'id = ?', whereArgs: [links.single['id']]);
      final c = await loadShareCandidates(db, pid);
      expect([for (final t in c) t.name], ['Ravi', 'Meena', 'Gopal']);
      expect([for (final t in c) t.chat], [true, false, false]);
      expect([for (final t in c) t.sms], [false, true, false]);
      expect(c.first.chatLinkId, 'L9');
    });

    Widget host(LiveShareController ctl, Server srv, {List<Uri>? opened}) => MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: Builder(
              builder: (c) => Column(children: [
                LiveLocationCard(
                    controller: ctl,
                    lang: 'en',
                    onShare: () => showLiveShareSheet(c,
                        db: db,
                        patientId: pid,
                        name: 'Asha Devi',
                        lang: 'en',
                        controller: ctl,
                        api: apiFor(srv),
                        launch: (u) async {
                          opened?.add(u);
                          return true;
                        })),
              ]),
            ),
          ),
        );

    testWidgets('card -> sheet -> start: SMS to the flagged family, card shows Stop', (t) async {
      await t.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final srv = Server();
      final ctl = LiveShareController(provider: FakeLocation(), api: apiFor(srv));
      final opened = <Uri>[];
      await t.pumpWidget(host(ctl, srv, opened: opened));
      expect(find.text('Share my live location'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('liveCardOff')));
      await t.pump();
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await t.pump(const Duration(milliseconds: 400));
      // only the ticked family member is selected
      expect(t.widget<CheckboxListTile>(find.byKey(const ValueKey('target_0'))).value, isTrue);
      expect(t.widget<CheckboxListTile>(find.byKey(const ValueKey('target_1'))).value, isFalse);
      await t.tap(find.byKey(const ValueKey('startShare')));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await t.pump(const Duration(milliseconds: 400));
      expect(opened.single.toString(), contains('+919822222222'));
      expect(opened.single.toString(), isNot(contains('+919833333333')));
      expect(opened.single.toString(), contains(Uri.encodeComponent('https://api.example.com/live/TOKEN123')));
      expect(ctl.active, isTrue);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('liveCardOn')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('liveStop')));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump();
      expect(find.byKey(const ValueKey('liveCardOff')), findsOneWidget);
      ctl.dispose();
    });

    testWidgets('permission refused: the reason is shown and nothing is sent', (t) async {
      await t.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final srv = Server();
      final ctl = LiveShareController(
          provider: FakeLocation(access: LocationAccess.deniedForever), api: apiFor(srv));
      final opened = <Uri>[];
      await t.pumpWidget(host(ctl, srv, opened: opened));
      await t.tap(find.byKey(const ValueKey('liveCardOff')));
      await t.pump();
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.byKey(const ValueKey('startShare')));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('liveProblem')), findsOneWidget);
      expect(find.textContaining('blocked'), findsOneWidget);
      expect(opened, isEmpty);
      expect(srv.calls, isEmpty);
    });

    testWidgets('with nobody to send to the button stays off and says why', (t) async {
      await t.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final lone = (await t.runAsync(() async {
        final a = await db.createAccount(phone: '+919000000001', role: 'patient', name: 'B');
        return db.createPatient(
            accountId: a, phone: '+919000000001', displayName: 'Bina',
            baselineLevel: 2, language: 'en', createdBy: 'x');
      }))!;
      final ctl = LiveShareController(provider: FakeLocation());
      await t.pumpWidget(MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
              body: Builder(
                  builder: (c) => TextButton(
                      onPressed: () => showLiveShareSheet(c,
                          db: db, patientId: lone, name: 'Bina', lang: 'en', controller: ctl),
                      child: const Text('open'))))));
      await t.tap(find.text('open'));
      await t.pump();
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('Nobody to send to yet'), findsOneWidget);
      expect(t.widget<FilledButton>(find.byKey(const ValueKey('startShare'))).onPressed, isNull);
    });
  });
}
