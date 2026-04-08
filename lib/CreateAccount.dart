import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'EmailVerificationScreen.dart'; // Import the new screen

class CreateAccount extends StatefulWidget {
  const CreateAccount({super.key});

  @override
  State<CreateAccount> createState() => _CreateAccountState();
}

class _CreateAccountState extends State<CreateAccount> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();

  late TextEditingController usernameController;
  late TextEditingController emailController;
  late TextEditingController passwordController;
  late TextEditingController confirmPasswordController;

  late FocusNode usernameFocusNode;
  late FocusNode emailFocusNode;
  late FocusNode passwordFocusNode;
  late FocusNode confirmPasswordFocusNode;

  String? selectedYear;
  String? selectedMonth;
  String? selectedDay;

  bool isLoading = false;

  List<String> years = List.generate(100, (index) => (DateTime.now().year - index).toString());
  List<String> months = List.generate(12, (index) => '${index + 1}'.padLeft(2, '0'));
  List<String> days = List.generate(31, (index) => '${index + 1}'.padLeft(2, '0'));

  @override
  void initState() {
    super.initState();
    usernameController = TextEditingController();
    emailController = TextEditingController();
    passwordController = TextEditingController();
    confirmPasswordController = TextEditingController();

    usernameFocusNode = FocusNode()..addListener(() => setState(() {}));
    emailFocusNode = FocusNode()..addListener(() => setState(() {}));
    passwordFocusNode = FocusNode()..addListener(() => setState(() {}));
    confirmPasswordFocusNode = FocusNode()..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    usernameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    usernameFocusNode.dispose();
    emailFocusNode.dispose();
    passwordFocusNode.dispose();
    confirmPasswordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleSignup() async {
    if (_formKey.currentState!.validate() &&
        selectedYear != null &&
        selectedMonth != null &&
        selectedDay != null) {

      setState(() => isLoading = true);

      // 1. Create account in Firebase & send verification link via AuthService
      final result = await _authService.signUp(
        email: emailController.text.trim(),
        password: passwordController.text,
        username: usernameController.text.trim(),
        birthYear: selectedYear!,
        birthMonth: selectedMonth!,
        birthDay: selectedDay!,
      );

      setState(() => isLoading = false);

      if (!mounted) return;

      if (result['success']) {
        // 2. Success - Go to the "Waiting Room" verification screen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const EmailVerificationScreen()),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['error']),
            backgroundColor: Colors.red,
          ),
        );
      }
    } else if (selectedYear == null || selectedMonth == null || selectedDay == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select your full date of birth')),
      );
    }
  }

  InputDecoration customInputDecoration(String label, FocusNode focusNode) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: focusNode.hasFocus ? Colors.blue : Colors.black),
      enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.black)),
      focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.blue, width: 2.0)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        titleTextStyle: const TextStyle(fontFamily: 'Slackey', fontSize: 25, fontWeight: FontWeight.bold, color: Colors.cyan),
        title: const Text('Create Account'),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.cyan))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: usernameController,
                focusNode: usernameFocusNode,
                decoration: customInputDecoration('Username', usernameFocusNode),
                validator: (value) => value == null || value.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: emailController,
                focusNode: emailFocusNode,
                decoration: customInputDecoration('Email', emailFocusNode),
                keyboardType: TextInputType.emailAddress,
                validator: (value) => (value == null || !value.contains('@')) ? 'Invalid email' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: passwordController,
                focusNode: passwordFocusNode,
                decoration: customInputDecoration('Password', passwordFocusNode),
                obscureText: true,
                validator: (value) => (value == null || value.length < 6) ? 'Min 6 chars' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: confirmPasswordController,
                focusNode: confirmPasswordFocusNode,
                decoration: customInputDecoration('Confirm Password', confirmPasswordFocusNode),
                obscureText: true,
                validator: (value) => value != passwordController.text ? 'Passwords do not match' : null,
              ),
              const SizedBox(height: 32),
              const Align(alignment: Alignment.centerLeft, child: Text('Date of Birth', style: TextStyle(fontWeight: FontWeight.bold))),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildDropdown('Year', years, selectedYear, (v) => setState(() => selectedYear = v)),
                  _buildDropdown('Month', months, selectedMonth, (v) => setState(() => selectedMonth = v)),
                  _buildDropdown('Day', days, selectedDay, (v) => setState(() => selectedDay = v)),
                ],
              ),
              const SizedBox(height: 48),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 55),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _handleSignup,
                child: const Text('Verify & Create Account', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDropdown(String hint, List<String> items, String? value, ValueChanged<String?> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(8)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          hint: Text(hint),
          value: value,
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}