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
  if (diff.inHours < 24) return trf(lang, 'rmAgoHour', a: diff.inHours);
  return trf(lang, 'rmAgoDay', a: diff.inDays);
}
