import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smriti_assist/features/chat/messages_screen.dart';
import 'package:smriti_assist/features/remote/remote_home.dart';
import 'package:smriti_assist/services/api_client.dart';
import 'package:smriti_assist/services/voice_notes.dart';

http.Response _j(Object b, [int s = 200]) =>
    http.Response(jsonEncode(b), s, headers: {'content-type': 'application/json'});

final _jpeg = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==');

/// A pretend chat server: keeps the messages in a list.
class _Server {
  final msgs = <Map<String, dynamic>>[];
  final sent = <Map<String, dynamic>>[];
  var reads = <int>[];
  var nextId = 1;
  var offline = false;
  var threads = <Map<String, dynamic>>[
    {
      'link_id': 'L1',
      'patient_id': 'p1',
      'patient_name': 'Asha Devi',
      'member_role': 'caretaker',
      'member_name': 'Ravi',
      'member_phone': null,
      'unread': 0,
      'last_at': null,
      'last_kind': null
    }
  ];

  Map<String, dynamic> theirs(String text, {String kind = 'text'}) {
    final m = {
      'id': nextId++,
      'sender_id': 'other',
      'mine': false,
      'kind': kind,
      'text': text,
      'mime': kind == 'voice' ? 'audio/mp4' : kind == 'image' ? 'image/jpeg' : '',
      'duration_ms': kind == 'voice' ? 4000 : 0,
      'has_media': kind != 'text',
      'created_at': '2026-10-29T10:00:00',
      'read': false
    };
    msgs.add(m);
    return m;
  }

  ApiClient api() => ApiClient(
      baseUrl: 'https://api.example.com',
      tokens: MemoryTokenStore(),
      client: MockClient(handle));

  Future<http.Response> handle(http.Request r) async {
        if (offline) throw http.ClientException('offline');
        final p = r.url.path;
        if (p == '/v1/chat/threads') return _j(threads);
        if (p == '/v1/chat/L1/messages' && r.method == 'GET') {
          final after = int.tryParse(r.url.queryParameters['after'] ?? '') ?? 0;
          return _j([for (final m in msgs) if ((m['id'] as int) > after) m]);
        }
        if (p == '/v1/chat/L1/messages' && r.method == 'POST') {
          final b = jsonDecode(r.body) as Map<String, dynamic>;
          sent.add(b);
          final m = {
            'id': nextId++,
            'sender_id': 'me',
            'mine': true,
            'kind': b['kind'],
            'text': b['text'],
            'mime': b['mime'],
            'duration_ms': b['duration_ms'],
            'has_media': b['media_b64'] != null,
            'created_at': '2026-10-29T10:01:00',
            'read': false
          };
          msgs.add(m);
          return _j(m, 201);
        }
        if (p == '/v1/chat/L1/read') {
          reads.add((jsonDecode(r.body) as Map)['upto'] as int);
          return http.Response('', 204);
        }
        if (p.startsWith('/v1/chat/media/')) return http.Response.bytes(_jpeg, 200);
        return _j({'detail': 'x'}, 404);
  }
}

class _FakeRecorder implements VoiceRecorder {
  var allowed = true;
  var started = false;
  @override
  Future<bool> start() async => started = allowed;
  @override
  Future<RecordedNote?> stop() async =>
      RecordedNote(Uint8List.fromList([1, 2, 3, 4]), 3200);
  @override
  Future<void> cancel() async => started = false;
}

class _FakePlayer implements VoicePlayer {
  final played = <int>[];
  final _done = StreamController<void>.broadcast();
  @override
  Future<void> play(Uint8List bytes, String mime) async => played.add(bytes.length);
  @override
  Future<void> stop() async {}
  @override
  Stream<void> get onFinished => _done.stream;
  @override
  void dispose() => _done.close();
}

Widget _app(_Server s,
        {_FakeRecorder? rec,
        _FakePlayer? player,
        Future<Uint8List?> Function(BuildContext, String)? photo,
        String? phone}) =>
    MaterialApp(
        home: MessagesScreen(
      api: s.api(),
      linkId: 'L1',
      title: 'Ravi',
      lang: 'en',
      callPhone: phone,
      recorder: rec ?? _FakeRecorder(),
      player: player ?? _FakePlayer(),
      pickPhoto: photo ?? (_, __) async => _jpeg,
      pollEvery: const Duration(milliseconds: 200),
    ));

void main() {
  testWidgets('shows the history, sends text, and marks theirs as read', (t) async {
    final s = _Server()..theirs('How are you today?');
    await t.pumpWidget(_app(s));
    await t.pumpAndSettle();
    expect(find.text('How are you today?'), findsOneWidget);
    expect(s.reads, [1]);
    await t.enterText(find.byKey(const ValueKey('chatInput')), 'I am fine');
    await t.pump();
    await t.tap(find.byKey(const ValueKey('sendText')));
    await t.pumpAndSettle();
    expect(find.text('I am fine'), findsOneWidget);
    expect(s.sent.single['kind'], 'text');
    expect(s.sent.single['text'], 'I am fine');
    // an empty box offers the microphone instead of send
    expect(find.byKey(const ValueKey('recordVoice')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('new messages arrive without leaving the screen', (t) async {
    final s = _Server();
    await t.pumpWidget(_app(s));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('noMessages')), findsOneWidget);
    s.theirs('Are you there?');
    await t.pump(const Duration(milliseconds: 300));
    await t.pumpAndSettle();
    expect(find.text('Are you there?'), findsOneWidget);
    expect(s.reads, [1]);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('sends a photo', (t) async {
    final s = _Server();
    await t.pumpWidget(_app(s));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('attachPhoto')));
    await t.pumpAndSettle();
    final b = s.sent.single;
    expect(b['kind'], 'image');
    expect(b['mime'], 'image/png'); // detected from the bytes
    expect(base64Decode(b['media_b64'] as String), _jpeg);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('records and sends a voice note, and plays one received', (t) async {
    final s = _Server();
    final rec = _FakeRecorder();
    final player = _FakePlayer();
    await t.pumpWidget(_app(s, rec: rec, player: player));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('recordVoice')));
    await t.pump();
    expect(rec.started, isTrue);
    expect(find.textContaining('Recording'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('sendVoice')));
    await t.pumpAndSettle();
    final b = s.sent.single;
    expect([b['kind'], b['mime'], b['duration_ms']], ['voice', 'audio/mp4', 3200]);
    expect(find.textContaining('Voice message'), findsOneWidget);

    final id = s.theirs('', kind: 'voice')['id'];
    await t.pump(const Duration(milliseconds: 300));
    await t.pumpAndSettle();
    await t.tap(find.byKey(ValueKey('play_$id')));
    await t.pumpAndSettle();
    expect(player.played, [_jpeg.length]); // the mock server returns the same bytes
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('cancelling a recording sends nothing; a denied microphone is explained', (t) async {
    final s = _Server();
    final rec = _FakeRecorder();
    await t.pumpWidget(_app(s, rec: rec));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('recordVoice')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('cancelVoice')));
    await t.pumpAndSettle();
    expect(s.sent, isEmpty);
    expect(find.byKey(const ValueKey('recordVoice')), findsOneWidget);
    rec.allowed = false;
    await t.tap(find.byKey(const ValueKey('recordVoice')));
    await t.pump();
    expect(find.text('Allow the microphone to send voice messages.'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a failed send is explained and the text is kept', (t) async {
    final s = _Server();
    await t.pumpWidget(_app(s));
    await t.pumpAndSettle();
    s.offline = true;
    await t.enterText(find.byKey(const ValueKey('chatInput')), 'hello');
    await t.pump();
    await t.tap(find.byKey(const ValueKey('sendText')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(find.text('Messages need an internet connection.'), findsOneWidget);
    expect(find.text('hello'), findsOneWidget); // back in the box
    expect(s.sent, isEmpty);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a call button appears only when a number was shared', (t) async {
    final s = _Server();
    await t.pumpWidget(_app(s));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('callThem')), findsNothing);
    await t.pumpWidget(_app(s, phone: '+919812345678'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('callThem')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('caregiver dashboard lists conversations with unread, and opens one', (t) async {
    final s = _Server();
    s.threads[0]['unread'] = 2;
    s.threads[0]['last_kind'] = 'voice';
    s.threads[0]['last_at'] = '2026-10-29T10:00:00';
    s.theirs('Please call me');
    final api = ApiClient(
        baseUrl: 'https://api.example.com',
        tokens: MemoryTokenStore(),
        client: MockClient((r) async {
          final p = r.url.path;
          if (p == '/v1/invites') return _j([]);
          if (p == '/v1/my-patients') {
            return _j([
              {'patient_id': 'p1', 'display_name': 'Asha Devi', 'alerts_needing_attention': 0}
            ]);
          }
          return s.handle(r);
        }));
    await t.pumpWidget(MaterialApp(
        home: RemoteHome(
            api: api,
            user: const ServerUser('u', 'caretaker', 'Ravi'),
            lang: 'en',
            onLogout: () {})));
    await t.pumpAndSettle();
    expect(find.text('Messages'), findsWidgets);
    expect(find.byKey(const ValueKey('thread_L1')), findsOneWidget);
    expect(find.text('2'), findsWidgets); // unread badge
    await t.tap(find.byKey(const ValueKey('thread_L1')));
    await t.pumpAndSettle();
    expect(find.text('Please call me'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
