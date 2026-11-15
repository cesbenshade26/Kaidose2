import 'dart:async';
import 'dart:ui' as ui;
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

/// Where the user is, for anything in the app that needs it: the country
/// code on sign-up/login today, nearby or regional feeds later.
///
/// Only ever asks for the lowest level that works: "While Using the App" on
/// iPhone, approximate location on Android. Never throws. A denied
/// permission, location turned off, or a timeout all just come back null,
/// and callers fall back to something sensible.
class LocationService {
  LocationService._();
  static final LocationService instance = LocationService._();

  // geocoding 5.0+ is used through an instance instead of top-level functions.
  final Geocoding _geocoding = Geocoding();

  Position? _lastPosition;
  String? _countryFromLocation; // 2-letter ISO, e.g. "US"
  Future<String?>? _countryInFlight;

  /// The most recent position we got this session, if any (no lookup).
  Position? get lastPosition => _lastPosition;

  /// True if the app may use location right now. Never shows a prompt.
  Future<bool> hasPermission() async {
    try {
      final p = await Geolocator.checkPermission();
      return p == LocationPermission.whileInUse ||
          p == LocationPermission.always;
    } catch (_) {
      return false;
    }
  }

  /// Shows the permission prompt if the user hasn't answered it yet, and
  /// returns whether location is allowed. Once someone says no, the system
  /// won't show the prompt again; this then just returns false.
  Future<bool> requestPermission() async {
    try {
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      return p == LocationPermission.whileInUse ||
          p == LocationPermission.always;
    } catch (_) {
      return false;
    }
  }

  /// Current position (approximate is plenty). [ask] shows the permission
  /// prompt if it hasn't been answered; otherwise this only works when
  /// location is already allowed.
  Future<Position?> currentPosition({bool ask = false}) async {
    final ok = ask ? await requestPermission() : await hasPermission();
    if (!ok) return null;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return _lastPosition;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 8),
        ),
      );
      _lastPosition = pos;
      return pos;
    } catch (_) {
      try {
        return _lastPosition ??= await Geolocator.getLastKnownPosition();
      } catch (_) {
        return _lastPosition;
      }
    }
  }

  /// The user's country as a 2-letter ISO code ("US").
  ///
  /// Uses location when it's allowed ([ask] shows the prompt if it hasn't
  /// been answered), otherwise the phone's region setting, which needs no
  /// permission. Null only if neither is known.
  Future<String?> countryCode({bool ask = false}) async {
    if (_countryFromLocation != null) return _countryFromLocation;
    final inFlight = _countryInFlight;
    if (inFlight != null) return inFlight;

    final future = _resolveCountry(ask);
    _countryInFlight = future;
    try {
      return await future;
    } finally {
      _countryInFlight = null;
    }
  }

  Future<String?> _resolveCountry(bool ask) async {
    final pos = await currentPosition(ask: ask);
    if (pos != null) {
      try {
        final marks = await _geocoding
            .placemarkFromCoordinates(pos.latitude, pos.longitude)
            .timeout(const Duration(seconds: 6));
        for (final m in marks) {
          final iso = m.isoCountryCode;
          if (iso != null && iso.length == 2) {
            // Only a real location result is remembered; the region fallback
            // below is re-checked so allowing location later still upgrades it.
            _countryFromLocation = iso.toUpperCase();
            return _countryFromLocation;
          }
        }
      } catch (_) {}
    }
    return deviceRegion;
  }

  /// The region from the phone's language settings ("US" from en_US).
  /// No permission needed.
  String? get deviceRegion {
    final c = ui.PlatformDispatcher.instance.locale.countryCode;
    return (c != null && c.length == 2) ? c.toUpperCase() : null;
  }
}