import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:url_launcher/url_launcher.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/app_database.dart';
import '../../services/companion_service.dart';
import '../../services/speech_input.dart';
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
    this.syncNow,
    this.speech,
  });

  /// Speech to text; tests pass a fake. Defaults to the phone's own recognition.
  final SpeechInput? speech;

  /// Sends the new consent to the server right away; without it the first
  /// question after "allow" would be refused until the next background sync.
  final Future<void> Function()? syncNow;
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
  String? _why; // why the online helper could not answer, shown in small print
  bool _canAskOnline = false; // server possible but the person has not agreed
  late final SpeechInput _speech = widget.speech ?? DeviceSpeechInput();
  bool _listening = false;
  bool _loaded = false;
  bool _hasMore = false;
  static const _page = 40;

  String t(String k) => tr(widget.lang, k);

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _checkOnline();
  }

  ChatTurn _fromRow(Map<String, Object?> r) => ChatTurn(
      (r['from_user'] as int) == 1, r['text'] as String,
      at: DateTime.tryParse(r['created_at'] as String) ?? DateTime.now(),
      id: r['id'] as int);

  /// The whole conversation is one continuous thread kept on this phone.
  Future<void> _loadHistory() async {
    final rows = await widget.db.companionMessages(widget.patientId, limit: _page);
    if (!mounted) return;
    setState(() {
      _turns.insertAll(0, rows.map(_fromRow));
      _hasMore = rows.length == _page;
      _loaded = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _loadEarlier() async {
    final firstId = _turns.isEmpty ? null : _turns.first.id;
    if (firstId == null) return;
    final rows = await widget.db
        .companionMessages(widget.patientId, limit: _page, beforeId: firstId);
    if (!mounted) return;
    setState(() {
      _turns.insertAll(0, rows.map(_fromRow));
      _hasMore = rows.length == _page;
    });
  }

  Future<void> _report(ChatTurn turn) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t('reportAnswer')),
        content: Text(t('reportAsk')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(t('chatSend'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final sent = await widget.service.reportAnswer(turn.text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sent ? t('reportSent') : t('chatNeedsOnline'))));
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(t('chatClearAsk')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(t('delete'))),
        ],
      ),
    );
    if (ok != true) return;
    await widget.db.clearCompanionMessages(widget.patientId);
    if (mounted) setState(() {
      _turns.clear();
      _hasMore = false;
      _emergency = false;
      _offlineNote = false;
      _why = null;
    });
  }

  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return t('chatToday');
    if (diff == 1) return t('chatYesterday');
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  String _clock(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _speech.stop();
    widget.voice.stop();
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// The microphone button: speak, and the words go into the box and are sent when
  /// the person stops. Tap again to stop early.
  Future<void> _toggleMic() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    if (_busy) return;
    widget.voice.stop(); // do not listen to Smriti's own voice
    final r = await _speech.start(
      widget.lang,
      onText: (text, done) {
        if (!mounted) return;
        setState(() => _input.text = text);
        _input.selection = TextSelection.collapsed(offset: _input.text.length);
        if (done && text.trim().isNotEmpty) {
          setState(() => _listening = false);
          _send();
        }
      },
      onEnd: () {
        if (mounted && _listening) setState(() => _listening = false);
      },
    );
    if (!mounted) return;
    switch (r) {
      case SpeechStart.listening:
        setState(() => _listening = true);
      case SpeechStart.denied:
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('micDenied')),
          action: SnackBarAction(
              label: t('osPermSettings'), onPressed: () => ph.openAppSettings()),
        ));
      case SpeechStart.unavailable:
        _focus.requestFocus();
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(t('chatMicUnavailable'))));
    }
  }

  Future<void> _checkOnline() async {
    final possible = await widget.service.onlinePossible();
    final allowed = await widget.service.onlineAllowed(widget.patientId);
    if (mounted) setState(() => _canAskOnline = possible && !allowed);
  }

  void _add(ChatTurn turn, {bool emergency = false, bool offline = false}) {
    widget.db.addCompanionMessage(widget.patientId,
        fromUser: turn.fromUser, text: turn.text, at: turn.at, emergency: emergency)
        .catchError((_) {}); // history is a convenience; never block the chat
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
    final before = List<ChatTurn>.from(_turns);
    _add(ChatTurn(true, text));
    setState(() => _busy = true);
    final r = await widget.service.ask(
      patientId: widget.patientId,
      lang: widget.lang,
      firstName: widget.name.split(' ').first,
      history: before,
      text: text,
      syncNow: widget.syncNow,
    );
    if (mounted) setState(() => _why = r.why);
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
    try {
      await widget.syncNow?.call();
    } catch (_) {}
    await _checkOnline();
  }

  Widget _bubble(ChatTurn turn) => Align(
        alignment: turn.fromUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment:
              turn.fromUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
        Container(
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
        Row(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(_clock(turn.at),
                style: const TextStyle(fontSize: 11, color: Palette.muted)),
          ),
          // An AI answer can be flagged for review (the greeting is fixed text).
          if (!turn.fromUser && turn.text != t('chatHello'))
            IconButton(
              key: ValueKey('report_${turn.at.microsecondsSinceEpoch}'),
              tooltip: t('reportAnswer'),
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              icon: const Icon(Icons.outlined_flag_rounded, color: Palette.muted),
              onPressed: () => _report(turn),
            ),
        ]),
      ]));

  Widget _dayChip(DateTime d) => Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
              color: Palette.tileGreen, borderRadius: BorderRadius.circular(12)),
          child: Text(_dayLabel(d),
              style: const TextStyle(fontSize: 12, color: Palette.muted)),
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
      appBar: AppBar(centerTitle: true, title: Text(t('chatTitle')), actions: [
        PopupMenuButton<String>(
          tooltip: t('chatClear'),
          onSelected: (_) => _clear(),
          itemBuilder: (_) => [
            PopupMenuItem(value: 'clear', child: Text(t('chatClear'))),
          ],
        ),
      ]),
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
                  child: Text('${t('chatNote')}\n${t('chatKeptNote')}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: Palette.muted)),
                ),
                if (_hasMore)
                  Center(
                    child: TextButton(
                        onPressed: _loadEarlier, child: Text(t('chatEarlier'))),
                  ),
                if (_loaded && _turns.isEmpty)
                  _bubble(ChatTurn(false, t('chatHello'))),
                for (var i = 0; i < _turns.length; i++) ...[
                  if (i == 0 ||
                      DateTime(_turns[i].at.year, _turns[i].at.month, _turns[i].at.day) !=
                          DateTime(_turns[i - 1].at.year, _turns[i - 1].at.month,
                              _turns[i - 1].at.day))
                    _dayChip(_turns[i].at),
                  _bubble(_turns[i]),
                ],
                if (_busy)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(t('chatThinking'),
                        style: const TextStyle(color: Palette.muted, fontSize: 15)),
                  ),
                if (_why != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: Text('Online helper: $_why',
                        key: const ValueKey('chatWhy'),
                        style: const TextStyle(fontSize: 12, color: Palette.muted)),
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
                color: _listening ? Palette.red : Palette.action,
                shape: const CircleBorder(),
                child: InkWell(
                  key: const ValueKey('micButton'),
                  customBorder: const CircleBorder(),
                  onTap: _toggleMic,
                  child: SizedBox(
                      width: 64,
                      height: 64,
                      child: Icon(_listening ? Icons.stop_rounded : Icons.mic_rounded,
                          size: 32, color: Colors.white)),
                ),
              ),
              const SizedBox(height: 4),
              Text(_listening ? t('chatListening') : t('chatTapSpeak'),
                  key: const ValueKey('micLabel'),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: _listening ? FontWeight.w700 : FontWeight.w400,
                      color: _listening ? Palette.red : Palette.muted)),
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
                    prefixIcon: IconButton(
                        key: const ValueKey('micSmall'),
                        tooltip: t('chatTapSpeak'),
                        onPressed: _toggleMic,
                        icon: Icon(_listening ? Icons.stop_circle_rounded : Icons.mic_rounded,
                            color: _listening ? Palette.red : Palette.action)),
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
