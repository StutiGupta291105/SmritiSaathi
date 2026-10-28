enum ReminderKind { medicine, hydration, activity, appointment }

/// A reminder. Weekly reminders repeat on [daysMask] (bit 0 = Monday ...
/// bit 6 = Sunday); one-off reminders (appointments) set [onDate] instead.
class Reminder {
  const Reminder({
    required this.id,
    required this.kind,
    required this.label,
    required this.hour,
    required this.minute,
    this.daysMask = 127,
    this.onDate,
    this.active = true,
    this.createdAt,
  });

  final String id;
  final ReminderKind kind;

  /// Free text such as a medicine name. Shown only inside the app, never in a
  /// lock-screen notification (data minimisation).
  final String label;
  final int hour;
  final int minute;
  final int daysMask;
  final DateTime? onDate;
  final bool active;

  /// When the reminder was created, so history never counts days before it existed.
  final DateTime? createdAt;

  bool runsOn(DateTime day) => (daysMask >> (day.weekday - 1)) & 1 == 1;
}

/// Next [count] fire times strictly after [from], in local time.
List<DateTime> nextOccurrences(Reminder r, DateTime from, {int count = 1}) {
  if (!r.active || count <= 0) return const [];
  if (r.onDate != null) {
    final at = DateTime(
        r.onDate!.year, r.onDate!.month, r.onDate!.day, r.hour, r.minute);
    return at.isAfter(from) ? [at] : const [];
  }
  if (r.daysMask & 127 == 0) return const [];
  final out = <DateTime>[];
  // Calendar-day stepping (not +24h) keeps the wall-clock time across DST.
  var day = DateTime(from.year, from.month, from.day);
  for (var i = 0; i < 400 && out.length < count; i++) {
    if (r.runsOn(day)) {
      final at = DateTime(day.year, day.month, day.day, r.hour, r.minute);
      if (at.isAfter(from)) out.add(at);
    }
    day = DateTime(day.year, day.month, day.day + 1);
  }
  return out;
}
