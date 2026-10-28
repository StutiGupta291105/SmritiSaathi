const kRoles = ['patient', 'doctor', 'caretaker'];
const kRelations = [
  'son',
  'daughter',
  'spouse',
  'sibling',
  'grandchild',
  'friend',
  'other',
];

/// Whole years between [dob] and [today] (birthday not yet reached this year
/// means one year less). Never negative.
int ageFromDob(DateTime dob, DateTime today) {
  var age = today.year - dob.year;
  final birthdayPassed = today.month > dob.month ||
      (today.month == dob.month && today.day >= dob.day);
  if (!birthdayPassed) age--;
  return age < 0 ? 0 : age;
}

/// Returns an E.164 number (+<country><number>) or null if it does not look
/// like a phone number. Bare 10-digit numbers get [defaultCountry].
String? normalizePhone(String raw, {String defaultCountry = '+91'}) {
  final cleaned = raw.replaceAll(RegExp(r'[\s\-().]'), '');
  if (cleaned.isEmpty) return null;
  if (cleaned.startsWith('+')) {
    final digits = cleaned.substring(1);
    return RegExp(r'^[1-9]\d{7,14}$').hasMatch(digits) ? '+$digits' : null;
  }
  if (!RegExp(r'^\d+$').hasMatch(cleaned)) return null;
  final national = cleaned.startsWith('0') ? cleaned.substring(1) : cleaned;
  if (defaultCountry == '+91') {
    if (national.length == 12 && national.startsWith('91')) {
      return '+$national';
    }
    return RegExp(r'^[6-9]\d{9}$').hasMatch(national)
        ? '$defaultCountry$national'
        : null;
  }
  return RegExp(r'^\d{7,14}$').hasMatch(national)
      ? '$defaultCountry$national'
      : null;
}

/// Shows only the last 4 digits (+91 ******3210) for on-screen confirmation.
String maskPhone(String e164) => e164.length <= 4
    ? e164
    : '${e164.substring(0, e164.length > 7 ? 3 : 1)} ${'*' * (e164.length - 7).clamp(0, 12)}${e164.substring(e164.length - 4)}';
