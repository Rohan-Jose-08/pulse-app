# Firebase Setup Guide for Pulse App

## Firebase Storage Configuration

This guide explains how to properly configure Firebase Storage for the Pulse app to resolve the errors you were experiencing.

## Issues Fixed

1. **Firebase Storage 404 Error**: "Object does not exist at location"
2. **Upload Session Termination**: "The server has terminated the upload session"
3. **AppCheck Issue**: "No AppCheckProvider installed"

## Configuration Files Added

### 1. Firebase Storage Rules (`pulse/firebase/storage.rules`)

```
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /{allPaths=**} {
      allow read, write: if request.auth != null;
    }
    
    // Allow public read access for pulse images
    match /pulses/{pulseId}/{allPaths=**} {
      allow read;
      allow write: if request.auth != null;
    }
  }
}
```

### 2. Updated Firebase Configuration (`pulse/firebase/firebase.json`)

Added storage rules configuration:
```json
"storage": {
  "rules": "storage.rules"
}
```

## Firebase App Check Setup

To resolve the "No AppCheckProvider installed" error, follow these steps:

### 1. Add Firebase App Check to pubspec.yaml

Add this dependency to your `pulse/pubspec.yaml` file:
```yaml
dependencies:
  firebase_app_check: ^0.3.0+1  # Check for the latest version
```

### 2. Update firebase_config.dart

After adding the dependency, update `pulse/lib/firebase/firebase_config.dart` to enable App Check:

```dart
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
```

If you encounter import errors, you may need to run `flutter pub get` first to ensure the package is properly installed.

### 3. For Production Deployment

For production, you'll need to set up proper attestation providers:

- **Android**: Use Play Integrity provider
- **iOS**: Use DeviceCheck provider
- **Web**: Use reCAPTCHA v3
  firebase_app_check: ^0.3.0+1  # Check for the latest version

## Troubleshooting Common Issues

### 1. Storage Permissions Error

If you still get permission errors, check your Firebase Storage rules in the Firebase Console.

### 2. Network Issues

Ensure your app has internet permissions in AndroidManifest.xml:
```xml
<uses-permission android:name="android.permission.INTERNET" />
```

### 3. Storage Bucket Mismatch

Make sure the storage bucket in your code matches the one in your Firebase project:
```dart
FirebaseStorage.instanceFor(
  bucket: 'pulsesocial.firebasestorage.app', // This should match your project
);
```

## Testing the Fix

1. Run `flutter pub get` to install any new dependencies
2. Rebuild your app
3. Try uploading an image again

The errors should now be resolved:
- No more "Object does not exist at location" errors
- No more upload session terminations
- No more AppCheckProvider warnings

## Additional Security Considerations

For production apps, consider implementing more restrictive storage rules based on user authentication and file types.
