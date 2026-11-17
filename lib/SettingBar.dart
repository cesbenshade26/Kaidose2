import 'package:flutter/material.dart';
import 'Customization.dart';
import 'SecurityInfo.dart';
import 'auth_service.dart';
import 'ProfilePicManager.dart';
import 'BioManager.dart';
import 'BackgroundPicManager.dart';
import 'SavedScreen.dart';
import 'ClipsActivity.dart' show MyClipsCache;
import 'NotificationService.dart';
import 'package:flutter/services.dart';
import 'SafetySheets.dart' show BlockedAccountsScreen;
import 'Moderation.dart';
import 'AdminReportsScreen.dart';
import 'AccountDeletion.dart';
import 'GroupAvatar.dart';
import 'Legal.dart';

// Settings Screen
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProfileSettingsSection(),
          ],
        ),
      ),
    );
  }
}

// Profile Settings Section
class ProfileSettingsSection extends StatelessWidget {
  const ProfileSettingsSection({Key? key}) : super(key: key);

  /// Clears this phone's account state and goes back to the opening
  /// screen. Used by Logout and after deleting the account.
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

  Widget _tile(
      BuildContext context, {
        required IconData icon,
        required String title,
        String? subtitle,
        Color? color,
        required VoidCallback onTap,
      }) {
    return ListTile(
      leading: Icon(icon, color: color ?? Colors.grey, size: 28),
      title: Text(
        title,
        style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w500, color: color),
      ),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, style: TextStyle(fontSize: 12.5, color: Colors.grey[600])),
      trailing: Icon(Icons.chevron_right, color: color ?? Colors.grey),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            'Account Settings',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Saved & Archives (temporary home until it gets a better spot)
        ListTile(
          leading: const Icon(Icons.bookmark_rounded, color: Colors.grey, size: 28),
          title: const Text(
            'Saved & Archives',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          trailing: const Icon(Icons.chevron_right, color: Colors.grey),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SavedScreen()),
            );
          },
        ),
        const Divider(color: Colors.grey, thickness: 0.5),
        // Customization Option
        ListTile(
          leading: const Icon(Icons.palette, color: Colors.grey, size: 28),
          title: const Text(
            'Customization',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          trailing: const Icon(Icons.chevron_right, color: Colors.grey),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const CustomizationScreen()),
            );
          },
        ),
        const Divider(color: Colors.grey, thickness: 0.5),
        // Security Info Option
        ListTile(
          leading: const Icon(Icons.security, color: Colors.grey, size: 28),
          title: const Text(
            'Security Info',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          trailing: const Icon(Icons.chevron_right, color: Colors.grey),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SecurityInfoScreen()),
            );
          },
        ),
        const Divider(color: Colors.grey, thickness: 0.5),

        // ── Privacy & safety ──
        const Padding(
          padding: EdgeInsets.only(top: 18, bottom: 8),
          child: Text(
            'Privacy & Safety',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
        _tile(
          context,
          icon: Icons.block_rounded,
          title: 'Blocked accounts',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const BlockedAccountsScreen()),
          ),
        ),
        const Divider(color: Colors.grey, thickness: 0.5),
        _tile(
          context,
          icon: Icons.menu_book_rounded,
          title: 'Community Guidelines',
          onTap: () => TermsGate.show(context),
        ),
        const Divider(color: Colors.grey, thickness: 0.5),
        _tile(
          context,
          icon: Icons.description_outlined,
          title: 'Terms and Conditions',
          onTap: Legal.openTerms,
        ),
        const Divider(color: Colors.grey, thickness: 0.5),
        _tile(
          context,
          icon: Icons.privacy_tip_outlined,
          title: 'Privacy Policy',
          onTap: Legal.openPrivacy,
        ),
        const Divider(color: Colors.grey, thickness: 0.5),
        _tile(
          context,
          icon: Icons.mail_outline_rounded,
          title: 'Contact support',
          subtitle: kSupportEmail,
          onTap: () {
            Clipboard.setData(const ClipboardData(text: kSupportEmail));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Email address copied'),
              duration: Duration(seconds: 2),
            ));
          },
        ),
        const Divider(color: Colors.grey, thickness: 0.5),
        // Only shows for admin accounts (users/{uid}.isAdmin == true).
        FutureBuilder<bool>(
          future: AdminAccess.isAdmin(),
          builder: (context, snap) {
            if (snap.data != true) return const SizedBox.shrink();
            return Column(
              children: [
                _tile(
                  context,
                  icon: Icons.shield_outlined,
                  title: 'Reports (admin)',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AdminReportsScreen()),
                  ),
                ),
                const Divider(color: Colors.grey, thickness: 0.5),
              ],
            );
          },
        ),
        const SizedBox(height: 12),

        // Logout Option
        ListTile(
          leading: const Icon(Icons.logout, color: Colors.red, size: 28),
          title: const Text(
            'Logout',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.red),
          ),
          trailing: const Icon(Icons.chevron_right, color: Colors.red),
          onTap: () async {
            final shouldLogout = await showDialog<bool>(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: const Text('Logout'),
                  content: const Text('Are you sure you want to logout?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text('Logout'),
                    ),
                  ],
                );
              },
            );

            if (shouldLogout == true && context.mounted) {
              await signOutAndLeave(context);
            }
          },
        ),
        const Divider(color: Colors.grey, thickness: 0.5),
        // Delete account (required in-app; will move to its own screen)
        _tile(
          context,
          icon: Icons.delete_forever_outlined,
          title: 'Delete account',
          color: Colors.red,
          onTap: () => AccountDeletion.start(
            context,
                () => signOutAndLeave(context, accountDeleted: true),
          ),
        ),
        const Divider(color: Colors.grey, thickness: 0.5),
      ],
    );
  }
}