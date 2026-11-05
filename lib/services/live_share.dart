import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/strings.dart';
import '../data/app_database.dart';
import 'api_client.dart';
import 'location_service.dart';

/// How a share went.
enum ShareOutcome { ok, denied, deniedForever, serviceOff, noPosition }

class ShareStart {
  const ShareStart(this.outcome, {this.point, this.link, this.until, this.live = false});
  final ShareOutcome outcome;
  final GeoPoint? point;

  /// The link to send: the live map page when the server is reachable, otherwise
  /// a plain maps link for this one spot.
  final String? link;
  final DateTime? until;

  /// True when the position keeps being updated (not just "right now").
  final bool live;
}

/// Runs a live location share: gets the position, starts the share on the
/// server, keeps sending the newest position until the time is up or the person
/// stops it. Only the patient's own phone does this, and only after they tap.
class LiveShareController extends ChangeNotifier {
  LiveShareController({
    required this.provider,
    this.api,
    DateTime Function()? clock,
    this.minGap = const Duration(seconds: 20),
  }) : _clock = clock ?? DateTime.now;

  final LocationProvider provider;
  final ApiClient? api;
  final DateTime Function() _clock;
  final Duration minGap;

  DateTime? _until;
  String? _link;
  StreamSubscription<GeoPoint>? _sub;
  Timer? _expiry;
  DateTime? _lastSent;

  bool get active => _until != null && _until!.isAfter(_clock());
  DateTime? get until => _until;
  String? get link => _link;

  /// Gets the position and (for [minutes] > 0) starts a live share.
  Future<ShareStart> start({
    required int minutes,
    required String notifyTitle,
    required String notifyText,
  }) async {
    final access = await provider.ensureAccess();
    if (access != LocationAccess.granted) {
      return ShareStart(switch (access) {
        LocationAccess.deniedForever => ShareOutcome.deniedForever,
        LocationAccess.serviceOff => ShareOutcome.serviceOff,
        _ => ShareOutcome.denied,
      });
    }
    GeoPoint p;
    try {
      p = await provider.current();
    } catch (_) {
      return const ShareStart(ShareOutcome.noPosition);
    }
    if (minutes <= 0) {
      return ShareStart(ShareOutcome.ok, point: p, link: p.mapsLink);
    }
    String? link;
    try {
      final r = await api?.liveStart(p.lat, p.lng, accuracy: p.accuracy, minutes: minutes);
      link = r?['url'] as String?;
    } on ApiException {
      link = null; // offline or not signed in: send a plain link for this spot
    }
    if (link == null) {
      return ShareStart(ShareOutcome.ok, point: p, link: p.mapsLink);
    }
    _begin(_clock().add(Duration(minutes: minutes)), link, notifyTitle, notifyText);
    return ShareStart(ShareOutcome.ok,
        point: p, link: link, until: _until, live: true);
  }

  void _begin(DateTime until, String link, String title, String text) {
    _cancelLocal();
    _until = until;
    _link = link;
    _lastSent = _clock();
    _sub = provider.updates(title: title, text: text).listen(_onPoint, onError: (_) {});
    _expiry = Timer(until.difference(_clock()), () => stop());
    notifyListeners();
  }

  Future<void> _onPoint(GeoPoint p) async {
    final last = _lastSent;
    if (last != null && _clock().difference(last) < minGap) return;
    _lastSent = _clock();
    try {
      await api?.liveUpdate(p.lat, p.lng, accuracy: p.accuracy);
    } on ApiException catch (e) {
      if (e.status == 404) await stop(tellServer: false); // the server ended it
    }
  }

  /// After the app restarts: pick up a share the server still has running.
  Future<void> resume(String notifyTitle, String notifyText) async {
    if (api == null || active) return;
    try {
      final r = await api!.liveMine();
      if (r['active'] == true) {
        final until = DateTime.tryParse('${r['expires_at']}')?.toLocal();
        if (until != null && until.isAfter(_clock()) &&
            await provider.ensureAccess() == LocationAccess.granted) {
          _begin(until, '${r['url']}', notifyTitle, notifyText);
        }
      }
    } catch (_) {}
  }

  Future<void> stop({bool tellServer = true}) async {
    final was = active;
    _cancelLocal();
    _until = null;
    _link = null;
    notifyListeners();
    if (was && tellServer) {
      try {
        await api?.liveStop();
      } catch (_) {}
    }
  }

  void _cancelLocal() {
    _sub?.cancel();
    _sub = null;
    _expiry?.cancel();
    _expiry = null;
  }

  @override
  void dispose() {
    _cancelLocal();
    super.dispose();
  }
}

/// Who a share goes to.
class ShareTarget {
  const ShareTarget({
    required this.name,
    this.phone,
    this.chatLinkId,
    this.sms = false,
    this.chat = false,
  });
  final String name;
  final String? phone; // for SMS
  final String? chatLinkId; // server link id of a caregiver, for the app chat
  final bool sms, chat;
}

String liveMessage(String lang, {
  required String name,
  required String link,
  DateTime? until,
}) {
  if (until == null) {
    return tr(lang, 'liveMsgNow').replaceAll('{name}', name).replaceAll('{link}', link);
  }
  final hh = until.hour % 12 == 0 ? 12 : until.hour % 12;
  final time = '$hh:${until.minute.toString().padLeft(2, '0')} ${until.hour < 12 ? 'am' : 'pm'}';
  return tr(lang, 'liveMsg')
      .replaceAll('{name}', name)
      .replaceAll('{time}', time)
      .replaceAll('{link}', link);
}

/// An SMS link for several people at once. Opens the person's own messaging
/// app with the text ready; they press send (the app cannot send SMS silently).
Uri smsUri(List<String> numbers, String body) =>
    Uri.parse('sms:${numbers.join(',')}?body=${Uri.encodeComponent(body)}');

class ShareReport {
  const ShareReport({this.chatSent = 0, this.chatQueued = 0, this.smsOpened = false});
  final int chatSent, chatQueued;

  /// The messaging app was opened with the text ready (the person presses send).
  final bool smsOpened;
}

/// Sends [text] by the app chat (queued if offline) and opens one SMS for the rest.
Future<ShareReport> sendLiveMessage({
  required String text,
  required List<ShareTarget> targets,
  ApiClient? api,
  Future<bool> Function(Uri)? launch,
}) async {
  var sent = 0, queued = 0;
  for (final t in targets.where((t) => t.chat && t.chatLinkId != null)) {
    if (api == null) continue;
    try {
      await api.sendChatMessage(t.chatLinkId!, kind: 'text', text: text);
      sent++;
    } on ApiException catch (e) {
      if (e.isNetwork && api.store != null) {
        await api.queueChatMessage(t.chatLinkId!, kind: 'text', text: text);
        queued++;
      }
    }
  }
  final numbers = {
    for (final t in targets)
      if (t.sms && (t.phone ?? '').isNotEmpty) t.phone!
  }.toList();
  var opened = false;
  if (numbers.isNotEmpty) {
    // One message to everyone, ready in the person's own messaging app. Android
    // does not let a sideloaded app send SMS silently (Play Protect blocks it).
    opened = await (launch ?? (u) => launchUrl(u, mode: LaunchMode.externalApplication))(
        smsUri(numbers, text));
  }
  return ShareReport(chatSent: sent, chatQueued: queued, smsOpened: opened);
}

/// The people a patient can share with, from what is saved on the phone.
Future<List<ShareTarget>> loadShareCandidates(AppDatabase db, String patientId) async {
  final out = <ShareTarget>[];
  for (final l in await db.listCareLinks(patientId)) {
    if (l['kind'] != 'caregiver' && l['kind'] != 'caretaker') continue;
    if (l['status'] != 'accepted') continue;
    out.add(ShareTarget(
        name: l['name'] as String,
        phone: l['phone'] as String?,
        chatLinkId: l['server_link_id'] as String?,
        chat: l['server_link_id'] != null));
  }
  for (final m in await db.listFamily(patientId)) {
    out.add(ShareTarget(
        name: m['name'] as String,
        phone: m['phone'] as String?,
        sms: m['share_location'] == 1));
  }
  return out;
}
