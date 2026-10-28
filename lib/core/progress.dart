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
