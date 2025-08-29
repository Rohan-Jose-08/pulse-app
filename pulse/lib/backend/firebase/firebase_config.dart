import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

Future initFirebase() async {
  if (kIsWeb) {
    await Firebase.initializeApp(
        options: FirebaseOptions(
            apiKey: "AIzaSyCpLgY_LbfWJ47olqB61c23YT8eVaH0DFk",
            authDomain: "pulsesocial.firebaseapp.com",
            projectId: "pulsesocial",
            storageBucket: "pulsesocial.firebasestorage.app",
            messagingSenderId: "586345699100",
            appId: "1:586345699100:web:a0cf1367373f9ab40eccd9"));
  } else {
    await Firebase.initializeApp();
  }
}
