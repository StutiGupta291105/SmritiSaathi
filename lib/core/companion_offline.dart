import 'adherence.dart';
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

/// Keep in step with backend/app/companion.py (a backend test checks this).
const emergencyWords = {
  'en': ['want to die', 'kill myself', 'end my life', 'suicide', 'chest pain',
    "can't breathe", 'cannot breathe', 'heart attack', 'stroke', 'i fell',
    'i have fallen', 'bleeding', 'unconscious', 'overdose', 'took too many'],
  'hi': ['मरना चाहता', 'मरना चाहती', 'जान दे', 'आत्महत्या', 'सीने में दर्द', 'साँस नहीं',
    'सांस नहीं', 'दिल का दौरा', 'गिर गया', 'गिर गई', 'खून', 'बेहोश'],
  'bn': ['মরতে চাই', 'আত্মহত্যা', 'বুকে ব্যথা', 'শ্বাস নিতে পারছি না', 'হার্ট অ্যাটাক',
    'পড়ে গেছি', 'রক্ত', 'অজ্ঞান'],
  'as': ['মৰিব বিচাৰো', 'মৰিব মন', 'আত্মহত্যা', 'বুকুত বিষ', "উশাহ ল'ব নোৱাৰো",
    'পৰি গৈছো', 'তেজ', 'অজ্ঞান'],
};

const emergencyReply = {
  'en': 'I am only a helper on your phone, so I cannot send help. If you are hurt or feeling very unwell, please call 112 now, or call your family. Use the Call family button on the home screen.',
  'hi': 'मैं आपके फ़ोन का एक सहायक हूँ, इसलिए मदद भेजना मेरे बस में नहीं है। अगर आपको चोट लगी है या तबीयत बहुत ख़राब है, तो अभी 112 पर फ़ोन करें, या अपने परिवार को फ़ोन करें। होम स्क्रीन पर "परिवार को फ़ोन करें" बटन दबाएँ।',
  'bn': 'আমি শুধু আপনার ফোনের একটি সহায়ক, তাই আমি সাহায্য পাঠাতে পারি না। আপনি আঘাত পেলে বা খুব অসুস্থ বোধ করলে এখনই ১১২ নম্বরে ফোন করুন, অথবা পরিবারকে ফোন করুন। হোম স্ক্রিনে "পরিবারকে ফোন করুন" বোতাম চাপুন।',
  'as': 'মই কেৱল আপোনাৰ ফোনৰ এটা সহায়ক, সেয়ে সহায় পঠাব নোৱাৰো। আপুনি আঘাত পালে বা বৰ বেয়া অনুভৱ কৰিলে এতিয়াই ১১২ নম্বৰত ফোন কৰক, বা পৰিয়ালক ফোন কৰক। হোম স্ক্ৰীণত "পৰিয়ালক ফোন কৰক" বুটাম টিপক।',
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
  final l = _dayTemplate.containsKey(lang) ? lang : 'en';
  return _dayTemplate[l]!
      .replaceAll('{w}', _weekdays[l]![now.weekday - 1])
      .replaceAll('{d}', '${now.day}')
      .replaceAll('{m}', _months[l]![now.month - 1])
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
  final list = _nice[lang] ?? _nice['en']!;
  return list[seed.abs() % list.length];
}
