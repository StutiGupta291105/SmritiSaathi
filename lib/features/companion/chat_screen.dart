import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/app_database.dart';
import '../../services/companion_service.dart';
import '../../services/voice.dart';
import '../onboarding/onboarding_screen.dart' show kNoticeVersion;

/// 'Talk to Smriti': big buttons for the common questions, a text box, and
/// spoken replies. Always says clearly that it is a helper program.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.service,
    required this.voice,
    required this.db,
    required this.patientId,
    required this.name,
    required this.lang,
    required this.voiceEnabled,
  });
  final CompanionService service;
  final Voice voice;
  final AppDatabase db;
  final String patientId, name, lang;
  final bool voiceEnabled;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _turns = <ChatTurn>[];
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  bool _busy = false;
  bool _emergency = false;
  bool _offlineNote = false;
  bool _canAskOnline = false; // server possible but the person has not agreed

  String t(String k) => tr(widget.lang, k);

  @override
  void initState() {
    super.initState();
    _turns.add(ChatTurn(false, t('chatHello')));
    _checkOnline();
  }

  @override
  void dispose() {
    widget.voice.stop();
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _checkOnline() async {
    final possible = await widget.service.onlinePossible();
    final allowed = await widget.service.onlineAllowed(widget.patientId);
    if (mounted) setState(() => _canAskOnline = possible && !allowed);
  }

  void _add(ChatTurn turn, {bool emergency = false, bool offline = false}) {
    setState(() {
      _turns.add(turn);
      _busy = false;
      if (emergency) _emergency = true;
      if (offline) _offlineNote = true;
    });
    if (!turn.fromUser) {
      widget.voice.speak(turn.text, widget.lang, enabled: widget.voiceEnabled);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _quick(String label, Future<CompanionReply> Function() answer) async {
    if (_busy) return;
    setState(() => _busy = true);
    _add(ChatTurn(true, label));
    setState(() => _busy = true);
    final r = await answer();
    _add(ChatTurn(false, r.text));
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    _input.clear();
    setState(() => _busy = true);
    final before = List<ChatTurn>.from(_turns.skip(1)); // without the greeting
    _add(ChatTurn(true, text));
    setState(() => _busy = true);
    final r = await widget.service.ask(
      patientId: widget.patientId,
      lang: widget.lang,
      firstName: widget.name.split(' ').first,
      history: before,
      text: text,
    );
    _add(ChatTurn(false, r.text), emergency: r.emergency, offline: r.offline);
  }

  Future<void> _allowOnline() async {
    await widget.db.recordConsent(
      patientId: widget.patientId,
      purposes: {'companion': true},
      givenByName: widget.name,
      givenByRelation: 'self_or_guardian',
      noticeVersion: kNoticeVersion,
    );
    await _checkOnline();
  }

  Widget _bubble(ChatTurn turn) => Align(
        alignment: turn.fromUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          constraints:
              BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
          decoration: BoxDecoration(
            color: turn.fromUser ? Palette.tileGreen : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Palette.line),
          ),
          child: Text(turn.text, style: const TextStyle(fontSize: 16, height: 1.35)),
        ),
      );

  Widget _chip(IconData icon, String label, VoidCallback onTap) => ActionChip(
        avatar: Icon(icon, size: 22, color: Palette.brandDeep),
        label: Text(label, style: const TextStyle(fontSize: 14)),
        backgroundColor: Colors.white,
        side: const BorderSide(color: Palette.line),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        onPressed: onTap,
      );

  @override
  Widget build(BuildContext context) {
    // Keyboard open or a short screen: drop the big avatar and mic, keep the
    // conversation, quick buttons, emergency button and input, so the messages stay readable.
    final roomy = MediaQuery.of(context).size.height -
            MediaQuery.of(context).viewInsets.bottom >=
        640;
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: Text(t('chatTitle'))),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              children: [
                if (roomy)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                        shape: BoxShape.circle, color: Palette.tilePurple),
                    child: const CircleAvatar(
                      radius: 52,
                      backgroundColor: Colors.white,
                      backgroundImage: AssetImage('assets/images/logo_icon.png'),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(t('chatNote'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: Palette.muted)),
                ),
                for (final turn in _turns) _bubble(turn),
                if (_busy)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(t('chatThinking'),
                        style: const TextStyle(color: Palette.muted, fontSize: 15)),
                  ),
                if (_offlineNote)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(t('chatWorkingOffline'),
                        style: const TextStyle(color: Palette.muted, fontSize: 13)),
                  ),
                if (_canAskOnline)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: AppCard(
                      color: Palette.tileOrange,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t('chatOnlineAsk'),
                                style: const TextStyle(fontSize: 15)),
                            const SizedBox(height: 10),
                            FilledButton(
                                onPressed: _allowOnline, child: Text(t('allow'))),
                          ]),
                    ),
                  ),
              ],
            ),
          ),
          // Pinned, so it can never be scrolled out of sight.
          if (_emergency)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Palette.red),
                onPressed: () => launchUrl(Uri(scheme: 'tel', path: '112')),
                icon: const Icon(Icons.call_rounded),
                label: Text(t('chatCall112')),
              ),
            ),
          if (roomy)
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Material(
                color: Palette.action,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () {
                    _focus.requestFocus();
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(t('chatMicHint'))));
                  },
                  child: const SizedBox(
                      width: 64,
                      height: 64,
                      child: Icon(Icons.mic_rounded,
                          size: 32, color: Colors.white)),
                ),
              ),
              const SizedBox(height: 4),
              Text(t('chatTapSpeak'),
                  style: const TextStyle(fontSize: 13, color: Palette.muted)),
            ]),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _chip(Icons.today_rounded, t('qaDay'),
                    () => _quick(t('qaDay'), () => widget.service.day(widget.lang))),
                const SizedBox(width: 8),
                _chip(
                    Icons.notifications_active_rounded,
                    t('qaNext'),
                    () => _quick(t('qaNext'),
                        () => widget.service.next(widget.patientId, widget.lang))),
                const SizedBox(width: 8),
                _chip(Icons.favorite_rounded, t('qaNice'),
                    () => _quick(t('qaNice'), () async => widget.service.nice(widget.lang))),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  focusNode: _focus,
                  style: const TextStyle(fontSize: 16),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: t('chatHint'),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: const BorderSide(color: Palette.line)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: const BorderSide(color: Palette.line)),
                    suffixIcon: IconButton(
                        tooltip: t('chatSend'),
                        onPressed: _busy ? null : _send,
                        icon: const Icon(Icons.send_rounded,
                            color: Palette.action)),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
