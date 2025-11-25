import 'package:flutter/material.dart';
import 'FriendsSearch.dart';
import 'DailySearch.dart';

// Search Screen
class SearchScreen extends StatefulWidget {
  const SearchScreen({Key? key}) : super(key: key);

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  int _selectedTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {}); // Rebuild when search text changes
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Search bar at top
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
              color: Colors.grey[100],
              child: Row(
                children: [
                  // Back arrow
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.black, size: 24),
                    onPressed: () {
                      Navigator.pop(context);
                    },
                  ),
                  // Search icon
                  const Icon(
                    Icons.search,
                    color: Colors.grey,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  // Search text field
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Search',
                        hintStyle: TextStyle(
                          color: Colors.grey,
                          fontSize: 16,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  // Clear button (shows when there's text)
                  if (_searchController.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                      onPressed: () {
                        _searchController.clear();
                      },
                    ),
                ],
              ),
            ),

            // Tab section
            Container(
              width: double.infinity,
              child: Column(
                children: [
                  // Tab buttons
                  Row(
                    children: [
                      // Friends tab
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedTabIndex = 0;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.people,
                                  size: 20,
                                  color: _selectedTabIndex == 0 ? Colors.black : Colors.grey,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Friends',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: _selectedTabIndex == 0 ? Colors.black : Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Dailies tab
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedTabIndex = 1;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              'Dailies',
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
                      // Empty tab 2
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedTabIndex = 2;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              'Tab 3',
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
                        Container(
                          width: double.infinity,
                          height: 2,
                          color: Colors.transparent,
                        ),
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
      ),
    );
  }

  Widget _getTabContent() {
    switch (_selectedTabIndex) {
      case 0:
      // Friends tab - show contacts from FriendsSearch
        return const FriendsSearchWidget();
      case 1:
      // Dailies tab - show DailySearch widget
        return DailySearchWidget(searchQuery: _searchController.text);
      case 2:
      // Empty tab 2
        return Container(
          color: Colors.white,
          child: const Center(
            child: Text(
              'Tab 3 Content',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey,
              ),
            ),
          ),
        );
      default:
        return Container(color: Colors.white);
    }
  }
}