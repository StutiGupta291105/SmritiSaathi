import 'package:flutter/material.dart';

import '../api.dart';
import '../ui.dart';
import 'audit.dart';

class SecurityPage extends StatefulWidget {
  const SecurityPage({super.key, required this.api, required this.onError});
  final AdminApi api;
  final void Function(Object e) onError;

  @override
  State<SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends State<SecurityPage> {
  Map<String, dynamic>? _d;
  Object? _error;

  @override
  void initState() {
    super.initState();
    widget.api.security().then((v) {
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
    final day = d['last_24h'] as Map<String, dynamic>;
    final week = d['last_7d'] as Map<String, dynamic>;
    final events = (d['recent_events'] as List).cast<Map<String, dynamic>>();
    final viewers =
        (d['top_report_viewers_7d'] as List).cast<Map<String, dynamic>>();
    final doctors =
        (d['doctors_unverified'] as List).cast<Map<String, dynamic>>();
    final locked = (d['locked_admins'] as List).cast<String>();
    Color c(int n, Color bad) => n > 0 ? bad : Pal.ok;
    return ListView(children: [
      const Text('Security',
          style: TextStyle(
              fontSize: 24, fontWeight: FontWeight.w800, color: Pal.ink)),
      const SizedBox(height: 14),
      Wrap(spacing: 14, runSpacing: 14, children: [
        StatCard('Wrong sign-in codes (24h)', '${day['otp_failed']}',
            color: c(day['otp_failed'] as int, Pal.warn)),
        StatCard('Blocked access attempts (24h)', '${day['access_denied']}',
            color: c(day['access_denied'] as int, Pal.warn),
            hint: 'someone reached for a patient they are not linked to'),
        StatCard(
            'Reused login tokens (24h)', '${day['refresh_reuse_detected']}',
            color: c(day['refresh_reuse_detected'] as int, Pal.bad)),
        StatCard('Failed admin sign-ins (24h)', '${day['admin_login_failed']}',
            color: c(day['admin_login_failed'] as int, Pal.warn)),
        StatCard('Patient reports viewed (24h)', '${day['report_viewed']}'),
        StatCard('Consent changes (7d)', '${week['consent_recorded']}'),
        StatCard('Data exports (7d)', '${week['patient_exported']}'),
        StatCard('Accounts erased (7d)', '${week['patient_erased']}'),
      ]),
      if (locked.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text('Admin accounts locked right now: ${locked.join(', ')}',
            style:
                const TextStyle(color: Pal.warn, fontWeight: FontWeight.w700)),
      ],
      const SizedBox(height: 18),
      Panel(
          title: 'Doctors waiting for a registration check',
          child: doctors.isEmpty
              ? const Text('None', style: TextStyle(color: Pal.muted))
              : Column(children: [
                  for (final x in doctors)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(children: [
                        SizedBox(
                            width: 220,
                            child: Text('${x['name']}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700))),
                        SizedBox(width: 130, child: Text('${x['care_id']}')),
                        Text('joined ${fmtTime(x['created_at'] as String?)}',
                            style: const TextStyle(color: Pal.muted)),
                      ]),
                    ),
                  const SizedBox(height: 6),
                  const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                          'Verification is done by the operator from the command line, not from this portal.',
                          style: TextStyle(color: Pal.muted, fontSize: 12.5))),
                ])),
      const SizedBox(height: 14),
      Panel(
          title: 'Who viewed the most patient reports this week',
          child: viewers.isEmpty
              ? const Text('None', style: TextStyle(color: Pal.muted))
              : Column(children: [
                  for (final v in viewers)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(children: [
                        SizedBox(
                            width: 280,
                            child: Text('${v['name'] ?? v['actor']}')),
                        Text('${v['views']} views',
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                      ]),
                    ),
                ])),
      const SizedBox(height: 14),
      Panel(
          title: 'Recent security-relevant events',
          child: events.isEmpty
              ? const Text('None', style: TextStyle(color: Pal.muted))
              : Column(children: [
                  for (final e in events)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(children: [
                        SizedBox(
                            width: 130,
                            child: Text(fmtTime(e['ts'] as String?),
                                style: const TextStyle(
                                    color: Pal.muted, fontSize: 12.5))),
                        SizedBox(
                            width: 200,
                            child: Chip2('${e['action']}',
                                color: actionColor('${e['action']}'))),
                        SizedBox(
                            width: 210,
                            child: Text('${e['actor_name'] ?? e['actor']}',
                                style: const TextStyle(fontSize: 12.5))),
                        Expanded(
                            child: Text('${e['detail']}',
                                style: const TextStyle(fontSize: 12.5))),
                      ]),
                    ),
                ])),
    ]);
  }
}
