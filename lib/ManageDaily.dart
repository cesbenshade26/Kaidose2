import 'package:flutter/material.dart';
import 'DailyData.dart';
import 'dart:io';

class ManageDailyScreen extends StatelessWidget {
  final DailyData daily;

  const ManageDailyScreen({Key? key, required this.daily}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black, size: 28),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: const Text(
          'Manage Daily',
          style: TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
            Center(
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Color(daily.iconColor ?? 0xFF00BCD4).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: daily.customIconPath != null && File(daily.customIconPath!).existsSync()
                    ? ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.file(
                    File(daily.customIconPath!),
                    fit: BoxFit.cover,
                  ),
                )
                    : Icon(
                  daily.icon,
                  color: Color(daily.iconColor ?? 0xFF00BCD4),
                  size: 50,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Title
            Text(
              'Title',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              daily.title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 20),

            // Description
            Text(
              'Description',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              daily.description.isEmpty ? 'No description' : daily.description,
              style: TextStyle(
                fontSize: 16,
                color: daily.description.isEmpty ? Colors.grey[500] : Colors.black87,
              ),
            ),
            const SizedBox(height: 20),

            // Privacy
            Text(
              'Privacy',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: daily.privacy == 'Public' ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: daily.privacy == 'Public' ? Colors.green : Colors.orange,
                ),
              ),
              child: Text(
                daily.privacy,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: daily.privacy == 'Public' ? Colors.green[700] : Colors.orange[700],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Keywords
            Text(
              'Keywords',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: daily.keywords.isEmpty
                  ? [
                Text(
                  'No keywords',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[500],
                  ),
                )
              ]
                  : daily.keywords.map((keyword) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.cyan.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.cyan),
                  ),
                  child: Text(
                    keyword,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.cyan,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Management Tiers
            Text(
              'Management Tiers',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            daily.managementTiers.isEmpty
                ? Text(
              'No management tiers',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[500],
              ),
            )
                : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: daily.managementTiers.asMap().entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Colors.cyan,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '${entry.key + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          entry.value,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Created Date
            Text(
              'Created',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _formatDateTime(daily.createdAt),
              style: const TextStyle(
                fontSize: 16,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 20),

            // Invited Friends
            Text(
              'Invited Friends',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              daily.invitedFriendIds.isEmpty
                  ? 'No friends invited'
                  : '${daily.invitedFriendIds.length} friends invited',
              style: TextStyle(
                fontSize: 16,
                color: daily.invitedFriendIds.isEmpty ? Colors.grey[500] : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime date) {
    return '${date.day}/${date.month}/${date.year} at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}