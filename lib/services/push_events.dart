import 'package:flutter/foundation.dart';

/// Where a tapped notification should take the person. Set when a push or an
/// on-device notification is tapped (also when it launched the app), and
/// consumed (set back to null) by the screen that opens the target.
class PushOpen {
  const PushOpen(this.type, {this.linkId});

  /// 'chat' (open that conversation), 'routine' / 'reminder' (open the reminders
  /// tab), anything else just opens the app.
  final String type;
  final String? linkId;

  /// From the data of a push message (see backend `notify_user`).
  static PushOpen? fromData(Map<String, dynamic> data) {
    final type = data['type'];
    if (type is! String || type.isEmpty) return null;
    final link = data['link_id'];
    return PushOpen(type, linkId: link is String && link.isNotEmpty ? link : null);
  }

  /// On-device notifications carry just their type as the payload.
  static PushOpen? fromPayload(String? payload) =>
      payload == null || payload.isEmpty ? null : PushOpen(payload);
}

final ValueNotifier<PushOpen?> kPushOpen = ValueNotifier<PushOpen?>(null);
