import 'package:flutter/material.dart';

import '../api.dart';
import '../ui.dart';
import 'detail.dart';

Color _statusColor(String s) =>
    s == 'accepted' ? Pal.ok : (s == 'pending' ? Pal.warn : Pal.muted);

/// Who is under whose supervision, and which doctor looks after which patient.
class SupervisionPage extends StatefulWidget {
  const SupervisionPage({super.key, required this.api, required this.onError});
  final AdminApi api;
  final void Function(Object e) onError;

  @override
  State<SupervisionPage> createState() => _SupervisionPageState();
}

class _SupervisionPageState extends State<SupervisionPage> {
  String _status = '', _role = '';

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Supervision',
            style: TextStyle(
                fontSize: 24, fontWeight: FontWeight.w800, color: Pal.ink)),
        const SizedBox(height: 4),
        const Text(
            'Which patient is under whose supervision, and which doctor looks after which patient.',
            style: TextStyle(color: Pal.muted)),
        const SizedBox(height: 10),
        const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [Tab(text: 'By supervisor'), Tab(text: 'All links')]),
        const SizedBox(height: 12),
        Expanded(
          child: TabBarView(children: [
            _BySupervisor(api: widget.api, onError: widget.onError),
            PagedTable(
              reloadKey: '$_status|$_role',
              searchHint: 'Patient, supervisor or Care ID',
              pageSize: 25,
              filters: [
                _drop(
                    'Status',
                    _status,
                    const ['', 'accepted', 'pending', 'declined', 'revoked'],
                    (v) => setState(() => _status = v)),
                const SizedBox(width: 8),
                _drop('Role', _role, const ['', 'doctor', 'caretaker'],
                    (v) => setState(() => _role = v)),
              ],
              fetch: (o, l, q) => widget.api
                  .links(
                      status: _status, role: _role, q: q, offset: o, limit: l)
                  .catchError((Object e) {
                widget.onError(e);
                throw e;
              }),
              columns: const [
                'Patient',
                'Supervisor',
                'Role',
                'Care ID',
                'Status',
                'Since',
                'Last change',
                'Messages'
              ],
              onRow: (r) => showUserDetail(
                  context, widget.api, r['patient_user_id'] as String),
              cells: (r) => [
                DataCell(Text('${r['patient_name']}',
                    style: const TextStyle(fontWeight: FontWeight.w700))),
                DataCell(Row(children: [
                  Text('${r['member_name']}'),
                  if (r['member_role'] == 'doctor' &&
                      r['member_verified'] == true)
                    const Chip2('verified', color: Pal.ok),
                ])),
                DataCell(Text('${r['member_role']}')),
                DataCell(Text('${r['member_care_id'] ?? '—'}')),
                DataCell(Chip2('${r['status']}',
                    color: _statusColor('${r['status']}'))),
                DataCell(Text(fmtTime(r['created_at'] as String?))),
                DataCell(Text(fmtTime(r['updated_at'] as String?))),
                DataCell(Text('${r['message_count']}')),
              ],
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _drop(String label, String value, List<String> opts,
          void Function(String) on) =>
      DropdownButton<String>(
        value: value,
        hint: Text(label),
        items: [
          for (final o in opts)
            DropdownMenuItem(
                value: o,
                child: Text(o.isEmpty ? 'All ${label.toLowerCase()}' : o))
        ],
        onChanged: (v) => on(v ?? ''),
      );
}

/// Every active supervisor with the patients they look after.
class _BySupervisor extends StatefulWidget {
  const _BySupervisor({required this.api, required this.onError});
  final AdminApi api;
  final void Function(Object e) onError;

  @override
  State<_BySupervisor> createState() => _BySupervisorState();
}

class _BySupervisorState extends State<_BySupervisor> {
  List<Map<String, dynamic>>? _rows;
  int _total = 0;
  Object? _error;

  @override
  void initState() {
    super.initState();
    widget.api.links(status: 'accepted', limit: 500).then((j) {
      if (mounted) {
        setState(() {
          _rows = (j['items'] as List).cast<Map<String, dynamic>>();
          _total = j['total'] as int;
        });
      }
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
    final rows = _rows;
    if (rows == null) return const Center(child: CircularProgressIndicator());
    if (rows.isEmpty) {
      return const Center(
          child: Text('No active supervision yet',
              style: TextStyle(color: Pal.muted)));
    }
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      groups
          .putIfAbsent(
              '${r['member_role']}|${r['member_user_id']}|${r['member_name']}|${r['member_care_id']}',
              () => [])
          .add(r);
    }
    final keys = groups.keys.toList()..sort();
    Widget section(String role, String title) {
      final mine = keys.where((k) => k.startsWith('$role|')).toList();
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 8),
          child: Text('$title (${mine.length})',
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800, color: Pal.ink)),
        ),
        for (final k in mine)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Panel(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(k.split('|')[2],
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w800)),
                      const SizedBox(width: 8),
                      Chip2(k.split('|')[3] == 'null'
                          ? 'no Care ID'
                          : k.split('|')[3]),
                      if (role == 'doctor' &&
                          groups[k]!.first['member_verified'] == true)
                        const Chip2('verified', color: Pal.ok),
                      const Spacer(),
                      Text(
                          '${groups[k]!.length} patient${groups[k]!.length == 1 ? '' : 's'}',
                          style: const TextStyle(color: Pal.muted)),
                    ]),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 6, children: [
                      for (final r in groups[k]!)
                        ActionChip(
                          key: ValueKey('patient_${r['id']}'),
                          label: Text('${r['patient_name']}'),
                          onPressed: () => showUserDetail(context, widget.api,
                              r['patient_user_id'] as String),
                        ),
                    ]),
                  ]),
            ),
          ),
      ]);
    }

    return ListView(children: [
      if (_total > rows.length)
        Text(
            'Showing the first ${rows.length} of $_total links. Use "All links" for the rest.',
            style: const TextStyle(color: Pal.warn)),
      section('doctor', 'Doctors and their patients'),
      section('caretaker', 'Caregivers and their patients'),
    ]);
  }
}
