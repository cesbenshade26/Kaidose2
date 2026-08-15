import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'DailyData.dart';
import 'DailyList.dart';
import 'daily_invitation_service.dart';
import 'user_service.dart';
import 'ManageDaily.dart';
import 'friend_request_service.dart';
import 'FeedService.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NewDailyScreen extends StatefulWidget {
  const NewDailyScreen({Key? key}) : super(key: key);

  @override
  State<NewDailyScreen> createState() => _NewDailyScreenState();
}

class _NewDailyScreenState extends State<NewDailyScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _promptController = TextEditingController();
  String _selectedPrivacy = 'Public';
  final List<TextEditingController> _tierControllers = [
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
  ];
  final Set<String> _selectedTags = {};

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _promptController.dispose();
    for (var controller in _tierControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addTierField() {
    setState(() {
      _tierControllers.add(TextEditingController());
    });
  }

  void _goToNextScreen() {
    final List<String> keywords = _selectedTags.toList();
    final List<String> tiers = _tierControllers
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NewDailyNextScreen(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          privacy: _selectedPrivacy,
          keywords: keywords,
          tiers: tiers,
          dailyEntryPrompt: _promptController.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Create Daily',
          style: TextStyle(
              color: Colors.black, fontSize: 18, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  _sectionLabel('Daily Title'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _titleController,
                    maxLength: 50,
                    style: const TextStyle(fontSize: 16, color: Colors.black87),
                    decoration: _inputDeco('Enter daily title...'),
                    buildCounter: (context,
                        {required currentLength,
                          required isFocused,
                          maxLength}) =>
                        Text('$currentLength/$maxLength',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600])),
                  ),
                  const SizedBox(height: 24),

                  // Prompt
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _sectionLabel('Daily Entry Prompt:'),
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border:
                          Border.all(color: Colors.grey[400]!, width: 2),
                        ),
                        child: Center(
                          child: Icon(Icons.info_outline,
                              size: 16, color: Colors.grey[600]),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _promptController,
                    maxLength: 100,
                    style: const TextStyle(fontSize: 16, color: Colors.black87),
                    decoration:
                    _inputDeco('Enter a prompt for daily entries...'),
                    buildCounter: (context,
                        {required currentLength,
                          required isFocused,
                          maxLength}) =>
                        Text('$currentLength/$maxLength',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600])),
                  ),
                  const SizedBox(height: 24),

                  // Privacy
                  _sectionLabel('Privacy'),
                  const SizedBox(height: 12),
                  _privacyOption('Public'),
                  const SizedBox(height: 12),
                  _privacyOption('Private'),
                  const SizedBox(height: 24),

                  // Description
                  _sectionLabel('Add Description!'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _descriptionController,
                    maxLines: 4,
                    maxLength: 200,
                    style: const TextStyle(fontSize: 16, color: Colors.black87),
                    decoration: _inputDeco('Enter description...'),
                    buildCounter: (context,
                        {required currentLength,
                          required isFocused,
                          maxLength}) =>
                        Text('$currentLength/$maxLength',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600])),
                  ),
                  const SizedBox(height: 24),

                  // Tags
                  _sectionLabel('Tags'),
                  const SizedBox(height: 4),
                  Text(
                    'Pick topics that fit your Daily — helps connect you with the right people.',
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 12),
                  DailyTagPicker(
                    selected: _selectedTags,
                    onToggle: (label) => setState(() {
                      _selectedTags.contains(label)
                          ? _selectedTags.remove(label)
                          : _selectedTags.add(label);
                    }),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
          _bottomButton('Next', _goToNextScreen),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: Colors.black87),
  );

  InputDecoration _inputDeco(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: Colors.grey[400], fontSize: 16),
    filled: true,
    fillColor: Colors.grey[100],
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none),
    focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.cyan, width: 2)),
    contentPadding:
    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  );

  Widget _privacyOption(String value) {
    final selected = _selectedPrivacy == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedPrivacy = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? Colors.cyan : Colors.transparent, width: 2),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_box : Icons.check_box_outline_blank,
              color: selected ? Colors.cyan : Colors.grey[400],
              size: 24,
            ),
            const SizedBox(width: 12),
            Text(value,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87)),
          ],
        ),
      ),
    );
  }
}

// ─── Next screen: friend picker (no invitations sent yet) ────────────────────

class NewDailyNextScreen extends StatefulWidget {
  final String title;
  final String description;
  final String privacy;
  final List<String> keywords;
  final List<String> tiers;
  final String dailyEntryPrompt;

  const NewDailyNextScreen({
    Key? key,
    required this.title,
    required this.description,
    required this.privacy,
    required this.keywords,
    required this.tiers,
    required this.dailyEntryPrompt,
  }) : super(key: key);

  @override
  State<NewDailyNextScreen> createState() => _NewDailyNextScreenState();
}

class _NewDailyNextScreenState extends State<NewDailyNextScreen> {
  Set<String> _invitedFriendIds = {};

  void _handleNext() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NewDailyFinalScreen(
          title: widget.title,
          description: widget.description,
          privacy: widget.privacy,
          keywords: widget.keywords,
          tiers: widget.tiers,
          selectedFriendIds: _invitedFriendIds.toList(),
          dailyEntryPrompt: widget.dailyEntryPrompt,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Invite Friends',
          style: TextStyle(
              color: Colors.black, fontSize: 18, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: _FriendPickerForDaily(
              onSelectionChanged: (ids) =>
                  setState(() => _invitedFriendIds = ids),
            ),
          ),
          _bottomButton('Next', _handleNext),
        ],
      ),
    );
  }
}

// ─── Friend picker — just selects, does NOT send invitations yet ─────────────

class _FriendPickerForDaily extends StatefulWidget {
  final Function(Set<String>) onSelectionChanged;

  const _FriendPickerForDaily({required this.onSelectionChanged});

  @override
  State<_FriendPickerForDaily> createState() => _FriendPickerForDailyState();
}

class _FriendPickerForDailyState extends State<_FriendPickerForDaily> {
  final FriendRequestService _friendRequestService = FriendRequestService();
  final Set<String> _selectedIds = {};

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FriendRequest>>(
      stream: _friendRequestService.getAcceptedFriends(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Colors.cyan));
        }

        final friends = snapshot.data ?? [];
        final currentUid = _friendRequestService.currentUserId;

        if (friends.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people_outline, size: 80, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text('No Friends Yet',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700])),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    'Add friends to invite them to your daily',
                    style:
                    TextStyle(fontSize: 14, color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          itemCount: friends.length,
          itemBuilder: (context, index) {
            final f = friends[index];
            final friendId = f.fromUserId == currentUid
                ? f.toUserId
                : f.fromUserId;
            final friendName = f.fromUserId == currentUid
                ? f.toUsername
                : f.fromUsername;
            final isSelected = _selectedIds.contains(friendId);

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.cyan.withOpacity(0.05)
                    : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? Colors.cyan : Colors.grey[300]!,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.cyan.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        friendName.isNotEmpty
                            ? friendName[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.cyan[700]),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(friendName,
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87)),
                        const SizedBox(height: 2),
                        Text('Friends on Kaidose',
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey[600])),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          _selectedIds.remove(friendId);
                        } else {
                          _selectedIds.add(friendId);
                        }
                      });
                      widget.onSelectionChanged(
                          Set<String>.from(_selectedIds));
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.orange : Colors.cyan,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        isSelected ? 'Remove' : 'Invite',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ─── Final screen: icon picker + publish ─────────────────────────────────────

class NewDailyFinalScreen extends StatefulWidget {
  final String title;
  final String description;
  final String privacy;
  final List<String> keywords;
  final List<String> tiers;
  final List<String> selectedFriendIds;
  final String dailyEntryPrompt;

  const NewDailyFinalScreen({
    Key? key,
    required this.title,
    required this.description,
    required this.privacy,
    required this.keywords,
    required this.tiers,
    required this.selectedFriendIds,
    required this.dailyEntryPrompt,
  }) : super(key: key);

  @override
  State<NewDailyFinalScreen> createState() => _NewDailyFinalScreenState();
}

class _NewDailyFinalScreenState extends State<NewDailyFinalScreen> {
  IconData _selectedIcon = Icons.star;
  File? _customIcon;
  Color _selectedColor = Colors.cyan;
  bool _publishing = false;
  final ImagePicker _picker = ImagePicker();

  final List<IconData> _presetIcons = [
    Icons.star, Icons.favorite, Icons.camera_alt, Icons.music_note,
    Icons.sports_basketball, Icons.restaurant, Icons.local_cafe,
    Icons.airplane_ticket, Icons.beach_access, Icons.fitness_center,
    Icons.book, Icons.palette, Icons.code, Icons.science,
    Icons.pets, Icons.games,
  ];

  final List<Color> _colorOptions = [
    Colors.cyan, Colors.blue, Colors.purple, Colors.pink,
    Colors.red, Colors.orange, Colors.amber, Colors.green,
    Colors.teal, Colors.indigo,
  ];

  Future<void> _pickCustomIcon() async {
    final XFile? image =
    await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) setState(() => _customIcon = File(image.path));
  }

  Future<void> _publishDaily() async {
    if (_publishing) return;
    setState(() => _publishing = true);

    final dailyId = DateTime.now().millisecondsSinceEpoch.toString();

    final daily = DailyData(
      id: dailyId,
      title: widget.title,
      description: widget.description,
      privacy: widget.privacy,
      keywords: widget.keywords,
      managementTiers: widget.tiers,
      icon: _selectedIcon,
      iconColor: _selectedColor.value,
      customIconPath: _customIcon?.path,
      invitedFriendIds: widget.selectedFriendIds,
      createdAt: DateTime.now(),
      dailyEntryPrompt: widget.dailyEntryPrompt,
    );

    // Save daily first so it gets a real doc in Firestore
    await DailyList.addDaily(daily);

    // Mirror into public_dailies (with creatorUid set) so the
    // discover feed can find it
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final dailyWithCreator = DailyData(
      id: daily.id,
      title: daily.title,
      description: daily.description,
      privacy: daily.privacy,
      keywords: daily.keywords,
      managementTiers: daily.managementTiers,
      icon: daily.icon,
      iconColor: daily.iconColor,
      customIconPath: daily.customIconPath,
      invitedFriendIds: daily.invitedFriendIds,
      foundingMemberIds: daily.foundingMemberIds,
      createdAt: daily.createdAt,
      isPinned: daily.isPinned,
      tierAssignments: daily.tierAssignments,
      tierPrivileges: daily.tierPrivileges,
      dailyEntryPrompt: daily.dailyEntryPrompt,
      titleFont: daily.titleFont,
      creatorUid: uid,
    );
    await FeedService.publishToPublicFeed(dailyWithCreator);

    // Now send invitations with the real daily ID
    if (widget.selectedFriendIds.isNotEmpty) {
      final invitationService = DailyInvitationService();
      final userService = UserService();

      final currentUser = await userService
          .getUserById(invitationService.currentUserId ?? '');
      final currentUsername = currentUser?.username ?? 'Someone';

      for (final friendUserId in widget.selectedFriendIds) {
        final friendUser = await userService.getUserById(friendUserId);
        if (friendUser != null) {
          await invitationService.sendDailyInvitation(
            dailyId: dailyId,
            dailyTitle: widget.title,
            toUserId: friendUserId,
            toUsername: friendUser.username,
            fromUsername: currentUsername,
          );
        }
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Daily published successfully!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Choose Icon',
          style: TextStyle(
              color: Colors.black, fontSize: 18, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Select an Icon',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87)),
                  const SizedBox(height: 16),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: _presetIcons.length,
                    itemBuilder: (context, index) {
                      final icon = _presetIcons[index];
                      final isSelected =
                          _selectedIcon == icon && _customIcon == null;
                      return GestureDetector(
                        onTap: () => setState(() {
                          _selectedIcon = icon;
                          _customIcon = null;
                        }),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isSelected
                                ? _selectedColor.withOpacity(0.1)
                                : Colors.grey[100],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? _selectedColor
                                  : Colors.grey[300]!,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Icon(icon,
                              color: isSelected
                                  ? _selectedColor
                                  : Colors.grey[700],
                              size: 32),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  const Text('Icon Color',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87)),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: _colorOptions.map((color) {
                      final isSelected = _selectedColor == color;
                      return GestureDetector(
                        onTap: () =>
                            setState(() => _selectedColor = color),
                        child: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected
                                  ? Colors.black
                                  : Colors.grey[300]!,
                              width: isSelected ? 3 : 1,
                            ),
                          ),
                          child: isSelected
                              ? const Icon(Icons.check,
                              color: Colors.white, size: 24)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  const Text('Or Upload Custom Icon',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87)),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: _pickCustomIcon,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: _customIcon != null
                            ? Colors.cyan.withOpacity(0.1)
                            : Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _customIcon != null
                              ? Colors.cyan
                              : Colors.grey[300]!,
                          width: _customIcon != null ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          if (_customIcon != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(_customIcon!,
                                  width: 80,
                                  height: 80,
                                  fit: BoxFit.cover),
                            )
                          else
                            Icon(Icons.cloud_upload_outlined,
                                size: 48, color: Colors.grey[600]),
                          const SizedBox(height: 8),
                          Text(
                            _customIcon != null
                                ? 'Custom icon selected'
                                : 'Upload Icon',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey[700]),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _bottomButton(
            _publishing ? 'Publishing...' : 'Publish Daily',
            _publishing ? null : _publishDaily,
          ),
        ],
      ),
    );
  }
}

// ─── Shared helpers ───────────────────────────────────────────────────────────

Widget _bottomButton(String label, VoidCallback? onPressed) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      boxShadow: [
        BoxShadow(
          color: Colors.grey.withOpacity(0.2),
          spreadRadius: 1,
          blurRadius: 4,
          offset: const Offset(0, -2),
        ),
      ],
    ),
    child: ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.cyan,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.cyan.withOpacity(0.6),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
      ),
      child: Text(label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
    ),
  );
}