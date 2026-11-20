import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'AppColors.dart';
import 'Customization.dart';
import 'auth_service.dart';
import 'ProfilePicManager.dart';
import 'BioManager.dart';
import 'BackgroundPicManager.dart';
import 'Archives.dart';
import 'YourActivity.dart';
import 'ClipsActivity.dart' show MyClipsCache;
import 'NotificationService.dart';
import 'PrivacySettings.dart';
import 'DisplaySettings.dart';
import 'HelpAbout.dart';
import 'ContentData.dart';
import 'ReportProblem.dart' show ProblemReportsScreen;
import 'AdminReportsScreen.dart';
import 'GroupAvatar.dart';
import 'AccountScreen.dart';
import 'SettingsWidgets.dart';
import 'NotificationSettings.dart';

/// Settings: your account card at the top, then the rest in groups.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const SettingsPage(
      title: 'Settings',
      children: [ProfileSettingsSection()],
    );
  }
}

/// Everything on the Settings page (kept as its own widget, and the home
/// of [signOutAndLeave], which other screens use).
class ProfileSettingsSection extends StatelessWidget {
  const ProfileSettingsSection({Key? key}) : super(key: key);

  /// Clears this phone's account state and goes back to the opening
  /// screen. Used by Log out and after deleting the account.
  static Future<void> signOutAndLeave(BuildContext context,
      {bool accountDeleted = false}) async {
    // Stop push notifications for this account on this phone. Must run
    // while still signed in: it removes this phone's token from the
    // account. (After a delete the token is already gone with it.)
    try {
      await NotificationService.instance.stop();
    } catch (_) {}

    // Clear state before signing out so it doesn't bleed into the next
    // account's session
    ProfilePicManager.clearForLogout();
    BioManager.clearForLogout();
    BackgroundPicManager.clearForLogout();
    MyClipsCache.instance.clear();
    MemberAvatar.clearCache();
    await AuthService().logout();

    if (!context.mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      '/opening',
          (route) => false,
    );
  }

  void _open(BuildContext context, Widget screen) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => screen),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        _AccountCard(onTap: () => _open(context, const AccountScreen())),

        SettingsGroup(
          children: [
            SettingsTile(
              icon: Icons.palette_outlined,
              title: 'Edit profile',
              subtitle: 'Profile picture, background, bio',
              onTap: () => _open(context, const CustomizationScreen()),
            ),
            SettingsTile(
              icon: Icons.notifications_none_rounded,
              title: 'Notifications',
              onTap: () => _open(context, const NotificationSettingsScreen()),
            ),
            SettingsTile(
              icon: Icons.lock_outline_rounded,
              title: 'Privacy',
              subtitle: 'Near you, story, blocked and muted, phone access',
              onTap: () => _open(context, const PrivacySettingsScreen()),
            ),
            SettingsTile(
              icon: Icons.brightness_6_outlined,
              title: 'Display',
              onTap: () => _open(context, const DisplaySettingsScreen()),
            ),
            SettingsTile(
              icon: Icons.data_usage_rounded,
              title: 'Content & data',
              subtitle: 'Data saver, cache, Not interested, download your data',
              onTap: () => _open(context, const ContentDataScreen()),
            ),
            SettingsTile(
              icon: Icons.bookmarks_outlined,
              title: 'Archives',
              subtitle: 'Your folders of saved posts and clips',
              onTap: () => _open(context, const ArchivesScreen()),
            ),
            SettingsTile(
              icon: Icons.history_rounded,
              title: 'Your activity',
              subtitle: 'Likes, reactions, comments and watch history',
              onTap: () => _open(context, const YourActivityScreen()),
            ),
          ],
        ),

        SettingsGroup(
          children: [
            SettingsTile(
              icon: Icons.help_outline_rounded,
              title: 'Help & About',
              subtitle: 'Contact support, report a problem, guidelines, terms',
              onTap: () => _open(context, const HelpAboutScreen()),
            ),
          ],
        ),

        // Only shows for admin accounts (users/{uid}.isAdmin == true).
        FutureBuilder<bool>(
          future: AdminAccess.isAdmin(),
          builder: (context, snap) {
            if (snap.data != true) return const SizedBox.shrink();
            return SettingsGroup(
              title: 'Admin',
              children: [
                SettingsTile(
                  icon: Icons.shield_outlined,
                  title: 'Reports',
                  onTap: () => _open(context, const AdminReportsScreen()),
                ),
                SettingsTile(
                  icon: Icons.bug_report_outlined,
                  title: 'Problem reports',
                  onTap: () => _open(context, const ProblemReportsScreen()),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Your picture, username and "Account" at the top of Settings.
class _AccountCard extends StatelessWidget {
  final VoidCallback onTap;
  const _AccountCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Material(
      color: kc.surface,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (uid != null) MemberAvatar(userId: uid, size: 54),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (uid != null)
                      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('users')
                            .doc(uid)
                            .snapshots(),
                        builder: (context, snap) => Text(
                          (snap.data?.data()?['username'] as String?) ?? ' ',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: SettingsStyle.ink),
                        ),
                      ),
                    const SizedBox(height: 2),
                    Text('Account, login, account status',
                        style:
                        TextStyle(fontSize: 13, color: SettingsStyle.subtle)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: kc.grey(400)),
            ],
          ),
        ),
      ),
    );
  }
}