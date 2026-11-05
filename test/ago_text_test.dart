import 'package:flutter_test/flutter_test.dart';
import 'package:smriti_assist/core/dates.dart';

void main() {
  final now = DateTime(2026, 5, 10, 12);
  test('English reads naturally for one hour and one day', () {
    expect(agoText('en', now.subtract(const Duration(hours: 1, minutes: 5)), now), '1 hour ago');
    expect(agoText('en', now.subtract(const Duration(hours: 3)), now), '3 hours ago');
    expect(agoText('en', now.subtract(const Duration(days: 1, hours: 2)), now), '1 day ago');
    expect(agoText('en', now.subtract(const Duration(days: 4)), now), '4 days ago');
    expect(agoText('en', now.subtract(const Duration(minutes: 30)), now), '30 min ago');
  });
  test('other languages are unchanged', () {
    expect(agoText('hi', now.subtract(const Duration(hours: 1, minutes: 5)), now), '1 घंटे पहले');
  });
}
