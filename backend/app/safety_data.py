"""Safety texts for every supported language, in one place.

Single source of truth: the app's offline copy (lib/core/safety_data.dart) is
generated from this file by `python tools/gen_safety.py`, and a test fails if
they drift apart. Words that mean someone may be in danger are deliberately
broad: a false alarm shows a kind message and a phone number, a miss could be
serious. All texts except English and Hindi are drafts that need review by
native speakers (docs/LANGUAGES.md).
"""

# Languages the service accepts (English plus the Eighth Schedule languages).
LANGUAGES = {
    "en": "English", "hi": "Hindi", "bn": "Bengali", "te": "Telugu", "mr": "Marathi",
    "ta": "Tamil", "ur": "Urdu", "gu": "Gujarati", "kn": "Kannada", "ml": "Malayalam",
    "or": "Odia", "pa": "Punjabi", "as": "Assamese", "mai": "Maithili", "sat": "Santali",
    "ks": "Kashmiri", "ne": "Nepali", "kok": "Konkani", "mni": "Manipuri (Meitei)",
    "brx": "Bodo", "doi": "Dogri", "sd": "Sindhi", "sa": "Sanskrit",
}

EMERGENCY_WORDS = {
    "en": ["want to die", "kill myself", "end my life", "suicide", "chest pain",
           "can't breathe", "cannot breathe", "heart attack", "stroke", "i fell",
           "i have fallen", "bleeding", "unconscious", "overdose", "took too many"],
    "hi": ["मरना चाहता", "मरना चाहती", "जान दे", "आत्महत्या", "सीने में दर्द", "साँस नहीं",
           "सांस नहीं", "दिल का दौरा", "गिर गया", "गिर गई", "खून", "बेहोश"],
    "bn": ["মরতে চাই", "আত্মহত্যা", "বুকে ব্যথা", "শ্বাস নিতে পারছি না", "হার্ট অ্যাটাক",
           "পড়ে গেছি", "রক্ত", "অজ্ঞান"],
    "as": ["মৰিব বিচাৰো", "মৰিব মন", "আত্মহত্যা", "বুকুত বিষ", "উশাহ ল'ব নোৱাৰো",
           "পৰি গৈছো", "তেজ", "অজ্ঞান"],
}

EMERGENCY_REPLY = {
    "en": "I am only a helper on your phone, so I cannot send help. If you are hurt or "
          "feeling very unwell, please call 112 now, or call your family. Use the Call "
          "family button on the home screen.",
    "hi": "मैं आपके फ़ोन का एक सहायक हूँ, इसलिए मदद भेजना मेरे बस में नहीं है। अगर आपको चोट लगी है या तबीयत "
          "बहुत ख़राब है, तो अभी 112 पर फ़ोन करें, या अपने परिवार को फ़ोन करें। होम स्क्रीन पर "
          "\"परिवार को फ़ोन करें\" बटन दबाएँ।",
    "bn": "আমি শুধু আপনার ফোনের একটি সহায়ক, তাই আমি সাহায্য পাঠাতে পারি না। আপনি আঘাত পেলে বা খুব "
          "অসুস্থ বোধ করলে এখনই ১১২ নম্বরে ফোন করুন, অথবা পরিবারকে ফোন করুন। হোম স্ক্রিনে "
          "\"পরিবারকে ফোন করুন\" বোতাম চাপুন।",
    "as": "মই কেৱল আপোনাৰ ফোনৰ এটা সহায়ক, সেয়ে সহায় পঠাব নোৱাৰো। আপুনি আঘাত পালে বা বৰ বেয়া অনুভৱ "
          "কৰিলে এতিয়াই ১১২ নম্বৰত ফোন কৰক, বা পৰিয়ালক ফোন কৰক। হোম স্ক্ৰীণত "
          "\"পৰিয়ালক ফোন কৰক\" বুটাম টিপক।",
}

UNAVAILABLE_REPLY = {
    "en": "I am not sure how to help with that. You could ask your family, or look at your reminders.",
    "hi": "इसमें मैं कैसे मदद करूँ, मुझे पता नहीं। आप अपने परिवार से पूछ सकते हैं, या अपने रिमाइंडर देख सकते हैं।",
    "bn": "এ বিষয়ে কীভাবে সাহায্য করব বুঝতে পারছি না। আপনি পরিবারকে জিজ্ঞাসা করতে পারেন, অথবা আপনার মনে করিয়ে দেওয়া দেখতে পারেন।",
    "as": "এইটোত কেনেকৈ সহায় কৰিম মই নাজানো। আপুনি পৰিয়ালক সুধিব পাৰে, বা আপোনাৰ সোঁৱৰণী চাব পাৰে।",
}
