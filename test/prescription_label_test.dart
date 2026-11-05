import 'package:flutter_test/flutter_test.dart';
import 'package:smriti_assist/features/reminders/reminders_screen.dart';

void main() {
  test('a prescription is written and read back the same way', () {
    final label = medicineLabel('en', 'Metformin', '500 mg', 'after');
    expect(label, 'Metformin · 500 mg · After food');
    final p = parseMedicineLabel('en', label);
    expect((p.name, p.dose, p.food), ('Metformin', '500 mg', 'after'));
  });

  test('dose and food are optional', () {
    expect(medicineLabel('en', ' Aspirin ', '', null), 'Aspirin');
    final p = parseMedicineLabel('en', 'Aspirin');
    expect((p.name, p.dose, p.food), ('Aspirin', '', null));
    final q = parseMedicineLabel('en', 'Vitamin D · With food');
    expect((q.name, q.dose, q.food), ('Vitamin D', '', 'with'));
  });

  test('works in another language and with a label typed freely', () {
    final hi = medicineLabel('hi', 'मेटफॉर्मिन', '500 मिग्रा', 'before');
    expect(hi, 'मेटफॉर्मिन · 500 मिग्रा · खाने से पहले');
    expect(parseMedicineLabel('hi', hi).food, 'before');
    // an older reminder like "Metformin 500 mg, after food" is kept whole as the name
    final old = parseMedicineLabel('en', 'Metformin 500 mg, after food');
    expect((old.name, old.dose, old.food), ('Metformin 500 mg, after food', '', null));
  });
}
