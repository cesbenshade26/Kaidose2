import 'package:flutter/material.dart';
import 'Customization.dart';
import 'SecurityInfo.dart';
import 'auth_service.dart';

// Settings Screen
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: const Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProfileSettingsSection(),
          ],
        ),
      ),
    );
  }
}

// Profile Settings Section
class ProfileSettingsSection extends StatelessWidget {
  const ProfileSettingsSection({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            'Account Settings',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Customization Option
        ListTile(
          leading: const Icon(
            Icons.palette,
            color: Colors.grey,
            size: 28,
          ),
          title: const Text(
            'Customization',
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
                builder: (context) => const CustomizationScreen(),
              ),
            );
          },
        ),
        const Divider(
          color: Colors.grey,
          thickness: 0.5,
        ),
        // Security Info Option
        ListTile(
          leading: const Icon(
            Icons.security,
            color: Colors.grey,
            size: 28,
          ),
          title: const Text(
            'Security Info',
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
                builder: (context) => const SecurityInfoScreen(),
              ),
            );
          },
        ),
        const Divider(
          color: Colors.grey,
          thickness: 0.5,
        ),
        // Logout Option
        ListTile(
          leading: const Icon(
            Icons.logout,
            color: Colors.red,
            size: 28,
          ),
          title: const Text(
            'Logout',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.red,
            ),
          ),
          trailing: const Icon(
            Icons.chevron_right,
            color: Colors.red,
          ),
          onTap: () async {
            // Show confirmation dialog
            final shouldLogout = await showDialog<bool>(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: const Text('Logout'),
                  content: const Text('Are you sure you want to logout?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                      child: const Text('Logout'),
                    ),
                  ],
                );
              },
            );

            if (shouldLogout == true && context.mounted) {
              // Logout from Firebase
              await AuthService().logout();

              // Navigate to opening screen and remove all previous routes
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/opening',
                    (route) => false,
              );
            }
          },
        ),
        const Divider(
          color: Colors.grey,
          thickness: 0.5,
        ),
      ],
    );
  }
}