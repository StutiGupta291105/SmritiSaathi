import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti_assist/data/app_database.dart';
import 'package:smriti_assist/features/companion/chat_screen.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smriti_assist/services/api_client.dart';
import 'package:smriti_assist/services/companion_service.dart';
import 'package:smriti_assist/services/speech_input.dart';
import 'package:smriti_assist/services/voice.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A service whose online AI fails, the way a bad key or a busy provider does.
/// A pretend microphone: [say] delivers words as if the person had spoken.
class _FakeSpeech implements SpeechInput {
  _FakeSpeech([this.result = SpeechStart.listening]);
  SpeechStart result;
  String? lang;
  bool _on = false;
  void Function(String, bool)? _onText;
  void Function()? _onEnd;
  @override
  bool get listening => _on;
  @override
  Future<SpeechStart> start(String l,
      {required void Function(String, bool) onText, required void Function() onEnd}) async {
    lang = l;
    _onText = onText;
    _onEnd = onEnd;
    _on = result == SpeechStart.listening;
    return result;
  }

  void say(String words, {bool done = false}) {
    _onText?.call(words, done);
    if (done) _on = false;
  }

  void silence() => _onEnd?.call();
  @override
  Future<void> stop() async => _on = false;
}

class _FailingAi extends CompanionService {
  _FailingAi(AppDatabase db) : super(db: db);
  @override
  Future<CompanionReply> ask({
    required String patientId,
    required String lang,
    required String firstName,
    required List<ChatTurn> history,
    required String text,
    Future<void> Function()? syncNow,
  }) async =>
      const CompanionReply('I can tell you the day.', offline: true, why: '503 companion_unavailable');
}

void main() {
  late Database raw;
  late AppDatabase db;

  setUp(() async {
    sqfliteFfiInit();
    raw = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(
            singleInstance: false,
            version: AppDatabase.schemaVersion,
            onCreate: (d, _) => AppDatabase.createSchema(d)));
    db = AppDatabase.forTesting(raw);
  });

  Widget app() => MaterialApp(
          home: ChatScreen(
        service: CompanionService(db: db, clock: () => DateTime(2026, 3, 10, 10, 30)),
        voice: Voice(),
        db: db,
        patientId: 'p',
        name: 'Asha Devi',
        lang: 'en',
        voiceEnabled: false,
      ));

  testWidgets('greets, answers the day button, and shows the helper note', (t) async {
    await t.pumpWidget(app());
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump();
    expect(find.textContaining('not a person, doctor or lawyer'), findsOneWidget);
    expect(find.textContaining('I am Smriti'), findsOneWidget);
    await t.tap(find.text('What day is it?'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Today is Tuesday, 10 March 2026'), findsOneWidget);
  });

  testWidgets('an emergency message shows the call button and no network is needed',
      (t) async {
    await t.pumpWidget(app());
    await t.enterText(find.byType(TextField), 'I have chest pain');
    await t.tap(find.byIcon(Icons.send_rounded));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('call 112'), findsOneWidget);
    expect(find.text('Call 112 (emergency)'), findsOneWidget);
  });

  testWidgets('when the online helper fails, the reason is shown under the basic answer', (t) async {
    await t.pumpWidget(MaterialApp(
        home: ChatScreen(
            service: _FailingAi(db), voice: Voice(), db: db, patientId: 'p',
            name: 'Asha Devi', lang: 'en', voiceEnabled: false)));
    await t.pump();
    expect(find.byKey(const ValueKey('chatWhy')), findsNothing);
    await t.enterText(find.byType(TextField), 'I am feeling nausea');
    await t.tap(find.byIcon(Icons.send_rounded));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('I can tell you the day.'), findsOneWidget);
    expect(find.text('Online helper: 503 companion_unavailable'), findsOneWidget);
  });

  testWidgets('the conversation is remembered: date, time, continuation, clear', (t) async {
    await t.runAsync(() async {
      await db.addCompanionMessage('p',
          fromUser: true, text: 'Old question', at: DateTime(2020, 1, 5, 9, 7));
      await db.addCompanionMessage('p',
          fromUser: false, text: 'Old answer', at: DateTime(2020, 1, 5, 9, 8));
    });
    await t.pumpWidget(app());
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump();
    expect(find.text('Old question'), findsOneWidget);
    expect(find.text('Old answer'), findsOneWidget);
    expect(find.text('5 Jan 2020'), findsOneWidget);
    expect(find.text('09:07'), findsOneWidget);
    expect(find.textContaining('I am Smriti'), findsNothing); // not a fresh chat
    // A new message continues the same thread and is saved.
    await t.tap(find.text('What day is it?'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Today'), findsOneWidget);
    final rows = await t.runAsync(() => db.companionMessages('p'));
    expect(rows!.length, 4);
    // Clear history after confirming.
    await t.tap(find.byType(PopupMenuButton<String>));
    await t.pumpAndSettle();
    await t.tap(find.text('Clear chat history'));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump();
    expect(find.text('Old question'), findsNothing);
    expect((await t.runAsync(() => db.companionMessages('p')))!, isEmpty);
  });

  testWidgets('an AI answer can be reported; the greeting cannot', (t) async {
    final sent = <Map<String, dynamic>>[];
    final api = ApiClient(
        baseUrl: 'https://api.example.com',
        tokens: MemoryTokenStore(),
        client: MockClient((r) async {
          if (r.url.path == '/v1/reports') sent.add(jsonDecode(r.body) as Map<String, dynamic>);
          return http.Response('{"ok":true}', 201, headers: {'content-type': 'application/json'});
        }));
    await t.pumpWidget(MaterialApp(
        home: ChatScreen(
      service: CompanionService(db: db, api: api, clock: () => DateTime(2026, 3, 10, 10, 30)),
      voice: Voice(), db: db, patientId: 'p', name: 'Asha Devi', lang: 'en', voiceEnabled: false,
    )));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump();
    expect(find.byTooltip('Report this answer'), findsNothing); // greeting only
    await t.tap(find.text('What day is it?'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byTooltip('Report this answer'), findsOneWidget);
    await t.tap(find.byTooltip('Report this answer'));
    await t.pumpAndSettle();
    await t.tap(find.text('Send'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump(const Duration(milliseconds: 300));
    expect(sent.single['kind'], 'ai');
    expect(sent.single['excerpt'], contains('Today is Tuesday'));
    expect(find.text('Thank you. We will review it.'), findsOneWidget);
  });

  Future<void> phone(WidgetTester t) async {
    // tall enough for the big microphone (the screen hides it on short screens)
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  Widget withSpeech(_FakeSpeech sp, {String lang = 'en'}) => MaterialApp(
          home: ChatScreen(
        service: CompanionService(db: db, clock: () => DateTime(2026, 3, 10, 10, 30)),
        voice: Voice(), db: db, patientId: 'p', name: 'Asha Devi', lang: lang, voiceEnabled: false,
        speech: sp,
      ));

  testWidgets('the microphone listens, shows the words, and sends them when speaking ends', (t) async {
    await phone(t);
    final sp = _FakeSpeech();
    await t.pumpWidget(withSpeech(sp));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump();
    expect(find.text('Tap to speak'), findsWidgets);
    await t.tap(find.byKey(const ValueKey('micButton')));
    await t.pump();
    expect(sp.lang, 'en');
    expect(find.text('Listening… speak now'), findsOneWidget);
    sp.say('what day is it'); // partial words appear in the box
    await t.pump();
    expect(find.widgetWithText(TextField, 'what day is it'), findsOneWidget);
    sp.say('what day is it', done: true); // the last words: it is sent by itself
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('what day is it'), findsWidgets);
    expect(find.text('Listening… speak now'), findsNothing);
  });

  testWidgets('the small microphone in the text box works too, and tapping again stops', (t) async {
    await phone(t);
    final sp = _FakeSpeech();
    await t.pumpWidget(withSpeech(sp));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('micSmall')));
    await t.pump();
    expect(sp.listening, isTrue);
    await t.tap(find.byKey(const ValueKey('micSmall')));
    await t.pump();
    expect(sp.listening, isFalse);
    expect(find.text('Listening… speak now'), findsNothing);
  });

  testWidgets('a refused microphone says so and offers Settings; no recogniser says to use the keyboard', (t) async {
    await phone(t);
    final denied = _FakeSpeech(SpeechStart.denied);
    await t.pumpWidget(withSpeech(denied));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('micButton')));
    await t.pump();
    expect(find.text('Allow the microphone to send voice messages.'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    final none = _FakeSpeech(SpeechStart.unavailable);
    await t.pumpWidget(withSpeech(none));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('micButton')));
    await t.pump();
    expect(find.textContaining('Voice typing is not available'), findsOneWidget);
  });

  testWidgets('it listens in the person\'s language', (t) async {
    await phone(t);
    final sp = _FakeSpeech();
    await t.pumpWidget(withSpeech(sp, lang: 'hi'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('micButton')));
    await t.pump();
    expect(sp.lang, 'hi');
  });
}
