import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';

// BioManager class with notification system and local storage - mirrors BackgroundPicManager structure
class BioManager {
  static String? _globalBioText;
  static bool _globalBold = false;
  static bool _globalItalic = false;
  static bool _globalUnderlined = false;
  static TextAlign _globalAlign = TextAlign.center; // Default to center
  static Color _globalColor = Colors.black;
  static final List<VoidCallback> _listeners = [];
  static const String _bioFileName = 'user_bio_data.json';

  // Getters
  static String? get globalBioText => _globalBioText;
  static bool get globalBold => _globalBold;
  static bool get globalItalic => _globalItalic;
  static bool get globalUnderlined => _globalUnderlined;
  static TextAlign get globalAlign => _globalAlign;
  static Color get globalColor => _globalColor;

  // Set bio with all formatting options
  static void setBio(String? text, bool bold, bool italic, bool underlined, TextAlign align, Color color) {
    print('BioManager: Setting bio to: "$text" with formatting');

    _globalBioText = text;
    _globalBold = bold;
    _globalItalic = italic;
    _globalUnderlined = underlined;
    _globalAlign = align;
    _globalColor = color;

    // Save to local storage whenever it changes
    _saveBioLocally();

    // Notify all listeners when bio changes
    print('BioManager: Notifying ${_listeners.length} listeners');
    for (var listener in _listeners) {
      try {
        listener();
      } catch (e) {
        print('Error calling listener: $e');
      }
    }
    print('BioManager: All listeners notified');
  }

  static void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  static void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  // Load bio data from local storage on app start
  static Future<void> loadBioFromStorage() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_bioFileName');

      if (await file.exists()) {
        final bioString = await file.readAsString();
        final bioData = json.decode(bioString);

        _globalBioText = bioData['text'];
        _globalBold = bioData['bold'] ?? false;
        _globalItalic = bioData['italic'] ?? false;
        _globalUnderlined = bioData['underlined'] ?? false;
        _globalAlign = _parseTextAlign(bioData['align'] ?? 'center');
        _globalColor = Color(bioData['color'] ?? Colors.black.value);

        print('Bio loaded from storage: "$_globalBioText" with formatting');
      } else {
        print('No saved bio found, using defaults');
        _globalBioText = null;
        _globalBold = false;
        _globalItalic = false;
        _globalUnderlined = false;
        _globalAlign = TextAlign.center;
        _globalColor = Colors.black;
      }

      // Notify listeners that we loaded everything
      for (var listener in _listeners) {
        try {
          listener();
        } catch (e) {
          print('Error calling listener during load: $e');
        }
      }
    } catch (e) {
      print('Error loading bio: $e');
      _globalBioText = null;
      _globalBold = false;
      _globalItalic = false;
      _globalUnderlined = false;
      _globalAlign = TextAlign.center;
      _globalColor = Colors.black;
    }
  }

  // Add the missing refreshBioFromStorage method that was being called
  static Future<void> refreshBioFromStorage() async {
    print('BioManager: Refreshing bio from storage...');
    await loadBioFromStorage();
  }

  // Save bio data to local storage
  static Future<void> _saveBioLocally() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_bioFileName');

      final bioData = {
        'text': _globalBioText,
        'bold': _globalBold,
        'italic': _globalItalic,
        'underlined': _globalUnderlined,
        'align': _globalAlign.toString().split('.').last,
        'color': _globalColor.value,
      };

      await file.writeAsString(json.encode(bioData));
      print('Bio saved to storage: $bioData');
    } catch (e) {
      print('Error saving bio: $e');
    }
  }

  // Helper method to parse TextAlign from string
  static TextAlign _parseTextAlign(String alignString) {
    switch (alignString) {
      case 'left':
        return TextAlign.left;
      case 'right':
        return TextAlign.right;
      case 'center':
      default:
        return TextAlign.center;
    }
  }

  // Force refresh the current bio (useful for debugging)
  static Future<void> forceRefresh() async {
    print('Force refreshing bio...');
    await loadBioFromStorage();
  }

  // Get the stored bio data as a map (useful for API integration later)
  static Map<String, dynamic> getBioData() {
    return {
      'text': _globalBioText,
      'bold': _globalBold,
      'italic': _globalItalic,
      'underlined': _globalUnderlined,
      'align': _globalAlign.toString().split('.').last,
      'color': _globalColor.value,
    };
  }

  // Clear bio data
  static void clearBio() {
    setBio(null, false, false, false, TextAlign.center, Colors.black);
  }
}