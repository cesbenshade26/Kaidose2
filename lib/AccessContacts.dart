import 'package:flutter/material.dart';
// import 'package:contacts_service/contacts_service.dart'; // TEMP: disabled — migrating to flutter_contacts
import 'package:permission_handler/permission_handler.dart';

class ContactData {
  final String? displayName;
  final String? phoneNumber;
  final String? email;

  ContactData({
    this.displayName,
    this.phoneNumber,
    this.email,
  });

  @override
  String toString() {
    return 'ContactData(name: $displayName, phone: $phoneNumber, email: $email)';
  }
}

// TEMP: contacts_service is disabled (crashing on launch, unmaintained,
// no Swift Package Manager support) while migrating to flutter_contacts.
// Every method below is a harmless no-op/empty-return stub so the rest of
// the app keeps compiling and running in the meantime — nothing calling
// into AccessContacts should crash, it'll just get an empty contact list
// until the real migration lands.
class AccessContacts {
  static List<ContactData> _contacts = [];

  static List<ContactData> get contacts => List.unmodifiable(_contacts);
  static int get contactsCount => _contacts.length;

  static Future<bool> hasPermission() async {
    try {
      final status = await Permission.contacts.status;
      return status.isGranted;
    } catch (e) {
      print('Error checking contacts permission: $e');
      return false;
    }
  }

  static Future<List<ContactData>> loadContacts(BuildContext context) async {
    print('AccessContacts: contacts_service temporarily disabled — returning empty list');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Contacts import is temporarily unavailable'),
          duration: Duration(seconds: 3),
          backgroundColor: Colors.orange,
        ),
      );
    }
    return [];
  }

  static List<ContactData> searchContactsByName(String query) {
    if (query.isEmpty) return _contacts;
    final lowerQuery = query.toLowerCase();
    return _contacts.where((contact) {
      final name = contact.displayName?.toLowerCase() ?? '';
      return name.contains(lowerQuery);
    }).toList();
  }

  static List<ContactData> searchContactsByPhone(String query) {
    if (query.isEmpty) return _contacts;
    return _contacts.where((contact) {
      final phone = contact.phoneNumber ?? '';
      return phone.contains(query);
    }).toList();
  }

  static List<ContactData> getContactsWithPhoneNumbers() {
    return _contacts.where((contact) => contact.phoneNumber != null).toList();
  }

  static List<ContactData> getContactsWithEmails() {
    return _contacts.where((contact) => contact.email != null).toList();
  }

  static void clearContacts() {
    _contacts.clear();
    print('Contacts cleared');
  }
}