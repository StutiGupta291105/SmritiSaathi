import 'package:flutter/material.dart';

import '../api.dart';
import '../ui.dart';
import 'detail.dart';

String _names(List l) =>
    l.isEmpty ? '—' : l.map((x) => (x as Map)['name']).join(', ');

class PatientsPage extends StatelessWidget {
  const PatientsPage({super.key, required this.api, required this.onError});
  final AdminApi api;
  final void Function(Object e) onError;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Patients',
          style: TextStyle(
              fontSize: 24, fontWeight: FontWeight.w800, color: Pal.ink)),
      const SizedBox(height: 12),
      Expanded(
        child: PagedTable(
          searchHint: 'Name, last 4 digits or id',
          fetch: (o, l, q) =>
              api.patients(q: q, offset: o, limit: l).catchError((Object e) {
            onError(e);
            throw e;
          }),
          columns: const [
            'Patient',
            'Phone',
            'Caregivers',
            'Doctors',
            'Sharing',
            'Games',
            'Last played',
            'Joined'
          ],
          onRow: (r) => showUserDetail(context, api, r['user_id'] as String),
          cells: (r) {
            final s = r['sharing'] as Map<String, dynamic>;
            return [
              DataCell(Text('${r['name']}',
                  style: const TextStyle(fontWeight: FontWeight.w700))),
              DataCell(Text('••••${r['phone_last4']}')),
              DataCell(Text(_names(r['caregivers'] as List))),
              DataCell(Text(_names(r['doctors'] as List))),
              DataCell(Row(children: [
                if (s['caregiver'] == true)
                  const Chip2('caregiver', color: Pal.ok),
                if (s['doctor'] == true)
                  const Chip2('doctor', color: Pal.brand),
                if (s['sync'] == true) const Chip2('sync'),
                if (s['companion'] == true) const Chip2('AI'),
              ])),
              DataCell(Text('${r['sessions']}')),
              DataCell(Text(fmtTime(r['last_played'] as String?))),
              DataCell(Text(fmtTime(r['created_at'] as String?))),
            ];
          },
        ),
      ),
    ]);
  }
}

/// Doctors or caregivers.
class PeoplePage extends StatelessWidget {
  const PeoplePage(
      {super.key,
      required this.api,
      required this.role,
      required this.onError});
  final AdminApi api;
  final String role;
  final void Function(Object e) onError;

  @override
  Widget build(BuildContext context) {
    final doctors = role == 'doctor';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(doctors ? 'Doctors' : 'Caregivers',
          style: const TextStyle(
              fontSize: 24, fontWeight: FontWeight.w800, color: Pal.ink)),
      const SizedBox(height: 12),
      Expanded(
        child: PagedTable(
          searchHint: 'Name, Care ID, last 4 digits',
          fetch: (o, l, q) => api
              .users(role: role, q: q, offset: o, limit: l)
              .catchError((Object e) {
            onError(e);
            throw e;
          }),
          columns: [
            'Name',
            'Care ID',
            'Phone',
            if (doctors) 'Verified',
            'Patients',
            'Last sign-in',
            'Joined'
          ],
          onRow: (r) => showUserDetail(context, api, r['id'] as String),
          cells: (r) => [
            DataCell(Text('${r['name']}',
                style: const TextStyle(fontWeight: FontWeight.w700))),
            DataCell(Text('${r['care_id'] ?? '—'}')),
            DataCell(Text('••••${r['phone_last4']}')),
            if (doctors)
              DataCell(r['verified'] == true
                  ? const Chip2('verified', color: Pal.ok)
                  : const Chip2('not verified', color: Pal.warn)),
            DataCell(Text('${r['patients'] ?? 0}')),
            DataCell(Text(fmtTime(r['last_login_at'] as String?))),
            DataCell(Text(fmtTime(r['created_at'] as String?))),
          ],
        ),
      ),
    ]);
  }
}
