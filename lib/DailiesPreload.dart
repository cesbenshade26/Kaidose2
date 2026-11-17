import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'DailyData.dart';
import 'DailyList.dart';
import 'DailyCover.dart' show DailyCoverPrefetch;
import 'DailyForYou.dart';

/// Gets the Dailies screen ready the moment someone is signed in (app
/// open or login), from anywhere in the app: My Dailies, the For You feed,
/// and the covers of the first cards on both tabs. The Dailies screen only
/// reads from here, so it never has to load from scratch when it's shown.
///
/// Call [start] once at launch (main.dart). Safe to call again.
class DailiesPreload {
  DailiesPreload._();

  static StreamSubscription<User?>? _auth;
  static String? _uid;

  static void start() {
    _auth ??= FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user?.uid == _uid) return;
      final switched = _uid != null; // signed out, or another account
      _uid = user?.uid;
      // New account (or signed out): nothing from the last one carries over.
      if (switched) DailiesScrollMemory.reset();
      MyDailiesStore.instance.ensureStarted();
      final existing = DailyForYouController.sharedOrNull;
      if (existing != null && existing.ownerUid != user?.uid) {
        DailyForYouController.resetShared();
      }
      if (user != null) {
        final forYou = DailyForYouController.shared;
        forYou.removeListener(_warmForYou);
        forYou.addListener(_warmForYou);
        _warmForYou();
      }
    });
  }

  static void _warmForYou() {
    final c = DailyForYouController.sharedOrNull;
    if (c == null || c.isLoading || c.hasError) return;
    DailyCoverPrefetch.warm(c.eligible);
  }
}

/// My Dailies (created or joined) and which were opened today, kept live
/// for the whole session.
class MyDailiesStore extends ChangeNotifier {
  MyDailiesStore._();
  static final MyDailiesStore instance = MyDailiesStore._();

  /// Null until the first load.
  List<DailyData>? dailies;
  Set<String> viewedToday = {};
  Object? error;

  StreamSubscription<List<DailyData>>? _sub;
  StreamSubscription<Set<String>>? _viewedSub;
  Timer? _retry;
  String? _for;

  bool get isListening => _sub != null;

  /// Starts listening if it isn't already (e.g. after a hot reload).
  void ensureStarted() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (_for != null) _restart(null); // signed out: drop the old list
      return;
    }
    if (_sub == null || _for != uid) _restart(uid);
  }

  void _restart(String? uid) {
    _sub?.cancel();
    _viewedSub?.cancel();
    _retry?.cancel();
    _sub = null;
    _viewedSub = null;
    if (_for != uid) {
      dailies = null;
      viewedToday = {};
      error = null;
    }
    _for = uid;
    notifyListeners();
    if (uid == null) return;

    _sub = DailyList.getDailiesStream().listen((list) {
      final first = dailies == null;
      dailies = list;
      error = null;
      _retry?.cancel();
      notifyListeners();
      if (first) DailyCoverPrefetch.warm(list);
    }, onError: (e) {
      error = e;
      notifyListeners();
    });
    _viewedSub = DailyList.getViewedDailiesStream().listen((v) {
      viewedToday = v;
      notifyListeners();
    }, onError: (_) {});

    // Nothing yet after a few seconds (slow sign-in, dropped stream): try
    // again rather than leaving the tab on a spinner.
    _retry = Timer(const Duration(seconds: 5), () {
      if (dailies == null && _for == uid) _restart(uid);
    });
  }
}

/// Which Dailies tab you were on and how far down each one you'd
/// scrolled. Lives outside the screen, so leaving Dailies (another tab,
/// another app) and coming back puts you exactly where you were. Reset on
/// sign-out / account switch, and naturally when the app is fully closed.
class DailiesScrollMemory {
  DailiesScrollMemory._();

  static bool showForYou = true;
  static final Map<bool, double> offsets = {true: 0, false: 0};

  static void reset() {
    showForYou = true;
    offsets[true] = 0;
    offsets[false] = 0;
  }
}