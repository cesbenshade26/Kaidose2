import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'AppColors.dart';
import 'ProfilePic.dart';
import 'BackgroundPic.dart';
import 'Bio.dart';
import 'GroupAvatar.dart';
import 'SettingsWidgets.dart';

/// Settings → Edit profile: how your profile looks to other people
/// (picture, background, bio). Your username is in Settings → Account,
/// since it's also how you log in.
class CustomizationScreen extends StatelessWidget {
  const CustomizationScreen({Key? key}) : super(key: key);

  void _open(BuildContext context, Widget screen) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => screen),
  );

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return SettingsPage(
      title: 'Edit profile',
      children: [
        if (uid != null) _Preview(uid: uid, onTapPicture: () => _open(context, const ProfilePicScreen())),
        SettingsGroup(
          title: 'Your profile',
          footer: 'Everyone who visits your profile sees these.',
          children: [
            SettingsTile(
              icon: Icons.account_circle_outlined,
              title: 'Profile picture',
              onTap: () => _open(context, const ProfilePicScreen()),
            ),
            SettingsTile(
              icon: Icons.wallpaper_rounded,
              title: 'Background picture',
              onTap: () => _open(context, const BackgroundPicScreen()),
            ),
            SettingsTile(
              icon: Icons.edit_note_rounded,
              title: 'Bio',
              onTap: () => _open(context, const BioScreen()),
            ),
          ],
        ),
      ],
    );
  }
}

/// Your picture and username, the way people see them (updates live).
class _Preview extends StatelessWidget {
  final String uid;
  final VoidCallback onTapPicture;
  const _Preview({required this.uid, required this.onTapPicture});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(vertical: 22),
      decoration: BoxDecoration(
        color: kc.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: onTapPicture,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                MemberAvatar(userId: uid, size: 84),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.cyan,
                      shape: BoxShape.circle,
                      border: Border.all(color: kc.background, width: 2.5),
                    ),
                    child: const Icon(Icons.edit, size: 14, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream:
            FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
            builder: (context, snap) => Text(
              (snap.data?.data()?['username'] as String?) ?? ' ',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: SettingsStyle.ink),
            ),
          ),
        ],
      ),
    );
  }
}