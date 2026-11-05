import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../services/api_client.dart';
import '../../services/voice_notes.dart';
import 'messages_screen.dart';

/// "Talk to Doctor": the doctor the patient is under comes first, pinned. Below
/// are all the other doctors on the app; the patient can ask any of them for an
/// opinion. Those doctors only ever see the messages the patient sends them.
class DoctorDirectoryScreen extends StatefulWidget {
  const DoctorDirectoryScreen({
    super.key,
    required this.api,
    required this.lang,
    this.onActivity,
    this.pollEvery = const Duration(seconds: 4),
    this.recorder,
    this.player,
  });
  final ApiClient api;
  final String lang;
  final VoidCallback? onActivity;
  final Duration pollEvery;

  /// Replaceable in tests (no microphone or speaker there).
  final VoiceRecorder? recorder;
  final VoicePlayer? player;

  @override
  State<DoctorDirectoryScreen> createState() => _DoctorDirectoryScreenState();
}

class _DoctorDirectoryScreenState extends State<DoctorDirectoryScreen> {
  List<Map<String, dynamic>> _doctors = const [];
  Map<String, int> _unread = const {}; // thread id -> unread
  bool _loading = true;
  bool _failed = false;
  String _query = '';
  String? _opening;

  String t(String k) => tr(widget.lang, k);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final docs = await widget.api.doctorDirectory();
      Map<String, int> unread = const {};
      try {
        unread = {
          for (final th in await widget.api.chatThreads())
            th['link_id'] as String: (th['unread'] as int?) ?? 0
        };
      } on ApiException {
        // The list is still useful without the badges.
      }
      if (!mounted) return;
      setState(() {
        _doctors = docs;
        _unread = unread;
        _loading = false;
        _failed = false;
      });
    } on ApiException {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _open(Map<String, dynamic> d) async {
    if (_opening != null) return;
    var id = d['thread_id'] as String?;
    if (id == null) {
      setState(() => _opening = d['doctor_id'] as String);
      try {
        id = await widget.api.openOpinionChat(d['doctor_id'] as String);
      } on ApiException catch (e) {
        if (!mounted) return;
        setState(() => _opening = null);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(t(e.isNetwork ? 'chatNeedsOnline' : 'errGeneric'))));
        return;
      }
      if (!mounted) return;
      setState(() => _opening = null);
    }
    final pinned = d['pinned'] == true;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => MessagesScreen(
        api: widget.api,
        linkId: id!,
        title: '${d['name']}',
        lang: widget.lang,
        accent: Palette.purple,
        onActivity: () {
          widget.onActivity?.call();
          _load();
        },
        pollEvery: widget.pollEvery,
        recorder: widget.recorder,
        player: widget.player,
      ),
    ));
    if (pinned || d['thread_id'] == null) _load();
  }

  Widget _row(Map<String, dynamic> d) {
    final pinned = d['pinned'] == true;
    final verified = d['verified'] == true;
    final unread = _unread[d['thread_id']] ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        key: ValueKey('doctor_${d['doctor_id']}'),
        color: pinned ? Palette.tilePurple : Colors.white,
        onTap: () => _open(d),
        child: Row(children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: pinned ? Colors.white : Palette.tileBlue,
            child: const Icon(Icons.medical_services_rounded,
                color: Palette.purple),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${d['name']}',
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Palette.brandDeep)),
                  const SizedBox(height: 2),
                  Row(children: [
                    if (verified) ...[
                      const Icon(Icons.verified_rounded,
                          size: 15, color: Palette.green),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(t('doctorVerified'),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12.5, color: Palette.green)),
                      ),
                    ] else
                      Flexible(
                        child: Text(t('tapToAsk'),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12.5, color: Palette.muted)),
                      ),
                  ]),
                ]),
          ),
          if (_opening == d['doctor_id'])
            const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2))
          else if (unread > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                  color: Palette.red, borderRadius: BorderRadius.circular(12)),
              child: Text('$unread',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: Colors.white)),
            )
          else
            Icon(pinned ? Icons.push_pin_rounded : Icons.chat_bubble_outline_rounded,
                color: Palette.purple),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    bool match(Map<String, dynamic> d) =>
        q.isEmpty || '${d['name']}'.toLowerCase().contains(q);
    final pinned = [for (final d in _doctors) if (d['pinned'] == true) d];
    final others =
        [for (final d in _doctors) if (d['pinned'] != true && match(d)) d];
    return Scaffold(
      appBar: AppBar(title: Text(t('talkToDoctor'))),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _failed && _doctors.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(t('errOffline'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 16)),
                        const SizedBox(height: 12),
                        IconButton.filledTonal(
                            key: const ValueKey('doctorsRetry'),
                            onPressed: () {
                              setState(() => _loading = true);
                              _load();
                            },
                            icon: const Icon(Icons.refresh_rounded)),
                      ]),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      children: [
                        if (pinned.isNotEmpty) ...[
                          _heading(t('yourDoctor')),
                          for (final d in pinned) _row(d),
                          const SizedBox(height: 8),
                        ],
                        _heading(t('otherDoctors')),
                        TextField(
                          key: const ValueKey('doctorSearch'),
                          onChanged: (v) => setState(() => _query = v),
                          decoration: InputDecoration(
                            hintText: t('searchDoctors'),
                            prefixIcon: const Icon(Icons.search_rounded),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                                borderSide: BorderSide.none),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (others.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Text(t('noDoctorsOnApp'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontSize: 15, color: Palette.muted)),
                          ),
                        for (final d in others) _row(d),
                        const SizedBox(height: 6),
                        AppCard(
                          color: Palette.tileBlue,
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.lock_outline_rounded,
                                    size: 20, color: Palette.blue),
                                const SizedBox(width: 10),
                                Expanded(
                                    child: Text(t('opinionNote'),
                                        style: const TextStyle(
                                            fontSize: 13.5, height: 1.4))),
                              ]),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 12, 2, 10),
        child: Text(text,
            style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: Palette.brandDeep)),
      );
}
