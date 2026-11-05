import 'package:flutter/material.dart';

import '../api.dart';
import '../ui.dart';
import 'audit.dart';
import 'overview.dart';
import 'people.dart';
import 'security.dart';
import 'supervision.dart';

typedef SignedOut = void Function([String? why]);

class Shell extends StatefulWidget {
  const Shell({super.key, required this.api, required this.onSignedOut});
  final AdminApi api;
  final SignedOut onSignedOut;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _i = 0;

  static const _items = [
    ('Overview', Icons.dashboard_outlined),
    ('Patients', Icons.elderly_outlined),
    ('Doctors', Icons.medical_services_outlined),
    ('Caregivers', Icons.volunteer_activism_outlined),
    ('Supervision', Icons.account_tree_outlined),
    ('Access log', Icons.fact_check_outlined),
    ('Security', Icons.shield_outlined),
  ];

  /// A 401 anywhere means the 30-minute session ran out.
  void _fail(Object e) {
    if (e is AdminApiException && e.isUnauthorized) {
      widget.onSignedOut('Your session ended. Sign in again.');
    }
  }

  Widget _page() => switch (_i) {
        0 => OverviewPage(
            api: widget.api,
            onError: _fail,
            onGo: (i) => setState(() => _i = i)),
        1 => PatientsPage(api: widget.api, onError: _fail),
        2 => PeoplePage(api: widget.api, role: 'doctor', onError: _fail),
        3 => PeoplePage(api: widget.api, role: 'caretaker', onError: _fail),
        4 => SupervisionPage(api: widget.api, onError: _fail),
        5 => AuditPage(api: widget.api, onError: _fail),
        _ => SecurityPage(api: widget.api, onError: _fail),
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(children: [
        Container(
          width: 220,
          color: Pal.ink,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 24, 20, 4),
              child: Text('Smriti Sathi',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Text('Admin portal',
                  style: TextStyle(color: Color(0xFFB8BFE0), fontSize: 13)),
            ),
            for (var i = 0; i < _items.length; i++)
              InkWell(
                key: ValueKey('nav$i'),
                onTap: () => setState(() => _i = i),
                child: Container(
                  color: i == _i ? Colors.white.withValues(alpha: .12) : null,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(children: [
                    Icon(_items[i].$2, size: 19, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(_items[i].$1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: i == _i
                                    ? FontWeight.w700
                                    : FontWeight.w500))),
                  ]),
                ),
              ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: Pal.ok.withValues(alpha: .25),
                          borderRadius: BorderRadius.circular(10)),
                      child: const Text('READ ONLY',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(height: 8),
                    Text(widget.api.username,
                        style: const TextStyle(color: Colors.white)),
                    TextButton(
                      key: const ValueKey('signOut'),
                      style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          foregroundColor: const Color(0xFFB8BFE0)),
                      onPressed: () => widget.onSignedOut(),
                      child: const Text('Sign out'),
                    ),
                  ]),
            ),
          ]),
        ),
        Expanded(
            child: Padding(padding: const EdgeInsets.all(24), child: _page())),
      ]),
    );
  }
}
