import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'GroupAvatar.dart';
import 'UserProfileScreen.dart';

/// Whether the signed-in account is an admin (users/{uid}.isAdmin == true,
/// set by hand in the Firebase console).
class AdminAccess {
  static Future<bool> isAdmin() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    try {
      final d = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      return d.data()?['isAdmin'] == true;
    } catch (_) {
      return false;
    }
  }
}

/// Open reports, newest first. Each one: what was reported, why, a copy of
/// the text, and buttons to remove it, dismiss, or open the person.
class AdminReportsScreen extends StatelessWidget {
  const AdminReportsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance
        .collection('reports')
        .where('status', isEqualTo: 'open')
        .orderBy('createdAt', descending: true)
        .limit(100);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: const Text('Reports'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        surfaceTintColor: Colors.transparent,
        elevation: 0.5,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Error: ${snap.error}', textAlign: TextAlign.center),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: Colors.cyan));
          }
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return Center(
              child: Text('No open reports 🎉',
                  style: TextStyle(fontSize: 16, color: Colors.grey[600])),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            itemBuilder: (context, i) => _ReportCard(doc: docs[i]),
          );
        },
      ),
    );
  }
}

class _ReportCard extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _ReportCard({required this.doc});

  @override
  State<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends State<_ReportCard> {
  bool _busy = false;

  Map<String, dynamic> get d => widget.doc.data();

  // Posts, clips and comments are hidden (never deleted) when removed, so a
  // mistake can be undone and evidence is kept.
  static const _content = {'clip', 'daily', 'dailyMessage', 'comment'};

  bool get _isAppeal => (d['extra'] as Map?)?['appeal'] == true;

  /// [action]: dismissed | removed | restored (appeal granted) |
  /// upheld (appeal denied).
  Future<void> _resolve(String action) async {
    setState(() => _busy = true);
    try {
      final db = FirebaseFirestore.instance;
      final path = d['path'] as String?;
      final target = d['target'] as String? ?? '';
      final hasPath = path != null && path.isNotEmpty;
      final adminMod = {
        'by': 'admin',
        'at': FieldValue.serverTimestamp(),
      };

      if (hasPath && _content.contains(target)) {
        if (action == 'dismissed' || action == 'restored') {
          // Put it back (it may have been hidden by reports or the AI).
          await db.doc(path).set({
            'hidden': false,
            'limited': false,
            'moderation': {...adminMod, 'verdict': 'ok'},
          }, SetOptions(merge: true));
        } else if (action == 'removed') {
          await db.doc(path).set({
            'hidden': true,
            'removedByAdmin': true,
            'moderation': {...adminMod, 'verdict': 'remove'},
          }, SetOptions(merge: true));
        } else if (action == 'upheld') {
          await db.doc(path).set({
            'moderation': {...adminMod, 'verdict': 'remove'},
          }, SetOptions(merge: true));
        }
      } else if (hasPath && action == 'removed') {
        if (target == 'user') {
          // Accounts aren't deleted from here: mark them for follow-up.
          await db.doc(path).set({'flagged': true}, SetOptions(merge: true));
        } else {
          await db.doc(path).delete();
        }
      }

      // Appeal answered: the creator's notice says how it went (a restored
      // post doesn't count against them).
      final noticePath = (d['extra'] as Map?)?['noticePath'] as String?;
      if (_isAppeal && noticePath != null &&
          (action == 'restored' || action == 'upheld')) {
        await db.doc(noticePath).set({
          'appeal': action == 'restored' ? 'restored' : 'denied',
          'appealAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      // Close this report and any others about the same thing.
      final same = await db
          .collection('reports')
          .where('targetId', isEqualTo: d['targetId'])
          .where('status', isEqualTo: 'open')
          .get();
      final batch = db.batch();
      for (final r in same.docs) {
        batch.update(r.reference, {
          'status': action,
          'resolvedAt': FieldValue.serverTimestamp(),
          'resolvedBy': FirebaseAuth.instance.currentUser?.uid,
        });
      }
      await batch.commit();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final owner = d['ownerUid'] as String? ?? '';
    final when = (d['createdAt'] as Timestamp?)?.toDate();
    final preview = d['preview'] as String?;
    final note = (d['note'] as String?) ?? '';
    final target = d['target'] as String? ?? '?';
    final auto = d['reporterUid'] == 'system';
    final urgent = d['urgent'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: urgent ? Border.all(color: Colors.red, width: 2) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                    urgent
                        ? 'URGENT'
                        : _isAppeal
                        ? 'APPEAL · ${target.toUpperCase()}'
                        : target.toUpperCase(),
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.red)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    auto && !urgent && d['reason'] != 'repeat'
                        ? 'Flagged automatically'
                        : (d['reasonLabel'] as String? ?? d['reason'] ?? ''),
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              if (when != null)
                Text(
                  '${when.month}/${when.day} ${when.hour}:${when.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
            ],
          ),
          if (owner.isNotEmpty) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => UserProfileScreen.open(context, owner),
              child: Row(
                children: [
                  MemberAvatar(userId: owner, size: 28),
                  const SizedBox(width: 8),
                  Text('Open their profile',
                      style: TextStyle(
                          fontSize: 13.5,
                          color: Colors.cyan[800],
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
          if (preview != null && preview.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(preview, style: const TextStyle(fontSize: 14)),
            ),
          ],
          if (note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_isAppeal ? 'AI said: "$note"' : 'Reporter: "$note"',
                style: TextStyle(fontSize: 13, color: Colors.grey[700])),
          ],
          if (d['path'] != null) ...[
            const SizedBox(height: 6),
            SelectableText(d['path'] as String,
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ],
          const SizedBox(height: 12),
          if (_isAppeal)
          // The creator asked for a review of an AI removal.
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => _resolve('upheld'),
                    child: const Text('Keep removed'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _busy ? null : () => _resolve('restored'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      elevation: 0,
                    ),
                    child: const Text('Restore'),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => _resolve('dismissed'),
                    child: Text(auto ? 'It\'s fine' : 'Dismiss'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _busy ? null : () => _resolve('removed'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      elevation: 0,
                    ),
                    child: Text(target == 'user' ? 'Flag account' : 'Remove'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}