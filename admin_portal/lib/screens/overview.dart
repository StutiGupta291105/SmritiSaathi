import 'dart:async';

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
  Map<String, dynamic>? _ai;
  bool _aiBusy = false;
  bool _clearing = false;

  Future<void> _testAi() async {
    setState(() {
      _aiBusy = true;
      _ai = null;
    });
    try {
      final r = await widget.api.aiCheck();
      if (mounted) setState(() => _ai = r);
    } catch (e) {
      widget.onError(e);
      if (mounted) setState(() => _ai = {'ok': false, 'error': errorText(e), 'reply': '', 'ms': 0, 'provider': ''});
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  Future<void> _clearAll() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Clear all data?'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text(
                  'This empties every table of the database: all accounts, patients, links, chats, reminders, game results and the access log. The tables stay, and numbering starts again from 1. It cannot be undone.'),
              const SizedBox(height: 12),
              const Text('Type CLEAR ALL DATA to confirm:'),
              const SizedBox(height: 6),
              TextField(
                  key: const ValueKey('clearPhrase'),
                  controller: ctrl,
                  autofocus: true,
                  onChanged: (_) => setD(() {}),
                  decoration: const InputDecoration(border: OutlineInputBorder())),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(
              key: const ValueKey('clearConfirm'),
              style: FilledButton.styleFrom(backgroundColor: Pal.bad),
              onPressed: ctrl.text.trim() == 'CLEAR ALL DATA' ? () => Navigator.pop(c, true) : null,
              child: const Text('Clear everything'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() => _clearing = true);
    try {
      await widget.api.clearAllData('CLEAR ALL DATA');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All data cleared. Every table is empty.')));
      _fetch();
    } catch (e) {
      widget.onError(e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e is AdminApiException && e.status == 403
                ? 'Not allowed: this server is in production mode.'
                : errorText(e))));
      }
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _fetch();
    // New sign-ups, links and alerts show up without leaving the page.
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _fetch());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _fetch() {
    widget.api.overview().then((v) {
      if (mounted) {
        setState(() {
          _d = v;
          _error = null;
        });
      }
    }).catchError((Object e) {
      widget.onError(e);
      // A failed refresh keeps the figures already shown.
      if (mounted && _d == null) setState(() => _error = e);
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
      Panel(
        title: 'AI helper',
        actions: [
          FilledButton(
            key: const ValueKey('testAi'),
            onPressed: _aiBusy ? null : _testAi,
            child: Text(_aiBusy ? 'Asking…' : 'Test the AI helper'),
          ),
        ],
        child: _ai == null
            ? const Text(
                'The health check only proves a key exists. This asks the helper one made-up question and shows whether it really answers.',
                style: TextStyle(color: Pal.muted))
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_ai!['ok'] == true ? 'Working (${_ai!['ms']} ms, ${_ai!['provider']})' : 'Not answering',
                    key: const ValueKey('aiResult'),
                    style: TextStyle(fontWeight: FontWeight.w800, color: _ai!['ok'] == true ? Pal.ok : Pal.bad)),
                if ('${_ai!['reply']}'.isNotEmpty) Text('Reply: ${_ai!['reply']}'),
                if ('${_ai!['error']}'.isNotEmpty) Text('Why: ${_ai!['error']}', style: const TextStyle(color: Pal.bad)),
              ]),
      ),
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
      const SizedBox(height: 22),
      Panel(
        title: 'Clear all data (test servers)',
        actions: [
          FilledButton(
            key: const ValueKey('clearAll'),
            style: FilledButton.styleFrom(backgroundColor: Pal.bad),
            onPressed: _clearing ? null : _clearAll,
            child: Text(_clearing ? 'Clearing…' : 'Clear all data'),
          ),
        ],
        child: const Text(
            'Empties every table, the access log included, and restarts the numbering. You must type a phrase to confirm. A production server refuses.',
            style: TextStyle(color: Pal.muted)),
      ),
    ]);
  }
}
