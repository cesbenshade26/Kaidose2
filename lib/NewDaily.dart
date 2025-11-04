import 'package:flutter/material.dart';

class NewDailyScreen extends StatefulWidget {
  const NewDailyScreen({Key? key}) : super(key: key);

  @override
  State<NewDailyScreen> createState() => _NewDailyScreenState();
}

class _NewDailyScreenState extends State<NewDailyScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  String _selectedPrivacy = 'Public';
  List<TextEditingController> _keywordControllers = [
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    for (var controller in _keywordControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addKeywordField() {
    setState(() {
      _keywordControllers.add(TextEditingController());
    });
  }

  void _goToNextScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const NewDailyNextScreen(),
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
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: const Text(
          'Create Daily',
          style: TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Daily Title
                    const Text(
                      'Daily Title',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _titleController,
                      decoration: InputDecoration(
                        hintText: 'Enter daily title...',
                        hintStyle: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 16,
                        ),
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Colors.cyan,
                            width: 2,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                      maxLength: 50,
                      buildCounter: (context, {required currentLength, required isFocused, maxLength}) {
                        return Text(
                          '$currentLength/$maxLength',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 24),

                    // Privacy Selection
                    const Text(
                      'Privacy',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Public checkbox
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedPrivacy = 'Public';
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _selectedPrivacy == 'Public' ? Colors.cyan : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _selectedPrivacy == 'Public'
                                  ? Icons.check_box
                                  : Icons.check_box_outline_blank,
                              color: _selectedPrivacy == 'Public' ? Colors.cyan : Colors.grey[400],
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Public',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Private checkbox
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedPrivacy = 'Private';
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _selectedPrivacy == 'Private' ? Colors.cyan : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _selectedPrivacy == 'Private'
                                  ? Icons.check_box
                                  : Icons.check_box_outline_blank,
                              color: _selectedPrivacy == 'Private' ? Colors.cyan : Colors.grey[400],
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Private',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Description
                    const Text(
                      'Add Description!',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _descriptionController,
                      decoration: InputDecoration(
                        hintText: 'Enter description...',
                        hintStyle: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 16,
                        ),
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Colors.cyan,
                            width: 2,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                      maxLines: 4,
                      maxLength: 200,
                      buildCounter: (context, {required currentLength, required isFocused, maxLength}) {
                        return Text(
                          '$currentLength/$maxLength',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 24),

                    // Keywords Section
                    const Text(
                      'Add some Keywords',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '(This will help us connect you with some users)',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Keywords container with scroll
                    Container(
                      height: _keywordControllers.length > 3 ? 200 : null,
                      decoration: _keywordControllers.length > 3
                          ? BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(12),
                      )
                          : null,
                      child: _keywordControllers.length > 3
                          ? Scrollbar(
                        thumbVisibility: true,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: _keywordControllers.length,
                          itemBuilder: (context, index) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _buildKeywordField(index),
                            );
                          },
                        ),
                      )
                          : Column(
                        children: List.generate(
                          _keywordControllers.length,
                              (index) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _buildKeywordField(index),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Add Another button
                    GestureDetector(
                      onTap: _addKeywordField,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.add,
                              size: 16,
                              color: Colors.grey[700],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Add another',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey[700],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),

          // Next button at bottom
          Container(
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
              onPressed: _goToNextScreen,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyan,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Next',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeywordField(int index) {
    return TextField(
      controller: _keywordControllers[index],
      decoration: InputDecoration(
        hintText: 'Keyword ${index + 1}',
        hintStyle: TextStyle(
          color: Colors.grey[400],
          fontSize: 14,
        ),
        filled: true,
        fillColor: Colors.grey[100],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(
            color: Colors.cyan,
            width: 2,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        isDense: true,
      ),
      style: const TextStyle(
        fontSize: 14,
        color: Colors.black87,
      ),
      maxLength: 20,
      buildCounter: (context, {required currentLength, required isFocused, maxLength}) {
        return const SizedBox.shrink(); // Hide counter for keyword fields
      },
    );
  }
}

// Next screen placeholder
class NewDailyNextScreen extends StatefulWidget {
  const NewDailyNextScreen({Key? key}) : super(key: key);

  @override
  State<NewDailyNextScreen> createState() => _NewDailyNextScreenState();
}

class _NewDailyNextScreenState extends State<NewDailyNextScreen> {
  List<dynamic> _friends = []; // Will be filled with FriendData later
  bool _isLoading = true;
  Set<String> _selectedFriendIds = {}; // Track selected friends

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    // TODO: Uncomment when UserFriends.dart is imported
    // await UserFriends.initializeFriends();
    // setState(() {
    //   _friends = UserFriends.friends;
    //   _isLoading = false;
    // });

    // For now, simulate loading with empty list
    await Future.delayed(const Duration(milliseconds: 500));
    setState(() {
      _friends = [];
      _isLoading = false;
    });
  }

  void _toggleFriendSelection(String friendId) {
    setState(() {
      if (_selectedFriendIds.contains(friendId)) {
        _selectedFriendIds.remove(friendId);
      } else {
        _selectedFriendIds.add(friendId);
      }
    });
  }

  bool _canProceed() {
    if (_friends.length < 3) {
      return true; // Can proceed with any selection if less than 3 friends
    } else {
      return _selectedFriendIds.length >= 2; // Must select at least 2 if 3+ friends
    }
  }

  void _handleNext() {
    if (!_canProceed()) {
      // Show error popup
      showDialog(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Selection Required',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: const Text(
            'Please select at least 2 friends to invite to your daily.',
            style: TextStyle(
              fontSize: 16,
              color: Colors.black87,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'OK',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.cyan,
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      // Proceed to next screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const NewDailyFinalScreen(),
        ),
      );
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
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Invite some Friends!',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                if (_friends.length >= 3) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Select at least 2 friends (${_selectedFriendIds.length} selected)',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Friends List
          Expanded(
            child: _isLoading
                ? const Center(
              child: CircularProgressIndicator(
                color: Colors.cyan,
              ),
            )
                : _friends.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.people_outline,
                    size: 80,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No Friends Yet',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      'Follow users to add them to your friends list',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _friends.length,
              itemBuilder: (context, index) {
                // TODO: Replace with actual friend data
                // final friend = _friends[index];
                final friendId = 'friend_$index'; // TODO: friend.userId
                final isSelected = _selectedFriendIds.contains(friendId);

                return GestureDetector(
                  onTap: () => _toggleFriendSelection(friendId),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.cyan.withOpacity(0.1) : Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? Colors.cyan : Colors.grey[300]!,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        // Checkbox
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.cyan : Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isSelected ? Colors.cyan : Colors.grey[400]!,
                              width: 2,
                            ),
                          ),
                          child: isSelected
                              ? const Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 16,
                          )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        // Profile picture placeholder
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.person,
                            color: Colors.grey[600],
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Username
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Friend ${index + 1}', // TODO: friend.username
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Mutual friend', // TODO: friend.isMutual ? 'Mutual friend' : 'Friend'
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Next button at bottom
          Container(
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
              onPressed: _handleNext,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyan,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Next',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Final screen placeholder
class NewDailyFinalScreen extends StatelessWidget {
  const NewDailyFinalScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black, size: 28),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: const Center(
        child: Text(
          'Final Screen',
          style: TextStyle(
            fontSize: 24,
            color: Colors.grey,
          ),
        ),
      ),
    );
  }
}