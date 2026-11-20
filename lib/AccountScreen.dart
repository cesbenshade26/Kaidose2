import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'AppColors.dart';
import 'AccountDeletion.dart';
import 'ContentNotices.dart';
import 'GroupAvatar.dart';
import 'auth_service.dart';
import 'SettingBar.dart' show ProfileSettingsSection;
import 'SettingsWidgets.dart';
import 'RankProgress.dart';

/// Settings → Account: who you are and how you log in.
///
///   Profile card   your picture, username, when you joined
///   Login          username (change it), email or phone, password
///   Account status posts removed for breaking the rules, and reviews
///   Bottom         Log out, then Delete account
///
/// Your picture, background and bio live in Customization (they're how
/// your profile looks, not your account).
class AccountScreen extends StatefulWidget {
  const AccountScreen({Key? key}) : super(key: key);

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  User? get _user => FirebaseAuth.instance.currentUser;

  late final Stream<DocumentSnapshot<Map<String, dynamic>>>? _me = _user ==
      null
      ? null
      : FirebaseFirestore.instance.collection('users').doc(_user!.uid).snapshots();

  // Birthday (and email/phone) are private to the account.
  late final Stream<DocumentSnapshot<Map<String, dynamic>>>? _private =
  _user == null
      ? null
      : FirebaseFirestore.instance
      .collection('user_private')
      .doc(_user!.uid)
      .snapshots();
  Map<String, dynamic> _privateData = {};
  StreamSubscription? _privateSub;

  @override
  void initState() {
    super.initState();
    _privateSub = _private?.listen((s) {
      if (mounted) setState(() => _privateData = s.data() ?? {});
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _privateSub?.cancel();
    super.dispose();
  }

  /// "March 4, 2008" from the birth date saved at sign-up, or null.
  String? _birthday(Map<String, dynamic> d) {
    final y = int.tryParse('${d['birthYear'] ?? ''}');
    final m = int.tryParse('${d['birthMonth'] ?? ''}');
    final day = int.tryParse('${d['birthDay'] ?? ''}');
    if (y == null || m == null || day == null || m < 1 || m > 12) return null;
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[m - 1]} $day, $y';
  }

  String _joined(DateTime? d) {
    if (d == null) return '';
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return 'Joined ${months[d.month - 1]} ${d.year}';
  }

  Future<void> _resetPassword(String email) async {
    final ok = await settingsConfirm(
      context,
      title: 'Change password',
      message: "We'll email $email a link to set a new password.",
      confirmLabel: 'Send link',
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final problem = await AuthService().sendPasswordReset(email);
    messenger.showSnackBar(SnackBar(
        content: Text(problem == null
            ? 'Check your email for the link'
            : "Couldn't send the email. Try again.")));
  }

  Future<void> _logOut() async {
    final ok = await settingsConfirm(
      context,
      title: 'Log out?',
      message: "You can log back in any time.",
      confirmLabel: 'Log out',
      danger: true,
    );
    if (ok && mounted) await ProfileSettingsSection.signOutAndLeave(context);
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    if (user == null || _me == null) {
      return const SettingsPage(title: 'Account', children: []);
    }
    final email = user.email;
    final phone = user.phoneNumber;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _me,
      builder: (context, snap) {
        final d = snap.data?.data() ?? {};
        final username = d['username'] as String? ?? '';
        // Older accounts have it on the profile until PrivateInfo moves it.
        final birthday = _birthday(_privateData) ?? _birthday(d);
        final changedAt = (d['usernameChangedAt'] as Timestamp?)?.toDate();

        return SettingsPage(
          title: 'Account',
          children: [
            // Who you are.
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: kc.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  MemberAvatar(userId: user.uid, size: 58),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          username.isEmpty ? ' ' : username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: SettingsStyle.ink),
                        ),
                        const SizedBox(height: 3),
                        Text(_joined(user.metadata.creationTime),
                            style: TextStyle(
                                fontSize: 13, color: SettingsStyle.subtle)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            SettingsGroup(
              title: 'Login',
              children: [
                SettingsTile(
                  icon: Icons.alternate_email_rounded,
                  title: 'Username',
                  value: username,
                  onTap: () => ChangeUsernameSheet.show(context,
                      current: username, lastChanged: changedAt),
                ),
                if (email != null && email.isNotEmpty)
                  SettingsTile(
                    icon: Icons.mail_outline_rounded,
                    title: 'Email',
                    value: email,
                    showChevron: false,
                  ),
                if (phone != null && phone.isNotEmpty)
                  SettingsTile(
                    icon: Icons.phone_iphone_rounded,
                    title: 'Phone',
                    value: phone,
                    showChevron: false,
                  ),
                if (birthday != null)
                  SettingsTile(
                    icon: Icons.cake_outlined,
                    title: 'Birthday',
                    subtitle: 'Only you can see this',
                    value: birthday,
                    showChevron: false,
                  ),
                // Phone accounts log in with a texted code: no password.
                if (email != null && email.isNotEmpty)
                  SettingsTile(
                    icon: Icons.lock_outline_rounded,
                    title: 'Change password',
                    onTap: () => _resetPassword(email),
                  ),
              ],
            ),

            const SettingsGroup(
              title: 'Rank',
              children: [RankTile()],
            ),

            SettingsGroup(
              title: 'Account status',
              footer: 'Posts removed for breaking the rules show up here, '
                  'with any reviews you asked for.',
              children: [
                SettingsTile(
                  icon: Icons.verified_user_outlined,
                  title: 'Account status',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AccountStatusScreen()),
                  ),
                ),
              ],
            ),

            SettingsGroup(
              children: [
                SettingsTile(
                  icon: Icons.logout_rounded,
                  title: 'Log out',
                  showChevron: false,
                  onTap: _logOut,
                ),
              ],
            ),

            SettingsGroup(
              footer: 'Deleting your account removes your profile, posts, '
                  "clips, chats and friends for good. It can't be undone.",
              children: [
                SettingsTile(
                  icon: Icons.delete_forever_outlined,
                  title: 'Delete account',
                  danger: true,
                  onTap: () => AccountDeletion.start(
                    context,
                        () => ProfileSettingsSection.signOutAndLeave(context,
                        accountDeleted: true),
                    logOutInstead: () =>
                        ProfileSettingsSection.signOutAndLeave(context),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

// ─── Change username ──────────────────────────────────────────────────────────

/// Bottom sheet to pick a new username. The server checks it's free and
/// swaps it in one go (so two people can't grab the same name), and
/// allows a change once every 14 days.
class ChangeUsernameSheet extends StatefulWidget {
  final String current;
  final DateTime? lastChanged;

  const ChangeUsernameSheet({Key? key, required this.current, this.lastChanged})
      : super(key: key);

  static const Duration cooldown = Duration(days: 14);

  static Future<void> show(BuildContext context,
      {required String current, DateTime? lastChanged}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          ChangeUsernameSheet(current: current, lastChanged: lastChanged),
    );
  }

  @override
  State<ChangeUsernameSheet> createState() => _ChangeUsernameSheetState();
}

class _ChangeUsernameSheetState extends State<ChangeUsernameSheet> {
  late final TextEditingController _c =
  TextEditingController(text: widget.current);
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(() => setState(() => _error = null));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Days until another change is allowed (0 = now).
  int get _daysLeft {
    final last = widget.lastChanged;
    if (last == null) return 0;
    final left = ChangeUsernameSheet.cooldown - DateTime.now().difference(last);
    return left.isNegative ? 0 : (left.inHours / 24).ceil();
  }

  /// Same rules as sign-up.
  String? _check(String s) {
    if (s.length < 3) return 'At least 3 characters';
    if (s.length > 20) return '20 characters at most';
    if (!RegExp(r'^[A-Za-z0-9_.]+$').hasMatch(s)) {
      return 'Letters, numbers, _ and . only';
    }
    if (!RegExp(r'[A-Za-z]').hasMatch(s)) return 'Include at least one letter';
    return null;
  }

  Future<void> _save() async {
    final name = _c.text.trim();
    final problem = _check(name);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    if (name == widget.current) {
      Navigator.pop(context);
      return;
    }
    setState(() => _saving = true);
    final problem2 = await AuthService().changeUsername(name);
    if (!mounted) return;
    if (problem2 == null) {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text("You're now @$name")));
    } else {
      setState(() {
        _saving = false;
        _error = problem2;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final daysLeft = _daysLeft;
    final locked = daysLeft > 0;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: kc.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: kc.grey(300),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text('Username',
                    style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: SettingsStyle.ink)),
                const SizedBox(height: 4),
                Text(
                  locked
                      ? 'You can change it again in $daysLeft day${daysLeft == 1 ? '' : 's'}.'
                      : 'You can change your username once every 14 days.',
                  style: TextStyle(
                      fontSize: 13.5, color: SettingsStyle.subtle),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _c,
                  enabled: !locked && !_saving,
                  autofocus: !locked,
                  maxLength: 20,
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _save(),
                  style: TextStyle(fontSize: 16, color: SettingsStyle.ink),
                  decoration: InputDecoration(
                    prefixText: '@',
                    errorText: _error,
                    filled: true,
                    fillColor: SettingsStyle.page,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: locked || _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyan,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.cyan.withOpacity(0.4),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _saving
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                        : const Text('Save',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Account status ───────────────────────────────────────────────────────────

/// Everything removed for breaking the rules, newest first, with the
/// rule, the date, and where any review stands. Lets you ask for a review
/// later if you closed the notice.
class AccountStatusScreen extends StatelessWidget {
  const AccountStatusScreen({Key? key}) : super(key: key);

  static const Map<String, String> _rules = {
    'nudity': 'Nudity or sexual content',
    'minor_sexual': 'Sexual content involving a minor',
    'gore': 'Graphic violence',
    'hate': 'Hate speech or slurs',
    'self_harm': 'Promoting self-harm',
    'weapons_drugs': 'Weapons',
    'drugs': 'Drugs or selling regulated goods',
    'threat': 'Threats',
  };

  String _date(DateTime? d) {
    if (d == null) return '';
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${m[d.month - 1]} ${d.day}, ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SettingsPage(title: 'Account status', children: []);
    final query = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('notices')
        .orderBy('createdAt', descending: true)
        .limit(50);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snap) {
        final docs = (snap.data?.docs ?? [])
            .where((d) => d.data()['kind'] == 'removed')
            .toList();
        final strikes = docs.where((d) {
          final at = (d.data()['createdAt'] as Timestamp?)?.toDate();
          return d.data()['appeal'] != 'restored' &&
              at != null &&
              DateTime.now().difference(at).inDays < 30;
        }).length;

        return SettingsPage(
          title: 'Account status',
          children: [
            // Summary.
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: kc.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    strikes == 0
                        ? Icons.check_circle_rounded
                        : Icons.info_rounded,
                    size: 30,
                    color: strikes == 0 ? kc.adapt(const Color(0xFF55595F)) : Colors.orange[700],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strikes == 0
                              ? "You're in good standing"
                              : '$strikes removal${strikes == 1 ? '' : 's'} in the last 30 days',
                          style: TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w800,
                              color: SettingsStyle.ink),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          strikes == 0
                              ? 'Nothing of yours has been removed recently.'
                              : 'Repeated removals can lead to your account being restricted.',
                          style: TextStyle(
                              fontSize: 13, color: SettingsStyle.subtle),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (docs.isNotEmpty)
              SettingsGroup(
                title: 'Removed',
                children: [
                  for (final d in docs) _removedTile(context, d),
                ],
              ),
          ],
        );
      },
    );
  }

  Widget _removedTile(
      BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final n = doc.data();
    final what = switch (n['target']) {
      'clip' => 'Clip',
      'comment' => 'Comment',
      _ => 'Post',
    };
    final rule = _rules[n['category']] ?? 'Community rules';
    final when = _date((n['createdAt'] as Timestamp?)?.toDate());
    final appeal = n['appeal'] as String?;
    final canAppeal = appeal == null && n['category'] != 'minor_sexual';
    final status = switch (appeal) {
      'requested' => 'Review requested',
      'restored' => 'Restored after review',
      'denied' => 'Review: kept removed',
      _ => null,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.visibility_off_outlined,
                size: 22, color: kc.adapt(const Color(0xFF55595F))),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$what removed · $when',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: SettingsStyle.ink)),
                const SizedBox(height: 2),
                Text(rule,
                    style: TextStyle(
                        fontSize: 13, color: SettingsStyle.subtle)),
                if ((n['preview'] as String?)?.isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text('"${n['preview']}"',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                          color: kc.grey(600))),
                ],
                if (status != null) ...[
                  const SizedBox(height: 4),
                  Text(status,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: appeal == 'restored'
                              ? Colors.cyan[700]
                              : SettingsStyle.subtle)),
                ],
              ],
            ),
          ),
          if (canAppeal)
            TextButton(
              onPressed: () async {
                final ok = await ContentNotices.requestReview(doc);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(ok
                      ? 'Review requested'
                      : "Couldn't send that. Try again."),
                ));
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.cyan[700],
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: const Text('Request review',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}