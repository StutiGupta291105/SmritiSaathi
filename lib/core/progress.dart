/// Consecutive local calendar days with at least one session, counted back
/// from [today]. A streak is still alive if the last session was yesterday.
int currentStreak(Iterable<DateTime> sessionTimes, DateTime today) {
  final days = {
    for (final t in sessionTimes) DateTime(t.year, t.month, t.day),
  };
  var day = DateTime(today.year, today.month, today.day);
  if (!days.contains(day)) day = DateTime(day.year, day.month, day.day - 1);
  var n = 0;
  while (days.contains(day)) {
    n++;
    day = DateTime(day.year, day.month, day.day - 1);
  }
  return n;
}

/// Sessions per day for the 7 days ending [today] (oldest first).
List<int> sessionsLast7Days(Iterable<DateTime> sessionTimes, DateTime today) {
  final start = DateTime(today.year, today.month, today.day - 6);
  final counts = List<int>.filled(7, 0);
  for (final t in sessionTimes) {
    final d = DateTime(t.year, t.month, t.day);
    final i = d.difference(start).inDays;
    if (i >= 0 && i < 7) counts[i]++;
  }
  return counts;
}

/// Longest run of consecutive local calendar days with at least one session.
int bestStreak(Iterable<DateTime> sessionTimes) {
  final days = {
    for (final t in sessionTimes) DateTime(t.year, t.month, t.day),
  }.toList()
    ..sort();
  var best = 0, run = 0;
  DateTime? prev;
  for (final d in days) {
    run = (prev != null && DateTime(prev.year, prev.month, prev.day + 1) == d)
        ? run + 1
        : 1;
    if (run > best) best = run;
    prev = d;
  }
  return best;
}
