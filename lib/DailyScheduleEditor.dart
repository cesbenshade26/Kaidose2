import 'dart:io';
import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'AppColors.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'DailyData.dart';
import 'DailyCoverData.dart';

/// What's saved for one calendar day.
class _DayEntry {
  final String prompt;
  final String hook;
  final String? coverUrl;
  // True when coverUrl is a still frame taken from a video (drives the
  // play badge). The video itself is never uploaded.
  final bool coverIsVideo;

  const _DayEntry({
    this.prompt = '',
    this.hook = '',
    this.coverUrl,
    this.coverIsVideo = false,
  });

  bool get isEmpty => prompt.isEmpty && hook.isEmpty && coverUrl == null;
}

/// Lets a Daily's owner schedule an entry prompt and a cover (hook text +
/// photo or video) for any day from today through the next 30. Each day is
/// its own doc, dailies/{dailyId}/daily_schedule/{yyyy-MM-dd}, so a cover
/// set for the 8th exists only for the 8th. DailyCoverService.watchCover
/// reads today's doc and layers it over the automatic cover.
///
/// A video cover is stored as one still frame (pulled on the phone, so the
/// video itself never uploads) plus a flag that adds the play badge.
///
/// Prompts work the same way: members get the entry prompt only on the day
/// it's scheduled for (DailyCoverService.todayPrompt).
///
/// "Select days" lets the owner tick several days (across weeks) and save
/// the same prompt and/or cover to all of them at once.
class DailyScheduleEditor extends StatefulWidget {
  final DailyData daily;
  final bool isOwner;
  final Color accentColor;

  const DailyScheduleEditor({
    Key? key,
    required this.daily,
    required this.isOwner,
    required this.accentColor,
  }) : super(key: key);

  @override
  State<DailyScheduleEditor> createState() => _DailyScheduleEditorState();
}

class _DailyScheduleEditorState extends State<DailyScheduleEditor> {
  static const int _maxDaysAhead = 30;
  static const List<String> _weekdayLetters = ['S', 'M', 'T', 'W', 'Th', 'F', 'Sa'];
  static const List<String> _weekdayNames = [
    'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'
  ];
  static const List<String> _monthAbbr = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  static const List<String> _videoExtensions = [
    '.mp4', '.mov', '.m4v', '.avi', '.3gp', '.webm', '.mkv'
  ];

  late final DateTime _today;
  late final DateTime _lastEditable;
  late DateTime _weekStart;
  late DateTime _selectedDay;

  int _tabIndex = 0;

  final TextEditingController _promptController = TextEditingController();
  final TextEditingController _hookController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  // A newly picked cover not yet uploaded: either a photo file, or a
  // still frame already pulled from a picked video.
  File? _pickedPhoto;
  Uint8List? _pickedVideoFrame;

  // The saved cover as the editor currently sees it (cleared when the
  // owner removes it, until they save).
  String? _savedCoverUrl;
  bool _savedCoverIsVideo = false;

  // Saved entries for every week viewed so far, keyed by yyyy-MM-dd.
  final Map<String, _DayEntry> _entries = {};
  final Set<String> _loadedKeys = {};

  // "Select days" mode: the day being edited (_selectedDay) plus any other
  // days ticked, by date key. Saving copies to all of them.
  bool _multiSelect = false;
  final Set<String> _extraDays = {};

  bool _loadingWeek = true;
  bool _saving = false;
  bool _extractingFrame = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _today = DateTime(now.year, now.month, now.day);
    _lastEditable = DateTime(now.year, now.month, now.day + _maxDaysAhead);
    _weekStart = _sundayOf(_today);
    _selectedDay = _today;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadWeek(_weekStart);
    });
  }

  @override
  void dispose() {
    _promptController.dispose();
    _hookController.dispose();
    super.dispose();
  }

  // ─── Date helpers ──────────────────────────────────────────────────────────

  DateTime _addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

  // Weekday is 1 (Mon) to 7 (Sun), so % 7 puts Sunday at 0.
  DateTime _sundayOf(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday % 7));

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _dateKey(DateTime d) => CoverWindow.dateKey(d);

  bool _isSelectable(DateTime d) => !d.isBefore(_today) && !d.isAfter(_lastEditable);

  bool get _canGoBack => _weekStart.isAfter(_sundayOf(_today));

  bool get _canGoForward => !_addDays(_weekStart, 7).isAfter(_lastEditable);

  String _monthLabel(List<DateTime> days) {
    final first = _monthAbbr[days.first.month - 1];
    final last = _monthAbbr[days.last.month - 1];
    return first == last ? first : '$first – $last';
  }

  String _dayHeading(DateTime d) {
    final base = '${_weekdayNames[d.weekday % 7]}, ${_monthAbbr[d.month - 1]} ${d.day}';
    return _sameDay(d, _today) ? '$base · Today' : base;
  }

  // ─── Loading ───────────────────────────────────────────────────────────────

  /// One query for the whole visible week (only days not already loaded),
  /// which also drives the dots under days that have something scheduled.
  Future<void> _loadWeek(DateTime weekStart, {bool fillEditor = true}) async {
    final keys = List.generate(7, (i) => _dateKey(_addDays(weekStart, i)))
        .where((k) => !_loadedKeys.contains(k))
        .toList();

    if (keys.isNotEmpty) {
      if (mounted) setState(() => _loadingWeek = true);
      try {
        final snap = await DailyCoverService.scheduleCollection(widget.daily.id)
            .where(FieldPath.documentId, whereIn: keys)
            .get();

        for (final doc in snap.docs) {
          final data = doc.data();
          final cover = (data['coverMediaUrl'] as String?)?.trim() ?? '';
          _entries[doc.id] = _DayEntry(
            prompt: (data['prompt'] as String?) ?? '',
            hook: (data['coverHook'] as String?) ?? '',
            coverUrl: cover.isEmpty ? null : cover,
            coverIsVideo: cover.isNotEmpty && (data['coverIsVideo'] as bool? ?? false),
          );
        }
        _loadedKeys.addAll(keys);
      } catch (e) {
        print('DailyScheduleEditor: load error: $e');
      }
    }

    if (!mounted) return;
    setState(() {
      _loadingWeek = false;
      if (fillEditor) _applyDay(_selectedDay);
    });
  }

  /// Fills the editor with a day's saved values.
  void _applyDay(DateTime day) {
    final entry = _entries[_dateKey(day)] ?? const _DayEntry();
    _promptController.text = entry.prompt;
    _hookController.text = entry.hook;
    _pickedPhoto = null;
    _pickedVideoFrame = null;
    _savedCoverUrl = entry.coverUrl;
    _savedCoverIsVideo = entry.coverIsVideo;
  }

  bool get _hasUnsavedChanges {
    final saved = _entries[_dateKey(_selectedDay)] ?? const _DayEntry();
    return _promptController.text.trim() != saved.prompt ||
        _hookController.text.trim() != saved.hook ||
        _pickedPhoto != null ||
        _pickedVideoFrame != null ||
        _savedCoverUrl != saved.coverUrl;
  }

  Future<bool> _confirmDiscardIfNeeded() async {
    if (!_hasUnsavedChanges) return true;

    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Discard changes?'),
        content: Text(
          'You have unsaved changes for ${_dayHeading(_selectedDay)}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return discard == true;
  }

  // ─── Navigation ────────────────────────────────────────────────────────────

  Future<void> _selectDay(DateTime day) async {
    if (!_isSelectable(day) || _saving) return;
    // Select days: tapping ticks / unticks extra days; the day being
    // edited stays put.
    if (_multiSelect) {
      if (_sameDay(day, _selectedDay)) return;
      final key = _dateKey(day);
      setState(() {
        if (!_extraDays.remove(key)) _extraDays.add(key);
      });
      return;
    }
    if (_sameDay(day, _selectedDay)) return;
    if (!await _confirmDiscardIfNeeded()) return;
    setState(() {
      _selectedDay = day;
      _applyDay(day);
    });
  }

  Future<void> _changeWeek(int delta) async {
    if (_saving) return;
    if (delta < 0 && !_canGoBack) return;
    if (delta > 0 && !_canGoForward) return;

    final newStart = _addDays(_weekStart, 7 * delta);

    // Select days: just look at another week; the day being edited (and
    // anything typed for it) and the ticked days stay as they are.
    if (_multiSelect) {
      setState(() => _weekStart = newStart);
      await _loadWeek(newStart, fillEditor: false);
      return;
    }

    if (!await _confirmDiscardIfNeeded()) return;

    DateTime target = newStart;
    for (int i = 0; i < 7; i++) {
      final d = _addDays(newStart, i);
      if (_isSelectable(d)) {
        target = d;
        break;
      }
    }

    setState(() {
      _weekStart = newStart;
      _selectedDay = target;
    });
    await _loadWeek(newStart);
  }

  // ─── Cover photo / video ───────────────────────────────────────────────────

  bool _looksLikeVideo(XFile file) {
    final mime = file.mimeType?.toLowerCase();
    if (mime != null && mime.startsWith('video/')) return true;
    final path = file.path.toLowerCase();
    return _videoExtensions.any(path.endsWith);
  }

  /// Pulls one still frame from a video on the phone. Tries a second in
  /// first (the very first frame is often black from a fade-in), then falls
  /// back to the first frame for very short clips.
  Future<Uint8List?> _extractFrame(String videoPath) async {
    for (final ms in [1000, 0]) {
      try {
        final bytes = await VideoThumbnail.thumbnailData(
          video: videoPath,
          imageFormat: ImageFormat.JPEG,
          maxWidth: 1080,
          quality: 80,
          timeMs: ms,
        ).timeout(const Duration(seconds: 20));
        if (bytes != null && bytes.isNotEmpty) return bytes;
      } catch (e) {
        print('DailyScheduleEditor: frame extraction at ${ms}ms failed: $e');
      }
    }
    return null;
  }

  Future<void> _pickCover() async {
    if (!widget.isOwner || _saving || _loadingWeek || _extractingFrame) return;

    final XFile? media = await _picker.pickMedia(
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (media == null || !mounted) return;

    if (_looksLikeVideo(media)) {
      setState(() => _extractingFrame = true);
      final frame = await _extractFrame(media.path);
      if (!mounted) return;
      setState(() => _extractingFrame = false);

      if (frame == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't read that video. Try another."),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }
      setState(() {
        _pickedVideoFrame = frame;
        _pickedPhoto = null;
      });
    } else {
      setState(() {
        _pickedPhoto = File(media.path);
        _pickedVideoFrame = null;
      });
    }
  }

  void _removeCover() {
    setState(() {
      _pickedPhoto = null;
      _pickedVideoFrame = null;
      _savedCoverUrl = null;
      _savedCoverIsVideo = false;
    });
  }

  /// Saves [prompt] and/or [cover] onto another day, keeping whatever
  /// that day already had for the part not given. A day left with nothing
  /// at all has its doc removed.
  Future<void> _applyToDay(String key, {String? prompt, _DayEntry? cover}) async {
    final ref = DailyCoverService.scheduleRef(widget.daily.id, key);
    final snap = await ref.get();
    final d = snap.data() ?? const <String, dynamic>{};
    final oldCover = ((d['coverMediaUrl'] as String?) ?? '').trim();

    final entry = _DayEntry(
      prompt: prompt ?? ((d['prompt'] as String?) ?? '').trim(),
      hook: cover?.hook ?? ((d['coverHook'] as String?) ?? '').trim(),
      coverUrl: cover != null
          ? cover.coverUrl
          : (oldCover.isEmpty ? null : oldCover),
      coverIsVideo: cover != null
          ? cover.coverIsVideo
          : (oldCover.isNotEmpty && d['coverIsVideo'] == true),
    );

    if (entry.isEmpty) {
      if (snap.exists) await ref.delete();
    } else {
      await ref.set({
        'prompt': entry.prompt.isNotEmpty ? entry.prompt : FieldValue.delete(),
        'coverHook': entry.hook.isNotEmpty ? entry.hook : FieldValue.delete(),
        'coverMediaUrl': entry.coverUrl ?? FieldValue.delete(),
        'coverIsVideo': (entry.coverUrl != null && entry.coverIsVideo)
            ? true
            : FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': FirebaseAuth.instance.currentUser?.uid,
      }, SetOptions(merge: true));
    }
    _entries[key] = entry;
    _loadedKeys.add(key);
  }

  String _shortDate(DateTime d) => '${_monthAbbr[d.month - 1]} ${d.day}';

  DateTime _parseKey(String key) {
    final p = key.split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2]);
  }

  void _setMultiSelect(bool on) {
    if (_saving) return;
    setState(() {
      _multiSelect = on;
      _extraDays.clear();
    });
  }

  // ─── Saving ────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!widget.isOwner || _saving || _loadingWeek || _extractingFrame) return;

    final day = _selectedDay;
    final key = _dateKey(day);
    final saved = _entries[key] ?? const _DayEntry();
    final extraKeys = _multiSelect ? _extraDays.toList() : const <String>[];
    setState(() => _saving = true);

    try {
      final prompt = _promptController.text.trim();
      final hook = _hookController.text.trim();
      String? coverUrl = _savedCoverUrl;
      bool coverIsVideo = _savedCoverIsVideo;

      // Unique file name per save, so a replaced cover gets a new URL and
      // the image cache can't keep showing the old one.
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final folder = FirebaseStorage.instance
          .ref()
          .child('daily_cover_thumbnails/${widget.daily.id}');

      if (_pickedVideoFrame != null) {
        final ref = folder.child('manual_${key}_$stamp.jpg');
        await ref.putData(
            _pickedVideoFrame!, SettableMetadata(contentType: 'image/jpeg'));
        coverUrl = await ref.getDownloadURL();
        coverIsVideo = true;
      } else if (_pickedPhoto != null) {
        final ref = folder.child('manual_${key}_$stamp.jpg');
        await ref.putFile(
            _pickedPhoto!, SettableMetadata(contentType: 'image/jpeg'));
        coverUrl = await ref.getDownloadURL();
        coverIsVideo = false;
      }

      final entry = _DayEntry(
        prompt: prompt,
        hook: hook,
        coverUrl: coverUrl,
        coverIsVideo: coverUrl != null && coverIsVideo,
      );
      final docRef = DailyCoverService.scheduleRef(widget.daily.id, key);

      if (entry.isEmpty) {
        // Nothing left for this day, so remove its doc entirely.
        await docRef.delete();
      } else {
        await docRef.set({
          if (prompt.isNotEmpty) 'prompt': prompt,
          if (hook.isNotEmpty) 'coverHook': hook,
          if (coverUrl != null) 'coverMediaUrl': coverUrl,
          if (coverUrl != null && coverIsVideo) 'coverIsVideo': true,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': FirebaseAuth.instance.currentUser?.uid,
        });
      }

      // Old cover images are never deleted here: one image can be shared
      // by several days.

      _entries[key] = entry;
      _loadedKeys.add(key);

      // Select days: copy what was changed to the other ticked days (or,
      // if nothing was changed, whatever tab is open). Each day keeps the
      // part that wasn't copied.
      if (extraKeys.isNotEmpty) {
        var copyPrompt = prompt != saved.prompt;
        var copyCover = hook != saved.hook ||
            coverUrl != saved.coverUrl ||
            entry.coverIsVideo != saved.coverIsVideo;
        if (!copyPrompt && !copyCover) {
          copyPrompt = _tabIndex == 0;
          copyCover = _tabIndex == 1;
        }
        for (final k in extraKeys) {
          await _applyToDay(
            k,
            prompt: copyPrompt ? prompt : null,
            cover: copyCover ? entry : null,
          );
        }
      }

      if (mounted) {
        setState(() {
          _pickedPhoto = null;
          _pickedVideoFrame = null;
          _savedCoverUrl = coverUrl;
          _savedCoverIsVideo = entry.coverIsVideo;
        });
        final label = extraKeys.isEmpty
            ? _shortDate(day)
            : '${extraKeys.length + 1} days';
        if (_multiSelect) {
          _multiSelect = false;
          _extraDays.clear();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved $label'),
            backgroundColor: widget.accentColor,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('DailyScheduleEditor: save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't save. Try again."),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ─── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kc.grey(50),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kc.grey(200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildWeekStrip(),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  _dayHeading(_selectedDay),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: kc.text,
                  ),
                ),
              ),
              if (widget.isOwner) _buildSelectDaysToggle(),
            ],
          ),
          if (_multiSelect) ...[
            const SizedBox(height: 6),
            Text(
              _extraDays.isEmpty
                  ? 'Tap other days to add them. Saving copies this '
                  'day\'s prompt and/or cover to every ticked day.'
                  : 'Also saving to ${_extraLabel()}.',
              style: TextStyle(fontSize: 12.5, color: kc.grey(600)),
            ),
          ],
          const SizedBox(height: 12),
          _buildTabs(),
          const SizedBox(height: 16),
          if (_loadingWeek)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator(color: kc.adapt(const Color(0xFFB0B5BC)))),
            )
          else ...[
            if (_tabIndex == 0) _buildPromptTab() else _buildCoverTab(),
            if (widget.isOwner) ...[
              const SizedBox(height: 16),
              _buildSaveButton(),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildWeekStrip() {
    final days = List.generate(7, (i) => _addDays(_weekStart, i));

    return Column(
      children: [
        Row(
          children: [
            _chevron(Icons.chevron_left, _canGoBack, () => _changeWeek(-1)),
            Expanded(
              child: Center(
                child: Text(
                  _monthLabel(days),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: kc.text,
                  ),
                ),
              ),
            ),
            _chevron(Icons.chevron_right, _canGoForward, () => _changeWeek(1)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: days.map((d) => Expanded(child: _dayCell(d))).toList(),
        ),
      ],
    );
  }

  Widget _chevron(IconData icon, bool enabled, VoidCallback onTap) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 26, color: enabled ? kc.text : kc.grey(300)),
      ),
    );
  }

  Widget _dayCell(DateTime d) {
    final selectable = _isSelectable(d);
    final selected = _sameDay(d, _selectedDay);
    // Ticked in "Select days" (gets the same save as the selected day).
    final ticked = _multiSelect && _extraDays.contains(_dateKey(d));
    final hasEntry = !(_entries[_dateKey(d)]?.isEmpty ?? true);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: selectable ? () => _selectDay(d) : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _weekdayLetters[d.weekday % 7],
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selectable ? kc.grey(600) : kc.grey(400),
            ),
          ),
          const SizedBox(height: 6),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? Colors.cyan
                  : (ticked ? Colors.cyan.withOpacity(0.15) : Colors.transparent),
              shape: BoxShape.circle,
              border: Border.all(
                color: ticked ? Colors.cyan : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Text(
              '${d.day}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: selected
                    ? Colors.white
                    : ticked
                    ? Colors.cyan[700]
                    : (selectable ? kc.text : kc.grey(400)),
              ),
            ),
          ),
          const SizedBox(height: 4),
          // Dot marks a day that already has something scheduled.
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hasEntry ? Colors.cyan : Colors.transparent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Row(
      children: [
        _tab(0, 'Entry Prompt'),
        _tab(1, 'Cover'),
      ],
    );
  }

  Widget _tab(int index, String label) {
    final active = _tabIndex == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _tabIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? Colors.cyan : kc.grey(300),
                width: 2,
              ),
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: active ? kc.text : kc.grey(500),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPromptTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Daily Entry Prompt'),
        const SizedBox(height: 10),
        TextField(
          controller: _promptController,
          enabled: widget.isOwner && !_saving,
          maxLength: 100,
          style: TextStyle(fontSize: 16, color: kc.text),
          decoration: _inputDeco('Enter a prompt for this day...'),
        ),
      ],
    );
  }

  Widget _buildCoverTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Cover Hook'),
        const SizedBox(height: 4),
        Text(
          'A short teaser above the photo. Optional.',
          style: TextStyle(fontSize: 12, color: kc.grey(500)),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _hookController,
          enabled: widget.isOwner && !_saving,
          maxLength: 90,
          style: TextStyle(fontSize: 16, color: kc.text),
          decoration: _inputDeco('Enter a hook...'),
        ),
        const SizedBox(height: 12),
        _fieldLabel('Cover Photo or Video'),
        const SizedBox(height: 4),
        Text(
          'Optional. A video shows one still frame with a play icon.',
          style: TextStyle(fontSize: 12, color: kc.grey(500)),
        ),
        const SizedBox(height: 10),
        _buildCoverPicker(),
      ],
    );
  }

  /// "Select days" on/off, next to the day's heading.
  Widget _buildSelectDaysToggle() {
    final on = _multiSelect;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _setMultiSelect(!on),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: on ? Colors.cyan.withOpacity(0.12) : kc.grey(100),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: on ? Colors.cyan : kc.grey(300)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(on ? Icons.close_rounded : Icons.date_range_rounded,
                size: 15, color: on ? Colors.cyan[700] : kc.grey(700)),
            const SizedBox(width: 5),
            Text(
              on ? 'Done' : 'Select days',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: on ? Colors.cyan[700] : kc.grey(700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "Nov 21, Nov 23 and 2 more"
  String _extraLabel() {
    final days = _extraDays.map(_parseKey).toList()..sort();
    final names = days.map(_shortDate).toList();
    if (names.length <= 3) {
      if (names.length == 1) return names.first;
      return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
    }
    return '${names.take(2).join(', ')} and ${names.length - 2} more';
  }

  Widget _playBadge() {
    return Positioned(
      left: 10,
      bottom: 10,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: const BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
      ),
    );
  }

  Widget _buildCoverPicker() {
    final hasCover =
        _pickedPhoto != null || _pickedVideoFrame != null || _savedCoverUrl != null;

    if (_extractingFrame) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 36),
        decoration: BoxDecoration(
          color: kc.grey(100),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kc.grey(300)),
        ),
        child: Column(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(color: kc.adapt(const Color(0xFFB0B5BC)), strokeWidth: 2.5),
            ),
            const SizedBox(height: 10),
            Text('Reading video...',
                style: TextStyle(fontSize: 13, color: kc.grey(600))),
          ],
        ),
      );
    }

    if (!hasCover) {
      return GestureDetector(
        onTap: widget.isOwner ? _pickCover : null,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 28),
          decoration: BoxDecoration(
            color: kc.grey(100),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kc.grey(300)),
          ),
          child: Column(
            children: [
              Icon(Icons.add_photo_alternate_outlined,
                  size: 36, color: kc.grey(600)),
              const SizedBox(height: 8),
              Text(
                'Upload a photo or video',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: kc.grey(700),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final showsBadge = _pickedVideoFrame != null ||
        (_pickedPhoto == null && _savedCoverIsVideo);

    return Stack(
      children: [
        GestureDetector(
          onTap: widget.isOwner ? _pickCover : null,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: double.infinity,
              height: 170,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_pickedVideoFrame != null)
                    Image.memory(_pickedVideoFrame!, fit: BoxFit.cover)
                  else if (_pickedPhoto != null)
                    Image.file(_pickedPhoto!, fit: BoxFit.cover)
                  else
                    CachedNetworkImage(
                      imageUrl: _savedCoverUrl!,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: kc.grey(200),
                        child: Center(
                          child: CircularProgressIndicator(
                              color: kc.adapt(const Color(0xFFB0B5BC)), strokeWidth: 2.5),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: kc.grey(200),
                        child: Icon(Icons.broken_image_outlined,
                            color: kc.grey(400), size: 36),
                      ),
                    ),
                  if (showsBadge) _playBadge(),
                ],
              ),
            ),
          ),
        ),
        if (widget.isOwner)
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: _saving ? null : _removeCover,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 18),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSaveButton() {
    final day = _selectedDay;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: (_saving || _extractingFrame) ? null : _save,
        style: ElevatedButton.styleFrom(
          backgroundColor: widget.accentColor,
          foregroundColor: Colors.white,
          disabledBackgroundColor: widget.accentColor.withOpacity(0.5),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: _saving
            ? const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
              color: Colors.white, strokeWidth: 2.5),
        )
            : Text(
          (_multiSelect && _extraDays.isNotEmpty)
              ? 'Save ${_extraDays.length + 1} days'
              : 'Save ${_monthAbbr[day.month - 1]} ${day.day}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) => Text(
    text,
    style: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: kc.text,
    ),
  );

  InputDecoration _inputDeco(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: kc.grey(400), fontSize: 16),
    filled: true,
    fillColor: widget.isOwner ? kc.surface : kc.grey(100),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: kc.grey(300)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: kc.grey(300)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: widget.accentColor, width: 2),
    ),
    disabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    contentPadding:
    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  );
}