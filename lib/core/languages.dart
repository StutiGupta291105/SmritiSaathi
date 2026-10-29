/// Languages the app can show, by code, written in their own script so a person
/// can find theirs without reading English. Bengali and Assamese texts are
/// drafts and need review by native speakers before real use.
const Map<String, String> kLanguages = {
  'en': 'English',
  'hi': 'हिन्दी',
  'bn': 'বাংলা',
  'as': 'অসমীয়া',
};

/// Text-to-speech locales to try, in order. Assamese voices are often missing
/// on phones, so Bengali is tried next; if none exists the app stays silent
/// and the written instruction is the only one.
const Map<String, List<String>> kTtsLocales = {
  'en': ['en-IN', 'en-US'],
  'hi': ['hi-IN'],
  'bn': ['bn-IN', 'bn-BD'],
  'as': ['as-IN', 'bn-IN'],
};

/// The next language in the list, for a one-tap switch.
String nextLanguage(String current) {
  final codes = kLanguages.keys.toList();
  final i = codes.indexOf(current);
  return codes[(i + 1) % codes.length];
}
