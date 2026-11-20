import 'package:flutter/material.dart';
import 'AppColors.dart';
import 'package:flutter/services.dart';
import 'CommunityGuidelines.dart';
import 'AppVersion.dart';
import 'Legal.dart';
import 'ReportProblem.dart';
import 'package:url_launcher/url_launcher.dart';
import 'Moderation.dart' show kSupportEmail;
import 'SettingsWidgets.dart';

/// Settings → Help & About: getting in touch, the Community Guidelines,
/// and the Terms and Privacy Policy (hosted on iubenda, opened in the
/// browser).
class HelpAboutScreen extends StatelessWidget {
  const HelpAboutScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final opensOutside =
    Icon(Icons.open_in_new_rounded, size: 18, color: kc.adapt(const Color(0xFFB0B4BA)));
    return SettingsPage(
      title: 'Help & About',
      children: [
        SettingsGroup(
          title: 'Help',
          children: [
            SettingsTile(
              icon: Icons.mail_outline_rounded,
              title: 'Contact support',
              subtitle: 'Questions, problems or feedback',
              onTap: () => ContactSupportSheet.show(context),
            ),
            SettingsTile(
              icon: Icons.bug_report_outlined,
              title: 'Report a problem',
              subtitle: 'Something broken or not working right',
              onTap: () => ReportProblemSheet.show(context),
            ),
          ],
        ),
        SettingsGroup(
          title: 'Policies',
          children: [
            SettingsTile(
              icon: Icons.menu_book_rounded,
              title: 'Community Guidelines',
              subtitle: "What's OK to post, and what happens if it isn't",
              onTap: () => CommunityGuidelinesScreen.open(context),
            ),
            SettingsTile(
              icon: Icons.description_outlined,
              title: 'Terms and Conditions',
              trailing: opensOutside,
              onTap: Legal.openTerms,
            ),
            SettingsTile(
              icon: Icons.privacy_tip_outlined,
              title: 'Privacy Policy',
              trailing: opensOutside,
              onTap: Legal.openPrivacy,
            ),
          ],
        ),
        // The installed app's version (from pubspec.yaml).
        Padding(
          padding: const EdgeInsets.only(top: 28),
          child: Center(
            child: FutureBuilder<String>(
              future: AppVersion.label(),
              builder: (context, snap) => Text(
                (snap.data ?? '').isEmpty ? ' ' : 'Kaidose ${snap.data}',
                style: TextStyle(
                    fontSize: 12.5, color: SettingsStyle.subtle),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// How to reach support: opens an email to the address (or copies it),
/// and says what to include so we can help faster.
class ContactSupportSheet extends StatelessWidget {
  const ContactSupportSheet({Key? key}) : super(key: key);

  static Future<void> show(BuildContext context) => showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => const ContactSupportSheet(),
  );

  /// Opens their email app with a new message to support. If there's no
  /// email app set up, copies the address instead.
  Future<void> _email(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: kSupportEmail,
      query: 'subject=${Uri.encodeComponent('Kaidose support')}',
    );
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!context.mounted) return;
    if (opened) {
      Navigator.pop(context);
    } else {
      _copy(context);
    }
  }

  void _copy(BuildContext context) {
    Clipboard.setData(const ClipboardData(text: kSupportEmail));
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(const SnackBar(
      content: Text('Email address copied'),
      duration: Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kc.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
              Text('Contact support',
                  style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: SettingsStyle.ink)),
              const SizedBox(height: 4),
              Text(
                'Email us and we\'ll get back to you. Include your username '
                    'and what happened (a screenshot helps).',
                style: TextStyle(
                    fontSize: 13.5, height: 1.35, color: SettingsStyle.subtle),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: SettingsStyle.page,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  kSupportEmail,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: SettingsStyle.ink),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _email(context),
                  icon: const Icon(Icons.mail_outline_rounded, size: 18),
                  label: const Text('Email support',
                      style:
                      TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyan,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () => _copy(context),
                  icon: const Icon(Icons.copy_rounded, size: 17),
                  label: const Text('Copy email address',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  style: TextButton.styleFrom(
                    foregroundColor: SettingsStyle.ink,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}