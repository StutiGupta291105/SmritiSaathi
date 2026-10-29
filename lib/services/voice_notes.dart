import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// A recorded voice note: AAC in an .m4a container (MIME audio/mp4).
class RecordedNote {
  const RecordedNote(this.bytes, this.durationMs);
  final Uint8List bytes;
  final int durationMs;
  static const mime = 'audio/mp4';
}

/// Records a voice note. Split from the screen so tests can fake the microphone.
abstract class VoiceRecorder {
  /// False when the microphone may not be used.
  Future<bool> start();
  Future<RecordedNote?> stop();
  Future<void> cancel();
}

/// Plays voice notes.
abstract class VoicePlayer {
  Future<void> play(Uint8List bytes, String mime);
  Future<void> stop();
  Stream<void> get onFinished;
  void dispose();
}

/// The phone's microphone. The recording lives in the app's temporary folder
/// just long enough to be read, then the file is deleted.
class DeviceRecorder implements VoiceRecorder {
  final AudioRecorder _rec = AudioRecorder();
  String? _path;
  DateTime? _started;

  @override
  Future<bool> start() async {
    if (!await _rec.hasPermission()) return false;
    final dir = await getTemporaryDirectory();
    _path = '${dir.path}/note_${DateTime.now().microsecondsSinceEpoch}.m4a';
    await _rec.start(
        const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 32000,
            sampleRate: 16000,
            numChannels: 1),
        path: _path!);
    _started = DateTime.now();
    return true;
  }

  @override
  Future<RecordedNote?> stop() async {
    final path = await _rec.stop() ?? _path;
    final ms = _started == null
        ? 0
        : DateTime.now().difference(_started!).inMilliseconds;
    _started = null;
    if (path == null) return null;
    final file = File(path);
    try {
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      return bytes.isEmpty ? null : RecordedNote(bytes, ms);
    } finally {
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  @override
  Future<void> cancel() async {
    final path = await _rec.stop() ?? _path;
    _started = null;
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }
}

class DevicePlayer implements VoicePlayer {
  final AudioPlayer _p = AudioPlayer();

  @override
  Future<void> play(Uint8List bytes, String mime) =>
      _p.play(BytesSource(bytes, mimeType: mime));

  @override
  Future<void> stop() => _p.stop();

  @override
  Stream<void> get onFinished => _p.onPlayerComplete;

  @override
  void dispose() => _p.dispose();
}
