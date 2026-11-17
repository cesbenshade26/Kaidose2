import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

/// "Near you" in Search. Opt-in both ways: you only see people nearby
/// after turning it on yourself, and only people who also turned it on
/// can see you.
///
/// Only a rough area is ever saved, never your exact location: a 4-letter
/// geohash, a box about 40 × 20 km (city-sized). It's stored on your user
/// doc as `geoCell`, with `nearbyVisible: true`. Turning it off deletes it.
class NearbyService {
  NearbyService._();

  static const int _precision = 4;
  static const Duration _refreshAfter = Duration(days: 3);

  static String? _cell;
  static String? _cellFor;

  static DocumentReference<Map<String, dynamic>>? get _me {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null
        ? null
        : FirebaseFirestore.instance.collection('users').doc(uid);
  }

  /// Your area if "Near you" is on, otherwise null. Refreshes the area in
  /// the background every few days (only if location is still allowed).
  static Future<String?> myCell() async {
    final ref = _me;
    if (ref == null) return null;
    if (_cellFor == ref.id && _cell != null) return _cell;
    try {
      final d = (await ref.get()).data() ?? {};
      if (d['nearbyVisible'] != true) return null;
      final cell = d['geoCell'] as String?;
      _cell = cell;
      _cellFor = ref.id;
      final at = (d['geoUpdatedAt'] as Timestamp?)?.toDate();
      if (at == null || DateTime.now().difference(at) > _refreshAfter) {
        _refreshQuietly();
      }
      return cell;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> isOn() async => (await myCell()) != null;

  /// Asks for location (once) and turns "Near you" on. Returns a short
  /// problem to show, or null when it worked.
  static Future<String?> turnOn() async {
    final ref = _me;
    if (ref == null) return 'Sign in first';
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return 'Turn on Location Services in your phone settings first';
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return 'Allow location for Kaidose in Settings to use Near you';
      }
      final cell = await _currentCell();
      if (cell == null) return "Couldn't get your location. Try again.";
      await ref.set({
        'nearbyVisible': true,
        'geoCell': cell,
        'geoUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _cell = cell;
      _cellFor = ref.id;
      return null;
    } catch (e) {
      print('NearbyService: turnOn failed: $e');
      return "Couldn't turn on Near you. Try again.";
    }
  }

  /// Turns it off and deletes the saved area.
  static Future<void> turnOff() async {
    final ref = _me;
    if (ref == null) return;
    _cell = null;
    await ref.set({
      'nearbyVisible': false,
      'geoCell': FieldValue.delete(),
      'geoUpdatedAt': FieldValue.delete(),
    }, SetOptions(merge: true));
  }

  static Future<void> _refreshQuietly() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm != LocationPermission.always &&
          perm != LocationPermission.whileInUse) {
        return;
      }
      final cell = await _currentCell();
      final ref = _me;
      if (cell == null || ref == null) return;
      await ref.set({
        'geoCell': cell,
        'geoUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _cell = cell;
    } catch (_) {}
  }

  static Future<String?> _currentCell() async {
    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 12),
        ),
      );
    } catch (_) {
      pos = await Geolocator.getLastKnownPosition();
    }
    if (pos == null) return null;
    return geohash(pos.latitude, pos.longitude, _precision);
  }

  static const _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

  /// Standard geohash of a point, [precision] characters long.
  static String geohash(double lat, double lon, int precision) {
    var latMin = -90.0, latMax = 90.0, lonMin = -180.0, lonMax = 180.0;
    final out = StringBuffer();
    var bit = 0, ch = 0;
    var even = true;
    while (out.length < precision) {
      if (even) {
        final mid = (lonMin + lonMax) / 2;
        if (lon >= mid) {
          ch = (ch << 1) | 1;
          lonMin = mid;
        } else {
          ch = ch << 1;
          lonMax = mid;
        }
      } else {
        final mid = (latMin + latMax) / 2;
        if (lat >= mid) {
          ch = (ch << 1) | 1;
          latMin = mid;
        } else {
          ch = ch << 1;
          latMax = mid;
        }
      }
      even = !even;
      if (++bit == 5) {
        out.write(_base32[ch]);
        bit = 0;
        ch = 0;
      }
    }
    return out.toString();
  }
}