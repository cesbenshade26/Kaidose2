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

  Future<void> _resolve(String action) async {
    setState(() => _busy = true);
    try {
      final db = FirebaseFirestore.instance;
      final path = d['path'] as String?;
      final target = d['target'] as String? ?? '';
      // Dismissing a clip puts it back if it was hidden automatically.
      if (action == 'dismissed' &&
          (target == 'clip' || target == 'daily') &&
          path != null &&
          path.isNotEmpty) {
        await db.doc(path).set({'hidden': false}, SetOptions(merge: true));
      }
      if (action == 'removed' && path != null && path.isNotEmpty) {
        if (target == 'user') {
          // Accounts aren't deleted from here: mark them for follow-up.
          await db.doc(path).set({'flagged': true}, SetOptions(merge: true));
        } else if (target == 'clip' || target == 'daily') {
          // Hidden (not deleted) so it can be restored if it was a mistake.
          await db.doc(path).set({'hidden': true, 'removedByAdmin': true},
              SetOptions(merge: true));
        } else {
          await db.doc(path).delete();
        }
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

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
                child: Text(target.toUpperCase(),
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.red)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    auto
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
            Text('Reporter: "$note"',
                style: TextStyle(fontSize: 13, color: Colors.grey[700])),
          ],
          if (d['path'] != null) ...[
            const SizedBox(height: 6),
            SelectableText(d['path'] as String,
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _resolve('dismissed'),
                  child: const Text('Dismiss'),
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