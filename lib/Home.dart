// Home.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'Profile.dart';
import 'Dailies.dart';
import 'Add.dart';
import 'Clips.dart';
import 'Chat.dart';
import 'HomeSwipe.dart';

class HomeScreen extends StatefulWidget {
  final bool fadeInFromAnimation;
  final int? initialTabIndex;

  const HomeScreen({
    Key? key,
    this.fadeInFromAnimation = false,
    this.initialTabIndex,
  }) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late int _selectedIndex;
  int _previousIndex = 0;

  late AnimationController _contentFadeController;
  late Animation<double> _contentFadeAnimation;
  late AnimationController _navBarSlideController;
  late Animation<Offset> _navBarSlideAnimation;
  late AnimationController _staggerController;
  late List<Animation<double>> _staggeredAnimations;

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();

    final String currentUid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';

    if (widget.initialTabIndex != null) {
      _selectedIndex = widget.initialTabIndex!;
    } else {
      // Landing on Profile (4) because we disabled the InterestDetector redirect
      _selectedIndex = widget.fadeInFromAnimation ? 0 : 4;
    }

    _previousIndex = _selectedIndex;

    _pages = [
      DailiesWidget(
        key: const PageStorageKey('dailies'),
        onNavigateToTab: (idx) => _onItemTapped(idx),
      ),
      const ChatWidget(key: PageStorageKey('chat')),
      const ClipsWidget(key: PageStorageKey('clips')),
      const AddWidget(key: PageStorageKey('add')),
      ProfilePage(key: ValueKey('profile_$currentUid')),
    ];

    _contentFadeController = AnimationController(duration: const Duration(milliseconds: 1200), vsync: this);
    _contentFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _contentFadeController, curve: Curves.easeInOut),
    );

    _navBarSlideController = AnimationController(duration: const Duration(milliseconds: 800), vsync: this);
    _navBarSlideAnimation = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(
      CurvedAnimation(parent: _navBarSlideController, curve: Curves.easeOut),
    );

    _staggerController = AnimationController(duration: const Duration(milliseconds: 1000), vsync: this);
    _staggeredAnimations = List.generate(5, (index) {
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _staggerController, curve: Interval(index * 0.1, (index * 0.1 + 0.4).clamp(0.0, 1.0), curve: Curves.easeOut)),
      );
    });

    if (widget.fadeInFromAnimation) {
      _startEntryAnimations();
    } else {
      _contentFadeController.value = 1.0;
      _navBarSlideController.value = 1.0;
      _staggerController.value = 1.0;
    }
  }

  void _startEntryAnimations() async {
    _contentFadeController.forward();
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) _navBarSlideController.forward();
    await Future.delayed(const Duration(milliseconds: 200));
    if (mounted) _staggerController.forward();
  }

  void _onItemTapped(int index) {
    if (index != _selectedIndex) {
      setState(() {
        _previousIndex = _selectedIndex;
        _selectedIndex = index;
      });
    }
  }

  @override
  void dispose() {
    _contentFadeController.dispose();
    _navBarSlideController.dispose();
    _staggerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: FadeTransition(
        opacity: _contentFadeAnimation,
        child: HomeSwipeDetector(
          currentIndex: _selectedIndex,
          totalPages: 5,
          edgeThreshold: 80.0,
          pages: _pages,
          onPageChanged: (newIndex) => _onItemTapped(newIndex),
        ),
      ),
      bottomNavigationBar: SlideTransition(
        position: _navBarSlideAnimation,
        child: Container(
          height: 80,
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.3), spreadRadius: 1, blurRadius: 8, offset: const Offset(0, -2))],
          ),
          child: Row(
            children: [
              _buildNavItem(0, Icons.wb_sunny, 'Sun', _staggeredAnimations[0]),
              _buildNavItem(1, Icons.chat_bubble_outline, 'Chat', _staggeredAnimations[1]),
              _buildNavItem(2, Icons.videocam_outlined, 'Camera', _staggeredAnimations[2]),
              _buildNavItem(3, Icons.add, 'Add', _staggeredAnimations[3]),
              _buildNavItem(4, Icons.person_outline, 'Profile', _staggeredAnimations[4]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label, Animation<double> animation) {
    final isSelected = _selectedIndex == index;
    return Expanded(
      child: FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: animation,
          child: GestureDetector(
            onTap: () => _onItemTapped(index),
            child: SizedBox(
              height: 80,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: isSelected ? 50 : 0,
                    height: isSelected ? 50 : 0,
                    decoration: BoxDecoration(color: isSelected ? Colors.black : Colors.transparent, borderRadius: BorderRadius.circular(25)),
                  ),
                  Icon(icon, size: 26, color: isSelected ? Colors.white : Colors.black),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}