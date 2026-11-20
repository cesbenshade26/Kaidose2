import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'AppColors.dart';
import 'RankBadge.dart';
import 'SettingsWidgets.dart';

/// userStats/{uid}.daysLit, live (written only by the server).
Stream<int> _daysLit(String uid) => FirebaseFirestore.instance
    .collection('userStats')
    .doc(uid)
    .snapshots()
    .map((s) => (s.data()?['daysLit'] as num?)?.toInt() ?? 0);

String _days(int n) => n == 1 ? '1 day' : '$n days';

/// The row in Settings → Account: your rank's badge, its name and your days
/// lit. Opens [RankProgressScreen].
class RankTile extends StatelessWidget {
  const RankTile({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();
    return StreamBuilder<int>(
      stream: _daysLit(uid),
      builder: (context, snap) {
        final days = snap.data ?? 0;
        final rank = KaidoseRank.forDays(days);
        return InkWell(
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const RankProgressScreen())),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                RankBadge(rank: rank, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Your rank',
                      style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w500,
                          color: SettingsStyle.ink)),
                ),
                if (snap.hasData)
                  Text('${rank.name} · ${_days(days)} lit',
                      style: TextStyle(
                          fontSize: 14.5, color: SettingsStyle.subtle)),
                Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(Icons.chevron_right_rounded,
                      size: 22, color: kc.adapt(const Color(0xFFC4C7CC))),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Settings → Account → Your rank: where you are and every milestone, as a
/// meter that fills as your days lit grow, with each rank's badge and what
/// it takes to reach it.
class RankProgressScreen extends StatelessWidget {
  const RankProgressScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      backgroundColor: SettingsStyle.page,
      appBar: AppBar(
        title: Text('Your rank',
            style: TextStyle(
                color: SettingsStyle.ink,
                fontSize: 18,
                fontWeight: FontWeight.w700)),
        centerTitle: true,
        backgroundColor: SettingsStyle.page,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: SettingsStyle.ink),
      ),
      body: StreamBuilder<int>(
        stream: uid.isEmpty ? Stream.value(0) : _daysLit(uid),
        builder: (context, snap) {
          if (!snap.hasData) {
            return Center(
                child: CircularProgressIndicator(color: kc.adapt(const Color(0xFFB0B5BC))));
          }
          final days = snap.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              _CurrentCard(days: days),
              const SizedBox(height: 18),
              Padding(
                padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text('Milestones',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: SettingsStyle.subtle)),
              ),
              _Ladder(days: days),
              Padding(
                padding: EdgeInsets.fromLTRB(6, 10, 6, 0),
                child: Text(
                  'A day lights up when you post in a Daily, answer a Daily\'s '
                      'prompt or post a clip. Each day counts once, and days '
                      'lit never go down.',
                  style: TextStyle(
                      fontSize: 12.5, height: 1.35, color: SettingsStyle.subtle),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Your badge, rank, days lit and a bar to the next rank.
class _CurrentCard extends StatelessWidget {
  final int days;
  const _CurrentCard({required this.days});

  @override
  Widget build(BuildContext context) {
    final rank = KaidoseRank.forDays(days);
    final next = rank.next;
    final span = next == null ? 1 : next.minDays - rank.minDays;
    final into = next == null ? 1 : days - rank.minDays;
    final fraction = (into / span).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        color: kc.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          RankBadge(rank: rank, size: 92),
          const SizedBox(height: 12),
          Text(rank.name,
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: rank.accent)),
          const SizedBox(height: 2),
          Text('${_days(days)} lit',
              style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                  color: SettingsStyle.subtle)),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(
              children: [
                Container(height: 10, color: kc.adapt(const Color(0xFFEDEEF1))),
                FractionallySizedBox(
                  widthFactor: fraction,
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        rank.accent.withOpacity(0.65),
                        (next ?? rank).accent,
                      ]),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(rank.name,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: SettingsStyle.subtle)),
              const Spacer(),
              Text(
                next == null
                    ? 'Top rank reached'
                    : '${_days(next.minDays - days)} to ${next.name}',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: SettingsStyle.ink),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Every rank top to bottom, joined by a meter that fills to where you are.
class _Ladder extends StatelessWidget {
  final int days;
  const _Ladder({required this.days});

  static const double _rail = 64; // width of the badge column

  @override
  Widget build(BuildContext context) {
    final ranks = KaidoseRank.all;
    final current = KaidoseRank.forDays(days);
    final rows = <Widget>[];
    for (var i = 0; i < ranks.length; i++) {
      rows.add(_node(ranks[i], current));
      if (i < ranks.length - 1) rows.add(_link(ranks[i], ranks[i + 1]));
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: kc.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: rows),
    );
  }

  Widget _node(KaidoseRank r, KaidoseRank current) {
    final reached = days >= r.minDays;
    final isCurrent = r.index == current.index;
    Widget badge = RankBadge(rank: r, size: 46);
    if (!reached) {
      // Locked: grey and faded until you get there.
      badge = Opacity(
        opacity: 0.4,
        child: ColorFiltered(
          colorFilter: const ColorFilter.matrix(<double>[
            0.2126, 0.7152, 0.0722, 0, 0,
            0.2126, 0.7152, 0.0722, 0, 0,
            0.2126, 0.7152, 0.0722, 0, 0,
            0, 0, 0, 1, 0,
          ]),
          child: badge,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          SizedBox(width: _rail, child: Center(child: badge)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.name,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: reached ? r.accent : kc.adapt(const Color(0xFFA5AAB2)))),
                const SizedBox(height: 1),
                Text(
                    r.minDays == 0
                        ? 'Where everyone starts'
                        : '${_days(r.minDays)} lit',
                    style: TextStyle(
                        fontSize: 13, color: SettingsStyle.subtle)),
              ],
            ),
          ),
          if (isCurrent)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: r.accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('You',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: r.accent)),
            )
          else if (reached)
            const Icon(Icons.check_circle_rounded,
                size: 20, color: Color(0xFF2FA36B))
          else
            Text('${_days(r.minDays - days)} to go',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: SettingsStyle.subtle)),
        ],
      ),
    );
  }

  /// The piece of meter between two ranks, filled as far as you've got.
  Widget _link(KaidoseRank from, KaidoseRank to) {
    final span = to.minDays - from.minDays;
    final fill = ((days - from.minDays) / span).clamp(0.0, 1.0);
    final here = fill > 0 && fill < 1;
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          const SizedBox(width: 12),
          SizedBox(
            width: _rail,
            child: Center(
              child: SizedBox(
                width: 6,
                child: LayoutBuilder(
                  builder: (context, box) => Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.topCenter,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: kc.adapt(const Color(0xFFEDEEF1)),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      Container(
                        height: box.maxHeight * fill,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [from.accent, to.accent],
                          ),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      // You are here.
                      if (here)
                        Positioned(
                          top: box.maxHeight * fill - 6,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: kc.surface,
                              shape: BoxShape.circle,
                              border: Border.all(color: to.accent, width: 3),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${to.minDays - from.minDays} more days',
              style: TextStyle(fontSize: 11.5, color: kc.adapt(const Color(0xFFB0B4BA))),
            ),
          ),
        ],
      ),
    );
  }
}