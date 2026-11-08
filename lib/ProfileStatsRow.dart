import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'RankBadge.dart';

/// The row under the avatar on Profile and on other people's profiles:
///
///   [days lit counter]   username   [rank icon + name]
///
/// Days lit and rank both come from userStats/{uid}, which only the server
/// writes (see the days-lit Cloud Functions). The sun glows when the person
/// has lit today.
class ProfileStatsRow extends StatelessWidget {
  final String userId;
  final String username;

  /// Shows the "N to next rank" line under the rank name. On for your own
  /// profile, off when viewing someone else's.
  final bool showProgress;

  const ProfileStatsRow({
    Key? key,
    required this.userId,
    required this.username,
    this.showProgress = true,
  }) : super(key: key);

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

  Widget _name() {
    if (username.isEmpty) return const SizedBox(height: 27);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 150),
      child: Text(
        username,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
      ),
    );
  }

  Widget _counter(int days, bool litToday) {
    final started = days > 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 32,
          height: 32,
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
                blurRadius: 10,
                spreadRadius: 1,
              ),
            ]
                : const [],
          ),
          child: Icon(
            started ? Icons.wb_sunny_rounded : Icons.wb_sunny_outlined,
            size: 20,
            color: litToday
                ? Colors.white
                : (started ? Colors.amber[800] : Colors.grey[500]),
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _withCommas(days),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.black,
                height: 1.1,
              ),
            ),
            Text(
              days == 1 ? 'day lit' : 'days lit',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Colors.grey[600],
                height: 1.1,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _rank(int days) {
    final rank = KaidoseRank.forDays(days);
    final next = rank.next;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        RankBadge(rank: rank, size: 40),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              rank.name,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: rank.accent,
                height: 1.1,
              ),
            ),
            if (showProgress)
              Text(
                next == null
                    ? 'Top rank'
                    : '${_withCommas(next.minDays - days)} to ${next.name}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[600],
                  height: 1.1,
                ),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (userId.isEmpty) return Center(child: _name());

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('userStats')
          .doc(userId)
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final days = (data?['daysLit'] as num?)?.toInt() ?? 0;
        final litToday = data?['lastLitDay'] == _todayKey();
        final opacity = snap.hasData ? 1.0 : 0.0;
        final rank = KaidoseRank.forDays(days);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 250),
                  opacity: opacity,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Semantics(
                      label: '$days ${days == 1 ? 'day' : 'days'} lit',
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _counter(days, litToday),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _name(),
              const SizedBox(width: 12),
              Expanded(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 250),
                  opacity: opacity,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Semantics(
                      label: 'Rank ${rank.name}',
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: _rank(days),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}