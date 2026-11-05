/// Texts for notification permission and push handling. Kept apart from
/// `kStrings` on purpose: every language there must carry every key, and these
/// need native-speaker review first (all are drafts). Santali, Manipuri, Bodo and
/// Kashmiri are left out on purpose and show English until a reviewed
/// translation is added.
const Map<String, Map<String, String>> kNotifyTexts = {
  'en': {
    'routineUpdated': 'Your daily routine was updated.',
    'notifBlocked':
        'Reminders are switched off on this phone, so they will not ring.',
    'notifInexact': 'Allow alarms so reminders ring exactly on time.',
    'notifAllow': 'Allow',
  },
  'hi': {
    'routineUpdated': 'आपकी दिनचर्या अपडेट की गई है।',
    'notifBlocked':
        'इस फ़ोन पर रिमाइंडर बंद हैं, इसलिए वे नहीं बजेंगे।',
    'notifInexact': 'अलार्म की अनुमति दें ताकि रिमाइंडर ठीक समय पर बजें।',
    'notifAllow': 'अनुमति दें',
  },
  'bn': {
    'routineUpdated': 'আপনার দৈনন্দিন রুটিন আপডেট করা হয়েছে।',
    'notifBlocked': 'এই ফোনে রিমাইন্ডার বন্ধ আছে, তাই বাজবে না।',
    'notifInexact': 'অ্যালার্মের অনুমতি দিন, যাতে রিমাইন্ডার ঠিক সময়ে বাজে।',
    'notifAllow': 'অনুমতি দিন',
  },
  'as': {
    'routineUpdated': 'আপোনাৰ দৈনন্দিন ৰুটিন আপডেট কৰা হৈছে।',
    'notifBlocked': 'এই ফোনত ৰিমাইণ্ডাৰ বন্ধ আছে, গতিকে বাজিব নোৱাৰে।',
    'notifInexact': 'এলাৰ্মৰ অনুমতি দিয়ক, যাতে ৰিমাইণ্ডাৰ ঠিক সময়ত বাজে।',
    'notifAllow': 'অনুমতি দিয়ক',
  },
  'te': {
    'routineUpdated': 'మీ రోజువారీ దినచర్య నవీకరించబడింది.',
    'notifBlocked': 'ఈ ఫోన్‌లో రిమైండర్లు ఆఫ్‌లో ఉన్నాయి, కాబట్టి అవి మోగవు.',
    'notifInexact': 'రిమైండర్లు సరైన సమయానికి మోగేలా అలారమ్‌లను అనుమతించండి.',
    'notifAllow': 'అనుమతించండి',
  },
  'mr': {
    'routineUpdated': 'तुमची दैनंदिन दिनचर्या अपडेट केली आहे.',
    'notifBlocked': 'या फोनवर स्मरणपत्रे बंद आहेत, त्यामुळे ती वाजणार नाहीत.',
    'notifInexact': 'स्मरणपत्रे अगदी वेळेवर वाजण्यासाठी अलार्मला परवानगी द्या.',
    'notifAllow': 'परवानगी द्या',
  },
  'ta': {
    'routineUpdated': 'உங்கள் தினசரி வழக்கம் புதுப்பிக்கப்பட்டது.',
    'notifBlocked': 'இந்த ஃபோனில் நினைவூட்டல்கள் அணைக்கப்பட்டுள்ளன, அதனால் அவை ஒலிக்காது.',
    'notifInexact': 'நினைவூட்டல்கள் சரியான நேரத்தில் ஒலிக்க அலாரங்களை அனுமதிக்கவும்.',
    'notifAllow': 'அனுமதி',
  },
  'ur': {
    'routineUpdated': 'آپ کا روزانہ کا معمول اپ ڈیٹ کر دیا گیا ہے۔',
    'notifBlocked': 'اس فون پر یاد دہانیاں بند ہیں، اس لیے وہ نہیں بجیں گی۔',
    'notifInexact': 'الارم کی اجازت دیں تاکہ یاد دہانیاں بالکل وقت پر بجیں۔',
    'notifAllow': 'اجازت دیں',
  },
  'gu': {
    'routineUpdated': 'તમારી રોજિંદી દિનચર્યા અપડેટ કરવામાં આવી છે.',
    'notifBlocked': 'આ ફોન પર રિમાઇન્ડર બંધ છે, તેથી તે વાગશે નહીં.',
    'notifInexact': 'રિમાઇન્ડર બરાબર સમયે વાગે તે માટે એલાર્મની પરવાનગી આપો.',
    'notifAllow': 'પરવાનગી આપો',
  },
  'kn': {
    'routineUpdated': 'ನಿಮ್ಮ ದೈನಂದಿನ ದಿನಚರಿಯನ್ನು ಅಪ್‌ಡೇಟ್ ಮಾಡಲಾಗಿದೆ.',
    'notifBlocked': 'ಈ ಫೋನ್‌ನಲ್ಲಿ ರಿಮೈಂಡರ್‌ಗಳು ಆಫ್ ಆಗಿವೆ, ಆದ್ದರಿಂದ ಅವು ಮೊಳಗುವುದಿಲ್ಲ.',
    'notifInexact': 'ರಿಮೈಂಡರ್‌ಗಳು ಸರಿಯಾದ ಸಮಯಕ್ಕೆ ಮೊಳಗಲು ಅಲಾರಂಗಳಿಗೆ ಅನುಮತಿ ನೀಡಿ.',
    'notifAllow': 'ಅನುಮತಿಸಿ',
  },
  'ml': {
    'routineUpdated': 'നിങ്ങളുടെ ദിനചര്യ അപ്‌ഡേറ്റ് ചെയ്തു.',
    'notifBlocked': 'ഈ ഫോണിൽ റിമൈൻഡറുകൾ ഓഫാണ്, അതിനാൽ അവ മുഴങ്ങില്ല.',
    'notifInexact': 'റിമൈൻഡറുകൾ കൃത്യസമയത്ത് മുഴങ്ങാൻ അലാറങ്ങൾക്ക് അനുമതി നൽകുക.',
    'notifAllow': 'അനുവദിക്കുക',
  },
  'or': {
    'routineUpdated': 'ଆପଣଙ୍କ ଦୈନିକ ରୁଟିନ୍ ଅପଡେଟ୍ ହୋଇଛି।',
    'notifBlocked': 'ଏହି ଫୋନରେ ରିମାଇଣ୍ଡର୍ ବନ୍ଦ ଅଛି, ତେଣୁ ସେଗୁଡ଼ିକ ବାଜିବ ନାହିଁ।',
    'notifInexact': 'ରିମାଇଣ୍ଡର୍ ଠିକ୍ ସମୟରେ ବାଜିବା ପାଇଁ ଆଲାର୍ମକୁ ଅନୁମତି ଦିଅନ୍ତୁ।',
    'notifAllow': 'ଅନୁମତି ଦିଅନ୍ତୁ',
  },
  'pa': {
    'routineUpdated': 'ਤੁਹਾਡੀ ਰੋਜ਼ਾਨਾ ਰੁਟੀਨ ਅੱਪਡੇਟ ਕੀਤੀ ਗਈ ਹੈ।',
    'notifBlocked': 'ਇਸ ਫ਼ੋਨ ’ਤੇ ਰਿਮਾਈਂਡਰ ਬੰਦ ਹਨ, ਇਸ ਲਈ ਉਹ ਨਹੀਂ ਵੱਜਣਗੇ।',
    'notifInexact': 'ਅਲਾਰਮ ਦੀ ਇਜਾਜ਼ਤ ਦਿਓ ਤਾਂ ਜੋ ਰਿਮਾਈਂਡਰ ਬਿਲਕੁਲ ਸਮੇਂ ’ਤੇ ਵੱਜਣ।',
    'notifAllow': 'ਇਜਾਜ਼ਤ ਦਿਓ',
  },
  'ne': {
    'routineUpdated': 'तपाईंको दैनिक दिनचर्या अपडेट गरिएको छ।',
    'notifBlocked': 'यो फोनमा रिमाइन्डरहरू बन्द छन्, त्यसैले ती बज्ने छैनन्।',
    'notifInexact': 'रिमाइन्डरहरू ठीक समयमा बज्न अलार्मलाई अनुमति दिनुहोस्।',
    'notifAllow': 'अनुमति दिनुहोस्',
  },
  'mai': {
    'routineUpdated': 'अहाँक दैनिक दिनचर्या अपडेट कएल गेल अछि।',
    'notifBlocked': 'एहि फोन पर रिमाइंडर बंद अछि, तेँ ओ नहि बजत।',
    'notifInexact': 'अलार्मक अनुमति दिअ जाहि सँ रिमाइंडर ठीक समय पर बजय।',
    'notifAllow': 'अनुमति दिअ',
  },
  'kok': {
    'routineUpdated': 'तुमची दिसाभरची दिनचर्या अपडेट केल्या.',
    'notifBlocked': 'ह्या फोनार आठवण बंद आसात, म्हणून तीं वाजची ना.',
    'notifInexact': 'आठवण बरोबर वेळार वाजचे खातीर अलार्माक परवानगी दिवची.',
    'notifAllow': 'परवानगी दिव',
  },
  'doi': {
    'routineUpdated': 'तुंदी रोज़ाना दी दिनचर्या अपडेट कीती गेदी ऐ।',
    'notifBlocked': 'इस फोन पर रिमाइंडर बंद न, इस आस्तै ओह् नेईं बजङन।',
    'notifInexact': 'अलार्म दी इजाज़त देयो ताकि रिमाइंडर ठीक वक्त पर बजन।',
    'notifAllow': 'इजाज़त देयो',
  },
  'sd': {
    'routineUpdated': 'توهان جو روزاني معمول اپڊيٽ ڪيو ويو آهي.',
    'notifBlocked': 'هن فون تي ياد ڏياريندڙ بند آهن، تنهنڪري اهي نه وڄندا.',
    'notifInexact': 'الارم جي اجازت ڏيو ته جيئن ياد ڏياريندڙ ٺيڪ وقت تي وڄن.',
    'notifAllow': 'اجازت ڏيو',
  },
  'sa': {
    'routineUpdated': 'भवतः दैनन्दिनी दिनचर्या नवीकृता अस्ति।',
    'notifBlocked': 'अस्मिन् दूरभाषे स्मारकानि निरुद्धानि सन्ति, अतः न ध्वनिष्यन्ति।',
    'notifInexact': 'स्मारकानि यथासमयं ध्वनेयुः इति सङ्केतघटिकाभ्यः अनुमतिं ददातु।',
    'notifAllow': 'अनुमतिं ददातु',
  },
};

String notifyText(String lang, String key) =>
    kNotifyTexts[lang]?[key] ?? kNotifyTexts['en']![key]!;
