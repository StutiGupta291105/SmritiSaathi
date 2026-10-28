import 'package:flutter/material.dart';

import '../../core/reminder_schedule.dart';
import '../../core/theme.dart';

/// Icon and colours for each kind of reminder, as on the design sheet:
/// medicine red, water blue, activity orange, appointment purple.
class KindStyle {
  const KindStyle(this.icon, this.fg, this.bg);
  final IconData icon;
  final Color fg, bg;
}

KindStyle kindStyle(ReminderKind k) => switch (k) {
      ReminderKind.medicine =>
        const KindStyle(Icons.medication_rounded, Palette.red, Palette.tileRed),
      ReminderKind.hydration => const KindStyle(
          Icons.water_drop_rounded, Palette.blue, Palette.tileBlue),
      ReminderKind.activity => const KindStyle(
          Icons.directions_walk_rounded, Palette.orange, Palette.tileOrange),
      ReminderKind.appointment => const KindStyle(
          Icons.event_rounded, Palette.purple, Palette.tilePurple),
    };
