import 'package:flutter_test/flutter_test.dart';
import 'package:smriti_assist/core/profile.dart';

void main() {
  test('age is whole years and respects the birthday', () {
    final dob = DateTime(1950, 6, 15);
    expect(ageFromDob(dob, DateTime(2026, 6, 14)), 75);
    expect(ageFromDob(dob, DateTime(2026, 6, 15)), 76);
    expect(ageFromDob(dob, DateTime(2026, 12, 1)), 76);
    expect(ageFromDob(DateTime(2030, 1, 1), DateTime(2026, 1, 1)), 0);
  });

  test('normalizePhone accepts common Indian formats', () {
    expect(normalizePhone('98765 43210'), '+919876543210');
    expect(normalizePhone('09876543210'), '+919876543210');
    expect(normalizePhone('+91 98765-43210'), '+919876543210');
    expect(normalizePhone('919876543210'), '+919876543210');
  });

  test('normalizePhone rejects junk and short numbers', () {
    expect(normalizePhone(''), isNull);
    expect(normalizePhone('12345'), isNull);
    expect(normalizePhone('5876543210'), isNull); // Indian mobiles start 6-9
    expect(normalizePhone('abcdefghij'), isNull);
    expect(normalizePhone('+0123456789'), isNull);
  });

  test('normalizePhone keeps other countries when + is given', () {
    expect(normalizePhone('+44 7911 123456'), '+447911123456');
  });

  test('maskPhone hides the middle digits', () {
    expect(maskPhone('+919876543210'), endsWith('3210'));
    expect(maskPhone('+919876543210'), isNot(contains('98765')));
  });
}
