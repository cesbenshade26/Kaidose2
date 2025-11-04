// Home.dart
import 'package:flutter/material.dart';
import 'Profile.dart'; // Import the Profile.dart file
import 'Dailies.dart'; // Import the Dailies.dart file
import 'Add.dart'; // Import the Add.dart file
import 'Clips.dart';
import 'Chat.dart';

class HomeScreen extends StatefulWidget {
  final bool fadeInFromAnimation; // New parameter to control fade-in
  final int? initialTabIndex; // Add parameter for initial tab selection

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

  late AnimationController _contentFadeController;
  late Animation<double> _contentFadeAnimation;

  late AnimationController _navBarSlideController;
  late Animation<Offset> _navBarSlideAnimation;

  late AnimationController _staggerController;
  late List<Animation<double>> _staggeredAnimations;

  @override
  void initState() {
    super.initState();

    // Use initialTabIndex if provided, otherwise use default logic
    if (widget.initialTabIndex != null) {
      _selectedIndex = widget.initialTabIndex!;
    } else {
      // Always start on Dailies (index 0) when coming from animation, otherwise Profile (index 4)
      _selectedIndex = widget.fadeInFromAnimation ? 0 : 4;
    }

    // Initialize content fade controller
    _contentFadeController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _contentFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _contentFadeController, curve: Curves.easeInOut),
    );

    // Initialize navigation bar slide controller
    _navBarSlideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _navBarSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 1), // Start from bottom
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _navBarSlideController, curve: Curves.easeOut));

    // Initialize staggered animation controller for nav items
    _staggerController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    // Create staggered animations for each nav item
    _staggeredAnimations = List.generate(5, (index) {
      final begin = index * 0.1; // 100ms delay between items
      final end = begin + 0.4; // 400ms duration for each item
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _staggerController,
          curve: Interval(begin, end.clamp(0.0, 1.0), curve: Curves.easeOut),
        ),
      );
    });

    // Start animations if coming from Kaidose animation
    if (widget.fadeInFromAnimation) {
      _startEntryAnimations();
    } else {
      // Normal appearance - set all animations to complete
      _contentFadeController.value = 1.0;
      _navBarSlideController.value = 1.0;
      _staggerController.value = 1.0;
    }
  }

  void _startEntryAnimations() async {
    // Start content fade first
    _contentFadeController.forward();

    // Start nav bar slide after a short delay
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) {
      _navBarSlideController.forward();
    }

    // Start staggered nav item animations
    await Future.delayed(const Duration(milliseconds: 200));
    if (mounted) {
      _staggerController.forward();
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
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
      body: AnimatedBuilder(
        animation: _contentFadeAnimation,
        builder: (context, child) {
          return FadeTransition(
            opacity: _contentFadeAnimation,
            child: _getSelectedPage(),
          );
        },
      ),
      bottomNavigationBar: SlideTransition(
        position: _navBarSlideAnimation,
        child: Container(
          height: 80,
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.3),
                spreadRadius: 1,
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: AnimatedBuilder(
            animation: _staggerController,
            builder: (context, child) {
              return Row(
                children: [
                  _buildNavItem(0, Icons.wb_sunny, 'Sun', _staggeredAnimations[0]),
                  _buildNavItem(1, Icons.chat_bubble_outline, 'Chat', _staggeredAnimations[1]),
                  _buildNavItem(2, Icons.videocam_outlined, 'Camera', _staggeredAnimations[2]),
                  _buildNavItem(3, Icons.add, 'Add', _staggeredAnimations[3]),
                  _buildNavItem(4, Icons.person_outline, 'Profile', _staggeredAnimations[4]),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _getSelectedPage() {
    switch (_selectedIndex) {
      case 0:
        return DailiesWidget(
          onNavigateToTab: (index) {
            _onItemTapped(index);
          },
        );
      case 1:
        return const ChatWidget();
      case 2:
        return const ClipsWidget();
      case 3:
        return const AddWidget();
      case 4:
        return const ProfilePage();
      default:
        return DailiesWidget(
          onNavigateToTab: (index) {
            _onItemTapped(index);
          },
        );
    }
  }

  Widget _buildNavItem(int index, IconData icon, String label, Animation<double> animation) {
    final isSelected = _selectedIndex == index;

    return Expanded(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          return Transform.scale(
            scale: 0.8 + (0.2 * animation.value), // Scale from 0.8 to 1.0
            child: Opacity(
              opacity: animation.value,
              child: GestureDetector(
                onTap: () => _onItemTapped(index),
                child: SizedBox(
                  height: 80,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Oval highlight background with smooth transition
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: isSelected ? 50 : 0,
                        height: isSelected ? 50 : 0,
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.black : Colors.transparent,
                          borderRadius: BorderRadius.circular(25),
                        ),
                      ),
                      // Icon with smooth color transition
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          icon,
                          key: ValueKey('${icon}_${isSelected}'),
                          size: 26,
                          color: isSelected ? Colors.white : Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}