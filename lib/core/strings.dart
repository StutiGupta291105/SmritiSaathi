/// Minimal in-app strings (English + Hindi). Replace with Flutter gen-l10n
/// (ARB files) once the text stabilises; kept as a map for speed now.
const Map<String, Map<String, String>> kStrings = {
  'en': {
    'appName': 'SmritiAssist',
    'notAMedicalDevice':
        'This app is for memory exercises and reminders. It does not diagnose or treat any condition.',
    'consentTitle': 'Your data and your permission',
    'consentIntro':
        'We save game results on this device. A caregiver or guardian can give permission on behalf of the person using the app.',
    'purposeGameplay': 'Save game results on this device (needed to use the app)',
    'purposeReminders': 'Show reminders (medicine, water, appointments)',
    'purposeCaregiverShare': 'Share progress with the caregiver',
    'purposeSync': 'Back up results online when internet is available',
    'givenByName': 'Name of person giving permission',
    'givenByRelation': 'Relationship (self, son, daughter, spouse, other)',
    'continue': 'Continue',
    'setupTitle': 'Caregiver setup',
    'patientName': 'Name of the person who will play',
    'startLevel': 'Starting level',
    'level1': 'Level 1 – very easy: few items, long time',
    'level2': 'Level 2 – easy',
    'level3': 'Level 3 – medium',
    'level4': 'Level 4 – a little challenging',
    'level5': 'Level 5 – challenging',
    'levelHelp':
        'The game will adjust only one step up or down from this level. You can change it any time.',
    'play': 'Play',
    'memoryGame': 'Match the pairs',
    'wellDone': 'Well done!',
    'tryAgain': 'Let us try another one',
    'finish': 'Finish',
  },
  'hi': {
    'appName': 'स्मृति सहायक',
    'notAMedicalDevice':
        'यह ऐप याददाश्त के अभ्यास और रिमाइंडर के लिए है। यह किसी बीमारी का निदान या इलाज नहीं करता।',
    'consentTitle': 'आपका डेटा और आपकी अनुमति',
    'consentIntro':
        'खेल के परिणाम इसी फ़ोन में सुरक्षित रहते हैं। ऐप इस्तेमाल करने वाले की ओर से देखभाल करने वाला या अभिभावक अनुमति दे सकता है।',
    'purposeGameplay': 'खेल के परिणाम इस फ़ोन में सहेजें (ऐप चलाने के लिए ज़रूरी)',
    'purposeReminders': 'रिमाइंडर दिखाएँ (दवा, पानी, अपॉइंटमेंट)',
    'purposeCaregiverShare': 'प्रगति देखभाल करने वाले के साथ साझा करें',
    'purposeSync': 'इंटरनेट होने पर परिणाम ऑनलाइन सुरक्षित रखें',
    'givenByName': 'अनुमति देने वाले का नाम',
    'givenByRelation': 'रिश्ता (स्वयं, बेटा, बेटी, जीवनसाथी, अन्य)',
    'continue': 'आगे बढ़ें',
    'setupTitle': 'देखभालकर्ता सेटअप',
    'patientName': 'खेलने वाले का नाम',
    'startLevel': 'शुरुआती स्तर',
    'level1': 'स्तर 1 – बहुत आसान: कम चीज़ें, ज़्यादा समय',
    'level2': 'स्तर 2 – आसान',
    'level3': 'स्तर 3 – मध्यम',
    'level4': 'स्तर 4 – थोड़ा कठिन',
    'level5': 'स्तर 5 – कठिन',
    'levelHelp':
        'खेल इस स्तर से केवल एक कदम ऊपर या नीचे जाएगा। आप इसे कभी भी बदल सकते हैं।',
    'play': 'खेलें',
    'memoryGame': 'जोड़ियाँ मिलाएँ',
    'wellDone': 'बहुत बढ़िया!',
    'tryAgain': 'एक और कोशिश करें',
    'finish': 'समाप्त',
  },
};

String tr(String lang, String key) =>
    kStrings[lang]?[key] ?? kStrings['en']![key] ?? key;
