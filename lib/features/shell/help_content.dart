/// Long-form copy for Help & Support and About App.
///
/// Written in English and Hindi. Other languages fall back to English for this
/// long text only (the headings reuse the translated app strings). It is kept
/// out of `strings*.dart` so the 23-language parity test is not affected; a
/// native-speaker review should translate it later.
library;

typedef Qa = ({String q, String a});

const Map<String, Map<String, Object>> _c = {
  'en': {
    'helpIntro':
        'Quick answers for patients, family members and caregivers. Nothing here replaces advice from your doctor.',
    'quick': 'Getting started',
    'steps': [
      'Games: tap Play to start a short, gentle game. There is no pass or fail.',
      'Reminders: see medicines, routine and appointments for the day. Tap the tick when done.',
      'Talk to Smriti: chat with the friendly helper any time.',
      'Caregiver area: a family member can add reminders and view progress, with your permission.',
    ],
    'faqTitle': 'Common questions',
    'faq': <Qa>[
      (
        q: 'Do I need internet to use the app?',
        a: 'No. Games, reminders and your history work offline. When the phone is online again, saved changes are sent automatically. A banner at the top tells you when you are offline.'
      ),
      (
        q: 'I am not getting reminder alerts.',
        a: 'Allow notifications for Smriti Sathi in phone Settings, switch off battery saving for the app, and make sure reminders are turned on under Privacy and permissions. You get an alert 30 minutes before and at the time.'
      ),
      (
        q: 'How do I change the language?',
        a: 'Open Profile and choose Language. 23 languages are available; some are early drafts, so please tell us if a word looks wrong.'
      ),
      (
        q: 'Who can see my information?',
        a: 'Only the people you allow. You can change permissions any time under Privacy and permissions, and ask for your data to be deleted.'
      ),
      (
        q: 'Does the app diagnose memory problems?',
        a: 'No. Smriti Sathi is not a medical device. Game results only show how a day went. Please speak to a doctor about any health concern.'
      ),
      (
        q: 'I forgot to mark a medicine. What now?',
        a: 'Open Reminders, go to Medicines and tap the tick. If you are unsure whether you took a dose, do not take extra; ask your doctor or pharmacist.'
      ),
      (
        q: 'How does a caregiver or doctor link to me?',
        a: 'Create an invite from the Caregiver area and share the code. They enter it in their own app. You can remove them at any time.'
      ),
    ],
    'fixTitle': 'If something is not working',
    'fix': [
      'Close and reopen the app.',
      'Check your internet, then pull down or wait a minute for syncing.',
      'Update to the latest version of the app.',
      'Still stuck? Ask your caregiver or doctor to message you from the app, or contact your care team.',
    ],
    'emergencyNote':
        'In an emergency call 112. For senior-citizen support in India you can also call the Elderline on 14567.',
    'teamNote':
        'Need help with the app itself? Ask your caregiver or care team. You can also message them from Talk to Smriti.',
    'aboutWhat': 'What Smriti Sathi does',
    'features': [
      'Gentle memory and attention games that adjust to you',
      'Medicine, routine and appointment reminders, with alerts before the time',
      'A friendly companion to talk with, in your language',
      'Family, caregiver and doctor connection, only with consent',
      'Works offline and syncs when you are online',
    ],
    'aboutPrivacyTitle': 'Your privacy',
    'aboutPrivacy':
        'Your information stays on your phone unless you choose to share it. Data is encrypted on the device, sharing needs your consent, and you can withdraw it any time. Built with India\'s DPDP Act in mind.',
    'disclaimerTitle': 'Important',
    'disclaimer':
        'Smriti Sathi is not a medical device. It does not diagnose, treat or prevent any condition. Always follow your doctor\'s advice.',
    'languagesLine': '23 languages: English and the 22 languages of the Eighth Schedule',
    'creditsTitle': 'Made by',
    'credits':
        'A project by students of NIET, Greater Noida, under the guidance of Mr. Ankit Sharma.',
    'licenses': 'Open-source licences',
    'version': 'Version',
  },
  'hi': {
    'helpIntro':
        'मरीज़ों, परिवार और देखभाल करने वालों के लिए छोटे उत्तर। यह आपके डॉक्टर की सलाह की जगह नहीं लेता।',
    'quick': 'शुरुआत कैसे करें',
    'steps': [
      'खेल: खेलें दबाकर छोटा, आसान खेल शुरू करें। इसमें पास या फ़ेल नहीं होता।',
      'रिमाइंडर: दिन की दवाइयाँ, दिनचर्या और अपॉइंटमेंट देखें। काम होने पर टिक दबाएँ।',
      'स्मृति से बात: दोस्ताना सहायक से कभी भी बात करें।',
      'देखभालकर्ता क्षेत्र: आपकी अनुमति से परिवार का सदस्य रिमाइंडर जोड़ सकता है और प्रगति देख सकता है।',
    ],
    'faqTitle': 'आम सवाल',
    'faq': <Qa>[
      (
        q: 'क्या ऐप के लिए इंटरनेट चाहिए?',
        a: 'नहीं। खेल, रिमाइंडर और इतिहास बिना इंटरनेट चलते हैं। फ़ोन ऑनलाइन होते ही सहेजे बदलाव अपने-आप भेज दिए जाते हैं। ऑफ़लाइन होने पर ऊपर एक पट्टी दिखती है।'
      ),
      (
        q: 'मुझे रिमाइंडर की सूचना नहीं मिल रही।',
        a: 'फ़ोन सेटिंग में स्मृति साथी की सूचनाएँ चालू करें, बैटरी सेविंग बंद करें, और गोपनीयता व अनुमतियाँ में रिमाइंडर चालू रखें। समय से 30 मिनट पहले और समय पर सूचना आती है।'
      ),
      (
        q: 'भाषा कैसे बदलें?',
        a: 'प्रोफ़ाइल खोलकर भाषा चुनें। 23 भाषाएँ उपलब्ध हैं; कुछ अभी शुरुआती हैं, कोई शब्द गलत लगे तो बताएँ।'
      ),
      (
        q: 'मेरी जानकारी कौन देख सकता है?',
        a: 'सिर्फ़ वही जिन्हें आप अनुमति दें। गोपनीयता और अनुमतियाँ में कभी भी बदलें, और अपना डेटा हटाने को कह सकते हैं।'
      ),
      (
        q: 'क्या ऐप याददाश्त की बीमारी पहचानता है?',
        a: 'नहीं। स्मृति साथी कोई चिकित्सा उपकरण नहीं है। खेल के नतीजे सिर्फ़ दिन का हाल दिखाते हैं। स्वास्थ्य की चिंता हो तो डॉक्टर से मिलें।'
      ),
      (
        q: 'दवा का टिक लगाना भूल गया, अब क्या करूँ?',
        a: 'रिमाइंडर में दवाइयाँ खोलकर टिक दबाएँ। खुराक लेने पर शक हो तो दोबारा न लें; डॉक्टर या फ़ार्मासिस्ट से पूछें।'
      ),
      (
        q: 'देखभालकर्ता या डॉक्टर मुझसे कैसे जुड़ें?',
        a: 'देखभालकर्ता क्षेत्र से आमंत्रण बनाकर कोड साझा करें। वे अपने ऐप में कोड डालते हैं। आप उन्हें कभी भी हटा सकते हैं।'
      ),
    ],
    'fixTitle': 'अगर कुछ ठीक न चले',
    'fix': [
      'ऐप बंद करके दोबारा खोलें।',
      'इंटरनेट जाँचें और एक मिनट सिंक होने दें।',
      'ऐप का नया संस्करण अपडेट करें।',
      'फिर भी दिक्कत हो तो अपने देखभालकर्ता या डॉक्टर से संपर्क करें।',
    ],
    'emergencyNote':
        'आपातकाल में 112 पर फ़ोन करें। भारत में वरिष्ठ नागरिक सहायता के लिए एल्डरलाइन 14567 भी है।',
    'teamNote':
        'ऐप में मदद चाहिए? अपने देखभालकर्ता या केयर टीम से पूछें। आप स्मृति से बात में उन्हें संदेश भी भेज सकते हैं।',
    'aboutWhat': 'स्मृति साथी क्या करता है',
    'features': [
      'आपके अनुसार ढलने वाले आसान याददाश्त और ध्यान के खेल',
      'दवा, दिनचर्या और अपॉइंटमेंट के रिमाइंडर, समय से पहले सूचना के साथ',
      'आपकी भाषा में बात करने वाला दोस्ताना साथी',
      'परिवार, देखभालकर्ता और डॉक्टर से जुड़ाव, सिर्फ़ सहमति से',
      'ऑफ़लाइन चलता है, ऑनलाइन आने पर सिंक होता है',
    ],
    'aboutPrivacyTitle': 'आपकी गोपनीयता',
    'aboutPrivacy':
        'आपकी जानकारी आपके फ़ोन में रहती है, जब तक आप साझा करना न चुनें। डेटा फ़ोन पर एन्क्रिप्टेड रहता है, साझा करने के लिए आपकी सहमति ज़रूरी है, जिसे आप कभी भी वापस ले सकते हैं।',
    'disclaimerTitle': 'ज़रूरी',
    'disclaimer':
        'स्मृति साथी चिकित्सा उपकरण नहीं है। यह किसी स्थिति की पहचान, इलाज या रोकथाम नहीं करता। हमेशा डॉक्टर की सलाह मानें।',
    'languagesLine': '23 भाषाएँ: अंग्रेज़ी और आठवीं अनुसूची की 22 भाषाएँ',
    'creditsTitle': 'निर्माता',
    'credits':
        'एनआईईटी, ग्रेटर नोएडा के छात्रों की परियोजना, श्री अंकित शर्मा के मार्गदर्शन में।',
    'licenses': 'ओपन-सोर्स लाइसेंस',
    'version': 'संस्करण',
  },
};

Object _get(String lang, String key) =>
    (_c[lang] ?? _c['en']!)[key] ?? _c['en']![key]!;

String helpText(String lang, String key) => _get(lang, key) as String;
List<String> helpList(String lang, String key) =>
    (_get(lang, key) as List).cast<String>();
List<Qa> helpFaq(String lang) => (_get(lang, 'faq') as List).cast<Qa>();
