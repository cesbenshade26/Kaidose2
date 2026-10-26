import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Shared look for the logged-out screens (opening/login, create account,
/// verify email, forgot password, onboarding) and the Kaidose wordmark.
///
/// To change the brand font, edit [KaidoseBrand.wordmark] / [KaidoseBrand.display]
/// below — nothing else needs touching.
class KaidoseBrand {
  static const Color cyan = Colors.cyan;
  static const Color ink = Color(0xFF111111);
  static final Color fieldFill = Colors.grey[100]!;

  /// The "Kaidose" logo text.
  static TextStyle wordmark(double size, {Color color = Colors.cyan}) =>
      GoogleFonts.fredoka(
        fontSize: size,
        fontWeight: FontWeight.w600,
        color: color,
        height: 1.1,
        letterSpacing: -0.5,
      );

  /// Big friendly screen titles on auth screens ("Create account").
  static TextStyle display(double size, {Color color = ink}) =>
      GoogleFonts.fredoka(
        fontSize: size,
        fontWeight: FontWeight.w600,
        color: color,
        height: 1.15,
      );

  /// Wait (briefly) for the brand font so the intro never flashes in a
  /// fallback font. Never throws and never waits more than 2 seconds.
  static Future<void> preloadFonts() async {
    try {
      await GoogleFonts.pendingFonts([
        GoogleFonts.fredoka(fontWeight: FontWeight.w600),
      ]).timeout(const Duration(seconds: 2), onTimeout: () => <void>[]);
    } catch (_) {}
  }
}

/// Remembers whether the intro animation already played during this app run,
/// so logging out (or going back to the opening screen) doesn't replay it.
class KaidoseIntro {
  static bool played = false;
}

/// "Error code" → something a person can read.
String authErrorMessage(String? code) {
  switch (code) {
    case 'invalid-credential':
    case 'wrong-password':
    case 'user-not-found':
      return 'Incorrect username/email or password';
    case 'invalid-email':
      return 'That email address doesn\'t look right';
    case 'email-already-in-use':
      return 'An account with that email already exists';
    case 'weak-password':
      return 'Choose a stronger password (at least 6 characters)';
    case 'too-many-requests':
      return 'Too many attempts. Please wait a bit and try again';
    case 'network-request-failed':
      return 'No connection. Check your internet and try again';
    case 'user-disabled':
      return 'This account has been disabled';
    case null:
    case '':
      return 'Something went wrong. Please try again';
  }
  // Already a sentence (e.g. "Username not found") → show as is.
  return code!.contains(' ') ? code : 'Something went wrong. Please try again';
}

// ─── Wordmark ────────────────────────────────────────────────────────────────

/// The logo, drawn letter by letter: each letter rises and fades in a beat
/// after the one before, then a cyan underline sweeps beneath. [progress]
/// runs 0 → 1.
class KaidoseWordmark extends StatelessWidget {
  final Animation<double> progress;
  final double fontSize;
  final bool underline;

  const KaidoseWordmark({
    Key? key,
    required this.progress,
    this.fontSize = 56,
    this.underline = true,
  }) : super(key: key);

  static const String _text = 'Kaidose';

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: progress,
      builder: (context, _) {
        final p = progress.value;
        final letters = <Widget>[];
        for (var i = 0; i < _text.length; i++) {
          final start = i * 0.07;
          final t = ((p - start) / 0.45).clamp(0.0, 1.0);
          final eased = Curves.easeOutCubic.transform(t);
          letters.add(Opacity(
            opacity: eased,
            child: Transform.translate(
              offset: Offset(0, (1 - eased) * fontSize * 0.35),
              child: Text(_text[i], style: KaidoseBrand.wordmark(fontSize)),
            ),
          ));
        }

        final line = Curves.easeInOut
            .transform(((p - 0.55) / 0.4).clamp(0.0, 1.0));

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: letters),
            if (underline) ...[
              SizedBox(height: fontSize * 0.08),
              Align(
                alignment: Alignment.center,
                child: FractionallySizedBox(
                  widthFactor: 0.34 * line,
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: KaidoseBrand.cyan,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

// ─── Form pieces ─────────────────────────────────────────────────────────────

class AuthField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;
  final TextCapitalization textCapitalization;
  final bool autocorrect;
  final int? maxLength;
  final FocusNode? focusNode;

  const AuthField({
    Key? key,
    required this.controller,
    required this.label,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.validator,
    this.onSubmitted,
    this.autofillHints,
    this.textCapitalization = TextCapitalization.none,
    this.autocorrect = false,
    this.maxLength,
    this.focusNode,
  }) : super(key: key);

  @override
  State<AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<AuthField> {
  late bool _hidden = widget.obscure;

  OutlineInputBorder _border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: color == Colors.transparent
            ? BorderSide.none
            : BorderSide(color: color, width: width),
      );

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      obscureText: _hidden,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      validator: widget.validator,
      onFieldSubmitted: widget.onSubmitted,
      autofillHints: widget.autofillHints,
      textCapitalization: widget.textCapitalization,
      autocorrect: widget.autocorrect,
      enableSuggestions: !widget.obscure,
      maxLength: widget.maxLength,
      cursorColor: KaidoseBrand.cyan,
      style: const TextStyle(fontSize: 16, color: KaidoseBrand.ink),
      decoration: InputDecoration(
        labelText: widget.label,
        counterText: '',
        labelStyle: TextStyle(color: Colors.grey[600], fontSize: 15),
        floatingLabelStyle: const TextStyle(
            color: KaidoseBrand.cyan, fontWeight: FontWeight.w600),
        filled: true,
        fillColor: KaidoseBrand.fieldFill,
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: _border(Colors.transparent),
        enabledBorder: _border(Colors.transparent),
        focusedBorder: _border(KaidoseBrand.cyan, 1.5),
        errorBorder: _border(Colors.red.shade300),
        focusedErrorBorder: _border(Colors.red.shade400, 1.5),
        suffixIcon: widget.obscure
            ? IconButton(
          icon: Icon(
            _hidden
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            size: 20,
            color: Colors.grey[500],
          ),
          onPressed: () => setState(() => _hidden = !_hidden),
        )
            : null,
      ),
    );
  }
}

class AuthButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  /// Outlined, for the less important of two buttons.
  final bool secondary;

  const AuthButton({
    Key? key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.secondary = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final shape =
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    final child = loading
        ? SizedBox(
      width: 22,
      height: 22,
      child: CircularProgressIndicator(
        strokeWidth: 2.5,
        color: secondary ? KaidoseBrand.cyan : Colors.white,
      ),
    )
        : Text(label,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700));

    return SizedBox(
      width: double.infinity,
      height: 54,
      child: secondary
          ? OutlinedButton(
        onPressed: loading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: KaidoseBrand.ink,
          side: BorderSide(color: Colors.grey.shade300, width: 1.5),
          shape: shape,
        ),
        child: child,
      )
          : ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: KaidoseBrand.cyan,
          foregroundColor: Colors.white,
          disabledBackgroundColor: KaidoseBrand.cyan.withOpacity(0.5),
          disabledForegroundColor: Colors.white,
          elevation: 0,
          shape: shape,
        ),
        child: child,
      ),
    );
  }
}

/// Round cyan icon, a title and a sentence — the top of the verify / reset
/// screens.
class AuthHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const AuthHeader({
    Key? key,
    required this.icon,
    required this.title,
    required this.subtitle,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: KaidoseBrand.cyan.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 42, color: KaidoseBrand.cyan),
        ),
        const SizedBox(height: 24),
        Text(title,
            textAlign: TextAlign.center, style: KaidoseBrand.display(26)),
        const SizedBox(height: 10),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, height: 1.4, color: Colors.grey[600]),
        ),
      ],
    );
  }
}