import 'package:flutter/material.dart';

import '../api.dart';
import '../ui.dart';

Color actionColor(String a) {
  if (a.contains('denied') || a.contains('failed') || a.contains('reuse')) {
    return Pal.bad;
  }
  if (a.contains('erased') ||
      a.contains('exported') ||
      a.contains('revoked') ||
      a.contains('consent')) {
    return Pal.warn;
  }
  if (a.startsWith('admin')) return Pal.brand;
  return Pal.muted;
}

/// The access log: every sign-in, view, change and blocked attempt, in order.
class AuditPage extends StatefulWidget {
  const AuditPage({super.key, required this.api, required this.onError});
  final AdminApi api;
  final void Function(Object e) onError;

  @override
  State<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends State<AuditPage> {
  String _action = '';
  int _hours = 0;
  List<String> _actions = const [];
  String? _verify;
  Color _verifyColor = Pal.muted;

  Future<void> _check() async {
    setState(() => _verify = 'Checking…');
    try {
      final v = await widget.api.verifyAudit();
      setState(() {
        _verifyColor = v['ok'] == true ? Pal.ok : Pal.bad;
        _verify = v['ok'] == true
            ? 'Log intact: ${v['entries']} entries, none altered or removed.'
            : 'LOG FAILED VERIFICATION. Entries were changed or removed.';
      });
    } catch (e) {
      widget.onError(e);
      setState(() {
        _verifyColor = Pal.bad;
        _verify = errorText(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('Access log',
            style: TextStyle(
                fontSize: 24, fontWeight: FontWeight.w800, color: Pal.ink)),
        const Spacer(),
        if (_verify != null)
          Text(_verify!,
              key: const ValueKey('verifyResult'),
              style:
                  TextStyle(color: _verifyColor, fontWeight: FontWeight.w700)),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          key: const ValueKey('verifyLog'),
          onPressed: _check,
          icon: const Icon(Icons.verified_outlined, size: 18),
          label: const Text('Check the log is intact'),
        ),
      ]),
      const SizedBox(height: 4),
      const Text(
          'Each entry links to the one before it, so a changed or deleted entry is detected. '
          'Entries hold ids only, never message text or health details.',
          style: TextStyle(color: Pal.muted)),
      const SizedBox(height: 12),
      Expanded(
        child: PagedTable(
          reloadKey: '$_action|$_hours',
          pageSize: 50,
          searchHint: 'Search the detail (patient=… link=…)',
          filters: [
            DropdownButton<String>(
              value: _action,
              items: [
                const DropdownMenuItem(value: '', child: Text('All actions')),
                for (final a in _actions)
                  DropdownMenuItem(value: a, child: Text(a)),
              ],
              onChanged: (v) => setState(() => _action = v ?? ''),
            ),
            const SizedBox(width: 8),
            DropdownButton<int>(
              value: _hours,
              items: const [
                DropdownMenuItem(value: 0, child: Text('All time')),
                DropdownMenuItem(value: 24, child: Text('Last 24 hours')),
                DropdownMenuItem(value: 168, child: Text('Last 7 days')),
                DropdownMenuItem(value: 720, child: Text('Last 30 days')),
              ],
              onChanged: (v) => setState(() => _hours = v ?? 0),
            ),
          ],
          fetch: (o, l, q) async {
            try {
              final j = await widget.api.audit(
                  action: _action,
                  q: q,
                  sinceHours: _hours,
                  offset: o,
                  limit: l);
              final acts = (j['actions'] as List).cast<String>();
              if (acts.length != _actions.length) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _actions = acts);
                });
              }
              return j;
            } catch (e) {
              widget.onError(e);
              rethrow;
            }
          },
          columns: const ['#', 'Time', 'Who', 'Action', 'Detail', 'Hash'],
          cells: (r) => [
            DataCell(Text('${r['id']}')),
            DataCell(Text(fmtTime(r['ts'] as String?))),
            DataCell(Text('${r['actor_name'] ?? r['actor']}')),
            DataCell(
                Chip2('${r['action']}', color: actionColor('${r['action']}'))),
            DataCell(Text('${r['detail']}', overflow: TextOverflow.ellipsis)),
            DataCell(Text('${r['hash']}',
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                    color: Pal.muted))),
          ],
        ),
      ),
    ]);
  }
}
