import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'DailyData.dart';
import 'FeedService.dart';

/// Joined vs. guest.
///
/// A "joined" Daily has a copy at users/{uid}/dailies/{dailyId} (that's
/// what My Dailies reads) plus an ACCEPTED daily_invitations doc, which is
/// what ManageDaily/ManageMembers use to decide who is a member and who the
/// owner is (owner = no accepted invitation for you). A guest has neither:
/// they can open and post in a Public Daily without it ever appearing in
/// My Dailies.
///
/// Both "Add to My Dailies" (For You cards, the chip inside a Daily) and
/// the Join button in search go through [addToMyDailies], so joining always
/// writes the same two things no matter where it was tapped.
class DailyMembershipService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// True when this Daily is in the current user's My Dailies (they own it
  /// or joined it). False means they'd be a guest.
  static Future<bool> isInMyDailies(String dailyId) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      final doc = await _firestore
          .collection('users')
          .doc(uid)
          .collection('dailies')
          .doc(dailyId)
          .get();
      return doc.exists;
    } catch (e) {
      print('DailyMembershipService: isInMyDailies error: $e');
      return false;
    }
  }

  /// Adds [daily] to the current user's My Dailies as a regular member.
  /// Safe to call twice: does nothing if they're already in it.
  static Future<Map<String, dynamic>> addToMyDailies(DailyData daily) async {
    final uid = _uid;
    if (uid == null) return {'success': false, 'error': 'Not signed in'};

    final ownerUid = daily.creatorUid;
    if (ownerUid == null || ownerUid.isEmpty) {
      return {'success': false, 'error': 'This Daily has no owner on record'};
    }
    if (ownerUid == uid) return {'success': true}; // your own Daily

    try {
      if (await isInMyDailies(daily.id)) return {'success': true};

      final userDoc = await _firestore.collection('users').doc(uid).get();
      final myUsername = (userDoc.data()?['username'] as String?) ?? 'Someone';

      // 1. The accepted invitation — this is what marks you as a member
      //    (and NOT the owner) everywhere else in the app.
      final existing = await _firestore
          .collection('daily_invitations')
          .where('dailyId', isEqualTo: daily.id)
          .where('toUserId', isEqualTo: uid)
          .limit(1)
          .get();

      if (existing.docs.isEmpty) {
        await _firestore.collection('daily_invitations').add({
          'dailyId': daily.id,
          'dailyTitle': daily.title,
          'fromUserId': ownerUid,
          'fromUsername': '',
          'toUserId': uid,
          'toUsername': myUsername,
          'status': 'accepted',
          'timestamp': Timestamp.now(),
        });
      } else if (existing.docs.first.data()['status'] != 'accepted') {
        await existing.docs.first.reference.update({'status': 'accepted'});
      }

      // 2. The copy My Dailies reads, same shape an accepted invite makes.
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('dailies')
          .doc(daily.id)
          .set({
        ...daily.toFirestoreJson(),
        'ownerUid': ownerUid,
        'isMemberCopy': true,
        'creatorUid': ownerUid,
      });

      // Adding a Daily is the strongest "I like this" signal the feed gets.
      FeedService.recordEvent(daily, FeedEvent.add);

      return {'success': true};
    } catch (e) {
      print('DailyMembershipService: addToMyDailies error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }
}