import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings → Content & data → Data saver.
///
/// When it's on and the phone is on cellular data, videos stop loading
/// ahead of time: Clips only gets the next clip ready (instead of the next
/// three), and Dailies don't warm up videos before you open them. Videos
/// still play when you get to them. On Wi-Fi nothing changes.
///
/// Saved on this phone. Started once in main.dart ([init]).
class DataSaver {
  DataSaver._();

  static const _key = 'data_saver_on';

  /// The switch in Settings.
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  static bool _cellular = false;
  static StreamSubscription<List<ConnectivityResult>>? _sub;

  /// True when preloading should be cut back right now.
  static bool get active => enabled.value && _cellular;

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled.value = prefs.getBool(_key) ?? false;
    } catch (_) {}
    try {
      _update(await Connectivity().checkConnectivity());
      _sub ??= Connectivity().onConnectivityChanged.listen(_update);
    } catch (_) {}
  }

  static void _update(List<ConnectivityResult> r) {
    _cellular = r.contains(ConnectivityResult.mobile) &&
        !r.contains(ConnectivityResult.wifi) &&
        !r.contains(ConnectivityResult.ethernet);
  }

  static Future<void> set(bool on) async {
    enabled.value = on;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, on);
    } catch (_) {}
  }

  /// How many clips below the current one to keep ready.
  static int get clipsAhead => active ? 1 : 3;
}