import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smriti_assist/data/app_database.dart';
import 'package:smriti_assist/services/api_client.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

http.Response _j(int s, Object b) =>
    http.Response(jsonEncode(b), s, headers: {'content-type': 'application/json'});

/// A server that can be switched off: when [up] is false every call fails the way
/// a phone with no signal does.
class _Net {
  bool up = true;
  final sent = <Map<String, dynamic>>[];
  final calls = <String>[];
  int nextId = 100;
  int refuse = 0; // answer 403 this many times
  bool revoked = false; // the patient withdrew sharing

  Future<http.Response> handle(http.Request r) async {
    calls.add('${r.method} ${r.url.path}');
    if (!up) throw http.ClientException('no route to host');
    final p = r.url.path;
    if (p == '/v1/my-patients') {
      return _j(200, [{'patient_id': 'p1', 'display_name': 'Asha'}]);
    }
    if (p == '/v1/patients/p1/report') {
      return revoked ? _j(404, {'detail': 'not_found'}) : _j(200, {'games_played': 4});
    }
    if (p == '/v1/chat/threads') return _j(200, [{'link_id': 'l1'}]);
    if (p == '/v1/chat/l1/messages' && r.method == 'GET') {
      return _j(200, [for (final m in sent) m]);
    }
    if (p == '/v1/chat/l1/messages' && r.method == 'POST') {
      if (refuse > 0) {
        refuse--;
        return _j(403, {'detail': 'link_ended'});
      }
      final b = jsonDecode(r.body) as Map<String, dynamic>;
      final m = {'id': nextId++, 'kind': b['kind'], 'text': b['text'], 'mine': true};
      sent.add(m);
      return _j(201, m);
    }
    return _j(404, {'detail': 'x'});
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

  test('a read that worked is shown again, marked as saved, when the network is gone', () async {
    expect((await api.myPatients()).single['display_name'], 'Asha');
    expect(api.staleSince.value, isNull);
    expect(api.online.value, isTrue);
    net.up = false;
    expect((await api.myPatients()).single['display_name'], 'Asha'); // from the phone
    expect(api.online.value, isFalse);
    expect(api.staleSince.value, isNotNull);
    await expectLater(api.report('p1', 7), throwsA(isA<ApiException>())); // never fetched: nothing saved
  });

  test('a read that was never fetched fails as offline, and live data clears the saved-data marker', () async {
    net.up = false;
    expect(await db.cacheGet('/v1/my-patients'), isNull, reason: 'fresh database');
    await expectLater(api.myPatients(), throwsA(isA<ApiException>().having((e) => e.isNetwork, 'offline', isTrue)));
    net.up = true;
    await api.myPatients();
    net.up = false;
    await api.myPatients();
    expect(api.staleSince.value, isNotNull);
    net.up = true;
    await api.myPatients();
    expect(api.staleSince.value, isNull);
  });

  test('messages written offline wait, keep their order, and go out by themselves once a call gets through', () async {
    net.up = false;
    await api.queueChatMessage('l1', kind: 'text', text: 'first');
    await api.queueChatMessage('l1', kind: 'image', media: Uint8List.fromList([1, 2, 3]), mime: 'image/png');
    await api.queueChatMessage('l1', kind: 'text', text: 'third');
    expect(api.outboxCount.value, 3);
    expect((await api.pendingMessages('l1')).length, 3);
    expect(await api.flushOutbox(), 0); // still offline: nothing lost, nothing sent
    expect(api.outboxCount.value, 3);
    net.up = true;
    await api.myPatients(); // any call that works proves we are back
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(net.sent.map((m) => '${m['kind']}:${m['text']}').toList(), ['text:first', 'image:', 'text:third']);
    expect(api.outboxCount.value, 0);
    expect(await api.pendingMessages(), isEmpty);
  });

  test('a message the server refuses for good is dropped instead of blocking the queue', () async {
    net.up = false;
    await api.queueChatMessage('l1', kind: 'text', text: 'doomed');
    await api.queueChatMessage('l1', kind: 'text', text: 'fine');
    net.up = true;
    net.refuse = 1;
    expect(await api.flushOutbox(), 1);
    expect(net.sent.single['text'], 'fine');
    expect(await api.pendingMessages(), isEmpty);
  });

  test('going offline halfway keeps the rest queued', () async {
    net.up = false;
    for (final t in ['a', 'b', 'c']) {
      await api.queueChatMessage('l1', kind: 'text', text: t);
    }
    net.up = true;
    final flushing = api.flushOutbox();
    await flushing;
    expect(net.sent.length, 3);
    net.up = false;
    await api.queueChatMessage('l1', kind: 'text', text: 'd');
    await api.flushOutbox();
    expect(api.outboxCount.value, 1);
    expect(net.sent.length, 3);
  });

  test('logging out wipes the saved answers and the queue (nothing carries over to the next person)', () async {
    await api.myPatients();
    net.up = false;
    await api.queueChatMessage('l1', kind: 'text', text: 'private');
    await api.logout();
    expect(await db.cacheGet('/v1/my-patients'), isNull);
    expect(await db.outboxList(), isEmpty);
  });

  test('the live message list is saved but the "newer than" poll is not', () async {
    await api.sendChatMessage('l1', kind: 'text', text: 'hi');
    await api.chatMessages('l1');
    await api.chatMessages('l1', after: 100);
    expect(await db.cacheGet('/v1/chat/l1/messages'), isNotNull);
    expect(await db.cacheGet('/v1/chat/l1/messages?after=100'), isNull);
    net.up = false;
    expect((await api.chatMessages('l1')).single['text'], 'hi'); // history readable offline
  });

  test('when access is withdrawn the saved copy is dropped, not shown later', () async {
    expect((await api.report('p1', 7))['games_played'], 4);
    expect(await db.cacheGet('/v1/patients/p1/report?days=7'), isNotNull);
    net.revoked = true;
    await expectLater(api.report('p1', 7), throwsA(isA<ApiException>().having((e) => e.status, 'status', 404)));
    expect(await db.cacheGet('/v1/patients/p1/report?days=7'), isNull);
    net.up = false;
    await expectLater(api.report('p1', 7), throwsA(isA<ApiException>().having((e) => e.isNetwork, 'offline', isTrue)));
  });
}
