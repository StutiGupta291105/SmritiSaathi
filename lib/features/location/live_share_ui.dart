import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/app_database.dart';
import '../../services/api_client.dart';
import '../../services/live_share.dart';

String _clockText(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'am' : 'pm'}';
}

/// Top of the patient's home screen: one big button to share the live
/// location, or, while sharing, who/until when and a Stop button.
class LiveLocationCard extends StatelessWidget {
  const LiveLocationCard({
    super.key,
    required this.controller,
    required this.lang,
    required this.onShare,
    this.onOptions,
  });
  final LiveShareController controller;
  final String lang;

  /// One tap: share now with the usual people (no questions).
  final VoidCallback onShare;

  /// The small slider icon: choose who and for how long.
  final VoidCallback? onOptions;

  @override
  Widget build(BuildContext context) {
    String t(String k) => tr(lang, k);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final on = controller.active;
        return AppCard(
          key: ValueKey(on ? 'liveCardOn' : 'liveCardOff'),
          color: on ? Palette.tileGreen : Palette.tileSky,
          onTap: on ? null : onShare,
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(children: [
            IconBadge(
                icon: on ? Icons.my_location_rounded : Icons.location_on_rounded,
                fg: on ? Palette.green : Palette.sky,
                bg: Colors.white,
                size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                    on
                        ? t('liveSharingUntil')
                            .replaceAll('{time}', _clockText(controller.until!))
                        : t('shareLiveLoc'),
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Palette.brandDeep)),
                if (!on)
                  Text(t('shareLiveLocSub'),
                      style: const TextStyle(fontSize: 12.5, color: Palette.muted)),
              ]),
            ),
            if (on)
              FilledButton(
                key: const ValueKey('liveStop'),
                style: FilledButton.styleFrom(
                    backgroundColor: Palette.red,
                    minimumSize: const Size(0, 42),
                    padding: const EdgeInsets.symmetric(horizontal: 14)),
                onPressed: () => controller.stop(),
                child: Text(t('stopSharing'), style: const TextStyle(fontSize: 14)),
              )
            else if (onOptions != null)
              IconButton(
                key: const ValueKey('liveOptions'),
                tooltip: t('shareOptions'),
                icon: const Icon(Icons.tune_rounded, color: Palette.muted),
                onPressed: onOptions,
              ),
          ]),
        );
      },
    );
  }
}

/// Lets the patient choose how long and with whom, then shares. Nothing is
/// sent until the button is pressed.
Future<void> showLiveShareSheet(
  BuildContext context, {
  required AppDatabase db,
  required String patientId,
  required String name,
  required String lang,
  required LiveShareController controller,
  ApiClient? api,
  Future<bool> Function(Uri)? launch,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Palette.cream,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (_) => _ShareSheet(
        db: db,
        patientId: patientId,
        name: name,
        lang: lang,
        controller: controller,
        api: api,
        launch: launch),
  );
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({
    required this.db,
    required this.patientId,
    required this.name,
    required this.lang,
    required this.controller,
    this.api,
    this.launch,
  });
  final AppDatabase db;
  final String patientId, name, lang;
  final LiveShareController controller;
  final ApiClient? api;
  final Future<bool> Function(Uri)? launch;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  List<ShareTarget> _people = [];
  final Set<int> _picked = {};
  bool _loaded = false;
  bool _alsoSms = false;
  bool _busy = false;
  int _minutes = kQuickMinutes;
  String? _problem;

  String t(String k) => tr(widget.lang, k);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await loadShareCandidates(widget.db, widget.patientId);
    if (!mounted) return;
    setState(() {
      _people = all;
      // Caregivers, and family members who were ticked "Include in live location".
      for (var i = 0; i < all.length; i++) {
        if (all[i].chat || all[i].sms) _picked.add(i);
      }
      _loaded = true;
    });
  }

  bool get _hasCaregiverPhone => _people.any((p) => p.chat && (p.phone ?? '').isNotEmpty);

  String _problemText(ShareOutcome o) => switch (o) {
        ShareOutcome.deniedForever => t('locDeniedForever'),
        ShareOutcome.serviceOff => t('locServiceOff'),
        ShareOutcome.noPosition => t('locNoPosition'),
        _ => t('locDenied'),
      };

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    final r = await widget.controller.start(
        minutes: _minutes,
        notifyTitle: t('liveNotifyTitle'),
        notifyText: t('liveNotifyText'));
    if (r.outcome != ShareOutcome.ok) {
      if (mounted) {
        setState(() {
          _busy = false;
          _problem = _problemText(r.outcome);
        });
      }
      return;
    }
    final text = liveMessage(widget.lang,
        name: widget.name.split(' ').first, link: r.link!, until: r.live ? r.until : null);
    final targets = [
      for (final i in _picked)
        ShareTarget(
          name: _people[i].name,
          phone: _people[i].phone,
          chatLinkId: _people[i].chatLinkId,
          chat: _people[i].chat,
          sms: _people[i].chat ? _alsoSms : true,
        )
    ];
    final report = await sendLiveMessage(
        text: text, targets: targets, api: widget.api, launch: widget.launch);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final note = report.smsOpened
        ? t('liveSmsNote')
        : report.chatQueued > 0 && report.chatSent == 0
            ? t('liveQueued')
            : t('liveSent');
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(content: Text(note)));
  }

  @override
  Widget build(BuildContext context) {
    final chips = <(int, String)>[
      (0, t('durNow')),
      (30, t('dur30')),
      (60, t('dur1h')),
      (120, t('dur2h')),
    ];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 18, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.location_on_rounded, color: Palette.sky, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(t('shareLiveLoc'),
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Palette.brandDeep)),
                ),
              ]),
              const SizedBox(height: 14),
              Text(t('shareFor'),
                  style: const TextStyle(fontSize: 13, color: Palette.muted)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 6, children: [
                for (final (m, label) in chips)
                  ChoiceChip(
                    key: ValueKey('dur$m'),
                    label: Text(label),
                    selected: _minutes == m,
                    onSelected: (_) => setState(() => _minutes = m),
                  ),
              ]),
              const SizedBox(height: 14),
              Text(t('shareWho'),
                  style: const TextStyle(fontSize: 13, color: Palette.muted)),
              if (!_loaded)
                const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()))
              else if (_people.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(t('shareNobody'), style: const TextStyle(fontSize: 14)),
                )
              else ...[
                for (var i = 0; i < _people.length; i++)
                  CheckboxListTile(
                    key: ValueKey('target_$i'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _picked.contains(i),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _picked.add(i);
                      } else {
                        _picked.remove(i);
                      }
                    }),
                    title: Text(_people[i].name, style: const TextStyle(fontSize: 16)),
                    subtitle: Text(_people[i].chat ? t('viaChat') : t('viaSms'),
                        style: const TextStyle(fontSize: 12.5)),
                  ),
                if (_hasCaregiverPhone)
                  SwitchListTile(
                    key: const ValueKey('alsoSms'),
                    contentPadding: EdgeInsets.zero,
                    value: _alsoSms,
                    onChanged: (v) => setState(() => _alsoSms = v),
                    title: Text(t('alsoSmsCaregiver'),
                        style: const TextStyle(fontSize: 14.5)),
                  ),
              ],
              const SizedBox(height: 6),
              Text(t('liveWhoSees'),
                  style: const TextStyle(fontSize: 12, color: Palette.muted)),
              if (_problem != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_problem!,
                      key: const ValueKey('liveProblem'),
                      style: const TextStyle(color: Palette.red, fontSize: 14)),
                ),
              const SizedBox(height: 14),
              FilledButton.icon(
                key: const ValueKey('startShare'),
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded),
                label: Text(_minutes == 0 ? t('sendNow') : t('startSharing')),
                onPressed: _busy || _picked.isEmpty ? null : _go,
              ),
            ],
          ),
        ),
      ),
    );
  }
}


/// How long the one-tap share lasts.
const kQuickMinutes = 120;

String _problemFor(String lang, ShareOutcome o) => switch (o) {
      ShareOutcome.deniedForever => tr(lang, 'locDeniedForever'),
      ShareOutcome.serviceOff => tr(lang, 'locServiceOff'),
      ShareOutcome.noPosition => tr(lang, 'locNoPosition'),
      _ => tr(lang, 'locDenied'),
    };

/// The one-tap share: starts at once and sends to the caregivers and to the
/// family members ticked "Include in live location", with no questions. The
/// caregiver gets the chat message (and is in the SMS too when their number is
/// known); the family SMS opens ready in the messaging app, one press to send.
/// The snackbar lists who it went to and has a Stop button.
Future<void> quickShareLiveLocation(
  BuildContext context, {
  required AppDatabase db,
  required String patientId,
  required String name,
  required String lang,
  required LiveShareController controller,
  ApiClient? api,
  Future<bool> Function(Uri)? launch,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  void say(String text, {bool stop = false}) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text),
      duration: Duration(seconds: stop ? 8 : 5),
      action: stop
          ? SnackBarAction(label: tr(lang, 'stopSharing'), onPressed: () => controller.stop())
          : null,
    ));

  if (controller.active) return;
  final people = await loadShareCandidates(db, patientId);
  final targets = [
    for (final p in people)
      if (p.chat || p.sms)
        ShareTarget(
            name: p.name,
            phone: p.phone,
            chatLinkId: p.chatLinkId,
            chat: p.chat,
            sms: p.chat ? (p.phone ?? '').isNotEmpty : true)
  ];
  if (targets.isEmpty) {
    say(tr(lang, 'shareNobody'));
    return;
  }
  final r = await controller.start(
      minutes: kQuickMinutes,
      notifyTitle: tr(lang, 'liveNotifyTitle'),
      notifyText: tr(lang, 'liveNotifyText'));
  if (r.outcome != ShareOutcome.ok) {
    say(_problemFor(lang, r.outcome));
    return;
  }
  final text = liveMessage(lang,
      name: name.split(' ').first, link: r.link!, until: r.live ? r.until : null);
  final report = await sendLiveMessage(
      text: text, targets: targets, api: api, launch: launch);
  final names = targets.map((t) => t.name).join(', ');
  if (report.chatQueued > 0 && report.chatSent == 0 && !report.smsOpened) {
    say(tr(lang, 'liveQueued'));
  } else {
    say(tr(lang, 'liveAutoSent').replaceAll('{names}', names), stop: r.live);
  }
}
