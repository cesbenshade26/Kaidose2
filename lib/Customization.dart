import 'package:flutter/material.dart';
import 'ProfilePic.dart'; // Import the ProfilePic screen
import 'BackgroundPic.dart'; // Import the BackgroundPic screen
import 'Bio.dart'; // Import the Bio screen

// Customization Screen
class CustomizationScreen extends StatelessWidget {
  const CustomizationScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customization'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                'Profile Customization',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Profile Picture Option
            ListTile(
              leading: const Icon(
                Icons.account_circle,
                color: Colors.grey,
                size: 28,
              ),
              title: const Text(
                'Profile Picture',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              trailing: const Icon(
                Icons.chevron_right,
                color: Colors.grey,
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ProfilePicScreen(),
                  ),
                );
              },
            ),
            const Divider(
              color: Colors.grey,
              thickness: 0.5,
            ),

            // Bio Option - Updated to navigate to BioScreen
            ListTile(
              leading: const Icon(
                Icons.edit_note,
                color: Colors.grey,
                size: 28,
              ),
              title: const Text(
                'Bio',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              trailing: const Icon(
                Icons.chevron_right,
                color: Colors.grey,
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const BioScreen(),
                  ),
                );
              },
            ),
            const Divider(
              color: Colors.grey,
              thickness: 0.5,
            ),

            // Background Picture Option
            ListTile(
              leading: const Icon(
                Icons.wallpaper,
                color: Colors.grey,
                size: 28,
              ),
              title: const Text(
                'Background Picture',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              trailing: const Icon(
                Icons.chevron_right,
                color: Colors.grey,
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const BackgroundPicScreen(),
                  ),
                );
              },
            ),
            const Divider(
              color: Colors.grey,
              thickness: 0.5,
            ),

            // Username Option
            ListTile(
              leading: const Icon(
                Icons.person,
                color: Colors.grey,
                size: 28,
              ),
              title: const Text(
                'Username',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              trailing: const Icon(
                Icons.chevron_right,
                color: Colors.grey,
              ),
              onTap: () {
                // TODO: Implement username editing functionality
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Username editing coming soon!'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
            const Divider(
              color: Colors.grey,
              thickness: 0.5,
            ),
          ],
        ),
      ),
    );
  }
}