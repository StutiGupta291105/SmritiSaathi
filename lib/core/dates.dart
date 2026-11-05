import 'languages.dart';
import 'strings.dart';

/// Short weekday names, Monday first, in each language.
const kWeekdayShort = {
  'en': ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
  'hi': ['सोम', 'मंगल', 'बुध', 'गुरु', 'शुक्र', 'शनि', 'रवि'],
  'bn': ['সোম', 'মঙ্গল', 'বুধ', 'বৃহ', 'শুক্র', 'শনি', 'রবি'],
  'as': ['সোম', 'মঙ্গল', 'বুধ', 'বৃহ', 'শুক্ৰ', 'শনি', 'দেও'],
};

String weekdayShort(String lang, int weekday) =>
    (kWeekdayShort[lang] ?? kLangPacks[lang]?.weekdaysShort ?? kWeekdayShort['en']!)[
        (weekday - 1) % 7];

/// "10 min ago", "3 hours ago", "2 days ago": how long before [now] a local
/// time was.
String agoText(String lang, DateTime then, DateTime now) {
  final diff = now.difference(then);
  if (diff.inMinutes < 2) return tr(lang, 'rmJustNow');
  if (diff.inMinutes < 60) return trf(lang, 'rmAgoMin', a: diff.inMinutes);
  // English only has a singular form to fix ("1 hours ago" reads wrongly).
  String one(String text, String plural, String singular, int n) =>
      lang == 'en' && n == 1 ? text.replaceFirst(plural, singular) : text;
  if (diff.inHours < 24) {
    return one(trf(lang, 'rmAgoHour', a: diff.inHours), 'hours', 'hour', diff.inHours);
  }
  return one(trf(lang, 'rmAgoDay', a: diff.inDays), 'days', 'day', diff.inDays);
}


/// "Every day", or the days a reminder runs on ("Mon, Wed, Fri") from a weekday
/// mask (bit 0 = Monday ... bit 6 = Sunday).
String daysText(String lang, int mask) {
  final m = mask & 127;
  if (m == 127 || m == 0) return tr(lang, 'everyDay');
  return [
    for (var i = 0; i < 7; i++)
      if ((m >> i) & 1 == 1) weekdayShort(lang, i + 1)
  ].join(', ');
}
