import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'AppColors.dart';
import 'auth_service.dart';
import 'CommunityGuidelines.dart';
import 'KaidoseBrand.dart';
import 'Legal.dart';

/// The last step of sign-up: the Terms, and a checkbox to agree before the
/// account is made. Returns true when they agreed.
///
///   final agreed = await TermsAgreementScreen.open(context);
///
/// The Terms are what people agree to; the Privacy Policy only has to be
/// easy to find and acknowledged, so it's a link here (and in Settings).
///
/// iubenda: the full text can come from iubenda's API (or be pasted from
/// your iubenda dashboard) into [kTermsText]. The "Read the full Terms"
/// link opens your hosted iubenda page (Legal.openTerms), which is always
/// the current version.
class TermsAgreementScreen extends StatefulWidget {
  const TermsAgreementScreen({super.key});

  static Future<bool> open(BuildContext context) async {
    final agreed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const TermsAgreementScreen()),
    );
    return agreed == true;
  }

  @override
  State<TermsAgreementScreen> createState() => _TermsAgreementScreenState();
}

// TODO: replace with your Terms and Conditions text from iubenda.
const String kTermsText = '''
1. Lorem ipsum dolor sit amet

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Integer vel nisl quis tortor posuere fermentum. Curabitur blandit, nibh at tincidunt pretium, magna erat ultricies ipsum, vel dictum lorem augue non sapien. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia curae.

2. Quisque sagittis

Quisque sagittis, nisl in aliquet sollicitudin, ex magna egestas lorem, at volutpat augue risus vitae nisi. Morbi feugiat mi a nunc pulvinar, eu tincidunt felis volutpat. Donec non arcu nec mauris luctus convallis. Aliquam erat volutpat. Phasellus vehicula justo at leo cursus, non varius erat accumsan.

3. Nullam faucibus

Nullam faucibus metus id dolor iaculis, in imperdiet nibh tempus. Suspendisse potenti. Praesent sed sem a enim interdum consequat. Fusce at velit sit amet ligula pretium placerat. Etiam euismod purus et justo dictum, vitae gravida purus posuere.

4. Sed ut perspiciatis

Sed ut perspiciatis unde omnis iste natus error sit voluptatem accusantium doloremque laudantium, totam rem aperiam, eaque ipsa quae ab illo inventore veritatis et quasi architecto beatae vitae dicta sunt explicabo.

5. Nemo enim ipsam

Nemo enim ipsam voluptatem quia voluptas sit aspernatur aut odit aut fugit, sed quia consequuntur magni dolores eos qui ratione voluptatem sequi nesciunt. Neque porro quisquam est, qui dolorem ipsum quia dolor sit amet.
''';

class _TermsAgreementScreenState extends State<TermsAgreementScreen> {
  bool _agreed = false;

  final TapGestureRecognizer _termsTap = TapGestureRecognizer()
    ..onTap = Legal.openTerms;
  final TapGestureRecognizer _privacyTap = TapGestureRecognizer()
    ..onTap = Legal.openPrivacy;
  late final TapGestureRecognizer _guidelinesTap = TapGestureRecognizer()
    ..onTap = () => CommunityGuidelinesScreen.open(context);

  @override
  void dispose() {
    _termsTap.dispose();
    _privacyTap.dispose();
    _guidelinesTap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const linkStyle = TextStyle(
      color: KaidoseBrand.cyan,
      fontWeight: FontWeight.w600,
    );

    return Scaffold(
      backgroundColor: kc.background,
      appBar: AppBar(
        backgroundColor: kc.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: kc.text),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('One last thing', style: KaidoseBrand.display(30)),
              const SizedBox(height: 6),
              Text('Please read and agree to our Terms to continue.',
                  style: TextStyle(fontSize: 15, color: kc.grey(600))),
              const SizedBox(height: 18),

              // The Terms themselves.
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: KaidoseBrand.fieldFill,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Scrollbar(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Terms and Conditions',
                              style: TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 12),
                          Text(
                            kTermsText.trim(),
                            style: TextStyle(
                                fontSize: 14,
                                height: 1.45,
                                color: kc.grey(800)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: Text.rich(
                  TextSpan(
                    style: TextStyle(fontSize: 13, color: kc.grey(500)),
                    children: [
                      TextSpan(
                        text: 'Read the full Terms',
                        style: linkStyle,
                        recognizer: _termsTap,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // The agreement.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _agreed = !_agreed),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: _agreed,
                        onChanged: (v) => setState(() => _agreed = v ?? false),
                        activeColor: KaidoseBrand.cyan,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(5)),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          style: const TextStyle(
                              fontSize: 14, height: 1.4, color: KaidoseBrand.ink),
                          children: [
                            const TextSpan(text: 'I have read and agree to the '),
                            TextSpan(
                                text: 'Terms and Conditions',
                                style: linkStyle,
                                recognizer: _termsTap),
                            const TextSpan(text: ' and '),
                            TextSpan(
                                text: 'Community Guidelines',
                                style: linkStyle,
                                recognizer: _guidelinesTap),
                            const TextSpan(text: ', and I acknowledge the '),
                            TextSpan(
                                text: 'Privacy Policy',
                                style: linkStyle,
                                recognizer: _privacyTap),
                            const TextSpan(text: '.'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              AuthButton(
                label: 'Agree and continue',
                loading: false,
                onPressed: () {
                  if (_agreed) {
                    Navigator.pop(context, true);
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: const Text('Check the box to agree first'),
                    backgroundColor: Colors.red.shade400,
                    behavior: SnackBarBehavior.floating,
                  ));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}