import 'package:geolocator/geolocator.dart';

import '../domain/attendance.dart';

/// The phone's GPS, read the way SpotLat does it.
class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  @override
  Future<void> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationUnavailable(LocationProblem.serviceOff);
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    switch (permission) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return;
      case LocationPermission.deniedForever:
        throw const LocationUnavailable(LocationProblem.permanentlyDenied);
      case LocationPermission.denied:
      case LocationPermission.unableToDetermine:
        throw const LocationUnavailable(LocationProblem.permissionDenied);
    }
  }

  @override
  Future<LocationFix> currentFix() async {
    // 1. A fresh high-accuracy fix, but don't wait forever: GPS can stall
    //    indoors or on a cold start.
    try {
      return _toFix(
        await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 12),
          ),
        ),
      );
    } on Object {
      // Fall through to the faster options.
    }
    // 2. A recent cached fix, if it's under two minutes old.
    final cached = await Geolocator.getLastKnownPosition();
    if (cached != null &&
        DateTime.now().difference(cached.timestamp).inMinutes < 2) {
      return _toFix(cached);
    }
    // 3. A lower-accuracy fix from Wi-Fi and mobile networks, which works
    //    indoors where GPS alone often can't.
    return _toFix(
      await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 18),
        ),
      ),
    );
  }

  @override
  Future<void> openSettings(LocationProblem problem) async {
    if (problem == LocationProblem.serviceOff) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }

  LocationFix _toFix(Position position) => LocationFix(
    latitude: position.latitude,
    longitude: position.longitude,
    accuracyM: position.accuracy,
    isMocked: position.isMocked,
  );
}
