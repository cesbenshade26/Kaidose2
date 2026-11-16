import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';

/// One person from the phone's contacts.
class ContactData {
  final String? displayName;
  final List<String> phones; // as saved in the contact
  final List<String> emails;

  /// [phoneNumber] / [email] are the older single-value way to make one;
  /// they're folded into [phones] / [emails].
  ContactData({
    this.displayName,
    List<String> phones = const [],
    List<String> emails = const [],
    String? phoneNumber,
    String? email,
  })  : phones = [
    ...phones,
    if (phoneNumber != null && !phones.contains(phoneNumber)) phoneNumber,
  ],
        emails = [
          ...emails,
          if (email != null && !emails.contains(email)) email,
        ];

  /// First number / email (older screens show just one).
  String? get phoneNumber => phones.isEmpty ? null : phones.first;
  String? get email => emails.isEmpty ? null : emails.first;

  @override
  String toString() =>
      'ContactData(name: $displayName, phones: $phones, emails: $emails)';
}

/// A contact who has a Kaidose account.
class ContactMatch {
  final String uid;
  final String username;

  /// Their name as saved in YOUR contacts ("Mom"), if we know it.
  final String? contactName;

  const ContactMatch({
    required this.uid,
    required this.username,
    this.contactName,
  });
}

/// The phone's contacts, read with flutter_contacts (v2 API:
/// FlutterContacts.permissions + FlutterContacts.getAll).
///
/// Nothing here ever pops up the system permission prompt by surprise:
/// only [requestAccess] asks (call it from a clear "Find friends from your
/// contacts" button). Everything else just returns empty until access has
/// been given.
///
/// [findOnKaidose] checks which contacts have accounts. The numbers and
/// emails go to the matchContacts Cloud Function and only the matches come
/// back; nothing is stored.
class AccessContacts {
  static const String _askedKey = 'contacts_permission_asked';
  // (Remembers that we've asked once; the phone itself won't re-prompt.)
  static List<ContactData> _contacts = [];

  static List<ContactData> get contacts => List.unmodifiable(_contacts);
  static int get contactsCount => _contacts.length;

  static Future<bool> wasAsked() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_askedKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Full access, or iOS's "limited" (only some contacts shared).
  static bool _allowed(Object status) {
    final name = status.toString().split('.').last;
    return name == 'granted' || name == 'limited';
  }

  /// True if the user already gave access. Never shows a prompt.
  static Future<bool> hasPermission() async {
    try {
      return await FlutterContacts.permissions.has(PermissionType.read);
    } catch (e) {
      print('AccessContacts: permission check failed: $e');
      return false;
    }
  }

  /// Shows the system prompt (first time only; after a "no" the phone won't
  /// ask again and this just returns false). Returns whether access is on.
  static Future<bool> requestAccess() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_askedKey, true);
    } catch (_) {}
    try {
      final status =
      await FlutterContacts.permissions.request(PermissionType.read);
      return _allowed(status);
    } catch (e) {
      print('AccessContacts: permission request failed: $e');
      return false;
    }
  }

  /// Loads the contacts (only if access was already given; never prompts).
  /// [context] is unused; kept so older callers still compile.
  static Future<List<ContactData>> loadContacts([BuildContext? context]) async {
    if (!await hasPermission()) return [];
    try {
      final list = await FlutterContacts.getAll(
        properties: {
          ContactProperty.name,
          ContactProperty.phone,
          ContactProperty.email,
        },
      );
      _contacts = list
          .map((c) {
        final name = (c.displayName ?? '').trim();
        return ContactData(
          displayName: name.isEmpty ? null : name,
          // Raw numbers; AuthService.normalizePhone tidies them up later.
          phones: c.phones
              .map((p) => p.number.trim())
              .where((n) => n.isNotEmpty)
              .toList(),
          emails: c.emails
              .map((e) => e.address.trim())
              .where((e) => e.isNotEmpty)
              .toList(),
        );
      })
          .where((c) => c.phones.isNotEmpty || c.emails.isNotEmpty)
          .toList();
      return _contacts;
    } catch (e) {
      print('AccessContacts: load failed: $e');
      return [];
    }
  }

  /// Which of [contacts] have Kaidose accounts (yourself left out).
  static Future<List<ContactMatch>> findOnKaidose(
      List<ContactData> contacts) async {
    if (contacts.isEmpty) return [];
    final dialCode = await _myDialCode();

    // number/email -> the name it's saved under, to label matches.
    final nameFor = <String, String?>{};
    for (final c in contacts) {
      for (final raw in c.phones) {
        final n = AuthService.normalizePhone(raw, dialCode: dialCode);
        if (n != null) nameFor.putIfAbsent(n, () => c.displayName);
      }
      for (final e in c.emails) {
        nameFor.putIfAbsent(e.toLowerCase(), () => c.displayName);
      }
    }
    final phones = nameFor.keys.where((k) => k.startsWith('+')).toList();
    final emails = nameFor.keys.where((k) => k.contains('@')).toList();
    if (phones.isEmpty && emails.isEmpty) return [];

    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('matchContacts')
          .call({'phones': phones, 'emails': emails});
      final raw = (result.data as Map?)?['matches'];
      if (raw is! List) return [];
      return raw.whereType<Map>().map((m) {
        final key = '${m['key'] ?? ''}';
        return ContactMatch(
          uid: '${m['uid']}',
          username: '${m['username']}',
          contactName: nameFor[key] ?? nameFor[key.toLowerCase()],
        );
      }).toList();
    } catch (e) {
      print('AccessContacts: matching failed: $e');
      return [];
    }
  }

  /// Country code for numbers saved without one ("555 123 4567"): taken
  /// from your own number when you signed up with a phone, else US/Canada.
  static Future<String> _myDialCode() async {
    const known = [
      '353', '1', '7', '20', '27', '30', '31', '32', '33', '34', '36', '39',
      '40', '41', '43', '44', '45', '46', '47', '48', '49', '51', '52', '53',
      '54', '55', '56', '57', '58', '60', '61', '62', '63', '64', '65', '66',
      '81', '82', '84', '86', '90', '91', '92', '351', '352', '354', '358',
      '370', '371', '372', '380', '420', '421', '971', '972', '966',
    ];
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      String? phone = FirebaseAuth.instance.currentUser?.phoneNumber;
      if ((phone == null || phone.isEmpty) && uid != null) {
        final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
        phone = doc.data()?['phone'] as String?;
      }
      if (phone != null && phone.startsWith('+')) {
        final digits = phone.substring(1);
        // Longest known code that the number starts with.
        final match = known
            .where((c) => digits.startsWith(c))
            .fold<String?>(null, (best, c) =>
        best == null || c.length > best.length ? c : best);
        if (match != null) return match;
      }
    } catch (_) {}
    return '1';
  }

  // ─── Small helpers older screens use ───────────────────────────────────────

  static List<ContactData> searchContactsByName(String query) {
    if (query.isEmpty) return _contacts;
    final q = query.toLowerCase();
    return _contacts
        .where((c) => (c.displayName ?? '').toLowerCase().contains(q))
        .toList();
  }

  static List<ContactData> searchContactsByPhone(String query) {
    if (query.isEmpty) return _contacts;
    return _contacts.where((c) => c.phones.any((p) => p.contains(query))).toList();
  }

  static List<ContactData> getContactsWithPhoneNumbers() =>
      _contacts.where((c) => c.phones.isNotEmpty).toList();

  static List<ContactData> getContactsWithEmails() =>
      _contacts.where((c) => c.emails.isNotEmpty).toList();

  static void clearContacts() => _contacts = [];
}