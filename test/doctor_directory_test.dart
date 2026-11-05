import 'dart:convert';

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smriti_assist/features/chat/doctor_directory_screen.dart';
import 'package:smriti_assist/features/chat/messages_screen.dart';
import 'package:smriti_assist/services/api_client.dart';
import 'package:smriti_assist/services/voice_notes.dart';

http.Response _j(int s, Object b) =>
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

void main() {
  late List<String> calls;
  late bool online;

  ApiClient api() => ApiClient(
      baseUrl: 'https://api.example.com',
      tokens: MemoryTokenStore(),
      client: MockClient((r) async {
        calls.add('${r.method} ${r.url.path}');
        if (!online) throw http.ClientException('no signal');
        final p = r.url.path;
        if (p == '/v1/chat/doctors') {
          return _j(200, [
            {'doctor_id': 'd1', 'name': 'Dr Asha Rao', 'verified': true, 'pinned': true, 'thread_id': 'L1'},
            {'doctor_id': 'd2', 'name': 'Dr Vikram Sen', 'verified': true, 'pinned': false, 'thread_id': null},
            {'doctor_id': 'd3', 'name': 'Dr Meera Pal', 'verified': false, 'pinned': false, 'thread_id': 'C9'},
          ]);
        }
        if (p == '/v1/chat/threads') {
          return _j(200, [
            {'link_id': 'L1', 'kind': 'care', 'unread': 2, 'member_role': 'doctor'},
          ]);
        }
        if (p == '/v1/chat/opinion') return _j(200, {'thread_id': 'C1', 'kind': 'opinion'});
        if (p.endsWith('/messages')) return _j(200, <Object>[]);
        return _j(404, {'detail': 'x'});
      }));

  setUp(() {
    calls = [];
    online = true;
  });

  Future<void> open(WidgetTester t) async {
    t.view.physicalSize = const Size(800, 1800);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
        home: DoctorDirectoryScreen(
            api: api(), lang: 'en', pollEvery: const Duration(hours: 1),
            recorder: _Voice(), player: _Player())));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pump();
    await t.pump();
  }

  testWidgets('the doctor the patient is under is pinned on top, others below', (t) async {
    await open(t);
    expect(find.text('Your doctor'), findsOneWidget);
    expect(find.text('Other doctors on Smriti Sathi'), findsOneWidget);
    final y = (String n) => t.getTopLeft(find.text(n)).dy;
    expect(y('Dr Asha Rao'), lessThan(y('Dr Vikram Sen')));
    expect(find.text('Dr Meera Pal'), findsOneWidget);
    expect(find.byIcon(Icons.push_pin_rounded), findsNothing,
        reason: 'the pinned row shows its unread count instead');
    expect(find.text('2'), findsOneWidget); // unread from the pinned doctor
    expect(find.textContaining('cannot see'), findsNothing);
    expect(find.textContaining('not your reports'), findsOneWidget); // privacy note
  });

  testWidgets('search narrows the other doctors but never hides the pinned one', (t) async {
    await open(t);
    await t.enterText(find.byKey(const ValueKey('doctorSearch')), 'vik');
    await t.pump();
    expect(find.text('Dr Vikram Sen'), findsOneWidget);
    expect(find.text('Dr Meera Pal'), findsNothing);
    expect(find.text('Dr Asha Rao'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('doctorSearch')), 'zzz');
    await t.pump();
    expect(find.text('No doctors have joined the app yet.'), findsOneWidget);
  });

  testWidgets('asking a new doctor opens an opinion chat; the pinned doctor opens the care chat', (t) async {
    await open(t);
    await t.tap(find.byKey(const ValueKey('doctor_d2')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pump();
    await t.pump();
    expect(calls, contains('POST /v1/chat/opinion'));
    expect(find.byType(MessagesScreen), findsOneWidget);
    expect(find.text('Dr Vikram Sen'), findsWidgets);
    expect(calls.any((c) => c.contains('/v1/chat/C1/messages')), isTrue);
    await t.pageBack();
    await t.pumpAndSettle();
    calls.clear();
    await t.tap(find.byKey(const ValueKey('doctor_d1')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pump();
    await t.pump();
    expect(calls, isNot(contains('POST /v1/chat/opinion')), reason: 'a thread already exists');
    expect(calls.any((c) => c.contains('/v1/chat/L1/messages')), isTrue);
  });

  testWidgets('offline: an existing chat opens but a new one says it needs internet', (t) async {
    await open(t);
    online = false;
    await t.tap(find.byKey(const ValueKey('doctor_d2')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pump();
    await t.pump();
    expect(find.text('Messages need an internet connection.'), findsOneWidget);
    expect(find.byType(MessagesScreen), findsNothing);
  });

  testWidgets('with no connection and nothing saved, a refresh button is shown', (t) async {
    online = false;
    await open(t);
    expect(find.byKey(const ValueKey('doctorsRetry')), findsOneWidget);
    online = true;
    await t.tap(find.byKey(const ValueKey('doctorsRetry')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pump();
    await t.pump();
    expect(find.text('Dr Asha Rao'), findsOneWidget);
  });
}
