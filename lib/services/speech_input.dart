import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../core/languages.dart';

/// Why speaking could not start.
enum SpeechStart { listening, denied, unavailable }

/// Turns speech into text for "Talk to Smriti". A small interface so tests can use a fake.
abstract class SpeechInput {
  /// Starts listening in [lang] (an app language code). [onText] gets the words so far;
  /// [done] is true for the last piece. [onEnd] is called when listening stops by itself.
  Future<SpeechStart> start(
    String lang, {
    required void Function(String text, bool done) onText,
    required void Function() onEnd,
  });
  Future<void> stop();
  bool get listening;
}

/// The phone's own speech recognition (Android: the Google speech service, which also works
/// offline when the language has been downloaded; iOS: Siri's). The microphone permission
/// is not asked for here, only checked: it was asked once, after sign-up, and a refusal is
/// explained with a Settings button.
class DeviceSpeechInput implements SpeechInput {
  final stt.SpeechToText _stt = stt.SpeechToText();
  bool _ready = false;
  void Function()? _onEnd;

  @override
  bool get listening => _stt.isListening;

  Future<String?> _localeFor(String lang) async {
    try {
      final have = await _stt.locales();
      final ids = {for (final l in have) l.localeId.replaceAll('_', '-'): l.localeId};
      for (final want in kTtsLocales[lang] ?? const ['en-IN']) {
        if (ids.containsKey(want)) return ids[want];
      }
      // Same language, any region (e.g. hi-IN wanted, hi_IN not listed but hi-... is).
      for (final e in ids.entries) {
        if (e.key.split('-').first == lang) return e.value;
      }
    } catch (_) {}
    return null; // the phone's own language
  }

  @override
  Future<SpeechStart> start(
    String lang, {
    required void Function(String text, bool done) onText,
    required void Function() onEnd,
  }) async {
    if (!await ph.Permission.microphone.isGranted) return SpeechStart.denied;
    try {
      if (!_ready) {
        _ready = await _stt.initialize(
          onStatus: (s) {
            if (s == 'done' || s == 'notListening') _onEnd?.call();
          },
          onError: (_) => _onEnd?.call(),
        );
      }
      if (!_ready) return SpeechStart.unavailable;
      _onEnd = onEnd;
      final locale = await _localeFor(lang);
      await _stt.listen(
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: stt.ListenMode.dictation,
          localeId: locale,
          pauseFor: const Duration(seconds: 3),
          listenFor: const Duration(seconds: 40),
        ),
        onResult: (r) => onText(r.recognizedWords, r.finalResult),
      );
      return SpeechStart.listening;
    } catch (_) {
      return SpeechStart.unavailable;
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _stt.stop();
    } catch (_) {}
  }
}
