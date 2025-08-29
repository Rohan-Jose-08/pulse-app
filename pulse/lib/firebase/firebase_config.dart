import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_app_check/firebase_app_check.dart';

Future<void> initFirebase() async {
  // Initialize Firebase
  await Firebase.initializeApp();
  
  // Initialize Firebase App Check
  try {
    await FirebaseAppCheck.instance.activate();
  } catch (e) {
    print('Firebase App Check not available or not configured: $e');
  }
}

// Function to get the correct storage bucket reference
FirebaseStorage getStorageInstance() {
  // Use the bucket from your Firebase configuration
  return FirebaseStorage.instanceFor(
    bucket: 'pulsesocial.firebasestorage.app', // This is from your google-services.json
  );
}
