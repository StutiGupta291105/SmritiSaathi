import 'lang_data.dart';

// One file per language under lib/core/lang/. Add the language code to
// kLanguageOrder, kLanguages, kLanguageEnglish, kTtsLocales (and kRtl if it is
// written right to left), and to the backend (backend/app/safety_data.py).
import 'lang/_all.dart';

/// Languages the app can show, written in their own script so a person can
/// find theirs without reading English: English plus the 22 languages of the
/// Eighth Schedule of the Constitution of India. All texts except the original
/// English and Hindi are drafts that need review by native speakers before
/// real use (see docs/LANGUAGES.md).
const List<String> kLanguageOrder = [
  'en', 'hi', 'bn', 'te', 'mr', 'ta', 'ur', 'gu', 'kn', 'ml', 'or', 'pa', 'as',
  'mai', 'sat', 'ks', 'ne', 'kok', 'mni', 'brx', 'doi', 'sd', 'sa',
];

const Map<String, String> kLanguages = {
  'en': 'English',
  'hi': 'हिन्दी',
  'bn': 'বাংলা',
  'te': 'తెలుగు',
  'mr': 'मराठी',
  'ta': 'தமிழ்',
  'ur': 'اردو',
  'gu': 'ગુજરાતી',
  'kn': 'ಕನ್ನಡ',
  'ml': 'മലയാളം',
  'or': 'ଓଡ଼ିଆ',
  'pa': 'ਪੰਜਾਬੀ',
  'as': 'অসমীয়া',
  'mai': 'मैथिली',
  'sat': 'ᱥᱟᱱᱛᱟᱲᱤ',
  'ks': 'کٲشُر',
  'ne': 'नेपाली',
  'kok': 'कोंकणी',
  'mni': 'ꯃꯅꯤꯄꯨꯔꯤ',
  'brx': 'बड़ो',
  'doi': 'डोगरी',
  'sd': 'سنڌي',
  'sa': 'संस्कृतम्',
};

/// Shown under the native name so a language can be found even when the
/// phone has no font for its script.
const Map<String, String> kLanguageEnglish = {
  'en': 'English',
  'hi': 'Hindi',
  'bn': 'Bengali',
  'te': 'Telugu',
  'mr': 'Marathi',
  'ta': 'Tamil',
  'ur': 'Urdu',
  'gu': 'Gujarati',
  'kn': 'Kannada',
  'ml': 'Malayalam',
  'or': 'Odia',
  'pa': 'Punjabi',
  'as': 'Assamese',
  'mai': 'Maithili',
  'sat': 'Santali',
  'ks': 'Kashmiri',
  'ne': 'Nepali',
  'kok': 'Konkani',
  'mni': 'Manipuri (Meitei)',
  'brx': 'Bodo',
  'doi': 'Dogri',
  'sd': 'Sindhi',
  'sa': 'Sanskrit',
};

/// English and Hindi were written with the app; every other language is a draft
/// that a native speaker should review before real use. The picker says so.
const Set<String> kDraftLanguages = {
  'bn', 'te', 'mr', 'ta', 'ur', 'gu', 'kn', 'ml', 'or', 'pa', 'as', 'mai', 'sat',
  'ks', 'ne', 'kok', 'mni', 'brx', 'doi', 'sd', 'sa',
};

/// Written right to left (Perso-Arabic script).
const Set<String> kRtl = {'ur', 'ks', 'sd'};

bool isRtl(String lang) => kRtl.contains(lang);

/// Data for the languages other than English, Hindi, Bengali and Assamese,
/// which predate the language packs.
const Map<String, LangData> kLangPacks = kAllLangPacks;

/// Text-to-speech locales to try, in order. Only voices in the same script are
/// used as fallbacks (Devanagari languages fall back to Hindi, for example); if
/// no voice exists the app stays silent and the written instruction is the
/// only one.
const Map<String, List<String>> kTtsLocales = {
  'en': ['en-IN', 'en-US'],
  'hi': ['hi-IN'],
  'bn': ['bn-IN', 'bn-BD'],
  'te': ['te-IN'],
  'mr': ['mr-IN'],
  'ta': ['ta-IN', 'ta-LK'],
  'ur': ['ur-IN', 'ur-PK'],
  'gu': ['gu-IN'],
  'kn': ['kn-IN'],
  'ml': ['ml-IN'],
  'or': ['or-IN'],
  'pa': ['pa-IN'],
  'as': ['as-IN', 'bn-IN'],
  'mai': ['mai-IN', 'hi-IN'],
  'sat': ['sat-IN'],
  'ks': ['ks-IN', 'ur-IN'],
  'ne': ['ne-NP', 'ne-IN', 'hi-IN'],
  'kok': ['kok-IN', 'mr-IN', 'hi-IN'],
  'mni': ['mni-IN'],
  'brx': ['brx-IN', 'hi-IN'],
  'doi': ['doi-IN', 'hi-IN'],
  'sd': ['sd-IN', 'ur-IN'],
  'sa': ['sa-IN', 'hi-IN'],
};

/// The next language in the list, for a one-tap switch.
String nextLanguage(String current) {
  final i = kLanguageOrder.indexOf(current);
  return kLanguageOrder[(i + 1) % kLanguageOrder.length];
}
