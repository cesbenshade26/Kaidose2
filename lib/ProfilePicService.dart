import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

class ProfilePicService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static String? get currentUid => _auth.currentUser?.uid;

  /// Compress, encode to base64, and save to Firestore
  static Future<bool> uploadProfilePic(File file) async {
    final uid = currentUid;
    if (uid == null) return false;

    try {
      // Compress to keep well under 1MB
      final compressed = await FlutterImageCompress.compressWithFile(
        file.absolute.path,
        minWidth: 300,
        minHeight: 300,
        quality: 70,
        format: CompressFormat.jpeg,
      );

      if (compressed == null) return false;

      final base64String = base64Encode(compressed);
      print('ProfilePicService: Compressed size = ${compressed.length} bytes');

      await _firestore.collection('users').doc(uid).set(
        {'profilePicBase64': base64String},
        SetOptions(merge: true),
      );

      print('ProfilePicService: Saved base64 pic for $uid');
      return true;
    } catch (e) {
      print('ProfilePicService: Upload error: $e');
      return false;
    }
  }

  /// Download base64 from Firestore and write to local cache file
  static Future<File?> downloadAndCacheProfilePic({String? uid}) async {
    final targetUid = uid ?? currentUid;
    if (targetUid == null) return null;

    try {
      final doc = await _firestore.collection('users').doc(targetUid).get();
      final base64String = doc.data()?['profilePicBase64'] as String?;
      if (base64String == null) return null;

      final bytes = base64Decode(base64String);
      final directory = await getApplicationDocumentsDirectory();
      final localFile = File('${directory.path}/profile_picture_$targetUid.jpg');
      await localFile.writeAsBytes(bytes);

      print('ProfilePicService: Cached pic for $targetUid');
      return localFile;
    } catch (e) {
      print('ProfilePicService: Download error: $e');
      return null;
    }
  }

  /// Remove base64 field from Firestore and delete local cache
  static Future<void> deleteProfilePic() async {
    final uid = currentUid;
    if (uid == null) return;

    try {
      await _firestore.collection('users').doc(uid).update({
        'profilePicBase64': FieldValue.delete(),
      });

      final directory = await getApplicationDocumentsDirectory();
      final localFile = File('${directory.path}/profile_picture_$uid.jpg');
      if (await localFile.exists()) await localFile.delete();

      print('ProfilePicService: Deleted pic for $uid');
    } catch (e) {
      print('ProfilePicService: Delete error: $e');
    }
  }
}