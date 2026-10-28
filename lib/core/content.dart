/// Culturally familiar content shared by all games. Widely supported emoji are
/// used so nothing needs to be downloaded (offline-first). Later: regional
/// packs per language and caregiver-added family photos and names.
class Item {
  const Item(this.emoji, this.en, this.hi);
  final String emoji, en, hi;
  String label(String lang) => lang == 'hi' ? hi : en;
}

const kObjects = [
  Item('🥭', 'Mango', 'आम'),
  Item('🌼', 'Marigold', 'गेंदा'),
  Item('☕', 'Tea', 'चाय'),
  Item('🐄', 'Cow', 'गाय'),
  Item('🥥', 'Coconut', 'नारियल'),
  Item('🍌', 'Banana', 'केला'),
  Item('🌺', 'Hibiscus', 'गुड़हल'),
  Item('🚲', 'Bicycle', 'साइकिल'),
  Item('🪔', 'Diya', 'दीया'),
  Item('🛺', 'Auto-rickshaw', 'ऑटो रिक्शा'),
  Item('🍛', 'Dal and rice', 'दाल-चावल'),
  Item('🌾', 'Rice plant', 'धान'),
];

/// Look-alike pairs for the harder attention levels (target vs distractor).
const kLookAlikes = [
  (Item('🌼', 'Marigold', 'गेंदा'), Item('🌻', 'Sunflower', 'सूरजमुखी')),
  (Item('🍎', 'Apple', 'सेब'), Item('🍅', 'Tomato', 'टमाटर')),
  (Item('🥭', 'Mango', 'आम'), Item('🍑', 'Peach', 'आड़ू')),
  (Item('🐄', 'Cow', 'गाय'), Item('🐃', 'Buffalo', 'भैंस')),
  (Item('🍌', 'Banana', 'केला'), Item('🌽', 'Corn', 'भुट्टा')),
];

/// Everyday sequences in their usual order. The order is a common one, not the
/// only one; caregivers will be able to edit routines to match the person's day.
class Routine {
  const Routine(this.en, this.hi, this.steps);
  final String en, hi;
  final List<Item> steps;
}

const kRoutines = [
  Routine('Morning', 'सुबह', [
    Item('🛏️', 'Wake up', 'उठें'),
    Item('🦷', 'Brush teeth', 'दाँत साफ़ करें'),
    Item('🚿', 'Take a bath', 'नहाएँ'),
    Item('🙏', 'Pray', 'पूजा करें'),
    Item('☕', 'Drink tea', 'चाय पिएँ'),
    Item('🥣', 'Have breakfast', 'नाश्ता करें'),
    Item('🚶', 'Go for a walk', 'सैर पर जाएँ'),
  ]),
  Routine('Making tea', 'चाय बनाना', [
    Item('💧', 'Boil water', 'पानी उबालें'),
    Item('🍃', 'Add tea leaves', 'चायपत्ती डालें'),
    Item('🥛', 'Add milk', 'दूध डालें'),
    Item('🍬', 'Add sugar', 'चीनी डालें'),
    Item('☕', 'Pour into a cup', 'कप में डालें'),
    Item('😋', 'Drink it', 'पिएँ'),
  ]),
  Routine('Evening', 'शाम', [
    Item('🍚', 'Have dinner', 'रात का खाना खाएँ'),
    Item('🦷', 'Brush teeth', 'दाँत साफ़ करें'),
    Item('💊', 'Take medicine', 'दवा लें'),
    Item('🙏', 'Pray', 'प्रार्थना करें'),
    Item('🛏️', 'Go to bed', 'सोने जाएँ'),
  ]),
];
