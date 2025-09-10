import 'package:flutter/material.dart';
import 'Search.dart'; // Import the Search screen
import 'DailyPhotoManager.dart'; // Import the DailyPhotoManager
import 'dart:io';

// Dailies Widget
class DailiesWidget extends StatefulWidget {
  const DailiesWidget({Key? key}) : super(key: key);

  @override
  State<DailiesWidget> createState() => _DailiesWidgetState();
}

class _DailiesWidgetState extends State<DailiesWidget> with WidgetsBindingObserver {
  File? _dailyPhoto;
  bool _isLoading = true;
  VoidCallback? _dailyPhotoListener;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Get any existing daily photo immediately
    _dailyPhoto = DailyPhotoManager.globalDailyPhoto;

    // Load from storage
    _loadFromStorage();

    // Create listener for daily photo changes
    _dailyPhotoListener = () {
      print('DailiesWidget: Daily photo changed!');
      if (mounted) {
        setState(() {
          _dailyPhoto = DailyPhotoManager.globalDailyPhoto;
          _isLoading = false;
        });
      }
    };

    // Add the listener
    DailyPhotoManager.addListener(_dailyPhotoListener!);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_dailyPhotoListener != null) {
      DailyPhotoManager.removeListener(_dailyPhotoListener!);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadDailyPhoto();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Always refresh photo when this widget becomes visible
    _loadDailyPhoto();
  }

  Future<void> _loadFromStorage() async {
    await DailyPhotoManager.loadDailyPhotoFromStorage();
    if (mounted) {
      setState(() {
        _dailyPhoto = DailyPhotoManager.globalDailyPhoto;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadDailyPhoto() async {
    print('Loading daily photo...');
    try {
      final photo = await DailyPhotoManager.getDailyPhoto();
      if (mounted) {
        setState(() {
          _dailyPhoto = photo;
          _isLoading = false;
        });
      }
      print('Daily photo loaded: ${photo?.path ?? "No photo found"}');
    } catch (e) {
      print('Error loading daily photo: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: IconButton(
              icon: const Icon(Icons.search, color: Colors.black, size: 28),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SearchScreen(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      body: Container(
        color: Colors.white,
        width: double.infinity,
        height: double.infinity,
        child: _isLoading
            ? const Center(
          child: CircularProgressIndicator(
            color: Colors.blue,
          ),
        )
            : _dailyPhoto != null && _dailyPhoto!.existsSync()
            ? Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              // Title
              const Text(
                'Your Daily',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 20),

              // Photo display
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey[300]!, width: 1),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.file(
                      _dailyPhoto!,
                      fit: BoxFit.cover,
                      key: ValueKey(_dailyPhoto!.path + _dailyPhoto!.lastModifiedSync().toString()),
                      errorBuilder: (context, error, stackTrace) {
                        print('Error displaying daily photo: $error');
                        return Container(
                          color: Colors.grey[200],
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  size: 48,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Error loading photo',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        )
            : Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.photo_size_select_actual_outlined,
                size: 64,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                'No Daily Photo Yet',
                style: TextStyle(
                  fontSize: 20,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Go to the Add tab to capture your daily moment!',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[500],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}