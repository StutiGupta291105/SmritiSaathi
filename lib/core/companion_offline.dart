import 'adherence.dart';
import 'languages.dart';
import 'safety_data.dart';
import 'reminder_schedule.dart';
import 'strings.dart';

/// Everything 'Talk to Smriti' can do without internet, a server or an AI
/// service: tell the day and time, say what is next, offer a kind thought, and
/// recognise an emergency. Plain code, so it is fast, predictable and testable.

const _weekdays = {
  'en': ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'],
  'hi': ['सोमवार', 'मंगलवार', 'बुधवार', 'गुरुवार', 'शुक्रवार', 'शनिवार', 'रविवार'],
  'bn': ['সোমবার', 'মঙ্গলবার', 'বুধবার', 'বৃহস্পতিবার', 'শুক্রবার', 'শনিবার', 'রবিবার'],
  'as': ['সোমবাৰ', 'মঙলবাৰ', 'বুধবাৰ', 'বৃহস্পতিবাৰ', 'শুকুৰবাৰ', 'শনিবাৰ', 'ৰবিবাৰ'],
};

const _months = {
  'en': ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
    'September', 'October', 'November', 'December'],
  'hi': ['जनवरी', 'फ़रवरी', 'मार्च', 'अप्रैल', 'मई', 'जून', 'जुलाई', 'अगस्त', 'सितंबर',
    'अक्टूबर', 'नवंबर', 'दिसंबर'],
  'bn': ['জানুয়ারি', 'ফেব্রুয়ারি', 'মার্চ', 'এপ্রিল', 'মে', 'জুন', 'জুলাই', 'আগস্ট',
    'সেপ্টেম্বর', 'অক্টোবর', 'নভেম্বর', 'ডিসেম্বর'],
  'as': ['জানুৱাৰী', 'ফেব্ৰুৱাৰী', 'মাৰ্চ', 'এপ্ৰিল', 'মে', 'জুন', 'জুলাই', 'আগষ্ট',
    'ছেপ্তেম্বৰ', 'অক্টোবৰ', 'নৱেম্বৰ', 'ডিচেম্বৰ'],
};

const _dayTemplate = {
  'en': 'Today is {w}, {d} {m} {y}. The time is {t}.',
  'hi': 'आज {w} है, {d} {m} {y}। अभी समय {t} है।',
  'bn': 'আজ {w}, {d} {m} {y}। এখন সময় {t}।',
  'as': 'আজি {w}, {d} {m} {y}। এতিয়া সময় {t}।',
};

const _nice = {
  'en': [
    'A cup of tea, a little sunshine and a kind word can make a good day.',
    'You are doing well. Take your time, there is no hurry.',
    'Would you like to play a game? Tap Games on the home screen.',
  ],
  'hi': [
    'एक कप चाय, थोड़ी धूप और एक मीठा बोल, इनसे दिन अच्छा बन जाता है।',
    'आप अच्छा कर रहे हैं। आराम से, कोई जल्दी नहीं है।',
    'क्या आप कोई खेल खेलना चाहेंगे? होम स्क्रीन पर "खेल" दबाएँ।',
  ],
  'bn': [
    'এক কাপ চা, একটু রোদ আর একটি মিষ্টি কথায় দিনটা ভালো হয়ে ওঠে।',
    'আপনি ভালো করছেন। ধীরে ধীরে, কোনো তাড়া নেই।',
    'একটা খেলা খেলবেন? হোম স্ক্রিনে "খেলা" চাপুন।',
  ],
  'as': [
    'এক কাপ চাহ, অলপ ৰ\'দ আৰু এষাৰ মৰমৰ কথাই দিনটো ভাল কৰি তোলে।',
    'আপুনি ভাল কৰি আছে। লাহে লাহে, কোনো খৰখেদা নাই।',
    'এটা খেল খেলিব নেকি? হোম স্ক্ৰীণত "খেল" টিপক।',
  ],
};

bool isEmergencyText(String text, String lang) {
  final low = text.toLowerCase();
  final words = [...?emergencyWords[lang], ...emergencyWords['en']!];
  return words.any(low.contains);
}

String emergencyText(String lang) => emergencyReply[lang] ?? emergencyReply['en']!;

String _hhmm(int h, int m) =>
    '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

/// Today's weekday, date and time in the person's language.
String dayAnswer(String lang, DateTime now) {
  final pack = kLangPacks[lang];
  final l = _dayTemplate.containsKey(lang) ? lang : 'en';
  final weekdays = pack?.weekdays ?? _weekdays[l]!;
  final months = pack?.months ?? _months[l]!;
  return (pack?.dayTemplate ?? _dayTemplate[l]!)
      .replaceAll('{w}', weekdays[now.weekday - 1])
      .replaceAll('{d}', '${now.day}')
      .replaceAll('{m}', months[now.month - 1])
      .replaceAll('{y}', '${now.year}')
      .replaceAll('{t}', _hhmm(now.hour, now.minute));
}

/// The next reminder today that has not been marked done, or a calm 'nothing'.
String nextAnswer(String lang, List<Reminder> reminders, Set<String> done, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  Reminder? best;
  for (final r in reminders) {
    if (!occursOn(r, today)) continue;
    if (done.contains(doneKey(r.id, today))) continue;
    final at = DateTime(today.year, today.month, today.day, r.hour, r.minute);
    if (at.isBefore(now)) continue;
    if (best == null || at.isBefore(DateTime(today.year, today.month, today.day, best.hour, best.minute))) {
      best = r;
    }
  }
  if (best == null) return tr(lang, 'chatNextNone');
  return tr(lang, 'chatNextAnswer')
      .replaceAll('{k}', tr(lang, 'kind_${best.kind.name}'))
      .replaceAll('{t}', _hhmm(best.hour, best.minute));
}

String niceThing(String lang, int seed) {
  final list = kLangPacks[lang]?.nice ?? _nice[lang] ?? _nice['en']!;
  return list[seed.abs() % list.length];
}
