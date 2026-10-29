import 'package:flutter_test/flutter_test.dart';
import 'package:smriti_assist/core/content.dart';
import 'package:smriti_assist/core/languages.dart';
import 'package:smriti_assist/core/strings.dart';

final _placeholders = RegExp(r'\{[ab]\}');

void main() {
  test('every language has exactly the same texts as English', () {
    final en = kStrings['en']!;
    for (final code in kLanguages.keys) {
      final m = kStrings[code];
      expect(m, isNotNull, reason: code);
      expect(en.keys.toSet().difference(m!.keys.toSet()), isEmpty,
          reason: '$code is missing texts');
      expect(m.keys.toSet().difference(en.keys.toSet()), isEmpty,
          reason: '$code has texts English lacks');
    }
  });

  test('placeholders survive translation, and no text is empty', () {
    final en = kStrings['en']!;
    for (final code in kLanguages.keys) {
      kStrings[code]!.forEach((k, v) {
        expect(v.trim(), isNotEmpty, reason: '$code/$k');
        expect(_placeholders.allMatches(v).map((m) => m[0]).toList()..sort(),
            _placeholders.allMatches(en[k]!).map((m) => m[0]).toList()..sort(),
            reason: '$code/$k placeholders');
      });
    }
  });

  test('translated texts differ from English except for names and numbers', () {
    final en = kStrings['en']!;
    for (final code in kLanguages.keys.where((c) => c != 'en')) {
      final same = [
        for (final k in en.keys)
          if (kStrings[code]![k] == en[k]) k
      ];
      expect(same.length, lessThan(8), reason: '$code left untranslated: $same');
    }
  });

  test('tr falls back to English, then to the key', () {
    expect(tr('xx', 'login'), 'Log in');
    expect(tr('bn', 'no_such_key'), 'no_such_key');
    expect(tr('as', 'login'), isNot('Log in'));
  });

  test('every language has a spoken-voice plan and the switch cycles through all', () {
    for (final c in kLanguages.keys) {
      expect(kTtsLocales[c], isNotEmpty);
    }
    var l = 'en';
    final seen = <String>[];
    for (var i = 0; i < kLanguages.length; i++) {
      seen.add(l);
      l = nextLanguage(l);
    }
    expect(seen.toSet(), kLanguages.keys.toSet());
    expect(l, 'en');
  });

  test('all game content is translated in every language', () {
    final items = [
      ...kObjects,
      for (final p in kLookAlikes) ...[p.$1, p.$2],
      for (final r in kRoutines) ...r.steps,
    ];
    for (final i in items) {
      for (final code in kLanguages.keys) {
        expect(i.label(code).trim(), isNotEmpty, reason: '${i.en} / $code');
      }
      expect(i.label('bn'), isNot(i.en), reason: '${i.en} bn');
    }
    for (final r in kRoutines) {
      for (final code in kLanguages.keys) {
        expect(r.title(code).trim(), isNotEmpty);
      }
    }
  });
}
