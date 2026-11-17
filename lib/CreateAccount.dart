import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'TermsAgreement.dart';
import 'EmailVerificationScreen.dart';
import 'PhoneVerificationScreen.dart';
import 'KaidoseBrand.dart';
import 'CountryPicker.dart';
import 'LocationService.dart';

class CreateAccount extends StatefulWidget {
  const CreateAccount({super.key});

  @override
  State<CreateAccount> createState() => _CreateAccountState();
}

class _CreateAccountState extends State<CreateAccount> {
  static const int _minAge = 13;
  static const List<String> _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();

  final _usernameController = TextEditingController();
  // Email OR phone number, decided by what's typed.
  final _contactController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  String? _year;
  String? _month; // '01'..'12'
  String? _day; // '01'..'31'
  String? _dobError;

  bool _isLoading = false;

  // Phone sign-up: no password, a country code button instead.
  bool _isPhone = false;
  Country _country = Country.byIso(LocationService.instance.deviceRegion) ??
      Country.unitedStates;
  bool _countryPickedByUser = false;
  bool _locationAsked = false;

  final List<String> _years =
  List.generate(100, (i) => (DateTime.now().year - i).toString());
  final List<String> _days =
  List.generate(31, (i) => '${i + 1}'.padLeft(2, '0'));

  @override
  void initState() {
    super.initState();
    _contactController.addListener(_onContactChanged);
  }

  @override
  void dispose() {
    _contactController.removeListener(_onContactChanged);
    _usernameController.dispose();
    _contactController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  /// Switches the form between email (password fields) and phone (country
  /// code button, no password) as they type.
  void _onContactChanged() {
    final text = _contactController.text;
    final isPhone = AuthService.looksLikePhoneInput(text);
    if (isPhone != _isPhone) setState(() => _isPhone = isPhone);

    // Once it's clearly a phone number, ask for location (once) to fill in
    // the country code. Waits for a few digits so someone typing an email
    // that starts with a number isn't asked.
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '').length;
    if (isPhone && digits >= 3 && !_locationAsked) {
      _locationAsked = true;
      _detectCountry();
    }
  }

  Future<void> _detectCountry() async {
    final iso = await LocationService.instance.countryCode(ask: true);
    final c = Country.byIso(iso);
    if (!mounted || c == null || _countryPickedByUser) return;
    setState(() => _country = c);
  }

  bool get _showCountryButton =>
      _isPhone && !_contactController.text.trim().startsWith('+');

  /// null = fine, otherwise what to tell the person.
  String? _checkBirthDate() {
    if (_year == null || _month == null || _day == null) {
      return 'Please select your full date of birth';
    }
    final y = int.parse(_year!), m = int.parse(_month!), d = int.parse(_day!);
    final dob = DateTime(y, m, d);
    if (dob.month != m || dob.day != d) return 'That date doesn\'t exist';
    final now = DateTime.now();
    var age = now.year - y;
    if (now.month < m || (now.month == m && now.day < d)) age--;
    if (age < _minAge) return 'You must be at least $_minAge to use Kaidose';
    return null;
  }

  String? _contactValidator(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Enter your email or phone number';
    if (AuthService.looksLikePhoneInput(s)) {
      return AuthService.normalizePhone(s, dialCode: _country.dial) != null
          ? null
          : 'That phone number doesn\'t look right';
    }
    return AuthService.looksLikeEmail(s)
        ? null
        : 'Enter a valid email or phone number';
  }

  Future<void> _handleSignup() async {
    FocusScope.of(context).unfocus();
    final formOk = _formKey.currentState!.validate();
    final dobError = _checkBirthDate();
    setState(() => _dobError = dobError);
    if (!formOk || dobError != null) return;

    setState(() => _isLoading = true);

    final username = _usernameController.text.trim();
    if (await _authService.isUsernameTaken(username)) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('That username is taken — try another');
      return;
    }

    // Last step: read and agree to the Terms (nothing is created until
    // they do). Backing out keeps everything they typed.
    if (!mounted) return;
    setState(() => _isLoading = false);
    final agreed = await TermsAgreementScreen.open(context);
    if (!agreed || !mounted) return;
    setState(() => _isLoading = true);

    final contact = _contactController.text.trim();
    if (_isPhone) {
      final phone =
      AuthService.normalizePhone(contact, dialCode: _country.dial)!;
      await _signUpWithPhone(phone, username);
    } else {
      await _signUpWithEmail(contact, username);
    }
  }

  /// Phone: nothing is created yet. The code screen texts them, checks the
  /// code, and only then makes the account.
  Future<void> _signUpWithPhone(String phone, String username) async {
    if (!mounted) return;
    setState(() => _isLoading = false);

    final outcome = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => PhoneVerificationScreen(
          phone: phone,
          signUp: PendingPhoneSignUp(
            username: username,
            birthYear: _year!,
            birthMonth: _month!,
            birthDay: _day!,
          ),
        ),
      ),
    );
    if (!mounted) return;

    if (outcome == 'username-taken') {
      _showError('That username was just taken — try another');
    } else if (outcome == 'phone-taken') {
      _showError('That phone number already has an account. Log in instead');
    }
  }

  Future<void> _signUpWithEmail(String email, String username) async {
    final result = await _authService.signUp(
      email: email,
      password: _passwordController.text,
      username: username,
      birthYear: _year!,
      birthMonth: _month!,
      birthDay: _day!,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success'] == true) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const EmailVerificationScreen()),
      );
    } else {
      if (result['error'] == 'username-taken') {
        _showError('That username is taken — try another');
      } else {
        _showError(authErrorMessage(result['error'] as String?));
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade400,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Create your account', style: KaidoseBrand.display(30)),
                const SizedBox(height: 6),
                Text('Takes less than a minute.',
                    style: TextStyle(fontSize: 15, color: Colors.grey[600])),
                const SizedBox(height: 28),

                AuthField(
                  controller: _usernameController,
                  label: 'Username',
                  maxLength: 20,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newUsername],
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.length < 3) return 'At least 3 characters';
                    if (!RegExp(r'^[A-Za-z0-9_.]+$').hasMatch(s)) {
                      return 'Letters, numbers, _ and . only';
                    }
                    // Keeps a username from ever looking like a phone number
                    // on the login screen.
                    if (!RegExp(r'[A-Za-z]').hasMatch(s)) {
                      return 'Include at least one letter';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                AuthField(
                  controller: _contactController,
                  label: 'Email or phone number',
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [
                    AutofillHints.email,
                    AutofillHints.telephoneNumber,
                  ],
                  validator: _contactValidator,
                  prefix: _showCountryButton
                      ? CountryCodeButton(
                    country: _country,
                    onChanged: (c) => setState(() {
                      _country = c;
                      _countryPickedByUser = true;
                    }),
                  )
                      : null,
                ),

                // Email accounts get a password; phone accounts log in with
                // a texted code, so these fields fold away.
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: _isPhone
                      ? const SizedBox(width: double.infinity)
                      : Column(
                    children: [
                      const SizedBox(height: 14),
                      AuthField(
                        controller: _passwordController,
                        label: 'Password',
                        obscure: true,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.newPassword],
                        validator: (v) => (v == null || v.length < 6)
                            ? 'At least 6 characters'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      AuthField(
                        controller: _confirmController,
                        label: 'Confirm password',
                        obscure: true,
                        textInputAction: TextInputAction.done,
                        validator: (v) => v != _passwordController.text
                            ? 'Passwords don\'t match'
                            : null,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),
                const Text('Date of birth',
                    style:
                    TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Used to confirm your age. It isn\'t shown on your profile.',
                    style: TextStyle(fontSize: 13, color: Colors.grey[500])),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _dropdown('Month', _monthNames, _month, (v) {
                        setState(() {
                          _month = v;
                          _dobError = null;
                        });
                      }, values: List.generate(
                          12, (i) => '${i + 1}'.padLeft(2, '0'))),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: _dropdown('Day', _days, _day, (v) {
                        setState(() {
                          _day = v;
                          _dobError = null;
                        });
                      }),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 3,
                      child: _dropdown('Year', _years, _year, (v) {
                        setState(() {
                          _year = v;
                          _dobError = null;
                        });
                      }),
                    ),
                  ],
                ),
                if (_dobError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, left: 4),
                    child: Text(_dobError!,
                        style: TextStyle(
                            fontSize: 12.5, color: Colors.red.shade600)),
                  ),

                const SizedBox(height: 32),
                AuthButton(
                  label: _isPhone ? 'Text me a code' : 'Create account',
                  loading: _isLoading,
                  onPressed: _handleSignup,
                ),
                const SizedBox(height: 14),
                Center(
                  child: Text(
                    _isPhone
                        ? 'We\'ll text you a code to confirm your number.'
                        : 'We\'ll email you a link to confirm your address.',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey[500]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// [items] are what's shown; [values] (if given) are what's stored.
  Widget _dropdown(
      String hint,
      List<String> items,
      String? value,
      ValueChanged<String?> onChanged, {
        List<String>? values,
      }) {
    final stored = values ?? items;
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      hint: Text(hint, style: TextStyle(color: Colors.grey[600], fontSize: 15)),
      icon: Icon(Icons.keyboard_arrow_down, color: Colors.grey[500]),
      dropdownColor: Colors.white,
      borderRadius: BorderRadius.circular(14),
      style: const TextStyle(fontSize: 15, color: KaidoseBrand.ink),
      decoration: InputDecoration(
        filled: true,
        fillColor: KaidoseBrand.fieldFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      items: [
        for (var i = 0; i < items.length; i++)
          DropdownMenuItem(value: stored[i], child: Text(items[i])),
      ],
      onChanged: onChanged,
    );
  }
}