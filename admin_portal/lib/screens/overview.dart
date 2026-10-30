import 'package:flutter/material.dart';

import '../api.dart';
import '../ui.dart';

class OverviewPage extends StatefulWidget {
  const OverviewPage(
      {super.key,
      required this.api,
      required this.onError,
      required this.onGo});
  final AdminApi api;
  final void Function(Object e) onError;
  final void Function(int page) onGo;

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  Map<String, dynamic>? _d;
  Object? _error;

  @override
  void initState() {
    super.initState();
    widget.api.overview().then((v) {
      if (mounted) setState(() => _d = v);
    }).catchError((Object e) {
      widget.onError(e);
      if (mounted) setState(() => _error = e);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Text(errorText(_error!), style: const TextStyle(color: Pal.bad));
    }
    final d = _d;
    if (d == null) return const Center(child: CircularProgressIndicator());
    final u = d['users'] as Map<String, dynamic>;
    final l = d['links'] as Map<String, dynamic>;
    return ListView(children: [
      const Text('Overview',
          style: TextStyle(
              fontSize: 24, fontWeight: FontWeight.w800, color: Pal.ink)),
      const SizedBox(height: 4),
      const Text(
          'Everything the server holds, at a glance. Figures marked 24h cover the last day.',
          style: TextStyle(color: Pal.muted)),
      const SizedBox(height: 18),
      Wrap(spacing: 14, runSpacing: 14, children: [
        StatCard('Patients', '${u['patient']}'),
        StatCard('Doctors', '${u['doctor']}',
            hint: '${d['doctors_unverified']} not verified yet',
            color: (d['doctors_unverified'] as int) > 0 ? Pal.warn : Pal.brand),
        StatCard('Caregivers', '${u['caretaker']}'),
        StatCard('Active supervision links', '${l['accepted']}', color: Pal.ok),
        StatCard('Invites waiting', '${l['pending']}'),
        StatCard('Patients with no supervisor',
            '${d['patients_without_supervisor']}',
            color: (d['patients_without_supervisor'] as int) > 0
                ? Pal.warn
                : Pal.ok),
      ]),
      const SizedBox(height: 22),
      const Text('Activity (24h)',
          style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w800, color: Pal.ink)),
      const SizedBox(height: 10),
      Wrap(spacing: 14, runSpacing: 14, children: [
        StatCard('Sign-ins', '${d['logins_24h']}'),
        StatCard('Games played', '${d['sessions_24h']}'),
        StatCard('Chat messages', '${d['messages_24h']}',
            hint: 'count only, never the content'),
        StatCard('Devices for push', '${d['devices']}'),
        StatCard('Care routines set', '${d['care_reminders']}',
            hint: 'by caregivers and doctors'),
      ]),
      const SizedBox(height: 22),
      Row(children: [
        const Text('Security (24h)',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800, color: Pal.ink)),
        TextButton(
            onPressed: () => widget.onGo(6),
            child: const Text('Open Security')),
      ]),
      const SizedBox(height: 6),
      Wrap(spacing: 14, runSpacing: 14, children: [
        StatCard('Wrong sign-in codes', '${d['otp_failed_24h']}',
            color: (d['otp_failed_24h'] as int) > 0 ? Pal.warn : Pal.ok),
        StatCard('Blocked access attempts', '${d['access_denied_24h']}',
            color: (d['access_denied_24h'] as int) > 0 ? Pal.warn : Pal.ok),
        StatCard('Reused login tokens', '${d['refresh_reuse_24h']}',
            color: (d['refresh_reuse_24h'] as int) > 0 ? Pal.bad : Pal.ok),
        StatCard('Admin sign-ins', '${d['admin_logins_24h']}'),
        StatCard('Audit entries in total', '${d['audit_entries']}'),
      ]),
    ]);
  }
}
