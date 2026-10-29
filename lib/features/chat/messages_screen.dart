import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../services/api_client.dart';
import '../../services/voice_notes.dart';
import '../profile/photo_picker.dart' show pickPhoto;

/// Picks a photo for a message (camera or gallery). Replaceable in tests.
typedef PhotoSource = Future<Uint8List?> Function(BuildContext context, String lang);

Future<Uint8List?> _pickMessagePhoto(BuildContext context, String lang) =>
    pickPhoto(context, lang, maxSide: 1280, quality: 70);

/// One conversation: text, photos and voice notes between a patient and the
/// caregiver or doctor they are linked to. Used by every role. New messages are
/// fetched every few seconds while the screen is open; the history is kept on
/// the server, so it is all here again on any phone.
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({
    super.key,
    required this.api,
    required this.linkId,
    required this.title,
    required this.lang,
    this.accent = Palette.brand,
    this.callPhone,
    this.onActivity,
    this.pickPhoto = _pickMessagePhoto,
    this.recorder,
    this.player,
    this.pollEvery = const Duration(seconds: 4),
  });
  final ApiClient api;
  final String linkId, title, lang;
  final Color accent;

  /// A number to call from the app bar, when the other person shared one.
  final String? callPhone;

  /// Called after messages were read or sent, so unread badges can refresh.
  final VoidCallback? onActivity;
  final PhotoSource pickPhoto;
  final VoiceRecorder? recorder;
  final VoicePlayer? player;
  final Duration pollEvery;

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final List<Map<String, dynamic>> _msgs = [];
  final Map<int, Uint8List> _media = {};
  late final VoiceRecorder _recorder = widget.recorder ?? DeviceRecorder();
  late final VoicePlayer _player = widget.player ?? DevicePlayer();
  StreamSubscription<void>? _playDone;
  Timer? _timer;
  Timer? _tick;
  bool _loading = true;
  bool _sending = false;
  bool _recording = false;
  int _recordedSeconds = 0;
  int? _playingId;
  String? _error;

  String t(String k) => tr(widget.lang, k);

  int get _lastId => _msgs.isEmpty ? 0 : _msgs.last['id'] as int;

  @override
  void initState() {
    super.initState();
    _playDone = _player.onFinished.listen((_) {
      if (mounted) setState(() => _playingId = null);
    });
    _first();
    _timer = Timer.periodic(widget.pollEvery, (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tick?.cancel();
    _playDone?.cancel();
    _text.dispose();
    _scroll.dispose();
    if (_recording) _recorder.cancel();
    _player.stop();
    _player.dispose();
    super.dispose();
  }

  Future<void> _first() async {
    try {
      final rows = await widget.api.chatMessages(widget.linkId);
      if (!mounted) return;
      setState(() {
        _msgs
          ..clear()
          ..addAll(rows);
        _loading = false;
        _error = null;
      });
      _afterNew(rows);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.isNetwork ? 'chatNeedsOnline' : 'chatSendFailed';
      });
    }
  }

  Future<void> _poll() async {
    if (_loading || _sending) return;
    try {
      final rows = await widget.api.chatMessages(widget.linkId, after: _lastId);
      if (!mounted || rows.isEmpty) return;
      setState(() => _msgs.addAll(rows));
      _afterNew(rows);
    } on ApiException {
      // The next poll tries again.
    }
  }

  /// Scrolls down and tells the server what has been seen.
  void _afterNew(List<Map<String, dynamic>> rows) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
    final theirs = rows.where((m) => m['mine'] != true).toList();
    if (theirs.isNotEmpty) {
      widget.api
          .chatMarkRead(widget.linkId, theirs.last['id'] as int)
          .then((_) => widget.onActivity?.call(), onError: (_) {});
    }
  }

  Future<bool> _send(
      {required String kind,
      String text = '',
      Uint8List? media,
      String mime = '',
      int durationMs = 0}) async {
    setState(() => _sending = true);
    try {
      final m = await widget.api.sendChatMessage(widget.linkId,
          kind: kind,
          text: text,
          media: media,
          mime: mime,
          durationMs: durationMs);
      if (!mounted) return true;
      if (media != null) _media[m['id'] as int] = media;
      setState(() {
        _msgs.add(m);
        _error = null;
      });
      _afterNew([m]);
      widget.onActivity?.call();
      return true;
    } on ApiException catch (e) {
      if (mounted) _snack(e.isNetwork ? 'chatNeedsOnline' : 'chatSendFailed');
      return false;
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _snack(String key) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(t(key))));

  Future<void> _sendText() async {
    final text = _text.text.trim();
    if (text.isEmpty || _sending) return;
    _text.clear();
    setState(() {});
    final ok = await _send(kind: 'text', text: text);
    // Keep what was typed when it could not be sent.
    if (!ok && mounted && _text.text.isEmpty) {
      _text.text = text;
      setState(() {});
    }
  }

  Future<void> _sendPhoto() async {
    final bytes = await widget.pickPhoto(context, widget.lang);
    if (bytes == null) return;
    await _send(kind: 'image', media: bytes, mime: _imageMime(bytes));
  }

  static String _imageMime(Uint8List b) {
    if (b.length > 8 && b[0] == 0x89 && b[1] == 0x50) return 'image/png';
    if (b.length > 12 && b[8] == 0x57 && b[9] == 0x45) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _startRecording() async {
    final ok = await _recorder.start();
    if (!ok) {
      if (mounted) _snack('micDenied');
      return;
    }
    setState(() {
      _recording = true;
      _recordedSeconds = 0;
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _recordedSeconds++);
      if (_recordedSeconds >= 120) _finishRecording(); // the server's limit
    });
  }

  Future<void> _cancelRecording() async {
    _tick?.cancel();
    await _recorder.cancel();
    if (mounted) setState(() => _recording = false);
  }

  Future<void> _finishRecording() async {
    if (!_recording) return;
    _tick?.cancel();
    setState(() => _recording = false);
    final note = await _recorder.stop();
    if (note == null) return;
    await _send(
        kind: 'voice',
        media: note.bytes,
        mime: RecordedNote.mime,
        durationMs: note.durationMs);
  }

  Future<Uint8List?> _bytesFor(int id) async {
    final have = _media[id];
    if (have != null) return have;
    try {
      final b = await widget.api.chatMedia(id);
      _media[id] = b;
      return b;
    } on ApiException {
      return null;
    }
  }

  Future<void> _togglePlay(Map<String, dynamic> m) async {
    final id = m['id'] as int;
    if (_playingId == id) {
      await _player.stop();
      if (mounted) setState(() => _playingId = null);
      return;
    }
    final b = await _bytesFor(id);
    if (b == null || !mounted) return;
    await _player.stop();
    setState(() => _playingId = id);
    await _player.play(b, '${m['mime']}');
  }

  String _time(String iso) {
    // The server sends UTC without a zone marker.
    final utc = iso.endsWith('Z') || iso.contains('+') ? iso : '${iso}Z';
    final d = DateTime.tryParse(utc)?.toLocal();
    if (d == null) return '';
    return TimeOfDay.fromDateTime(d).format(context);
  }

  String _dur(int ms) {
    final s = (ms / 1000).round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  Widget _bubble(Map<String, dynamic> m) {
    final mine = m['mine'] == true;
    final kind = m['kind'] as String;
    final fg = mine ? Colors.white : Palette.ink;
    Widget body;
    if (kind == 'image') {
      final id = m['id'] as int;
      body = FutureBuilder<Uint8List?>(
        future: _bytesFor(id),
        builder: (context, snap) {
          final b = snap.data;
          if (b == null) {
            return SizedBox(
                width: 180,
                height: 120,
                child: Center(
                    child: snap.connectionState == ConnectionState.done
                        ? Icon(Icons.broken_image_rounded, color: fg)
                        : const CircularProgressIndicator(strokeWidth: 2)));
          }
          return GestureDetector(
            key: ValueKey('image_$id'),
            onTap: () => showDialog<void>(
                context: context,
                builder: (_) => Dialog.fullscreen(
                      backgroundColor: Colors.black,
                      child: Stack(children: [
                        Center(
                            child: InteractiveViewer(child: Image.memory(b))),
                        SafeArea(
                          child: IconButton(
                              color: Colors.white,
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => Navigator.pop(context)),
                        ),
                      ]),
                    )),
            child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(b, width: 220, fit: BoxFit.cover)),
          );
        },
      );
    } else if (kind == 'voice') {
      final playing = _playingId == m['id'];
      body = Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          key: ValueKey('play_${m['id']}'),
          visualDensity: VisualDensity.compact,
          color: fg,
          icon: Icon(
              playing ? Icons.stop_circle_rounded : Icons.play_circle_rounded,
              size: 34),
          onPressed: () => _togglePlay(m),
        ),
        const SizedBox(width: 4),
        Text('${t('voiceNote')}  ${_dur(m['duration_ms'] as int)}',
            style: TextStyle(fontSize: 15, color: fg)),
      ]);
    } else {
      body = Text('${m['text']}',
          style: TextStyle(fontSize: 16, height: 1.3, color: fg));
    }
    final caption = kind != 'text' && '${m['text']}'.isNotEmpty
        ? Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('${m['text']}', style: TextStyle(fontSize: 15, color: fg)))
        : const SizedBox.shrink();
    return Align(
      alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          decoration: BoxDecoration(
            color: mine ? widget.accent : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: mine ? null : Border.all(color: Palette.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(alignment: AlignmentDirectional.centerStart, child: body),
              caption,
              const SizedBox(height: 2),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text(_time('${m['created_at']}'),
                    style: TextStyle(
                        fontSize: 11, color: fg.withValues(alpha: 0.75))),
                if (mine) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.done_all_rounded,
                      size: 14,
                      color: m['read'] == true
                          ? Colors.lightBlueAccent
                          : fg.withValues(alpha: 0.6)),
                ],
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _composer() {
    if (_recording) {
      return Row(children: [
        IconButton(
          key: const ValueKey('cancelVoice'),
          icon: const Icon(Icons.delete_outline_rounded, color: Palette.red),
          onPressed: _cancelRecording,
        ),
        const Icon(Icons.fiber_manual_record, color: Palette.red, size: 16),
        const SizedBox(width: 6),
        Expanded(
          child: Text('${t('recordingVoice')}  ${_dur(_recordedSeconds * 1000)}',
              style: const TextStyle(fontSize: 15)),
        ),
        IconButton.filled(
          key: const ValueKey('sendVoice'),
          style: IconButton.styleFrom(backgroundColor: widget.accent),
          icon: const Icon(Icons.send_rounded),
          onPressed: _finishRecording,
        ),
      ]);
    }
    final hasText = _text.text.trim().isNotEmpty;
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      IconButton(
        key: const ValueKey('attachPhoto'),
        icon: Icon(Icons.photo_camera_rounded, color: widget.accent),
        onPressed: _sending ? null : _sendPhoto,
      ),
      Expanded(
        child: TextField(
          key: const ValueKey('chatInput'),
          controller: _text,
          minLines: 1,
          maxLines: 4,
          maxLength: 2000,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
              hintText: t('typeMessage'),
              counterText: '',
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
        ),
      ),
      const SizedBox(width: 6),
      hasText
          ? IconButton.filled(
              key: const ValueKey('sendText'),
              style: IconButton.styleFrom(backgroundColor: widget.accent),
              icon: const Icon(Icons.send_rounded),
              onPressed: _sending ? null : _sendText,
            )
          : IconButton.filled(
              key: const ValueKey('recordVoice'),
              style: IconButton.styleFrom(backgroundColor: widget.accent),
              icon: const Icon(Icons.mic_rounded),
              onPressed: _sending ? null : _startRecording,
            ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        actions: [
          if (widget.callPhone != null)
            IconButton(
              key: const ValueKey('callThem'),
              tooltip: t('callThem'),
              icon: Icon(Icons.call_rounded, color: widget.accent),
              onPressed: () =>
                  launchUrl(Uri(scheme: 'tel', path: widget.callPhone)),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null && _msgs.isEmpty
                    ? Center(
                        child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(t(_error!),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontSize: 16, color: Palette.muted))))
                    : _msgs.isEmpty
                        ? Center(
                            child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(t('noMessagesYet'),
                                    key: const ValueKey('noMessages'),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        fontSize: 16, color: Palette.muted))))
                        : ListView(
                            controller: _scroll,
                            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                            children: [for (final m in _msgs) _bubble(m)]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: _composer(),
          ),
        ]),
      ),
    );
  }
}
