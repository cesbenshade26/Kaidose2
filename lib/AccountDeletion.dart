import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

/// "Delete account" (required by the App Store and Google Play): asks
/// twice, then the deleteAccount Cloud Function removes the account and
/// everything in it (profile, clips, stories, chats, friends, files).
class AccountDeletion {
  /// [afterDeleted] signs out locally and leaves (same as Logout).
  static Future<void> start(
      BuildContext context, Future<void> Function() afterDeleted) async {
    final first = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Delete your account?'),
        content: const Text(
          'This permanently deletes your profile, clips, Your Daily posts, '
              'Daily Bubbles, chats and friends. Posts you made inside other '
              "people's Dailies are deleted too. This can't be undone.",
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (first != true || !context.mounted) return;

    final typed = TextEditingController();
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('Are you sure?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Type DELETE to confirm.'),
              const SizedBox(height: 12),
              TextField(
                controller: typed,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) => setLocal(() {}),
                decoration: InputDecoration(
                  hintText: 'DELETE',
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            TextButton(
              onPressed: typed.text.trim().toUpperCase() == 'DELETE'
                  ? () => Navigator.pop(ctx, true)
                  : null,
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete forever'),
            ),
          ],
        ),
      ),
    );
    typed.dispose();
    if (sure != true || !context.mounted) return;

    final nav = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 14),
            Material(
              color: Colors.transparent,
              child: Text('Deleting your account…',
                  style: TextStyle(color: Colors.white, fontSize: 15)),
            ),
          ],
        ),
      ),
    );
    try {
      await FirebaseFunctions.instance
          .httpsCallable('deleteAccount',
          options: HttpsCallableOptions(timeout: const Duration(minutes: 5)))
          .call();
      nav.pop();
      await afterDeleted();
    } catch (e) {
      nav.pop();
      print('AccountDeletion: failed: $e');
      messenger.showSnackBar(SnackBar(
        content: Text("Couldn't delete your account. Try again. ($e)"),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ));
    }
  }
}