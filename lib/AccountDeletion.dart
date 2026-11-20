import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'AppColors.dart';
import 'SettingsWidgets.dart';

/// "Delete account" (required by the App Store and Google Play):
///
///   1. What gets deleted (with "Log out instead" for anyone who just
///      needs a break)
///   2. Type DELETE to confirm
///   3. A short exit survey: why are you leaving? (optional)
///   4. The deleteAccount Cloud Function removes everything. The survey
///      goes with it and is saved, without any account details, in
///      deletion_reasons for admins to read.
class AccountDeletion {
  AccountDeletion._();

  /// [afterDeleted] signs out locally and leaves (same as Log out).
  /// [logOutInstead] is offered on the first step.
  static Future<void> start(
      BuildContext context,
      Future<void> Function() afterDeleted, {
        Future<void> Function()? logOutInstead,
      }) async {
    // 1. What happens.
    final first = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kc.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete your account?',
            style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: SettingsStyle.ink)),
        content: Text(
          'This permanently deletes your profile, clips, stories, Daily '
              'Bubbles, chats and friends, plus everything you posted in '
              "Dailies. It can't be undone.\n\n"
              'Just need a break? You can log out instead and come back any time.',
          style: TextStyle(fontSize: 14.5, height: 1.4, color: kc.adapt(const Color(0xFF555A61))),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          if (logOutInstead != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'logout'),
              child: Text('Log out instead',
                  style: TextStyle(color: Colors.cyan[700])),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cancel',
                    style: TextStyle(color: SettingsStyle.ink)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'continue'),
                child: Text('Continue',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: SettingsStyle.danger)),
              ),
            ],
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (first == 'logout') {
      await logOutInstead?.call();
      return;
    }
    if (first != 'continue') return;

    // 2. Type DELETE.
    final sure = await showDialog<bool>(
      context: context,
      builder: (_) => const _TypeDeleteDialog(),
    );
    if (sure != true || !context.mounted) return;

    // 3. Why are you leaving? (optional)
    final survey = await showModalBottomSheet<_Survey>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ExitSurveySheet(),
    );
    if (survey == null || !context.mounted) return; // backed out

    // 4. Delete.
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
          .call({
        'reasons': survey.reasons.toList(),
        'other': survey.other,
      });
      nav.pop();
      await afterDeleted();
    } catch (e) {
      nav.pop();
      print('AccountDeletion: failed: $e');
      messenger.showSnackBar(SnackBar(
        content: Text("Couldn't delete your account. Try again."),
        backgroundColor: SettingsStyle.danger,
        duration: Duration(seconds: 4),
      ));
    }
  }
}

class _TypeDeleteDialog extends StatefulWidget {
  const _TypeDeleteDialog();

  @override
  State<_TypeDeleteDialog> createState() => _TypeDeleteDialogState();
}

class _TypeDeleteDialogState extends State<_TypeDeleteDialog> {
  final TextEditingController _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  bool get _ok => _typed.text.trim().toUpperCase() == 'DELETE';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: kc.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Are you sure?',
          style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: SettingsStyle.ink)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Type DELETE to confirm.',
              style: TextStyle(fontSize: 14.5, color: kc.adapt(const Color(0xFF555A61)))),
          const SizedBox(height: 12),
          TextField(
            controller: _typed,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'DELETE',
              filled: true,
              fillColor: SettingsStyle.page,
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
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancel', style: TextStyle(color: SettingsStyle.ink)),
        ),
        TextButton(
          onPressed: _ok ? () => Navigator.pop(context, true) : null,
          child: Text('Continue',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _ok ? SettingsStyle.danger : kc.grey(400))),
        ),
      ],
    );
  }
}

/// What someone said on the way out.
class _Survey {
  final Set<String> reasons;
  final String other;
  const _Survey(this.reasons, this.other);
}

class _ExitSurveySheet extends StatefulWidget {
  const _ExitSurveySheet();

  @override
  State<_ExitSurveySheet> createState() => _ExitSurveySheetState();
}

class _ExitSurveySheetState extends State<_ExitSurveySheet> {
  // key (saved) -> what they see. Keys match index.js.
  static const List<(String, String)> _reasons = [
    ('break', 'I need a break / spending too much time on it'),
    ('friends', "My friends aren't on Kaidose"),
    ('not_useful', "I don't find it useful or fun"),
    ('confusing', 'It was confusing to use'),
    ('bugs', "Something wasn't working"),
    ('privacy', "I'm worried about my privacy"),
    ('bad_experience', 'I had a bad experience with someone'),
    ('notifications', 'Too many notifications'),
    ('other_account', 'I have another account'),
    ('other', 'Something else'),
  ];

  final Set<String> _picked = {};
  final TextEditingController _other = TextEditingController();

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  void _finish({bool skip = false}) {
    Navigator.pop(
      context,
      skip
          ? const _Survey({}, '')
          : _Survey({..._picked},
          _picked.contains('other') ? _other.text.trim() : ''),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.88;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Container(
          decoration: BoxDecoration(
            color: kc.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 8, 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Before you go…',
                                style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: SettingsStyle.ink)),
                            SizedBox(height: 4),
                            Text(
                              "Why are you leaving? Pick any that fit. It's "
                                  'anonymous and helps us make Kaidose better.',
                              style: TextStyle(
                                  fontSize: 13.5,
                                  height: 1.35,
                                  color: SettingsStyle.subtle),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded,
                            color: SettingsStyle.subtle),
                        onPressed: () => Navigator.pop(context), // back out
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                    children: [
                      for (final r in _reasons)
                        CheckboxListTile(
                          value: _picked.contains(r.$1),
                          onChanged: (v) => setState(() {
                            v == true ? _picked.add(r.$1) : _picked.remove(r.$1);
                          }),
                          title: Text(r.$2,
                              style: TextStyle(
                                  fontSize: 15, color: SettingsStyle.ink)),
                          activeColor: Colors.cyan,
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                          dense: true,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      if (_picked.contains('other'))
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                          child: TextField(
                            controller: _other,
                            maxLines: 3,
                            minLines: 2,
                            maxLength: 500,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(
                              hintText: 'Tell us more (optional)',
                              filled: true,
                              fillColor: SettingsStyle.page,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _finish,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: SettingsStyle.danger,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: const Text('Delete my account',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700)),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _finish(skip: true),
                        child: Text('Skip and delete',
                            style: TextStyle(color: SettingsStyle.subtle)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}