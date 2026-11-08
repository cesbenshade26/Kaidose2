import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// "Days lit": how many different days someone has shown up in Kaidose
/// (posted in a Daily, answered a Daily's prompt, or posted a clip). It only
/// ever goes up, and a day counts once no matter how much they post.
///
/// Read from userStats/{uid}, which only the server writes (see the
/// onDailyEntryLightsDay / onClipLightsDay Cloud Functions).
///
/// The sun glows when the person has lit today, and rests quietly when they
/// haven't. Used on the Profile tab and on other people's profiles.
class DaysLitStat extends StatelessWidget {
  final String userId;

  const DaysLitStat({Key? key, required this.userId}) : super(key: key);

  static String _todayKey() {
    final n = DateTime.now();
    final m = n.month.toString().padLeft(2, '0');
    final d = n.day.toString().padLeft(2, '0');
    return '${n.year}-$m-$d';
  }

  static String _withCommas(int n) {
    final s = n.toString();
    final out = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
      out.write(s[i]);
    }
    return out.toString();
  }

  @override
  Widget build(BuildContext context) {
    if (userId.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('userStats')
          .doc(userId)
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final days = (data?['daysLit'] as num?)?.toInt() ?? 0;
        final litToday = data?['lastLitDay'] == _todayKey();
        final started = days > 0;

        return Semantics(
          label: '$days ${days == 1 ? 'day' : 'days'} lit',
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 250),
            opacity: snap.hasData ? 1 : 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
              decoration: BoxDecoration(
                color: started
                    ? Colors.amber.withOpacity(0.12)
                    : Colors.grey.withOpacity(0.08),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: started
                      ? Colors.amber.withOpacity(0.4)
                      : Colors.grey.withOpacity(0.25),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: litToday
                          ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFFFD54F), Color(0xFFFF9800)],
                      )
                          : null,
                      color: litToday
                          ? null
                          : (started
                          ? Colors.amber.withOpacity(0.18)
                          : Colors.grey.withOpacity(0.15)),
                      boxShadow: litToday
                          ? [
                        BoxShadow(
                          color: Colors.orange.withOpacity(0.45),
                          blurRadius: 12,
                          spreadRadius: 1,
                        ),
                      ]
                          : const [],
                    ),
                    child: Icon(
                      started ? Icons.wb_sunny_rounded : Icons.wb_sunny_outlined,
                      size: 21,
                      color: litToday
                          ? Colors.white
                          : (started ? Colors.amber[800] : Colors.grey[500]),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _withCommas(days),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    days == 1 ? 'day lit' : 'days lit',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}