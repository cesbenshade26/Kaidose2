import 'package:flutter/material.dart';
import 'DailyList.dart';
import 'DailyData.dart';
import 'DailyPostDetailsScreen.dart';

/// Lists every Daily the current user is on that's marked Public, shown as
/// a card matching each Daily's own color/icon (same accent used on the
/// Dailies screen) — name, color, and icon only, nothing else.
///
/// Wired directly to DailyList's live stream via StreamBuilder rather than
/// a one-shot fetch, so it can't race with itself and always reflects the
/// current state of the user's dailies.
class DailyPostActivity extends StatelessWidget {
  const DailyPostActivity({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DailyData>>(
      stream: DailyList.getDailiesStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.cyan),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error loading dailies: ${snapshot.error}',
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          );
        }

        final publicDailies = (snapshot.data ?? [])
            .where((d) => d.privacy == 'Public')
            .toList();

        if (publicDailies.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.public, size: 80, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No Public Dailies Yet',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Public Dailies you\'re on will appear here',
                  style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: publicDailies.length,
          itemBuilder: (context, index) {
            final daily = publicDailies[index];
            return GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => DailyPostDetailScreen(daily: daily),
                  ),
                );
              },
              child: _DailyCard(daily: daily),
            );
          },
        );
      },
    );
  }
}

class _DailyCard extends StatelessWidget {
  final DailyData daily;

  const _DailyCard({required this.daily});

  @override
  Widget build(BuildContext context) {
    final Color color = Color(daily.iconColor ?? 0xFF9E9E9E);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color, width: 2),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(daily.icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              daily.title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}