import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'UserManager.dart';

// Username Edit Screen
class EditUsernameScreen extends StatefulWidget {
  const EditUsernameScreen({Key? key}) : super(key: key);

  @override
  State<EditUsernameScreen> createState() => _EditUsernameScreenState();
}

class _EditUsernameScreenState extends State<EditUsernameScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUsernameData();
  }

  // Load current username from UserManager
  Future<void> _loadUsernameData() async {
    // Ensure username is loaded from storage first
    await UserManager.loadUsernameFromStorage();

    // Then update the UI with the loaded data
    setState(() {
      _controller.text = UserManager.globalUsername ?? '';
      _isLoading = false;
    });

    print('Username loaded in EditUsernameScreen: "${_controller.text}"');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showConfirmDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Confirm Username'),
        content: Text('Your username will be changed to "${_controller.text}"'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              print('Confirm pressed - saving username: "${_controller.text}"');

              try {
                // Save the username to SharedPreferences
                await _saveUsername(_controller.text);

                // Update UserManager
                await UserManager.loadUsernameFromStorage();

                // Close dialog first
                Navigator.of(dialogContext).pop();

                // Show success message
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Username Updated!'),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 1),
                    ),
                  );

                  // Wait a brief moment for the snackbar to show, then navigate back
                  await Future.delayed(const Duration(milliseconds: 800));

                  // Navigate back to customization screen
                  Navigator.of(context).pop();
                }
              } catch (e) {
                print('Error saving username: $e');
                // Close dialog even if there's an error
                Navigator.of(dialogContext).pop();

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Error saving username'),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              }
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  // Save username to SharedPreferences
  Future<void> _saveUsername(String username) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('kaidose_user', username);
    print('Username saved to storage: $username');
  }

  @override
  Widget build(BuildContext context) {
    // Show loading indicator while data is being loaded
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Edit Username'),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Username'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Current Username:',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),

            // Username text field
            TextField(
              controller: _controller,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
              decoration: const InputDecoration(
                hintText: 'Enter your username...',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.all(16),
              ),
            ),

            const SizedBox(height: 24),

            // Save button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  if (_controller.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Username cannot be empty'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                  _showConfirmDialog();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Save Username', style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}