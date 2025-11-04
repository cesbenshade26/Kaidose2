import 'package:flutter/material.dart';
import 'package:contacts_service/contacts_service.dart';
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

class AccessContacts {
  static List<ContactData> _contacts = [];

  static List<ContactData> get contacts => List.unmodifiable(_contacts);
  static int get contactsCount => _contacts.length;

  /// Check if we already have contacts permission
  static Future<bool> hasPermission() async {
    try {
      final status = await Permission.contacts.status;
      return status.isGranted;
    } catch (e) {
      print('Error checking contacts permission: $e');
      return false;
    }
  }

  /// Load all contacts from the device
  /// The native iOS/Android permission dialog will appear automatically if needed
  static Future<List<ContactData>> loadContacts(BuildContext context) async {
    try {
      print('Loading contacts...');

      // Get all contacts - this will trigger the native permission dialog if needed
      Iterable<Contact> deviceContacts = await ContactsService.getContacts();

      _contacts.clear();

      for (Contact contact in deviceContacts) {
        // Extract phone number
        String? phoneNumber;
        if (contact.phones != null && contact.phones!.isNotEmpty) {
          phoneNumber = contact.phones!.first.value;
        }

        // Extract email
        String? email;
        if (contact.emails != null && contact.emails!.isNotEmpty) {
          email = contact.emails!.first.value;
        }

        _contacts.add(ContactData(
          displayName: contact.displayName,
          phoneNumber: phoneNumber,
          email: email,
        ));
      }

      print('Loaded ${_contacts.length} contacts');
      return List.unmodifiable(_contacts);
    } catch (e) {
      print('Error loading contacts: $e');

      // Show error message to user
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error accessing contacts: $e'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
      }

      return [];
    }
  }

  /// Search contacts by name
  static List<ContactData> searchContactsByName(String query) {
    if (query.isEmpty) return _contacts;

    final lowerQuery = query.toLowerCase();
    return _contacts.where((contact) {
      final name = contact.displayName?.toLowerCase() ?? '';
      return name.contains(lowerQuery);
    }).toList();
  }

  /// Search contacts by phone number
  static List<ContactData> searchContactsByPhone(String query) {
    if (query.isEmpty) return _contacts;

    return _contacts.where((contact) {
      final phone = contact.phoneNumber ?? '';
      return phone.contains(query);
    }).toList();
  }

  /// Get contacts with phone numbers only
  static List<ContactData> getContactsWithPhoneNumbers() {
    return _contacts.where((contact) => contact.phoneNumber != null).toList();
  }

  /// Get contacts with emails only
  static List<ContactData> getContactsWithEmails() {
    return _contacts.where((contact) => contact.email != null).toList();
  }

  /// Clear cached contacts
  static void clearContacts() {
    _contacts.clear();
    print('Contacts cleared');
  }
}