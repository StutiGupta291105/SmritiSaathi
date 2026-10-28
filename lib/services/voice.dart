import 'package:flutter_tts/flutter_tts.dart';

/// Spoken instructions using the phone's own text-to-speech engine. We send no
/// text to any service ourselves. Voice availability depends on the voices the
/// device has installed (Hindi may need a one-time voice download). Failures
/// are swallowed: the on-screen text is always the primary instruction.
class Voice {
  final _tts = FlutterTts();
  static const _locales = {'en': 'en-IN', 'hi': 'hi-IN'};

  Future<void> speak(String text, String lang, {required bool enabled}) async {
    if (!enabled) return;
    try {
      await _tts.setLanguage(_locales[lang] ?? 'en-IN');
      await _tts.setSpeechRate(0.4); // slower than default for older listeners
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
