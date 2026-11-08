import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'UserManager.dart';
import 'auth_service.dart';

class EditUsernameScreen extends StatefulWidget {
  const EditUsernameScreen({Key? key}) : super(key: key);

  @override
  State<EditUsernameScreen> createState() => _EditUsernameScreenState();
}

class _EditUsernameScreenState extends State<EditUsernameScreen> {
  final TextEditingController _controller = TextEditingController();
  final AuthService _authService = AuthService();
  String _original = '';
  bool _isLoading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await UserManager.loadUsernameFromStorage();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _original = UserManager.globalUsername ?? '';
      _controller.text = _original;
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _validate(String s) {
    if (s.length < 3) return 'At least 3 characters';
    if (s.length > 20) return 'At most 20 characters';
    if (!RegExp(r'^[A-Za-z0-9_.]+$').hasMatch(s)) return 'Letters, numbers, _ and . only';
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _controller.text.trim();

    final problem = _validate(name);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    if (name == _original) {
      Navigator.of(context).pop();
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      if (await _authService.isUsernameTaken(name, exceptUid: uid)) {
        if (mounted) setState(() {
          _saving = false;
          _error = 'That username is taken. Try another.';
        });
        return;
      }

      // Claim the new name first. This is what actually guarantees nobody
      // else has it, even if they grabbed it a moment after the check above.
      final changedName =
          name.trim().toLowerCase() != _original.trim().toLowerCase();
      if (changedName) {
        try {
          await _authService.reserveUsername(name);
        } catch (_) {
          if (mounted) {
            setState(() {
              _saving = false;
              _error = 'That username is taken. Try another.';
            });
          }
          return;
        }
      }

      // Firestore is the source of truth (login, search and profiles read it)
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({'username': name}, SetOptions(merge: true));

      // Let go of the old name so someone else can use it
      if (changedName) await _authService.releaseUsername(_original);

      // Keep the local cache in sync
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('kaidose_user', name);
      await UserManager.loadUsernameFromStorage();

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save. Check your connection and try again.';
        });
      }
    }
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
        title: const Text('Username',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600, fontSize: 18)),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.cyan))
          : Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              maxLength: 20,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _save(),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: 'Username',
                hintStyle: TextStyle(color: Colors.grey[500]),
                errorText: _error,
                filled: true,
                fillColor: Colors.grey[100],
                contentPadding: const EdgeInsets.all(16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Colors.cyan, width: 1.5),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text('Letters, numbers, _ and . only. This is also what friends search for.',
                style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            const Spacer(),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyan,
                      foregroundColor: Colors.white,
                      surfaceTintColor: Colors.transparent,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _saving
                        ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Save',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}