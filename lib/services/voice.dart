import 'package:flutter_tts/flutter_tts.dart';

import '../core/languages.dart';

/// Spoken instructions using the phone's own text-to-speech engine. We send no
/// text to any service ourselves. Voice availability depends on the voices the
/// device has installed (Indian-language voices may need a one-time download).
/// If no voice exists for the language the app stays silent rather than reading
/// the text in the wrong accent. Failures are swallowed: the on-screen text is
/// always the primary instruction.
class Voice {
  final _tts = FlutterTts();
  final Map<String, String?> _chosen = {};

  Future<String?> _locale(String lang) async {
    if (_chosen.containsKey(lang)) return _chosen[lang];
    String? found;
    for (final l in kTtsLocales[lang] ?? const ['en-IN']) {
      try {
        final ok = await _tts.isLanguageAvailable(l);
        if (ok == true || ok == 1) {
          found = l;
          break;
        }
      } catch (_) {}
    }
    return _chosen[lang] = found;
  }

  Future<void> speak(String text, String lang, {required bool enabled}) async {
    if (!enabled) return;
    try {
      final locale = await _locale(lang);
      if (locale == null) return;
      await _tts.setLanguage(locale);
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
