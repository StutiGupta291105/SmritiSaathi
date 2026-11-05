import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../reminders/reminder_style.dart';
import '../../core/reminder_schedule.dart';

/// One thing planned for today, for the caregiver's timeline.
class TodayItem {
  const TodayItem(this.at, this.kind, this.label, {this.patient = '', this.addedBy = ''});
  final DateTime at;
  final ReminderKind kind;
  final String label, patient, addedBy;
}

/// The routines set for today, from a list of care reminders as the server sends
/// them (kind, label, hour, minute, days_mask, on_date), soonest first. Anything
/// that does not fall on today is left out.
List<TodayItem> todayItems(List<Map<String, dynamic>> care, DateTime now,
    {String patient = ''}) {
  final startOfDay = DateTime(now.year, now.month, now.day);
  final out = <TodayItem>[];
  for (final x in care) {
    final kind = ReminderKind.values.firstWhere((k) => k.name == x['kind'],
        orElse: () => ReminderKind.activity);
    final on = x['on_date'] == null ? null : DateTime.tryParse('${x['on_date']}');
    final r = Reminder(
      id: '${x['id']}',
      kind: kind,
      label: '${x['label'] ?? ''}',
      hour: (x['hour'] as num).toInt(),
      minute: (x['minute'] as num).toInt(),
      daysMask: (x['days_mask'] as num?)?.toInt() ?? 127,
      onDate: on,
    );
    final next = nextOccurrences(r, startOfDay.subtract(const Duration(seconds: 1)));
    if (next.isEmpty) continue;
    final at = next.first;
    if (at.year == now.year && at.month == now.month && at.day == now.day) {
      out.add(TodayItem(at, kind, r.label,
          patient: patient, addedBy: '${x['created_by_name'] ?? ''}'));
    }
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out;
}

/// Today as a line through the day, in the same style as the patient's own home:
/// what is already past is soft, the next one glows ("now").
class CareTimeline extends StatelessWidget {
  const CareTimeline({
    super.key,
    required this.title,
    required this.empty,
    required this.items,
    required this.lang,
    required this.now,
    this.maxItems = 6,
  });
  final String title, empty, lang;
  final List<TodayItem> items;
  final DateTime now;
  final int maxItems;

  @override
  Widget build(BuildContext context) {
    // A long day shows a window around "now" (the last thing done, then what is next).
    var shown = items;
    if (items.length > maxItems) {
      final next = items.indexWhere((x) => !x.at.isBefore(now));
      final start = next < 0
          ? items.length - maxItems
          : (next - 1).clamp(0, items.length - maxItems);
      shown = items.sublist(start, start + maxItems);
    }
    final nowIndex = shown.indexWhere((x) => !x.at.isBefore(now));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title,
          style: const TextStyle(
              fontSize: 20, fontWeight: FontWeight.w700, color: Palette.brandDeep)),
      const SizedBox(height: 10),
      if (shown.isEmpty)
        Text(empty,
            key: const ValueKey('noTimeline'),
            style: const TextStyle(fontSize: 15, color: Palette.muted, height: 1.35))
      else
        for (var i = 0; i < shown.length; i++)
          _Row(
            item: shown[i],
            lang: lang,
            first: i == 0,
            last: i == shown.length - 1,
            isNow: i == nowIndex,
            past: shown[i].at.isBefore(now),
          ),
    ]);
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.item,
    required this.lang,
    required this.first,
    required this.last,
    required this.isNow,
    required this.past,
  });
  final TodayItem item;
  final String lang;
  final bool first, last, isNow, past;

  @override
  Widget build(BuildContext context) {
    final style = kindStyle(item.kind);
    final label = item.label.isEmpty ? tr(lang, 'kind_${item.kind.name}') : item.label;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 62,
          child: Stack(alignment: Alignment.topCenter, children: [
            Positioned.fill(
              child: Align(
                alignment: Alignment.center,
                child: Container(
                  width: 4,
                  margin: EdgeInsets.only(top: first ? 32 : 0, bottom: last ? 32 : 0),
                  decoration: BoxDecoration(
                      color: const Color(0xFFE1D6C4), borderRadius: BorderRadius.circular(2)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Container(
                key: isNow ? const ValueKey('timelineNow') : null,
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: past ? Palette.tileGreen : style.bg,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    if (isNow)
                      BoxShadow(
                          color: Palette.action.withValues(alpha: 0.35),
                          blurRadius: 0,
                          spreadRadius: 5),
                    const BoxShadow(
                        color: Color(0x26000000), blurRadius: 8, offset: Offset(0, 3)),
                  ],
                ),
                child: Icon(past ? Icons.check_rounded : style.icon,
                    size: 24, color: past ? Palette.action : style.fg),
              ),
            ),
          ]),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppCard(
              color: past ? const Color(0xFFF4F7F3) : Colors.white,
              padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: past ? Palette.muted : Palette.ink)),
                Text(
                    [
                      TimeOfDay.fromDateTime(item.at).format(context),
                      if (item.patient.isNotEmpty) item.patient,
                    ].join(' · '),
                    style: const TextStyle(fontSize: 13.5, color: Palette.muted)),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
