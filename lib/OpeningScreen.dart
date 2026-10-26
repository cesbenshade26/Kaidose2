import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'CreateAccount.dart';
import 'ForgotPasswordScreen.dart';
import 'InterestOnboarding.dart';
import 'auth_service.dart';
import 'KaidoseBrand.dart';

/// The logged-out front door: the Kaidose wordmark and the login form.
///
/// The wordmark animation plays once per app run. Coming back here later
/// (logging out, backing out of sign-up) shows the finished screen at once.
class OpeningScreen extends StatefulWidget {
  final bool skipAnimation;
  const OpeningScreen({super.key, this.skipAnimation = false});

  @override
  State<OpeningScreen> createState() => _OpeningScreenState();
}

class _OpeningScreenState extends State<OpeningScreen>
    with TickerProviderStateMixin {
  late final AnimationController _draw;
  late final AnimationController _form;

  final _authService = AuthService();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();

  bool _moveToTop = false;
  bool _isLoggingIn = false;
  String _loginError = '';

  @override
  void initState() {
    super.initState();
    _draw = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _form = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    if (widget.skipAnimation || KaidoseIntro.played) {
      _moveToTop = true;
      _draw.value = 1.0;
      _form.value = 1.0;
    } else {
      KaidoseIntro.played = true;
      _playIntro();
    }
  }

  Future<void> _playIntro() async {
    await KaidoseBrand.preloadFonts();
    if (!mounted) return;
    await _draw.forward();
    await Future.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    setState(() => _moveToTop = true);
    await Future.delayed(const Duration(milliseconds: 450));
    if (mounted) _form.forward();
  }

  @override
  void dispose() {
    _draw.dispose();
    _form.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _attemptLogin() async {
    if (_isLoggingIn) return;
    FocusScope.of(context).unfocus();
    setState(() => _loginError = '');

    final inputUser = _usernameController.text.trim();
    final inputPass = _passwordController.text;

    if (inputUser.isEmpty || inputPass.isEmpty) {
      setState(() => _loginError = 'Enter your username (or email) and password');
      return;
    }

    setState(() => _isLoggingIn = true);
    final result = await _authService.login(
      usernameOrEmail: inputUser,
      password: inputPass,
    );
    if (!mounted) return;

    if (result['success'] != true) {
      setState(() {
        _isLoggingIn = false;
        _loginError = authErrorMessage(result['error'] as String?);
      });
      return;
    }

    // Signed in. Has this person finished onboarding?
    final uid = FirebaseAuth.instance.currentUser?.uid;
    var onboardingDone = true;
    if (uid != null) {
      try {
        final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
        onboardingDone = doc.data()?['onboardingComplete'] == true;
      } catch (_) {}
    }
    if (!mounted) return;

    if (onboardingDone) {
      Navigator.pushReplacementNamed(context, '/user-account');
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const InterestOnboarding()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final topInset = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: Colors.white,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: Column(
          children: [
            // This spacer is what slides the wordmark from the middle of the
            // screen up to the top.
            AnimatedContainer(
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeInOutCubic,
              height: _moveToTop ? topInset + 56 : size.height / 2 - 44,
            ),
            KaidoseWordmark(progress: _draw, fontSize: 56),
            const SizedBox(height: 28),
            Expanded(
              child: FadeTransition(
                opacity: _form,
                child: IgnorePointer(
                  ignoring: !_moveToTop,
                  child: _buildForm(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(28, 4, 28, 28),
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthField(
              controller: _usernameController,
              label: 'Username or email',
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.username],
              onSubmitted: (_) => _passwordFocus.requestFocus(),
            ),
            const SizedBox(height: 14),
            AuthField(
              controller: _passwordController,
              focusNode: _passwordFocus,
              label: 'Password',
              obscure: true,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) => _attemptLogin(),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ForgotPasswordScreen()),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey[600],
                  padding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Forgot password?',
                    style: TextStyle(fontSize: 13.5)),
              ),
            ),
            if (_loginError.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 4, bottom: 8),
                padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline,
                        size: 18, color: Colors.red.shade400),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(_loginError,
                          style: TextStyle(
                              fontSize: 13.5, color: Colors.red.shade700)),
                    ),
                  ],
                ),
              )
            else
              const SizedBox(height: 12),
            AuthButton(
              label: 'Log in',
              loading: _isLoggingIn,
              onPressed: _attemptLogin,
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(child: Divider(color: Colors.grey[300])),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Text('or',
                      style: TextStyle(fontSize: 13, color: Colors.grey[500])),
                ),
                Expanded(child: Divider(color: Colors.grey[300])),
              ],
            ),
            const SizedBox(height: 22),
            AuthButton(
              label: 'Create account',
              secondary: true,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CreateAccount()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}