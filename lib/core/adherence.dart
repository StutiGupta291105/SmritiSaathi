import 'reminder_schedule.dart';

/// Whether reminders were marked done. "Not marked done" is all this can say:
/// a person may have taken their medicine and simply not tapped, so every
/// message built on it is worded that way.

/// Key under which a done mark is stored: the reminder and the local day.
String doneKey(String reminderId, DateTime day) =>
    '$reminderId|${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

/// One reminder that was due on one day.
class DueItem {
  const DueItem(this.reminder, this.day, this.at);
  final Reminder reminder;
  final DateTime day; // local midnight
  final DateTime at; // the time it fell due
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

bool occursOn(Reminder r, DateTime day) {
  if (!r.active) return false;
  if (r.onDate != null && r.kind == ReminderKind.birthday) {
    return r.onDate!.month == day.month && r.onDate!.day == day.day;
  }
  if (r.onDate != null) return _sameDay(r.onDate!, day);
  return r.runsOn(day);
}

/// Everything that fell due in the [days] days up to and including today, and
/// whose time has already passed at [now]. Days before the reminder was
/// created are not counted.
List<DueItem> dueItems(List<Reminder> reminders, DateTime now, {int days = 7}) {
  final today = DateTime(now.year, now.month, now.day);
  final out = <DueItem>[];
  for (final r in reminders) {
    for (var i = 0; i < days; i++) {
      final day = DateTime(today.year, today.month, today.day - i);
      if (!occursOn(r, day)) continue;
      final at = DateTime(day.year, day.month, day.day, r.hour, r.minute);
      if (at.isAfter(now)) continue;
      if (r.createdAt != null && at.isBefore(r.createdAt!)) continue;
      out.add(DueItem(r, day, at));
    }
  }
  return out;
}

class AdherenceSummary {
  const AdherenceSummary(this.expected, this.done);
  final int expected, done;

  /// 0..1; 1 when nothing was due.
  double get rate => expected == 0 ? 1 : done / expected;
}

AdherenceSummary adherence(
  List<Reminder> reminders,
  Set<String> doneKeys,
  DateTime now, {
  int days = 7,
}) {
  final due = dueItems(reminders, now, days: days);
  final done =
      due.where((d) => doneKeys.contains(doneKey(d.reminder.id, d.day))).length;
  return AdherenceSummary(due.length, done);
}

/// Medicine reminders from today that fell due at least [grace] ago and are
/// still not marked done.
List<DueItem> overdueMedicines(
  List<Reminder> reminders,
  Set<String> doneKeys,
  DateTime now, {
  Duration grace = const Duration(hours: 2),
}) =>
    dueItems(reminders, now, days: 1)
        .where((d) =>
            d.reminder.kind == ReminderKind.medicine &&
            !d.at.add(grace).isAfter(now) &&
            !doneKeys.contains(doneKey(d.reminder.id, d.day)))
        .toList();
