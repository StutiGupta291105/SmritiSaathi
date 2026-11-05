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

/// How often one scheduled notification repeats by itself.
enum AlertRepeat { none, daily, weekly, yearly }

/// A notification the phone repeats on its own (the OS keeps repeating it with
/// no help from the app), so reminders keep ringing even if the app is not
/// opened for weeks. [first] is the first time it rings; later times follow
/// from [repeat].
class RepeatingAlert {
  const RepeatingAlert(this.first, this.kind, this.headsUp, this.repeat);
  final DateTime first;
  final ReminderKind kind;
  final bool headsUp;
  final AlertRepeat repeat;
}

/// The next time of a repeating alert strictly after [now], stepping by whole
/// calendar days (not 24h) so the wall-clock time survives a DST change.
DateTime _firstAfter(DateTime t, DateTime now, AlertRepeat repeat) {
  var out = t;
  while (!out.isAfter(now)) {
    switch (repeat) {
      case AlertRepeat.daily:
        out = DateTime(out.year, out.month, out.day + 1, out.hour, out.minute);
      case AlertRepeat.weekly:
        out = DateTime(out.year, out.month, out.day + 7, out.hour, out.minute);
      case AlertRepeat.yearly:
        out = DateTime(out.year + 1, out.month, out.day, out.hour, out.minute);
      case AlertRepeat.none:
        return out;
    }
  }
  return out;
}

/// What to hand to the OS so it repeats reminders by itself:
///  * every-day reminders: one daily alarm (plus one daily heads-up),
///  * some days of the week: one weekly alarm per day (plus heads-ups),
///  * birthdays: yearly,
///  * dated appointments and events: one-off.
/// The platform keeps at most [limit] pending (iOS: 64), so the alerts at the
/// time itself are kept before the 30-minute heads-ups.
List<RepeatingAlert> repeatingAlerts(List<Reminder> reminders, DateTime now,
    {int limit = 60}) {
  final main = <RepeatingAlert>[];
  final heads = <RepeatingAlert>[];
  void add(DateTime at, ReminderKind kind, AlertRepeat repeat) {
    main.add(RepeatingAlert(at, kind, false, repeat));
    final before = _firstAfter(at.subtract(kReminderLead), now, repeat);
    // A one-off heads-up that is already past is simply skipped.
    if (repeat != AlertRepeat.none || before.isAfter(now)) {
      heads.add(RepeatingAlert(before, kind, true, repeat));
    }
  }

  for (final r in reminders) {
    if (!r.active) continue;
    if (r.onDate != null) {
      final next = nextOccurrences(r, now);
      if (next.isEmpty) continue;
      add(next.first,
          r.kind, r.kind == ReminderKind.birthday ? AlertRepeat.yearly : AlertRepeat.none);
      continue;
    }
    final mask = r.daysMask & 127;
    if (mask == 0) continue;
    if (mask == 127) {
      final next = nextOccurrences(r, now);
      if (next.isNotEmpty) add(next.first, r.kind, AlertRepeat.daily);
      continue;
    }
    var days = 0;
    for (var b = 0; b < 7; b++) {
      if ((mask >> b) & 1 == 1) days++;
    }
    // The next [days] occurrences are exactly one per chosen weekday.
    for (final at in nextOccurrences(r, now, count: days)) {
      add(at, r.kind, AlertRepeat.weekly);
    }
  }
  main.sort((a, b) => a.first.compareTo(b.first));
  heads.sort((a, b) => a.first.compareTo(b.first));
  return [...main, ...heads].take(limit).toList();
}
