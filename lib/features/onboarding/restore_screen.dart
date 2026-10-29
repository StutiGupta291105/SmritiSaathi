import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';

/// Shown after signing in on a new phone when the server already holds this
/// person's progress.
class RestoreScreen extends StatefulWidget {
  const RestoreScreen({
    super.key,
    required this.name,
    required this.lang,
    required this.onRestore,
    required this.onStartFresh,
  });
  final String name, lang;

  /// Returns false when restoring failed (e.g. no connection).
  final Future<bool> Function() onRestore;
  final VoidCallback onStartFresh;

  @override
  State<RestoreScreen> createState() => _RestoreScreenState();
}

class _RestoreScreenState extends State<RestoreScreen> {
  bool _busy = false;
  bool _failed = false;

  String t(String k) => tr(widget.lang, k);

  Future<void> _restore() async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    final ok = await widget.onRestore();
    if (mounted && !ok) {
      setState(() {
        _busy = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 24),
            const BrandLogo(),
            const SizedBox(height: 24),
            Text('${t('rsWelcomeBack')}, ${widget.name}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: Palette.brandDeep)),
            const SizedBox(height: 12),
            Text(t('rsBody'),
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            Text(t('rsNote'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Palette.muted)),
            if (_failed)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(t('errOffline'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Palette.red, fontSize: 18, fontWeight: FontWeight.w600)),
              ),
            const SizedBox(height: 24),
            FilledButton(
                onPressed: _busy ? null : _restore, child: Text(t('rsRestore'))),
            const SizedBox(height: 8),
            TextButton(
                onPressed: _busy ? null : widget.onStartFresh,
                child: Text(t('rsFresh'), style: const TextStyle(fontSize: 18))),
          ],
        ),
      ),
    );
  }
}
