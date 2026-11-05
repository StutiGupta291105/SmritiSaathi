import 'package:flutter/material.dart';

import '../api.dart';
import '../ui.dart';

Future<void> showUserDetail(
        BuildContext context, AdminApi api, String userId) =>
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: SizedBox(
            width: 860,
            height: 640,
            child: UserDetail(api: api, userId: userId)),
      ),
    );

class UserDetail extends StatefulWidget {
  const UserDetail({super.key, required this.api, required this.userId});
  final AdminApi api;
  final String userId;

  @override
  State<UserDetail> createState() => _UserDetailState();
}

class _UserDetailState extends State<UserDetail> {
  Map<String, dynamic>? _d;
  Object? _error;

  @override
  void initState() {
    super.initState();
    widget.api.userDetail(widget.userId).then((v) {
      if (mounted) setState(() => _d = v);
    }).catchError((Object e) {
      if (mounted) setState(() => _error = e);
    });
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 170,
              child: Text(k, style: const TextStyle(color: Pal.muted))),
          Expanded(
              child:
                  Text(v, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );

  Widget _links(List rows, {required bool forPatient}) {
    if (rows.isEmpty) {
      return const Text('None', style: TextStyle(color: Pal.muted));
    }
    return DataTable(
      columns: [
        DataColumn(label: Text(forPatient ? 'Supervisor' : 'Patient')),
        const DataColumn(label: Text('Role')),
        const DataColumn(label: Text('Care ID')),
        const DataColumn(label: Text('Status')),
        const DataColumn(label: Text('Since')),
        const DataColumn(label: Text('Messages')),
      ],
      rows: [
        for (final x in rows.cast<Map<String, dynamic>>())
          DataRow(cells: [
            DataCell(
                Text('${forPatient ? x['member_name'] : x['patient_name']}')),
            DataCell(Text('${x['member_role']}')),
            DataCell(Text('${x['member_care_id'] ?? '—'}')),
            DataCell(Chip2('${x['status']}',
                color: x['status'] == 'accepted'
                    ? Pal.ok
                    : (x['status'] == 'pending' ? Pal.warn : Pal.muted))),
            DataCell(Text(fmtTime(x['created_at'] as String?))),
            DataCell(Text('${x['message_count']}')),
          ]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
          child:
              Text(errorText(_error!), style: const TextStyle(color: Pal.bad)));
    }
    final d = _d;
    if (d == null) return const Center(child: CircularProgressIndicator());
    final u = d['user'] as Map<String, dynamic>;
    final p = d['patient'] as Map<String, dynamic>?;
    final consents = p?['consents'] as Map<String, dynamic>?;
    final isPatient = u['role'] == 'patient';
    final activity =
        (d['recent_activity'] as List).cast<Map<String, dynamic>>();
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Text('${u['name']}  ·  ${u['role']}'),
        actions: [
          IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context))
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Panel(
            title: 'Account',
            child: Column(children: [
              _kv('Id', '${u['id']}'),
              _kv('Phone',
                  '••••${u['phone_last4']}  (the full number is not stored)'),
              if (u['care_id'] != null) _kv('Care ID', '${u['care_id']}'),
              if (u['role'] == 'doctor')
                _kv('Registration verified',
                    u['verified'] == true ? 'yes' : 'no'),
              _kv('Joined', fmtTime(u['created_at'] as String?)),
              _kv('Last sign-in', fmtTime(u['last_login_at'] as String?)),
              _kv('Phones registered for push', '${d['devices']}'),
              if (!isPatient)
                _kv('Shares a number for calls',
                    d['contact_phone_shared'] == true ? 'yes' : 'no'),
            ])),
        const SizedBox(height: 14),
        if (p != null) ...[
          Panel(
              title: 'Patient record',
              child: Column(children: [
                _kv('Language', '${p['language']}'),
                _kv('Difficulty baseline (set by caregiver)',
                    'level ${p['baseline_level']}'),
                _kv('Games played',
                    '${p['sessions']}  ·  last ${fmtTime(p['last_played'] as String?)}'),
                _kv('Routines set by care team', '${p['care_reminders']}'),
                _kv('Consent changes recorded', '${p['consent_changes']}'),
              ])),
          const SizedBox(height: 14),
          Panel(
              title: 'Consents (what the patient currently allows)',
              child: Wrap(runSpacing: 6, children: [
                for (final e in consents!.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 18),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Chip2(
                              '${e.key}: ${(e.value as Map)['granted'] == true ? 'allowed' : 'off'}',
                              color: (e.value as Map)['granted'] == true
                                  ? Pal.ok
                                  : Pal.muted),
                          Text(fmtTime((e.value as Map)['at'] as String?),
                              style: const TextStyle(
                                  fontSize: 11, color: Pal.muted)),
                        ]),
                  ),
              ])),
          const SizedBox(height: 14),
          Panel(
              title: 'Supervised by',
              child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: _links((d['supervisors'] as List?) ?? [],
                      forPatient: true))),
        ] else ...[
          Panel(
              title: 'Looks after',
              child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: _links((d['patients'] as List?) ?? [],
                      forPatient: false))),
          const SizedBox(height: 14),
          Panel(
              title: 'Activity totals',
              child: Column(children: [
                _kv('Invitations waiting', '${d['pending_invites']}'),
                _kv('Routines or reminders set', '${d['care_reminders_set']}'),
                _kv('Chat messages sent',
                    '${d['messages_sent']}  (content is never shown here)'),
              ])),
        ],
        const SizedBox(height: 14),
        Panel(
            title: 'Recent activity in the access log',
            child: activity.isEmpty
                ? const Text('Nothing yet', style: TextStyle(color: Pal.muted))
                : Column(children: [
                    for (final e in activity)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(children: [
                          SizedBox(
                              width: 130,
                              child: Text(fmtTime(e['ts'] as String?),
                                  style: const TextStyle(
                                      color: Pal.muted, fontSize: 12.5))),
                          SizedBox(
                              width: 190,
                              child: Text('${e['action']}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12.5))),
                          Expanded(
                              child: Text('${e['detail']}',
                                  style: const TextStyle(fontSize: 12.5))),
                        ]),
                      ),
                  ])),
      ]),
    );
  }
}
