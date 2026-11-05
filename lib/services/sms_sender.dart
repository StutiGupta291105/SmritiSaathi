import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Sends SMS straight from the phone, with no messaging app and no extra tap.
abstract class SmsSender {
  /// Sends [text] to every number. Returns how many were sent; 0 means this
  /// phone cannot send silently (not Android, or permission refused), and the
  /// caller falls back to opening the messaging app.
  Future<int> sendAll(List<String> numbers, String text);
}

/// Android only. Uses the SEND_SMS permission (the app never reads messages);
/// the actual sending is a small native function added by the build script
/// (`.github/scripts/patch_android.py`). Normal SMS charges of the SIM apply.
class AndroidSmsSender implements SmsSender {
  static const _channel = MethodChannel('in.smritisathi/sms');

  @override
  Future<int> sendAll(List<String> numbers, String text) async {
    if (!Platform.isAndroid || numbers.isEmpty) return 0;
    try {
      var status = await Permission.sms.status;
      if (!status.isGranted) status = await Permission.sms.request();
      if (!status.isGranted) return 0;
      var sent = 0;
      for (final to in numbers) {
        if (await _channel.invokeMethod<bool>('send', {'to': to, 'body': text}) == true) {
          sent++;
        }
      }
      return sent;
    } catch (_) {
      return 0;
    }
  }
}
