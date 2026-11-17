import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Where people can reach you (App Store requirement: published contact
/// info). Change to your real support address.
const String kSupportEmail = 'cwesbenshade@icloud.com';

/// The first line of defense before something is posted: blocks text with
/// slurs or direct threats. Photos and videos on Clips are also checked on
/// the server (see onClipWritten), and anything that slips through can be
/// reported.
class ContentFilter {
  ContentFilter._();

  // Matched as whole words after normalizing (case, l33t, repeats).
  // Add to this list as you see new problems in reports.
  static const List<String> _blockedWords = [
    'nigger', 'nigga', 'niggas', 'faggot', 'fag', 'fags', 'retard', 'retards',
    'tranny', 'chink', 'spic', 'kike', 'wetback', 'gook', 'coon', 'dyke',
    'kys',
  ];

  // Phrases (matched with spaces collapsed).
  static const List<String> _blockedPhrases = [
    'kill yourself',
    'killyourself',
    'go die',
    'hang yourself',
  ];

  static String _normalize(String s) {
    var t = s.toLowerCase();
    const leet = {
      '0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '7': 't',
      '@': 'a', r'$': 's', '!': 'i',
    };
    leet.forEach((k, v) => t = t.replaceAll(k, v));
    // "niiiigggger" -> "niger"-ish; compare both forms below.
    return t;
  }

  static String _squash(String s) => s.replaceAllMapped(
      RegExp(r'(.)\1{2,}'), (m) => m.group(1)! + m.group(1)!);

  /// Null when the text is fine; otherwise a short reason to show.
  static String? problem(String text) {
    if (text.trim().isEmpty) return null;
    final norm = _squash(_normalize(text));
    final words = norm.split(RegExp(r'[^a-z]+')).where((w) => w.isNotEmpty);
    for (final w in words) {
      if (_blockedWords.contains(w)) {
        return "That includes language that isn't allowed on Kaidose.";
      }
    }
    final spaced = norm.replaceAll(RegExp(r'[^a-z ]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
    for (final p in _blockedPhrases) {
      if (spaced.contains(p)) {
        return "That includes language that isn't allowed on Kaidose.";
      }
    }
    return null;
  }

  /// Checks [text] and tells the person if it can't be posted. Returns
  /// true when it's OK to post.
  static bool allow(BuildContext context, String text) {
    final p = problem(text);
    if (p == null) return true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(p),
      backgroundColor: Colors.black87,
      duration: const Duration(seconds: 3),
    ));
    return false;
  }
}

/// Community Guidelines: everyone agrees once before posting anything
/// (Google Play requires this before people can post). Saved as
/// users/{uid}.termsAcceptedAt.
class TermsGate {
  TermsGate._();

  static bool _accepted = false;
  static String? _forUid;

  /// Shows the guidelines if this person hasn't agreed yet. Returns true
  /// when they have (already, or just now).
  static Future<bool> ensure(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    if (_accepted && _forUid == uid) return true;

    try {
      final doc =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.data()?['termsAcceptedAt'] != null) {
        _accepted = true;
        _forUid = uid;
        return true;
      }
    } catch (_) {}
    if (!context.mounted) return false;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _GuidelinesSheet(askToAgree: true),
    );
    if (ok != true) return false;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
          {'termsAcceptedAt': FieldValue.serverTimestamp()},
          SetOptions(merge: true));
    } catch (_) {}
    _accepted = true;
    _forUid = uid;
    return true;
  }

  /// Just shows the guidelines (e.g. from Settings).
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _GuidelinesSheet(askToAgree: false),
    );
  }

  /// One call for every "post" button: guidelines agreed + text is OK.
  static Future<bool> readyToPost(BuildContext context, String text) async {
    if (!await ensure(context)) return false;
    if (!context.mounted) return false;
    return ContentFilter.allow(context, text);
  }
}

class _GuidelinesSheet extends StatelessWidget {
  final bool askToAgree;
  const _GuidelinesSheet({required this.askToAgree});

  static const _rules = <(IconData, String, String)>[
    (Icons.favorite_border_rounded, 'Be kind',
    'No bullying, harassment, threats or hate toward anyone.'),
    (Icons.no_adult_content_outlined, 'Keep it appropriate',
    'No nudity, sexual content, or graphic violence.'),
    (Icons.health_and_safety_outlined, 'Stay safe',
    "Don't encourage self-harm or dangerous acts. If someone's in danger, report it."),
    (Icons.verified_user_outlined, 'Be yourself',
    "Don't pretend to be someone else, spam, or scam people."),
    (Icons.copyright_rounded, 'Post what\'s yours',
    "Only share things you have the right to share."),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 10, 20, MediaQuery.of(context).padding.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text('Community Guidelines',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            'Kaidose is for real people sharing their days. To keep it that way:',
            style: TextStyle(fontSize: 14, color: Colors.grey[700], height: 1.35),
          ),
          const SizedBox(height: 14),
          for (final r in _rules)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.cyan.withOpacity(0.10),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(r.$1, size: 19, color: Colors.cyan[700]),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.$2,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(r.$3,
                            style: TextStyle(
                                fontSize: 13.5,
                                color: Colors.grey[700],
                                height: 1.3)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Text(
            'Content that breaks these rules can be removed, and accounts can '
                'be suspended. Report anything that looks wrong. Questions? '
                '$kSupportEmail',
            style: TextStyle(fontSize: 12.5, color: Colors.grey[600], height: 1.35),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyan,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25)),
              ),
              child: Text(askToAgree ? 'I agree' : 'Got it',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}