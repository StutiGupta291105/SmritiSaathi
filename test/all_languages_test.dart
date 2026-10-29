import 'package:flutter_test/flutter_test.dart';
import 'package:smriti_assist/core/companion_offline.dart';
import 'package:smriti_assist/core/content.dart';
import 'package:smriti_assist/core/dates.dart';
import 'package:smriti_assist/core/languages.dart';
import 'package:smriti_assist/core/safety_data.dart';
import 'package:smriti_assist/core/strings.dart';

void main() {
  test('English plus the 22 Eighth Schedule languages', () {
    expect(kLanguages.length, 23);
    expect(kLanguageOrder.toSet(), kLanguages.keys.toSet());
    expect(kLanguageEnglish.keys.toSet(), kLanguages.keys.toSet());
    expect(kTtsLocales.keys.toSet(), kLanguages.keys.toSet());
    for (final code in [
      'hi', 'bn', 'te', 'mr', 'ta', 'ur', 'gu', 'kn', 'ml', 'or', 'pa', 'as',
      'mai', 'sat', 'ks', 'ne', 'kok', 'mni', 'brx', 'doi', 'sd', 'sa'
    ]) {
      expect(kLanguages.containsKey(code), isTrue, reason: code);
    }
    expect(kRtl, {'ur', 'ks', 'sd'});
  });

  test('every language can name today, the weekdays and the game pictures', () {
    final now = DateTime(2026, 3, 10, 9, 5); // a Tuesday
    for (final code in kLanguages.keys) {
      final day = dayAnswer(code, now);
      expect(day.contains('{'), isFalse, reason: '$code day sentence');
      expect(day.contains('2026'), isTrue, reason: code);
      expect(day.contains('09:05'), isTrue, reason: code);
      for (final w in [1, 7]) {
        expect(weekdayShort(code, w).trim(), isNotEmpty, reason: code);
      }
      for (final item in kObjects) {
        expect(item.label(code).trim(), isNotEmpty, reason: '$code/${item.en}');
      }
      for (final r in kRoutines) {
        expect(r.title(code).trim(), isNotEmpty, reason: code);
        for (final step in r.steps) {
          expect(step.label(code).trim(), isNotEmpty, reason: '$code/${step.en}');
        }
      }
      expect(niceThing(code, 1).trim(), isNotEmpty, reason: code);
    }
  });

  test('new languages show their own words for pictures, not English', () {
    for (final code in kLanguages.keys.where((c) => !{'en', 'hi', 'bn', 'as'}.contains(c))) {
      final same = [for (final i in kObjects) if (i.label(code) == i.en) i.en];
      expect(same, isEmpty, reason: '$code left pictures in English: $same');
    }
  });

  test('every language recognises an emergency and answers with 112', () {
    for (final code in kLanguages.keys) {
      expect(emergencyWords[code], isNotNull, reason: code);
      expect(emergencyWords[code]!.length, greaterThanOrEqualTo(6), reason: code);
      expect(isEmergencyText(emergencyWords[code]!.first, code), isTrue, reason: code);
      expect(isEmergencyText('chest pain', code), isTrue, reason: '$code English words');
      // Bengali and Assamese write the number in their own digits.
      expect(RegExp('112|११२|১১২').hasMatch(emergencyText(code)), isTrue, reason: code);
      expect(isEmergencyText('what is the weather', code), isFalse, reason: code);
    }
  });

  test('language tables cover every code the app can switch to', () {
    for (final code in kLanguages.keys) {
      expect(kStrings[code], isNotNull, reason: code);
      expect(tr(code, 'appName').trim(), isNotEmpty, reason: code);
    }
    expect(nextLanguage('sa'), 'en');
    expect(nextLanguage('en'), 'hi');
  });
}
