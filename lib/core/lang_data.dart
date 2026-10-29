/// Everything the app needs for one language beyond its own screen texts:
/// the UI strings, labels for the game pictures and routines (keyed by their
/// English label), day and month names and a few fixed sentences.
class LangData {
  const LangData({
    required this.strings,
    required this.labels,
    required this.weekdays,
    required this.weekdaysShort,
    required this.months,
    required this.dayTemplate,
    required this.nice,
  });

  /// UI texts, same keys as English.
  final Map<String, String> strings;

  /// Game picture and routine labels, keyed by the English label.
  final Map<String, String> labels;

  /// Monday first.
  final List<String> weekdays, weekdaysShort;
  final List<String> months;

  /// "Today is {w}, {d} {m} {y}. The time is {t}."
  final String dayTemplate;

  /// Three kind sentences for "Say something kind".
  final List<String> nice;
}
