// HomeScreen.dart
import 'package:flutter/material.dart';
import 'Profile.dart'; // Import the Profile.dart file

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: _getSelectedPage(),
      ),
      bottomNavigationBar: Container(
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
        child: Row(
          children: [
            _buildNavItem(0, Icons.wb_sunny, 'Sun'),
            _buildNavItem(1, Icons.chat_bubble_outline, 'Chat'),
            _buildNavItem(2, Icons.videocam_outlined, 'Camera'),
            _buildNavItem(3, Icons.add, 'Add'),
            _buildNavItem(4, Icons.person_outline, 'Profile'),
          ],
        ),
      ),
    );
  }

  Widget _getSelectedPage() {
    switch (_selectedIndex) {
      case 0:
        return _buildSunPage();
      case 1:
        return _buildChatPage();
      case 2:
        return _buildCameraPage();
      case 3:
        return _buildAddPage();
      case 4:
        return const ProfilePage(); // Use the actual ProfilePage widget
      default:
        return _buildSunPage();
    }
  }

  Widget _buildSunPage() {
    return const Text(
      'Sun Page',
      style: TextStyle(
        fontFamily: 'Slackey',
        fontSize: 48,
        color: Colors.black,
      ),
    );
  }

  Widget _buildChatPage() {
    return const Text(
      'Chat Page',
      style: TextStyle(
        fontFamily: 'Slackey',
        fontSize: 48,
        color: Colors.black,
      ),
    );
  }

  Widget _buildCameraPage() {
    return const Text(
      'Camera Page',
      style: TextStyle(
        fontFamily: 'Slackey',
        fontSize: 48,
        color: Colors.black,
      ),
    );
  }

  Widget _buildAddPage() {
    return const Text(
      'Add Page',
      style: TextStyle(
        fontFamily: 'Slackey',
        fontSize: 48,
        color: Colors.black,
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _selectedIndex == index;

    return Expanded(
      child: GestureDetector(
        onTap: () => _onItemTapped(index),
        child: SizedBox(
          height: 80,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Oval highlight background
              if (isSelected)
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
              // Icon
              Icon(
                icon,
                size: 26,
                color: isSelected ? Colors.white : Colors.black,
              ),
            ],
          ),
        ),
      ),
    );
  }
}