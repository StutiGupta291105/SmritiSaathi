import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/app_database.dart';
import '../onboarding/onboarding_screen.dart' show kNoticeVersion;

/// Shows [child] only while the purpose is consented. Otherwise shows the
/// purpose in plain words with an Allow button, so a page never touches
/// personal data the person has not agreed to.
class ConsentGate extends StatefulWidget {
  const ConsentGate({
    super.key,
    required this.db,
    required this.patientId,
    required this.purpose,
    required this.purposeTextKey,
    required this.lang,
    required this.byName,
    required this.child,
    this.onChanged,
  });
  final AppDatabase db;
  final String patientId;
  final String purpose;
  final String purposeTextKey;
  final String lang;
  final String byName;
  final Widget child;
  final VoidCallback? onChanged;

  @override
  State<ConsentGate> createState() => _ConsentGateState();
}

class _ConsentGateState extends State<ConsentGate> {
  bool? _granted;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final g = await widget.db.hasConsent(widget.patientId, widget.purpose);
    if (mounted) setState(() => _granted = g);
  }

  Future<void> _allow() async {
    await widget.db.recordConsent(
      patientId: widget.patientId,
      purposes: {widget.purpose: true},
      givenByName: widget.byName,
      givenByRelation: 'self_or_guardian',
      noticeVersion: kNoticeVersion,
    );
    await _load();
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_granted == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_granted!) return widget.child;
    return AppCard(
      color: Palette.tileOrange,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr(widget.lang, widget.purposeTextKey),
              style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                  color: Palette.brandDeep)),
          const SizedBox(height: 12),
          FilledButton(onPressed: _allow, child: Text(tr(widget.lang, 'allow'))),
        ],
      ),
    );
  }
}
