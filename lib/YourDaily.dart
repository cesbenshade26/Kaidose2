import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'DailyPhotoManager.dart';
import 'DailyPhotoTracker.dart';
import 'DailyVideoTracker.dart';
import 'FriendDailyService.dart';
import 'friend_request_service.dart';
import 'YourDailyBubbles.dart';
import 'YourDailyBubbleSelectSheet.dart';
import 'VideoClipPlayer.dart';
import 'UnifiedMediaPicker.dart';
import 'PhotoEditor.dart';
import 'StoryPhotoFrame.dart';
import 'MusicSearch.dart';
import 'ClipMusic.dart';
import 'StoryMusic.dart';

class UseCam {
  static final ImagePicker _picker = ImagePicker();

  static Future<XFile?> openCamera(BuildContext context) async {
    print("Camera button tapped!");
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1800,
        maxHeight: 1800,
        imageQuality: 80,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (image != null) {
        print('Captured image path: ${image.path}');
        return image;
      } else {
        print('No image captured - user cancelled');
        return null;
      }
    } catch (e) {
      print('Error accessing camera: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error accessing camera: $e'),
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.red,
        ),
      );
      return null;
    }
  }
}

// ─── Friend picker sheet (photo or video) ─────────────────────────────────────

class _FriendPickerSheet extends StatefulWidget {
  final File file;
  final bool isVideo;

  const _FriendPickerSheet({required this.file, required this.isVideo});

  @override
  State<_FriendPickerSheet> createState() => _FriendPickerSheetState();
}

class _FriendPickerSheetState extends State<_FriendPickerSheet> {
  final FriendRequestService _friendRequestService = FriendRequestService();
  List<_FriendEntry> _friends = [];
  bool _isLoading = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    _friendRequestService.getAcceptedFriends().first.then((friends) {
      if (!mounted) return;
      final currentUid = _friendRequestService.currentUserId;
      final entries = friends.map((f) {
        final friendId =
        f.fromUserId == currentUid ? f.toUserId : f.fromUserId;
        final friendName =
        f.fromUserId == currentUid ? f.toUsername : f.fromUsername;
        return _FriendEntry(uid: friendId, username: friendName);
      }).toList();

      setState(() {
        _friends = entries;
        _isLoading = false;
      });
    }).catchError((e) {
      print('FriendPickerSheet: error loading friends: $e');
      if (mounted) setState(() => _isLoading = false);
    });
  }

  int get _checkedCount => _friends.where((f) => f.checked).length;

  Future<void> _send() async {
    final selected =
    _friends.where((f) => f.checked).map((f) => f.uid).toList();
    if (selected.isEmpty) return;

    setState(() => _isSending = true);
    if (widget.isVideo) {
      await FriendDailyService.shareVideoWithFriends(widget.file, selected);
    } else {
      await FriendDailyService.sharePhotoWithFriends(widget.file, selected);
    }
    if (mounted) {
      Navigator.pop(context, true); // true = sent successfully
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Share with Friends',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87),
            ),
            const SizedBox(height: 4),
            Text(
              'Only the friends you pick will see this',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(color: Colors.cyan),
              )
            else if (_friends.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No friends yet — add friends first!',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.4,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _friends.length,
                  itemBuilder: (context, index) {
                    final friend = _friends[index];
                    return CheckboxListTile(
                      value: friend.checked,
                      onChanged: (val) =>
                          setState(() => friend.checked = val ?? false),
                      title: Text(
                        friend.username,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      secondary: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            friend.username.isNotEmpty
                                ? friend.username[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey[800],
                            ),
                          ),
                        ),
                      ),
                      activeColor: Colors.cyan,
                      checkboxShape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(5)),
                      controlAffinity: ListTileControlAffinity.trailing,
                      contentPadding:
                      const EdgeInsets.symmetric(horizontal: 4),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: (_isLoading || _isSending || _checkedCount == 0)
                    ? null
                    : _send,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyan,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.cyan.withOpacity(0.35),
                  disabledForegroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                child: _isSending
                    ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.5),
                )
                    : Text(
                  _checkedCount == 0
                      ? 'Send'
                      : 'Send to $_checkedCount',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 12),
          ],
        ),
      ),
    );
  }
}

class _FriendEntry {
  final String uid;
  final String username;
  bool checked;

  _FriendEntry({
    required this.uid,
    required this.username,
    this.checked = false,
  });
}

// ─── YourDailyWidget ──────────────────────────────────────────────────────────

/// Post to Your Daily: pick or capture one photo/video, then either share it
/// with chosen friends or post it to your Daily. Today's posted photos can be
/// browsed with the side arrows; the leftmost "page" is the new-post state.
///
/// Daily Bubble creation is not here — it lives in the Add sheet.
class YourDailyWidget extends StatefulWidget {
  const YourDailyWidget({Key? key}) : super(key: key);

  @override
  State<YourDailyWidget> createState() => _YourDailyWidgetState();
}

class _YourDailyWidgetState extends State<YourDailyWidget> {
  static const double _pickerHeight = 330;

  File? _selectedPhoto;
  File? _selectedVideo;
  // True once text/drawing has been baked in: the photo is then already a
  // whole story-shaped picture.
  bool _composited = false;
  // Song picked in the editor for the Daily being made, and whether the
  // editor is open (the song is silent here while it is).
  MusicTrack? _dailyMusic;
  bool _editorOpen = false;
  // -1 = new-post mode; 0.._todaysPhotos.length-1 = browsing posted photos.
  int _currentPhotoIndex = -1;
  List<File> _todaysPhotos = [];
  VoidCallback? _trackerListener;
  bool _showPicker = false;

  @override
  void initState() {
    super.initState();

    _initializeTracker();
    DailyVideoTracker.initialize();

    _trackerListener = () {
      if (mounted) {
        setState(() {
          _todaysPhotos = DailyPhotoTracker.todaysPhotos;
          if (_todaysPhotos.isNotEmpty &&
              _currentPhotoIndex == -1 &&
              !_hasSelectedMedia) {
            _currentPhotoIndex = _todaysPhotos.length - 1;
          }
        });
      }
    };

    DailyPhotoTracker.addListener(_trackerListener!);
  }

  @override
  void dispose() {
    if (_trackerListener != null) {
      DailyPhotoTracker.removeListener(_trackerListener!);
    }
    super.dispose();
  }

  Future<void> _initializeTracker() async {
    await DailyPhotoTracker.initialize();
    if (mounted) {
      setState(() {
        _todaysPhotos = DailyPhotoTracker.todaysPhotos;
        if (_todaysPhotos.isNotEmpty) {
          _currentPhotoIndex = _todaysPhotos.length - 1;
        }
      });
    }
  }

  bool get _isInNewPhotoMode => _currentPhotoIndex == -1;
  bool get _hasSelectedMedia =>
      _selectedPhoto != null || _selectedVideo != null;

  File? get _postedPhoto =>
      (_currentPhotoIndex >= 0 && _currentPhotoIndex < _todaysPhotos.length)
          ? _todaysPhotos[_currentPhotoIndex]
          : null;

  // ─── Selecting media ────────────────────────────────────────────────────

  void _onLibraryPicked(List<PickedMedia> items) {
    if (items.isEmpty) {
      setState(() => _showPicker = false);
      return;
    }
    final item = items.first;
    setState(() {
      _showPicker = false;
      _currentPhotoIndex = -1;
      if (item.isVideo) {
        _selectedVideo = item.file;
        _selectedPhoto = null;
      } else {
        _selectedPhoto = item.file;
        _selectedVideo = null;
        _composited = false;
        _dailyMusic = null;
      }
    });
  }

  Future<void> _openCamera() async {
    FocusScope.of(context).unfocus();
    final XFile? pickedFile = await UseCam.openCamera(context);
    if (pickedFile != null && mounted) {
      setState(() {
        _selectedPhoto = File(pickedFile.path);
        _selectedVideo = null;
        _composited = false;
        _dailyMusic = null;
        _currentPhotoIndex = -1;
        _showPicker = false;
      });
    }
  }

  /// Opens the editor (crop, text, draw, music) on the chosen photo or
  /// video. The edited copy replaces it, so posting and sharing work exactly
  /// as before.
  Future<void> _editSelected() async {
    final photo = _selectedPhoto;
    final video = _selectedVideo;
    final file = photo ?? video;
    if (file == null) return;
    setState(() => _editorOpen = true);
    final result = await PhotoEditor.open(
      context,
      file,
      isVideo: video != null,
      storyLayout: !_composited,
      allowCrop: !_composited,
      withAudio: true,
    );
    if (!mounted) return;
    setState(() => _editorOpen = false);
    if (result == null) return;
    setState(() {
      _dailyMusic = result.music ?? _dailyMusic;
      if (video != null) {
        _selectedVideo = result.file;
      } else {
        _selectedPhoto = result.file;
        _composited = _composited || result.composite;
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _composited = false;
      _dailyMusic = null;
      _selectedPhoto = null;
      _selectedVideo = null;
    });
  }

  void _addAnotherDaily() {
    setState(() {
      _composited = false;
      _dailyMusic = null;
      _selectedPhoto = null;
      _selectedVideo = null;
      _currentPhotoIndex = -1;
    });
  }

  void _navigatePhotos(int direction) {
    if (_todaysPhotos.isEmpty) return;
    final newIndex =
    (_currentPhotoIndex + direction).clamp(-1, _todaysPhotos.length - 1);
    if (newIndex == _currentPhotoIndex) return;
    setState(() {
      _currentPhotoIndex = newIndex;
      _selectedPhoto = null;
      _selectedVideo = null;
      _showPicker = false;
    });
  }

  // ─── Sharing / posting ──────────────────────────────────────────────────

  /// Show the friend picker sheet and share to selected friends
  Future<void> _shareWithFriends() async {
    final hasPhoto = _selectedPhoto != null && _selectedPhoto!.existsSync();
    final hasVideo = _selectedVideo != null && _selectedVideo!.existsSync();

    if (!hasPhoto && !hasVideo) {
      _showNoPhotoDialog();
      return;
    }

    final file = hasVideo ? _selectedVideo! : _selectedPhoto!;

    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _FriendPickerSheet(file: file, isVideo: hasVideo),
    );

    if (sent == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(hasVideo
              ? 'Video shared with selected friends!'
              : 'Shared with selected friends!'),
          backgroundColor: Colors.black87,
          duration: const Duration(seconds: 2),
        ),
      );

      if (hasVideo) setState(() => _selectedVideo = null);

      // Sharing already happened in the friend picker — this step is purely
      // optional, to attach the media to Daily Bubbles.
      await _maybeShowBubbleSelector(
        mediaFile: file,
        isVideo: hasVideo,
        onPost: () async {},
      );
    }
  }

  Future<void> _confirmPhoto() async {
    final hasPhoto = _selectedPhoto != null && _selectedPhoto!.existsSync();
    final hasVideo = _selectedVideo != null && _selectedVideo!.existsSync();

    if (!hasPhoto && !hasVideo) {
      _showNoPhotoDialog();
      return;
    }

    if (hasVideo) {
      await _maybeShowBubbleSelector(
        mediaFile: _selectedVideo!,
        isVideo: true,
        onPost: _doConfirmVideoPost,
      );
      return;
    }

    await _maybeShowBubbleSelector(
      mediaFile: _selectedPhoto!,
      onPost: _doConfirmPost,
    );
  }

  /// Shows the Daily Bubble select sheet if any bubbles exist (letting the
  /// user optionally attach this photo/video before [onPost] actually
  /// runs), or just runs [onPost] immediately if there are none — "post
  /// as intended".
  Future<void> _maybeShowBubbleSelector({
    required File mediaFile,
    bool isVideo = false,
    required Future<void> Function() onPost,
  }) async {
    if (YourDailyBubbleManager.bubbles.isEmpty) {
      await onPost();
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => YourDailyBubbleSelectSheet(
        mediaFile: mediaFile,
        isVideo: isVideo,
        onPost: onPost,
      ),
    );
  }

  Future<void> _doConfirmPost() async {
    print('========== CONFIRM PHOTO DEBUG (Daily Post) ==========');

    try {
      await DailyPhotoTracker.addPhoto(_selectedPhoto!);
      await DailyPhotoManager.setDailyPhoto(_selectedPhoto!);
      if (_dailyMusic != null) {
        await StoryMusic.remember(_selectedPhoto!, _dailyMusic!);
      }
      await FriendDailyService.uploadMyDailyPhoto(_selectedPhoto!,
          music: _dailyMusic);

      print('Photo saved and uploaded to friend stories');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Daily photo posted!'),
            backgroundColor: Colors.black87,
            duration: Duration(seconds: 2),
          ),
        );
      }

      setState(() {
        _todaysPhotos = DailyPhotoTracker.todaysPhotos;
        _currentPhotoIndex = _todaysPhotos.length - 1;
        _selectedPhoto = null;
        _dailyMusic = null;
        _composited = false;
      });

      print('Daily photo confirmed and saved successfully');
    } catch (e) {
      print('ERROR in _confirmPhoto: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving photo: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
    print('========== END CONFIRM PHOTO DEBUG ==========');
  }

  Future<void> _doConfirmVideoPost() async {
    print('========== CONFIRM VIDEO DEBUG (Daily Post) ==========');

    try {
      await DailyVideoTracker.addVideo(_selectedVideo!);
      if (_dailyMusic != null) {
        await StoryMusic.remember(_selectedVideo!, _dailyMusic!);
      }
      await FriendDailyService.uploadMyDailyVideo(_selectedVideo!,
          music: _dailyMusic);

      print('Video saved and uploaded to friend stories');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Daily video posted!'),
            backgroundColor: Colors.black87,
            duration: Duration(seconds: 2),
          ),
        );
      }

      setState(() {
        _selectedVideo = null;
        _dailyMusic = null;
        _composited = false;
      });

      print('Daily video confirmed and saved successfully');
    } catch (e) {
      print('ERROR in _doConfirmVideoPost: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving video: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
    print('========== END CONFIRM VIDEO DEBUG ==========');
  }

  void _showNoPhotoDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Your Daily Awaits!'),
        content: const Text(
            'Choose a photo or video from your library or take a new one to create Your Daily moment.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it!'),
          ),
        ],
      ),
    );
  }

  // ─── UI ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bool showPostActions = _isInNewPhotoMode && _hasSelectedMedia;
    final bool showAddAnother = !_isInNewPhotoMode;

    return Column(
      children: [
        // The song picked for this Daily plays while you look at it here.
        ClipMusicPlayer(
          track: _dailyMusic,
          active: _hasSelectedMedia && _isInNewPhotoMode && !_editorOpen,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
            child: Center(
              child: AspectRatio(
                aspectRatio: kStoryAspect,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: KeyedSubtree(
                          key: ValueKey(_viewKey),
                          child: _buildCard(),
                        ),
                      ),
                    ),
                    if (_currentPhotoIndex >= 0) _arrow(left: true),
                    if (_todaysPhotos.isNotEmpty &&
                        _currentPhotoIndex < _todaysPhotos.length - 1 &&
                        !_hasSelectedMedia)
                      _arrow(left: false),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (showPostActions) _buildPostActions(),
        if (showAddAnother) _buildAddAnother(),
        AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter,
          child: _showPicker
              ? UnifiedMediaPickerPanel(
            height: _pickerHeight,
            title: 'Choose media',
            singleSelect: true,
            showDraw: false,
            maxVideoDuration: const Duration(minutes: 2),
            onMediaSelected: _onLibraryPicked,
            onDrawTap: () {},
            onClose: () => setState(() => _showPicker = false),
          )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  String get _viewKey {
    if (_selectedVideo != null) return 'v_${_selectedVideo!.path}';
    if (_selectedPhoto != null) return 'p_${_selectedPhoto!.path}';
    if (_currentPhotoIndex >= 0) return 'posted_$_currentPhotoIndex';
    return 'empty';
  }

  Widget _arrow({required bool left}) {
    return Positioned(
      left: left ? 10 : null,
      right: left ? null : 10,
      top: 0,
      bottom: 0,
      child: Center(
        child: GestureDetector(
          onTap: () => _navigatePhotos(left ? -1 : 1),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
                color: Colors.black54, shape: BoxShape.circle),
            child: Icon(
              left ? Icons.arrow_back_ios_new : Icons.arrow_forward_ios,
              color: Colors.white,
              size: 18,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard() {
    if (_selectedVideo != null) {
      return _mediaCard(
        child: VideoClipPlayer(
          videoFile: _selectedVideo!,
          autoPlay: true,
          looping: true,
          fit: BoxFit.cover,
        ),
        onClose: _clearSelection,
        onEdit: _editSelected,
      );
    }
    if (_selectedPhoto != null) {
      return _mediaCard(
        child: _photo(_selectedPhoto!),
        onClose: _clearSelection,
        onEdit: _editSelected,
      );
    }
    final posted = _postedPhoto;
    if (posted != null) {
      return _mediaCard(
        child: _photo(posted),
        badge: 'Posted · ${_currentPhotoIndex + 1} of ${_todaysPhotos.length}',
      );
    }
    return _buildEmptyCard();
  }

  Widget _photo(File file) {
    if (!file.existsSync()) {
      return Container(
        color: Colors.grey[900],
        child: const Center(
          child: Icon(Icons.broken_image_outlined,
              color: Colors.white54, size: 44),
        ),
      );
    }
    // Looks the way it will when posted: blurred backdrop, photo on top.
    return StoryPhotoFrame(file: file);
  }

  Widget _mediaCard(
      {required Widget child,
        VoidCallback? onClose,
        VoidCallback? onEdit,
        String? badge}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          fit: StackFit.expand,
          children: [
            child,
            if (onClose != null)
              Positioned(
                top: 10,
                right: 10,
                child: GestureDetector(
                  onTap: onClose,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                        color: Colors.black54, shape: BoxShape.circle),
                    child: const Icon(Icons.close,
                        color: Colors.white, size: 18),
                  ),
                ),
              ),
            if (onEdit != null)
              Positioned(
                right: 12,
                bottom: 12,
                child: GestureDetector(
                  onTap: onEdit,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_fix_high_rounded,
                            color: Colors.white, size: 16),
                        SizedBox(width: 6),
                        Text('Edit',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ),
            if (badge != null)
              Positioned(
                left: 12,
                bottom: 12,
                child: Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(badge,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.grey[800]!, width: 1),
      ),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Icon(Icons.add_a_photo_outlined,
                    size: 28, color: Colors.grey[800]),
              ),
              const SizedBox(height: 16),
              const Text(
                'Your Daily',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87),
              ),
              const SizedBox(height: 6),
              Text(
                "Share a photo or video from today",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () {
                    setState(() => _showPicker = !_showPicker);
                  },
                  icon: const Icon(Icons.photo_library_outlined, size: 20),
                  label: const Text('Choose from library',
                      style:
                      TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyan,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: _openCamera,
                  icon: const Icon(Icons.camera_alt_outlined, size: 20),
                  label: const Text('Camera',
                      style:
                      TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black87,
                    side: BorderSide(color: Colors.grey[400]!),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPostActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 52,
              child: OutlinedButton(
                onPressed: _shareWithFriends,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.black87,
                  side: BorderSide(color: Colors.grey[800]!),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Share with Friends',
                    style:
                    TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _confirmPhoto,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyan,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Post to Daily',
                    style:
                    TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddAnother() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: OutlinedButton.icon(
          onPressed: _addAnotherDaily,
          icon: const Icon(Icons.add, size: 20),
          label: const Text('Add another',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.black87,
            side: BorderSide(color: Colors.grey[800]!),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ),
    );
  }
}