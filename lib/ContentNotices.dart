import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'NotificationService.dart';

/// Tells you when one of your posts, clips or comments was removed for
/// breaking the rules, and lets you ask for a human to look at it.
///
/// The server writes users/{uid}/notices/{id} when it removes something
/// (see "Content moderation" in index.js). This listens for unseen ones and
/// shows them one at a time, wherever you are in the app. Start it once
/// after sign-in ([start], called from Home).
class ContentNotices {
  ContentNotices._();

  static StreamSubscription<User?>? _auth;
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  static String? _uid;
  static bool _showing = false;
  static final Set<String> _shown = {};

  static void start() {
    _auth ??= FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user?.uid == _uid) return;
      _uid = user?.uid;
      _sub?.cancel();
      _sub = null;
      _shown.clear();
      if (user == null) return;
      _sub = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('notices')
          .where('seen', isEqualTo: false)
          .limit(10)
          .snapshots()
          .listen(_onNotices, onError: (e) => print('ContentNotices: $e'));
    });
  }

  static void _onNotices(QuerySnapshot<Map<String, dynamic>> snap) {
    if (_showing) return;
    final pending = snap.docs.where((d) => !_shown.contains(d.id)).toList()
      ..sort((a, b) {
        final ta = a.data()['createdAt'] as Timestamp?;
        final tb = b.data()['createdAt'] as Timestamp?;
        return (ta?.millisecondsSinceEpoch ?? 0)
            .compareTo(tb?.millisecondsSinceEpoch ?? 0);
      });
    if (pending.isEmpty) return;
    final context = NotificationService.navigatorKey.currentContext;
    if (context == null) return;
    final doc = pending.first;
    _shown.add(doc.id);
    _showing = true;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NoticeSheet(doc: doc),
    ).whenComplete(() async {
      _showing = false;
      try {
        await doc.reference.update({'seen': true});
      } catch (_) {}
    });
  }
}

class _NoticeSheet extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _NoticeSheet({required this.doc});

  @override
  State<_NoticeSheet> createState() => _NoticeSheetState();
}

class _NoticeSheetState extends State<_NoticeSheet> {
  bool _sending = false;
  bool _requested = false;

  Map<String, dynamic> get n => widget.doc.data();

  static const Map<String, String> _rules = {
    'nudity': 'No nudity or sexual content',
    'minor_sexual': 'No sexual content involving anyone under 18',
    'gore': 'No graphic violence or gore',
    'hate': 'No slurs or hate speech',
    'self_harm': 'No promoting self-harm',
    'weapons_drugs': 'No selling drugs or real weapons',
    'threat': 'No threats against real people',
  };

  String get _what {
    switch (n['target']) {
      case 'clip':
        return 'clip';
      case 'comment':
        return 'comment';
      default:
        return 'post';
    }
  }

  bool get _canAppeal =>
      n['appeal'] == null && n['category'] != 'minor_sexual' && !_requested;

  /// Sends it to an admin to look at. If they agree it was a mistake, it
  /// comes back and doesn't count against you.
  Future<void> _requestReview() async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) return;
    setState(() => _sending = true);
    try {
      await FirebaseFirestore.instance.collection('reports').add({
        'reporterUid': me,
        'target': n['target'] ?? 'dailyMessage',
        'targetId': n['targetId'] ?? '',
        'ownerUid': me,
        'reason': 'appeal',
        'reasonLabel': 'Review requested: removed for ${n['category'] ?? 'rules'}',
        if (n['path'] != null) 'path': n['path'],
        if ((n['preview'] as String?)?.isNotEmpty == true) 'preview': n['preview'],
        'note': (n['reason'] as String?) ?? '',
        'extra': {
          'appeal': true,
          'noticePath': widget.doc.reference.path,
          'category': n['category'],
        },
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
      });
      await widget.doc.reference.update({'appeal': 'requested', 'seen': true});
      if (mounted) setState(() => _requested = true);
    } catch (e) {
      print('ContentNotices: appeal failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't send that. Try again.")),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rule = _rules[n['category']] ?? 'It goes against our community rules';
    final reason = (n['reason'] as String?) ?? '';
    final preview = (n['preview'] as String?) ?? '';

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.visibility_off_outlined,
                    size: 26, color: Colors.grey[800]),
              ),
              const SizedBox(height: 14),
              Text(
                'Your $_what was removed',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                rule,
                style: TextStyle(fontSize: 15, color: Colors.grey[800]),
              ),
              if (reason.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(reason,
                    style: TextStyle(fontSize: 14, color: Colors.grey[600])),
              ],
              if (preview.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Text(
                    preview,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Text(
                _requested || n['appeal'] == 'requested'
                    ? "Thanks. A person will look at it. If it was a mistake, "
                    "it'll come back and won't count against you."
                    : "It's hidden from everyone. Repeated removals can lead "
                    "to your account being restricted. Think we got it wrong? "
                    "Ask for a review.",
                style: TextStyle(fontSize: 13, height: 1.35, color: Colors.grey[600]),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  if (_canAppeal) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _sending ? null : _requestReview,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.black87,
                          side: BorderSide(color: Colors.grey[300]!),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: _sending
                            ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                            : const Text('Request a review',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('OK',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}