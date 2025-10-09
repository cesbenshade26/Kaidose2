import 'package:flutter/material.dart';
import 'YourDailyArchives.dart'; // Import the YourDailyArchives screen

class ArchivesScreen extends StatelessWidget {
  const ArchivesScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Archives'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: const Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ArchivesSection(),
          ],
        ),
      ),
    );
  }
}

class ArchivesSection extends StatelessWidget {
  const ArchivesSection({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            'View Your Past Content',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Your Daily Posts Option
        ListTile(
          leading: const Icon(
            Icons.photo_camera,
            color: Colors.blue,
            size: 28,
          ),
          title: const Text(
            'Your Daily Posts',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: const Text(
            'View all your daily photos by date',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
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
                builder: (context) => const YourDailyArchivesScreen(),
              ),
            );
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