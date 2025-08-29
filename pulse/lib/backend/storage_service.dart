import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path/path.dart' as path;

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  Future<String?> uploadImage({
    required File file,
    required String folder,
    String? fileName,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Generate unique filename if not provided
      final name = fileName ??
          '${DateTime.now().millisecondsSinceEpoch}_${path.basename(file.path)}';
      final refPath = '$folder/${user.uid}/$name';

      // Create reference
      final ref = _storage.ref(refPath);

      // Upload file
      final uploadTask = ref.putFile(file);
      final snapshot = await uploadTask;

      // Get download URL
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      print('Storage upload error: $e');
      return null;
    }
  }

  Future<bool> deleteFile(String url) async {
    try {
      final ref = _storage.refFromURL(url);
      await ref.delete();
      return true;
    } catch (e) {
      print('Storage delete error: $e');
      return false;
    }
  }

  Future<String?> uploadPulseImage(File file) async {
    return await uploadImage(
      file: file,
      folder: 'pulses',
    );
  }

  Future<String?> uploadProfileImage(File file) async {
    return await uploadImage(
      file: file,
      folder: 'profiles',
    );
  }

  Future<String?> uploadPostImage(File file) async {
    return await uploadImage(
      file: file,
      folder: 'posts',
    );
  }
}
