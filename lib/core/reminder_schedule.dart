enum ReminderKind { medicine, hydration, activity, appointment, birthday, event }

/// A reminder. Weekly reminders repeat on [daysMask] (bit 0 = Monday ...
/// bit 6 = Sunday); dated reminders (appointments, events) set [onDate] and
/// happen once; a birthday also sets [onDate] but repeats every year.
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
    this.addedBy,
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

  /// Set when a caregiver or doctor added it: their name.
  final String? addedBy;

  bool runsOn(DateTime day) => (daysMask >> (day.weekday - 1)) & 1 == 1;
}

/// Next [count] fire times strictly after [from], in local time.
List<DateTime> nextOccurrences(Reminder r, DateTime from, {int count = 1}) {
  if (!r.active || count <= 0) return const [];
  if (r.onDate != null && r.kind == ReminderKind.birthday) {
    final d = r.onDate!;
    var at = DateTime(from.year, d.month, d.day, r.hour, r.minute);
    if (!at.isAfter(from)) {
      at = DateTime(from.year + 1, d.month, d.day, r.hour, r.minute);
    }
    return [at];
  }
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


/// How long before a routine or reminder the heads-up notification goes off.
const kReminderLead = Duration(minutes: 30);

/// One notification to schedule: when, for which kind, and whether it is the
/// "in 30 minutes" heads-up rather than the one at the time itself.
class PlannedAlert {
  const PlannedAlert(this.at, this.kind, this.headsUp);
  final DateTime at;
  final ReminderKind kind;
  final bool headsUp;
}

/// Two alerts per occurrence (30 minutes before, and at the time), soonest
/// first, at most [limit] (iOS keeps 64 pending local notifications). A
/// heads-up that would already be in the past is left out.
List<PlannedAlert> plannedAlerts(List<Reminder> reminders, DateTime now,
    {int perReminder = 14, int limit = 60}) {
  final out = <PlannedAlert>[];
  for (final r in reminders) {
    for (final at in nextOccurrences(r, now, count: perReminder)) {
      out.add(PlannedAlert(at, r.kind, false));
      final before = at.subtract(kReminderLead);
      if (before.isAfter(now)) out.add(PlannedAlert(before, r.kind, true));
    }
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out.take(limit).toList();
}
