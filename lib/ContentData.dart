import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'AppColors.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'DataSaver.dart';
import 'SafetyService.dart';
import 'SettingsWidgets.dart';

/// Settings → Content & data.
///
///   Data usage    Data saver (less video preloading on cellular)
///   Storage       Clear cache (shows how much space it frees)
///   Your feed     Reset "Not interested"
///   Your data     Download your data
class ContentDataScreen extends StatefulWidget {
  const ContentDataScreen({Key? key}) : super(key: key);

  @override
  State<ContentDataScreen> createState() => _ContentDataScreenState();
}

class _ContentDataScreenState extends State<ContentDataScreen> {
  int? _cacheBytes; // null while measuring
  bool _clearing = false;

  int? _hiddenDailies; // null while counting
  bool _resetting = false;

  bool _exporting = false;

  final SafetyService _safety = SafetyService.instance;

  @override
  void initState() {
    super.initState();
    _safety.changes.addListener(_refresh);
    _measure();
    _countHidden();
  }

  @override
  void dispose() {
    _safety.changes.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _snack(String text) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(text)));

  // ─── Storage ──────────────────────────────────────────────────────────

  Future<void> _measure() async {
    final bytes = await AppCache.size();
    if (mounted) setState(() => _cacheBytes = bytes);
  }

  Future<void> _clearCache() async {
    final ok = await settingsConfirm(
      context,
      title: 'Clear cache?',
      message: 'Saved copies of photos and videos are removed from this '
          "phone. Nothing you've posted or saved is deleted. Things may "
          'load a little slower until they\'re saved again.',
      confirmLabel: 'Clear',
    );
    if (!ok || !mounted) return;
    setState(() => _clearing = true);
    final freed = await AppCache.clear();
    if (!mounted) return;
    setState(() => _clearing = false);
    _snack(freed > 0 ? 'Cleared ${formatBytes(freed)}' : 'Cache cleared');
    _measure();
  }

  // ─── Your feed ────────────────────────────────────────────────────────

  Future<void> _countHidden() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final c = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('feed_hidden')
          .count()
          .get();
      if (mounted) setState(() => _hiddenDailies = c.count ?? 0);
    } catch (_) {
      if (mounted) setState(() => _hiddenDailies = 0);
    }
  }

  int get _hiddenTotal =>
      _safety.notInterested.length + (_hiddenDailies ?? 0);

  Future<void> _resetNotInterested() async {
    final ok = await settingsConfirm(
      context,
      title: 'Reset "Not interested"?',
      message: 'Clips and Dailies you marked "Not interested" can show up '
          'again, and your feed stops steering away from things like them. '
          'Everything else your feed has learned stays.',
      confirmLabel: 'Reset',
    );
    if (!ok || !mounted) return;
    setState(() => _resetting = true);
    final done = await FeedReset.notInterested();
    if (!mounted) return;
    setState(() {
      _resetting = false;
      if (done) _hiddenDailies = 0;
    });
    _snack(done
        ? 'Reset. Your feed will update the next time it refreshes.'
        : "Couldn't reset everything. Try again.");
  }

  // ─── Your data ────────────────────────────────────────────────────────

  Future<void> _download() async {
    final ok = await settingsConfirm(
      context,
      title: 'Download your data?',
      message: 'We\'ll put together a file with your profile, posts, clips, '
          'comments, messages you sent, friends and settings. It can take '
          'up to a minute. The link opens in your browser and works for 7 '
          'days.',
      confirmLabel: 'Continue',
    );
    if (!ok || !mounted) return;
    setState(() => _exporting = true);
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('exportMyData',
          options: HttpsCallableOptions(timeout: const Duration(minutes: 3)))
          .call();
      final url = (res.data as Map?)?['url'] as String?;
      if (!mounted) return;
      setState(() => _exporting = false);
      if (url == null) {
        _snack("Couldn't make your file. Try again.");
        return;
      }
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() => _exporting = false);
      _snack(e.message ?? "Couldn't make your file. Try again.");
    } catch (_) {
      if (!mounted) return;
      setState(() => _exporting = false);
      _snack("Couldn't make your file. Try again.");
    }
  }

  // ─── UI ───────────────────────────────────────────────────────────────

  static Widget get _spinner => SizedBox(
    width: 20,
    height: 20,
    child: CircularProgressIndicator(strokeWidth: 2, color: kc.adapt(const Color(0xFFB0B5BC))),
  );

  @override
  Widget build(BuildContext context) {
    final cache = _cacheBytes;
    return SettingsPage(
      title: 'Content & data',
      children: [
        SettingsGroup(
          title: 'Data usage',
          footer: 'On cellular data, videos load when you get to them '
              'instead of ahead of time. Uses less data, but videos may take '
              'a moment to start. Nothing changes on Wi-Fi.',
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: DataSaver.enabled,
              builder: (context, on, _) => SettingsTile(
                icon: Icons.data_saver_on_outlined,
                title: 'Data saver',
                trailing: Switch(
                  value: on,
                  onChanged: DataSaver.set,
                  activeColor: Colors.white,
                  activeTrackColor: Colors.cyan,
                ),
                onTap: () => DataSaver.set(!on),
              ),
            ),
          ],
        ),

        SettingsGroup(
          title: 'Storage',
          footer: 'Photos and videos Kaidose saved on this phone so they '
              'load faster.',
          children: [
            SettingsTile(
              icon: Icons.cleaning_services_outlined,
              title: 'Clear cache',
              value: _clearing || cache == null ? null : formatBytes(cache),
              trailing: _clearing || cache == null ? _spinner : null,
              onTap: _clearing || cache == null ? null : _clearCache,
            ),
          ],
        ),

        SettingsGroup(
          title: 'Your feed',
          children: [
            SettingsTile(
              icon: Icons.restart_alt_rounded,
              title: 'Reset "Not interested"',
              subtitle: _hiddenDailies == null
                  ? null
                  : _hiddenTotal == 0
                  ? "You haven't hidden anything"
                  : '$_hiddenTotal hidden',
              trailing: _resetting ? _spinner : null,
              onTap: _resetting ? null : _resetNotInterested,
            ),
          ],
        ),

        SettingsGroup(
          title: 'Your data',
          children: [
            SettingsTile(
              icon: Icons.download_outlined,
              title: 'Download your data',
              subtitle: _exporting ? 'Putting your file together…' : null,
              trailing: _exporting ? _spinner : null,
              onTap: _exporting ? null : _download,
            ),
          ],
        ),
      ],
    );
  }
}

String formatBytes(int b) {
  if (b < 1024 * 1024) return '${(b / 1024).ceil()} KB';
  if (b < 1024 * 1024 * 1024) {
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

// ─── Cache on this phone ──────────────────────────────────────────────────

/// What Kaidose keeps on the phone to load faster: the image cache
/// (cached_network_image), temporary files (edited photos/videos, picked
/// media), and friends' story videos/photos downloaded for viewing.
class AppCache {
  AppCache._();

  static bool _isStoryFile(FileSystemEntity f) =>
      f is File && f.uri.pathSegments.last.startsWith('friend_story_');

  static Future<int> _dirSize(Directory d) async {
    var total = 0;
    try {
      if (!await d.exists()) return 0;
      await for (final e in d.list(recursive: true, followLinks: false)) {
        if (e is File) {
          try {
            total += await e.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return total;
  }

  static Future<int> size() async {
    var total = 0;
    try {
      total += await _dirSize(await getTemporaryDirectory());
    } catch (_) {}
    try {
      final docs = await getApplicationDocumentsDirectory();
      await for (final e in docs.list(followLinks: false)) {
        if (_isStoryFile(e)) total += await (e as File).length();
      }
    } catch (_) {}
    return total;
  }

  /// Clears it all. Returns about how many bytes were freed.
  static Future<int> clear() async {
    final before = await size();

    // The image cache keeps a small database of what it saved; empty it
    // through its own API so it doesn't point at missing files.
    try {
      await DefaultCacheManager().emptyCache();
    } catch (_) {}

    try {
      final tmp = await getTemporaryDirectory();
      await for (final e in tmp.list(followLinks: false)) {
        try {
          await e.delete(recursive: true);
        } catch (_) {} // in use right now: skip it
      }
    } catch (_) {}

    try {
      final docs = await getApplicationDocumentsDirectory();
      await for (final e in docs.list(followLinks: false)) {
        if (_isStoryFile(e)) {
          try {
            await e.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}

    // Pictures already decoded in memory.
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();

    final after = await size();
    return before > after ? before - after : 0;
  }
}

// ─── Reset "Not interested" ───────────────────────────────────────────────

class FeedReset {
  FeedReset._();

  static Future<void> _deleteAll(Query<Map<String, dynamic>> q) async {
    while (true) {
      final snap = await q.limit(400).get();
      if (snap.docs.isEmpty) return;
      final batch = FirebaseFirestore.instance.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
      if (snap.docs.length < 400) return;
    }
  }

  /// Un-hides every clip and Daily marked "Not interested", and drops the
  /// "show less of this" the feed learned (topics and creators with a
  /// negative score). Positive likes stay. True when it all went through.
  static Future<bool> notInterested() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    final me = FirebaseFirestore.instance.collection('users').doc(uid);
    var ok = true;
    Future<void> step(Future<void> Function() fn) async {
      try {
        await fn();
      } catch (e) {
        ok = false;
        print('FeedReset: $e');
      }
    }

    await step(() => _deleteAll(me.collection('not_interested')));
    await step(() => _deleteAll(me.collection('feed_hidden')));
    await step(() =>
        _deleteAll(me.collection('taste').where('score', isLessThan: 0)));
    await step(() => _deleteAll(
        me.collection('creator_affinity').where('score', isLessThan: 0)));
    return ok;
  }
}