import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/app_database.dart';
import '../../services/api_client.dart';

/// A thin bar that says when the phone cannot reach the server. For a patient it
/// reassures ("everything is saved on this phone") and counts what is waiting to
/// be sent; for a caregiver or doctor it says the screen shows saved information
/// and from when. Nothing is shown while online.
class OfflineBar extends StatefulWidget {
  const OfflineBar({
    super.key,
    required this.api,
    required this.lang,
    this.db,
    this.patientId,
    this.refresh = const Duration(seconds: 5),
  });
  final ApiClient api;
  final String lang;

  /// With a patient's database, the number waiting to send is shown.
  final AppDatabase? db;
  final String? patientId;
  final Duration refresh;

  @override
  State<OfflineBar> createState() => _OfflineBarState();
}

class _OfflineBarState extends State<OfflineBar> {
  int _waiting = 0;
  Timer? _timer;

  String t(String k) => tr(widget.lang, k);

  @override
  void initState() {
    super.initState();
    widget.api.online.addListener(_changed);
    widget.api.waking.addListener(_changed);
    widget.api.staleSince.addListener(_changed);
    widget.api.outboxCount.addListener(_changed);
    _count();
    _timer = Timer.periodic(widget.refresh, (_) => _count());
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.api.online.removeListener(_changed);
    widget.api.waking.removeListener(_changed);
    widget.api.staleSince.removeListener(_changed);
    widget.api.outboxCount.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
    _count();
  }

  Future<void> _count() async {
    final db = widget.db, id = widget.patientId;
    if (db == null || id == null || widget.api.online.value != false) {
      if (_waiting != 0 && mounted) setState(() => _waiting = 0);
      return;
    }
    try {
      final n = await db.pendingSyncCount(id);
      if (mounted && n != _waiting) setState(() => _waiting = n);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final stale = widget.api.staleSince.value;
    final offline = widget.api.online.value == false;
    final waking = widget.api.waking.value;
    if (stale == null && !offline && !waking) return const SizedBox.shrink();
    final text = waking && stale == null
        ? t('wakingBar')
        : stale != null
        ? t('staleBar').replaceAll('{t}', TimeOfDay.fromDateTime(stale).format(context))
        : t('offlineBar');
    return Container(
      key: const ValueKey('offlineBar'),
      width: double.infinity,
      color: const Color(0xFFFFF4D6),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(children: [
        Icon(waking && stale == null ? Icons.cloud_sync_rounded : Icons.cloud_off_rounded, size: 18, color: Palette.ink),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _waiting > 0 && stale == null && !waking
                ? '$text  ·  ${t('offlinePending').replaceAll('{a}', '$_waiting')}'
                : text,
            style: const TextStyle(fontSize: 13, color: Palette.ink, height: 1.25),
          ),
        ),
      ]),
    );
  }
}
