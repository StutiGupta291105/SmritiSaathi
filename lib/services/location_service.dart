import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// A point on the map.
class GeoPoint {
  const GeoPoint(this.lat, this.lng, [this.accuracy = 0]);
  final double lat, lng, accuracy;

  /// A link that opens this spot in any maps app.
  String get mapsLink => 'https://www.google.com/maps?q=$lat,$lng';
}

enum LocationAccess { granted, denied, deniedForever, serviceOff }

/// Where the phone is. A small interface so tests can use a fake.
abstract class LocationProvider {
  /// Asks for permission if needed.
  Future<LocationAccess> ensureAccess();
  Future<GeoPoint> current();

  /// Position updates while a live share is on. [title] and [text] are shown
  /// in the phone's notification while the app keeps sharing in the background.
  Stream<GeoPoint> updates({required String title, required String text});
}

class GeolocatorProvider implements LocationProvider {
  @override
  Future<LocationAccess> ensureAccess() async {
    if (!await Geolocator.isLocationServiceEnabled()) return LocationAccess.serviceOff;
    // Never asks here: the permission was asked once on the Permissions screen. If it was
    // refused, the message says to turn it on in the phone's settings.
    final p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
      return LocationAccess.deniedForever;
    }
    return LocationAccess.granted;
  }

  GeoPoint _p(Position x) => GeoPoint(x.latitude, x.longitude, x.accuracy);

  @override
  Future<GeoPoint> current() async => _p(await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 25))));

  @override
  Stream<GeoPoint> updates({required String title, required String text}) =>
      Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 15,
          intervalDuration: const Duration(seconds: 30),
          // Keeps sharing while the app is not on screen, and tells the person.
          foregroundNotificationConfig: ForegroundNotificationConfig(
            notificationTitle: title,
            notificationText: text,
            enableWakeLock: true,
            setOngoing: true,
          ),
        ),
      ).map(_p);
}
