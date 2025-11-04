import 'package:flutter/material.dart';
import 'YourDaily.dart';
import 'AddClip.dart';
import 'AddDailies.dart';

// Add Post Widget
class AddWidget extends StatefulWidget {
  const AddWidget({Key? key}) : super(key: key);

  @override
  State<AddWidget> createState() => _AddWidgetState();
}

class _AddWidgetState extends State<AddWidget> {
  int _selectedTabIndex = 0; // Track selected tab

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Add Post',
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
          // Tab section with smooth animation
          Container(
            width: double.infinity,
            child: Column(
              children: [
                // Tab buttons
                Row(
                  children: [
                    // Daily tab
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedTabIndex = 0;
                          });
                          print('Daily tab tapped');
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'Daily',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: _selectedTabIndex == 0 ? Colors.black : Colors.grey,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Clip tab
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedTabIndex = 1;
                          });
                          print('Clip tab tapped');
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'Clip',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: _selectedTabIndex == 1 ? Colors.black : Colors.grey,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Your Daily tab
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedTabIndex = 2;
                          });
                          print('Your Daily tab tapped');
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'Your Daily',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: _selectedTabIndex == 2 ? Colors.black : Colors.grey,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                // Animated sliding indicator
                Container(
                  height: 2,
                  child: Stack(
                    children: [
                      // Background line (transparent)
                      Container(
                        width: double.infinity,
                        height: 2,
                        color: Colors.transparent,
                      ),
                      // Animated black line
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        left: MediaQuery.of(context).size.width * _selectedTabIndex / 3,
                        width: MediaQuery.of(context).size.width / 3,
                        child: Container(
                          height: 2,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Content area based on selected tab
          Expanded(
            child: _getTabContent(),
          ),
        ],
      ),
    );
  }

  Widget _getTabContent() {
    switch (_selectedTabIndex) {
      case 0:
      // Daily tab content
        return const AddDailiesWidget();
      case 1:
      // Clip tab content
        return const AddClipWidget();
      case 2:
      // Your Daily tab content - show photos
        return const YourDailyWidget();
      default:
        return Container(color: Colors.white);
    }
  }
}