import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'AppColors.dart';
import 'package:image_picker/image_picker.dart';
import 'SettingsWidgets.dart';
import 'AppVersion.dart';

/// Settings → Help & About → Report a problem.
///
/// People describe what went wrong and can add a screenshot. It goes to
/// the reportProblem function (index.js), which saves the screenshot to
/// Storage, writes problem_reports/{id} and pushes the admins. Admins read
/// them in Settings → Admin → Problem reports.
class ReportProblemSheet extends StatefulWidget {
  const ReportProblemSheet({Key? key}) : super(key: key);

  static Future<void> show(BuildContext context) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const ReportProblemSheet(),
  );

  @override
  State<ReportProblemSheet> createState() => _ReportProblemSheetState();
}

class _ReportProblemSheetState extends State<ReportProblemSheet> {
  static const int _min = 10;

  final _text = TextEditingController();
  Uint8List? _shot;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _ready => _text.text.trim().length >= _min && !_sending;

  Future<void> _pickScreenshot() async {
    try {
      final x = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1400,
        imageQuality: 70,
      );
      if (x == null) return;
      final bytes = await x.readAsBytes();
      if (mounted) setState(() => _shot = bytes);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Couldn't open your photos. Check Kaidose has access.")));
    }
  }

  Future<void> _send() async {
    if (!_ready) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await FirebaseFunctions.instance
          .httpsCallable('reportProblem',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 60)))
          .call({
        'text': _text.text.trim(),
        if (_shot != null) 'screenshot': base64Encode(_shot!),
        'platform': Platform.operatingSystem,
        'osVersion': Platform.operatingSystemVersion,
        'appVersion': await AppVersion.label(),
      });
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(
          content: Text('Thanks! We got your report.')));
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      messenger.showSnackBar(SnackBar(
          content: Text(e.message ?? "Couldn't send that. Try again.")));
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      messenger.showSnackBar(
          const SnackBar(content: Text("Couldn't send that. Try again.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final shot = _shot;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: kc.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: kc.grey(300),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text('Report a problem',
                    style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: SettingsStyle.ink)),
                const SizedBox(height: 4),
                Text(
                  'Tell us what happened and what you were doing when it did.',
                  style: TextStyle(
                      fontSize: 13.5, height: 1.35, color: SettingsStyle.subtle),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _text,
                  autofocus: true,
                  minLines: 4,
                  maxLines: 8,
                  maxLength: 1500,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'e.g. My video got stuck loading in a Daily…',
                    hintStyle: TextStyle(color: kc.adapt(const Color(0xFFA5AAB2))),
                    filled: true,
                    fillColor: SettingsStyle.page,
                    counterText: '',
                    contentPadding: const EdgeInsets.all(14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (shot == null)
                  TextButton.icon(
                    onPressed: _sending ? null : _pickScreenshot,
                    icon: const Icon(Icons.add_photo_alternate_outlined, size: 20),
                    label: const Text('Add a screenshot',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.cyan[700],
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                  )
                else
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(shot,
                            width: 56, height: 56, fit: BoxFit.cover),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('Screenshot added',
                            style: TextStyle(
                                fontSize: 14.5, color: SettingsStyle.ink)),
                      ),
                      TextButton(
                        onPressed: _sending ? null : () => setState(() => _shot = null),
                        style: TextButton.styleFrom(
                            foregroundColor: SettingsStyle.subtle),
                        child: const Text('Remove'),
                      ),
                    ],
                  ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _ready ? _send : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyan,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: kc.adapt(const Color(0xFFE6E7EA)),
                      disabledForegroundColor: kc.adapt(const Color(0xFFA5AAB2)),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _sending
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                        : const Text('Send',
                        style: TextStyle(
                            fontSize: 15.5, fontWeight: FontWeight.w700)),
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

// ─── Admin: reading them ──────────────────────────────────────────────────

/// Settings → Admin → Problem reports. Newest first; open ones on top
/// of the "Fixed" ones.
class ProblemReportsScreen extends StatelessWidget {
  const ProblemReportsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SettingsStyle.page,
      appBar: AppBar(
        title: Text('Problem reports',
            style: TextStyle(
                color: SettingsStyle.ink,
                fontSize: 18,
                fontWeight: FontWeight.w700)),
        centerTitle: true,
        backgroundColor: SettingsStyle.page,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: SettingsStyle.ink),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('problem_reports')
            .orderBy('createdAt', descending: true)
            .limit(150)
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Text("Couldn't load reports",
                  style: TextStyle(color: kc.grey(600))),
            );
          }
          if (!snap.hasData) {
            return Center(
                child: CircularProgressIndicator(color: kc.adapt(const Color(0xFFB0B5BC))));
          }
          final docs = [...snap.data!.docs]..sort((a, b) {
            final ao = a.data()['status'] == 'open' ? 0 : 1;
            final bo = b.data()['status'] == 'open' ? 0 : 1;
            return ao.compareTo(bo);
          });
          if (docs.isEmpty) {
            return Center(
              child: Text('No problem reports',
                  style: TextStyle(fontSize: 15, color: SettingsStyle.subtle)),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            itemCount: docs.length,
            itemBuilder: (_, i) => _ProblemCard(doc: docs[i]),
          );
        },
      ),
    );
  }
}

class _ProblemCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _ProblemCard({required this.doc});

  String _when(Timestamp? t) {
    if (t == null) return '';
    final d = t.toDate();
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '${d.month}/${d.day} $h:${d.minute.toString().padLeft(2, '0')} '
        '${d.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    final r = doc.data();
    final open = r['status'] == 'open';
    final shot = r['screenshotUrl'] as String?;
    return Opacity(
      opacity: open ? 1 : 0.55,
      child: Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kc.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('@${r['username'] ?? 'unknown'}',
                      style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: SettingsStyle.ink)),
                ),
                Text(_when(r['createdAt'] as Timestamp?),
                    style: TextStyle(
                        fontSize: 12.5, color: SettingsStyle.subtle)),
              ],
            ),
            const SizedBox(height: 2),
            Text(
                [
                  if (r['appVersion'] != null) 'v${r['appVersion']}',
                  '${r['platform'] ?? ''} ${r['osVersion'] ?? ''}'.trim(),
                ].where((x) => x.isNotEmpty).join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                TextStyle(fontSize: 12, color: SettingsStyle.subtle)),
            const SizedBox(height: 10),
            SelectableText(r['text'] as String? ?? '',
                style: TextStyle(
                    fontSize: 14.5, height: 1.35, color: SettingsStyle.ink)),
            if (shot != null) ...[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => showDialog(
                  context: context,
                  builder: (_) => Dialog(
                    backgroundColor: Colors.black,
                    insetPadding: const EdgeInsets.all(12),
                    child: InteractiveViewer(child: Image.network(shot)),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(shot,
                      height: 140, width: 100, fit: BoxFit.cover),
                ),
              ),
            ],
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => doc.reference.update({
                  'status': open ? 'done' : 'open',
                  'doneAt': open ? FieldValue.serverTimestamp() : null,
                }),
                style: TextButton.styleFrom(foregroundColor: Colors.cyan[700]),
                child: Text(open ? 'Mark fixed' : 'Reopen',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}