import 'package:url_launcher/url_launcher.dart';

/// Kaidose's Terms and Privacy Policy: where they live, and which version
/// new accounts agree to.
///
/// When you publish new terms or a new privacy policy, bump [termsVersion]
/// (e.g. "2027-03"). Every account stores the version it agreed to
/// (users/{uid}.termsVersion), so anyone on an older version can be shown
/// "We updated our terms" later.
class Legal {
  /// The version of the Terms + Privacy Policy that sign-ups agree to.
  static const String termsVersion = '2026-11';

  /// TODO: replace with the real links once the documents are published.
  static const String termsUrl = 'https://kaidose.app/terms';
  static const String privacyUrl = 'https://kaidose.app/privacy';

  static Future<void> openTerms() => _open(termsUrl);
  static Future<void> openPrivacy() => _open(privacyUrl);

  /// Opens the page in an in-app browser sheet, so people come straight
  /// back to sign-up when they close it.
  static Future<void> _open(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);
    } catch (e) {
      print('Legal: could not open $url: $e');
    }
  }
}