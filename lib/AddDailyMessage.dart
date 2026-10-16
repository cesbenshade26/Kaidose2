import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'DailyData.dart';
import 'DailyList.dart';
import 'DrawPad.dart';
import 'MessageStorage.dart';
import 'SendDailyMessage.dart';
import 'UnifiedMediaPicker.dart';
import 'user_service.dart';

/// Post one message to several of your Dailies at once: a text box with a
/// media button beside it, a checklist of your Dailies, and Send.
///
/// Built to live inside the Add sheet (see AddSheet.dart), which supplies
/// [onBack]/[onClose] for its header; with neither given there is no
/// header, so it can also be dropped straight into a tab.
///
/// The media picker is the same panel the Daily chat uses. It opens between
/// the text box and the checklist, so the sheet simply grows taller.
class AddDailyMessage extends StatefulWidget {
  /// Shows a back arrow in the header (e.g. back to the Add menu).
  final VoidCallback? onBack;

  /// Shows an X in the header that closes the whole sheet.
  final VoidCallback? onClose;

  /// Called after a successful send. When null the form just clears.
  final VoidCallback? onSent;

  const AddDailyMessage({Key? key, this.onBack, this.onClose, this.onSent})
      : super(key: key);

  @override
  State<AddDailyMessage> createState() => _AddDailyMessageState();
}

class _AddDailyMessageState extends State<AddDailyMessage> {
  static const double _pickerHeight = 300;

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final UserService _userService = UserService();

  List<PickedMedia> _media = [];
  final Set<String> _selectedIds = {};
  bool _showPicker = false;
  bool _sending = false;
  VoidCallback? _dailyListListener;
  StreamSubscription<List<DailyData>>? _dailiesSub;
  // Same source the Dailies tab uses; DailyList.dailies alone can still be
  // empty when this opens.
  List<DailyData> _all = [];
  bool _loadingDailies = true;

  /// Pinned Dailies first, then the rest in their usual order.
  List<DailyData> get _dailies {
    final all = _all;
    return [
      ...all.where((d) => d.isPinned),
      ...all.where((d) => !d.isPinned),
    ];
  }

  bool get _hasContent =>
      _controller.text.trim().isNotEmpty || _media.isNotEmpty;

  bool get _canSend => !_sending && _hasContent && _selectedIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
    _dailyListListener = () {
      if (mounted) setState(() {});
    };
    DailyList.addListener(_dailyListListener!);

    _all = List.of(DailyList.dailies);
    _loadingDailies = _all.isEmpty;
    _dailiesSub = DailyList.getDailiesStream().listen((list) {
      if (!mounted) return;
      setState(() {
        _all = list;
        _loadingDailies = false;
      });
    }, onError: (_) {
      if (mounted) setState(() => _loadingDailies = false);
    });
  }

  @override
  void dispose() {
    _dailiesSub?.cancel();
    if (_dailyListListener != null) {
      DailyList.removeListener(_dailyListListener!);
    }
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ─── Media ────────────────────────────────────────────────────────────────

  void _togglePicker() {
    if (_showPicker) {
      setState(() => _showPicker = false);
    } else {
      // Keyboard and picker share the same space, so drop the keyboard.
      _focusNode.unfocus();
      setState(() => _showPicker = true);
    }
  }

  void _handleMediaPicked(List<PickedMedia> items) {
    setState(() {
      _media = [..._media, ...items];
      _showPicker = false;
    });
  }

  Future<void> _openDrawPad() async {
    final File? drawingFile = await Navigator.push<File>(
      context,
      MaterialPageRoute(
        builder: (context) => DrawingScreen(
          onDrawingComplete: (file) {
            Navigator.pop(context, file);
          },
        ),
      ),
    );

    if (drawingFile != null && mounted) {
      setState(() {
        _media = [..._media, PickedMedia(file: drawingFile, isVideo: false)];
        _showPicker = false;
      });
    }
  }

  // ─── Send ─────────────────────────────────────────────────────────────────

  Future<void> _send() async {
    if (!_canSend) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final currentUid =
          FirebaseAuth.instance.currentUser?.uid ?? 'current_user';
      final user = await _userService.getUserById(currentUid);
      final username = user?.username ?? 'You';
      final text = _controller.text.trim();

      final targets =
      _dailies.where((d) => _selectedIds.contains(d.id)).toList();

      // One separate message per Daily (each needs its own id and dailyId).
      for (final daily in targets) {
        final message = DailyMessage(
          text: text.isNotEmpty ? text : null,
          media: _media
              .map((p) => DailyMediaItem(path: p.file.path, isVideo: p.isVideo))
              .toList(),
          timestamp: DateTime.now(),
          dailyId: daily.id,
          userId: currentUid,
          username: username,
        );
        await MessageStorage.saveMessages(daily.id, [message]);
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text(targets.length == 1
              ? 'Sent to ${targets.first.title}'
              : 'Sent to ${targets.length} Dailies'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );

      if (widget.onSent != null) {
        widget.onSent!();
      } else if (mounted) {
        setState(() {
          _controller.clear();
          _media = [];
          _selectedIds.clear();
          _showPicker = false;
        });
      }
    } catch (e) {
      print('AddDailyMessage: send error: $e');
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not send: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ─── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.onBack != null || widget.onClose != null) _buildHeader(),
        _buildComposeRow(),
        _buildPendingStrip(),
        // The picker opens here, between the text box and the checklist.
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: _showPicker
              ? Padding(
            padding: const EdgeInsets.only(top: 10),
            child: SizedBox(
              height: _pickerHeight,
              child: UnifiedMediaPickerPanel(
                height: _pickerHeight,
                onMediaSelected: _handleMediaPicked,
                onDrawTap: _openDrawPad,
                onClose: () => setState(() => _showPicker = false),
              ),
            ),
          )
              : const SizedBox(width: double.infinity),
        ),
        _buildListLabel(),
        Flexible(child: _buildDailiesList()),
        _buildSendButton(),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
      child: Row(
        children: [
          if (widget.onBack != null)
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.black87),
              onPressed: widget.onBack,
            )
          else
            const SizedBox(width: 16),
          const Expanded(
            child: Text(
              'Daily Message',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
          ),
          if (widget.onClose != null)
            IconButton(
              icon: const Icon(Icons.close, color: Colors.black87),
              onPressed: widget.onClose,
            ),
        ],
      ),
    );
  }

  Widget _buildComposeRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(22),
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(fontSize: 16, color: Colors.black87),
                decoration: InputDecoration(
                  hintText: 'Write a message...',
                  hintStyle: TextStyle(color: Colors.grey[500], fontSize: 16),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 12),
                ),
                onTap: () {
                  if (_showPicker) setState(() => _showPicker = false);
                },
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _togglePicker,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: _showPicker
                    ? Colors.cyan.withOpacity(0.15)
                    : Colors.grey[100],
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.perm_media,
                size: 22,
                color: _showPicker ? Colors.cyan : Colors.grey[700],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingStrip() {
    if (_media.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 76,
      margin: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _media.length,
        itemBuilder: (context, index) {
          final item = _media[index];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 76,
                    height: 76,
                    child: item.isVideo
                        ? Container(
                      color: Colors.grey[800],
                      child: const Center(
                        child: Icon(Icons.play_circle_fill,
                            color: Colors.white, size: 26),
                      ),
                    )
                        : Image.file(
                      item.file,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          Container(
                            color: Colors.grey[200],
                            child: Icon(Icons.broken_image,
                                color: Colors.grey[400]),
                          ),
                    ),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: GestureDetector(
                    onTap: () => setState(() => _media.removeAt(index)),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close,
                          color: Colors.white, size: 14),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildListLabel() {
    final dailies = _dailies;
    final allSelected =
        dailies.isNotEmpty && _selectedIds.length == dailies.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _selectedIds.isEmpty
                  ? 'Send to'
                  : 'Send to · ${_selectedIds.length} selected',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.grey[600],
                letterSpacing: 0.3,
              ),
            ),
          ),
          if (dailies.length > 1)
            TextButton(
              onPressed: () => setState(() {
                if (allSelected) {
                  _selectedIds.clear();
                } else {
                  _selectedIds
                    ..clear()
                    ..addAll(dailies.map((d) => d.id));
                }
              }),
              style: TextButton.styleFrom(
                foregroundColor: Colors.cyan,
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(allSelected ? 'Clear' : 'Select all',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }

  Widget _buildDailiesList() {
    final dailies = _dailies;

    if (dailies.isEmpty && _loadingDailies) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator(color: Colors.cyan)),
      );
    }

    if (dailies.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Text(
          'You are not in any Dailies yet. Create or join one to post to it.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      itemCount: dailies.length,
      itemBuilder: (context, index) {
        final daily = dailies[index];
        final selected = _selectedIds.contains(daily.id);
        final color = Color(daily.iconColor ?? 0xFF00BCD4);

        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() {
            selected
                ? _selectedIds.remove(daily.id)
                : _selectedIds.add(daily.id);
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: daily.customIconPath != null &&
                      File(daily.customIconPath!).existsSync()
                      ? ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(File(daily.customIconPath!),
                        fit: BoxFit.cover),
                  )
                      : Icon(daily.icon, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    daily.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),
                Checkbox(
                  value: selected,
                  activeColor: Colors.cyan,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(5)),
                  onChanged: (_) => setState(() {
                    selected
                        ? _selectedIds.remove(daily.id)
                        : _selectedIds.add(daily.id);
                  }),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSendButton() {
    final count = _selectedIds.length;
    final label = count == 0
        ? 'Send'
        : (count == 1 ? 'Send to 1 Daily' : 'Send to $count Dailies');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: SizedBox(
        height: 52,
        child: ElevatedButton(
          onPressed: _canSend ? _send : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.cyan,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.cyan.withOpacity(0.35),
            disabledForegroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
          ),
          child: _sending
              ? const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
                color: Colors.white, strokeWidth: 2.5),
          )
              : Text(label,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}