// CreateAccount.dart
import 'package:flutter/material.dart';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'OpeningScreen.dart';

class CreateAccount extends StatefulWidget {
  const CreateAccount({super.key});

  @override
  State<CreateAccount> createState() => _CreateAccountState();
}

class _CreateAccountState extends State<CreateAccount> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController usernameController;
  late TextEditingController emailController;
  late TextEditingController passwordController;
  late TextEditingController confirmPasswordController;
  late TextEditingController codeController;

  late FocusNode usernameFocusNode;
  late FocusNode emailFocusNode;
  late FocusNode passwordFocusNode;
  late FocusNode confirmPasswordFocusNode;

  String? selectedYear;
  String? selectedMonth;
  String? selectedDay;

  bool showVerification = false;
  String generatedCode = '';

  List<String> years =
  List.generate(100, (index) => (DateTime.now().year - index).toString());
  List<String> months =
  List.generate(12, (index) => '${index + 1}'.padLeft(2, '0'));
  List<String> days =
  List.generate(31, (index) => '${index + 1}'.padLeft(2, '0'));

  @override
  void initState() {
    super.initState();

    usernameController = TextEditingController();
    emailController = TextEditingController();
    passwordController = TextEditingController();
    confirmPasswordController = TextEditingController();
    codeController = TextEditingController();

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
    codeController.dispose();

    usernameFocusNode.dispose();
    emailFocusNode.dispose();
    passwordFocusNode.dispose();
    confirmPasswordFocusNode.dispose();

    super.dispose();
  }

  void generateCode() {
    generatedCode = (Random().nextInt(900000) + 100000).toString();
  }

  Future<void> saveCredentials() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('kaidose_user', usernameController.text);
    await prefs.setString('kaidose_email', emailController.text);
    await prefs.setString('kaidose_pass', passwordController.text);
  }

  void validateAndProceed() {
    if (_formKey.currentState!.validate() &&
        selectedYear != null &&
        selectedMonth != null &&
        selectedDay != null) {
      generateCode();
      setState(() {
        showVerification = true;
      });
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Verification Sent'),
          content: Text(
            'Thanks for joining Kaidose! To verify your account, enter the following six-digit code in the provided box on your device:\n\n$generatedCode',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            )
          ],
        ),
      );
    }
  }

  void verifyCode() async {
    if (codeController.text == generatedCode) {
      await saveCredentials();
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
            builder: (context) => const OpeningScreen(skipAnimation: true)),
            (Route<dynamic> route) => false,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Incorrect verification code')),
      );
    }
  }

  InputDecoration customInputDecoration(String label, FocusNode focusNode) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        color: focusNode.hasFocus ? Colors.blue : Colors.black,
      ),
      enabledBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: Colors.black),
      ),
      focusedBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: Colors.blue, width: 2.0),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleTextStyle: const TextStyle(
          fontFamily: 'Slackey',
          fontSize: 25,
          fontWeight: FontWeight.bold,
          color: Colors.cyan,
        ),
        title: const Text('Create Account'),
        backgroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: showVerification
            ? Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Enter the 6-digit code sent to your email/phone:'),
            const SizedBox(height: 16),
            TextField(
              controller: codeController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Verification Code',
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: verifyCode,
              child: const Text('Verify'),
            ),
          ],
        )
            : Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextFormField(
                controller: usernameController,
                focusNode: usernameFocusNode,
                decoration: customInputDecoration('Username', usernameFocusNode),
                cursorColor: Colors.black,
                validator: (value) =>
                value == null || value.isEmpty ? 'Required' : null,
              ),
              TextFormField(

                controller: emailController,
                focusNode: emailFocusNode,
                decoration: customInputDecoration(
                    'Email or Phone Number (XXX-XXX-XXXX)', emailFocusNode),
                validator: (value) =>
                value == null || value.isEmpty ? 'Required' : null,
              ),
              TextFormField(
                controller: passwordController,
                focusNode: passwordFocusNode,
                decoration:
                customInputDecoration('Password', passwordFocusNode),
                obscureText: true,
                validator: (value) => value == null || value.length < 6
                    ? 'Min 6 chars'
                    : null,
              ),
              TextFormField(
                controller: confirmPasswordController,
                focusNode: confirmPasswordFocusNode,
                decoration: customInputDecoration(
                    'Confirm Password', confirmPasswordFocusNode),
                obscureText: true,
                validator: (value) => value != passwordController.text
                    ? 'Passwords do not match'
                    : null,
              ),
              const SizedBox(height: 16),
              const Text('Date of Birth:'),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  DropdownButton<String>(
                    dropdownColor: Colors.white,
                    hint: const Text('Year'),
                    value: selectedYear,
                    items: years
                        .map((e) =>
                        DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (value) =>
                        setState(() => selectedYear = value),
                  ),
                  DropdownButton<String>(
                    dropdownColor: Colors.white,
                    hint: const Text('Month'),
                    value: selectedMonth,
                    items: months
                        .map((e) =>
                        DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (value) =>
                        setState(() => selectedMonth = value),
                  ),
                  DropdownButton<String>(
                    dropdownColor: Colors.white,
                    hint: const Text('Day'),
                    value: selectedDay,
                    items: days
                        .map((e) =>
                        DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (value) =>
                        setState(() => selectedDay = value),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                ),
                onPressed: validateAndProceed,
                child: const Text('Next'),

              ),
            ],
          ),
        ),
      ),
    );
  }
}
