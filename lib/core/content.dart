/// Culturally familiar content shared by all games. Widely supported emoji are
/// used so nothing needs to be downloaded (offline-first). Later: regional
/// packs per language and caregiver-added family photos and names.
class Item {
  const Item(this.emoji, this.en, this.hi, this.bn, this.asm);
  final String emoji, en, hi, bn, asm;

  /// Text in the given language; English if the language has no entry.
  String label(String lang) => switch (lang) {
        'hi' => hi,
        'bn' => bn,
        'as' => asm,
        _ => en,
      };
}

const kObjects = [
  Item('🥭', 'Mango', 'आम', 'আম', 'আম'),
  Item('🌼', 'Marigold', 'गेंदा', 'গাঁদা', 'গেন্দাফুল'),
  Item('☕', 'Tea', 'चाय', 'চা', 'চাহ'),
  Item('🐄', 'Cow', 'गाय', 'গরু', 'গৰু'),
  Item('🥥', 'Coconut', 'नारियल', 'নারকেল', 'নাৰিকল'),
  Item('🍌', 'Banana', 'केला', 'কলা', 'কল'),
  Item('🌺', 'Hibiscus', 'गुड़हल', 'জবা', 'জবা ফুল'),
  Item('🚲', 'Bicycle', 'साइकिल', 'সাইকেল', 'চাইকেল'),
  Item('🪔', 'Diya', 'दीया', 'প্রদীপ', 'চাকি'),
  Item('🛺', 'Auto-rickshaw', 'ऑटो रिक्शा', 'অটো রিকশা', 'অটো ৰিক্সা'),
  Item('🍛', 'Dal and rice', 'दाल-चावल', 'ডাল-ভাত', 'ডাইল-ভাত'),
  Item('🌾', 'Rice plant', 'धान', 'ধান গাছ', 'ধান গছ'),
];

/// Look-alike pairs for the harder attention levels (target vs distractor).
const kLookAlikes = [
  (Item('🌼', 'Marigold', 'गेंदा', 'গাঁদা', 'গেন্দাফুল'), Item('🌻', 'Sunflower', 'सूरजमुखी', 'সূর্যমুখী', 'সূৰ্যমুখী')),
  (Item('🍎', 'Apple', 'सेब', 'আপেল', 'আপেল'), Item('🍅', 'Tomato', 'टमाटर', 'টমেটো', 'বিলাহী')),
  (Item('🥭', 'Mango', 'आम', 'আম', 'আম'), Item('🍑', 'Peach', 'आड़ू', 'পীচ', 'পীচ')),
  (Item('🐄', 'Cow', 'गाय', 'গরু', 'গৰু'), Item('🐃', 'Buffalo', 'भैंस', 'মহিষ', 'মহ')),
  (Item('🍌', 'Banana', 'केला', 'কলা', 'কল'), Item('🌽', 'Corn', 'भुट्टा', 'ভুট্টা', 'ভুট্টা')),
];

/// Everyday sequences in their usual order. The order is a common one, not the
/// only one; caregivers will be able to edit routines to match the person's day.
class Routine {
  const Routine(this.en, this.hi, this.bn, this.asm, this.steps);
  final String en, hi, bn, asm;
  final List<Item> steps;

  String title(String lang) => switch (lang) {
        'hi' => hi,
        'bn' => bn,
        'as' => asm,
        _ => en,
      };
}

const kRoutines = [
  Routine('Morning', 'सुबह', 'সকাল', 'পুৱা', [
    Item('🛏️', 'Wake up', 'उठें', 'ঘুম থেকে উঠুন', 'শুই উঠক'),
    Item('🦷', 'Brush teeth', 'दाँत साफ़ करें', 'দাঁত মাজুন', 'দাঁত ঘহক'),
    Item('🚿', 'Take a bath', 'नहाएँ', 'স্নান করুন', 'গা ধুওক'),
    Item('🙏', 'Pray', 'पूजा करें', 'প্রার্থনা করুন', 'প্ৰাৰ্থনা কৰক'),
    Item('☕', 'Drink tea', 'चाय पिएँ', 'চা খান', 'চাহ খাওক'),
    Item('🥣', 'Have breakfast', 'नाश्ता करें', 'সকালের খাবার খান', 'পুৱাৰ আহাৰ খাওক'),
    Item('🚶', 'Go for a walk', 'सैर पर जाएँ', 'হাঁটতে যান', 'খোজ কাঢ়িবলৈ যাওক'),
  ]),
  Routine('Making tea', 'चाय बनाना', 'চা বানানো', 'চাহ বনোৱা', [
    Item('💧', 'Boil water', 'पानी उबालें', 'জল ফোটান', 'পানী উতলাওক'),
    Item('🍃', 'Add tea leaves', 'चायपत्ती डालें', 'চা-পাতা দিন', 'চাহপাত দিয়ক'),
    Item('🥛', 'Add milk', 'दूध डालें', 'দুধ দিন', 'গাখীৰ দিয়ক'),
    Item('🍬', 'Add sugar', 'चीनी डालें', 'চিনি দিন', 'চেনি দিয়ক'),
    Item('☕', 'Pour into a cup', 'कप में डालें', 'কাপে ঢালুন', 'কাপত ঢালক'),
    Item('😋', 'Drink it', 'पिएँ', 'খান', 'খাওক'),
  ]),
  Routine('Evening', 'शाम', 'সন্ধ্যা', 'সন্ধিয়া', [
    Item('🍚', 'Have dinner', 'रात का खाना खाएँ', 'রাতের খাবার খান', 'ৰাতিৰ আহাৰ খাওক'),
    Item('🦷', 'Brush teeth', 'दाँत साफ़ करें', 'দাঁত মাজুন', 'দাঁত ঘহক'),
    Item('💊', 'Take medicine', 'दवा लें', 'ওষুধ খান', 'দৰব খাওক'),
    Item('🙏', 'Pray', 'प्रार्थना करें', 'প্রার্থনা করুন', 'প্ৰাৰ্থনা কৰক'),
    Item('🛏️', 'Go to bed', 'सोने जाएँ', 'ঘুমাতে যান', 'শুবলৈ যাওক'),
  ]),
];
