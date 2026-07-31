import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_sign_in/google_sign_in.dart'; // REQUIRED FOR GOOGLE SIGN IN

class AppState extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseDatabase _db = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: 'https://memorando-jba-default-rtdb.europe-west1.firebasedatabase.app',
  );

  User? _user;
  String? _deviceId;
  bool _isLoading = true;
  bool _isGoogleInitialized = false;

  User? get user => _user;
  String? get deviceId => _deviceId;
  bool get isLoading => _isLoading;

  AppState() {
    _auth.authStateChanges().listen((User? user) async {
      _user = user;
      if (_user != null) {
        await _fetchDeviceId();
      } else {
        _deviceId = null;
      }
      _isLoading = false;
      notifyListeners();
    });
  }

  Future<void> _fetchDeviceId() async {
    if (_user == null) return;
    try {
      final snapshot = await _db.ref('carers/${_user!.uid}/device_id').get();
      if (snapshot.exists) {
        _deviceId = snapshot.value as String?;
        
        if (_deviceId != null) {
          await FirebaseMessaging.instance.requestPermission();
          String? token = await FirebaseMessaging.instance.getToken();
          if (token != null) {
            await _db.ref('devices/$_deviceId/fcm_token').set(token);
          }
        }
      } else {
        _deviceId = null;
      }
    } catch (e) {
      debugPrint("Error fetching device_id: $e");
    }
  }

  Future<void> linkDeviceId(String serialNumber) async {
    if (_user == null) return;
    final cleanedId = serialNumber.trim();
    
    await _db.ref('carers/${_user!.uid}').set({
      'device_id': cleanedId,
      'email': _user!.email,
    });

    final deviceRef = _db.ref('devices/$cleanedId/basic_info');
    final snapshot = await deviceRef.get();
    if (!snapshot.exists) {
      await deviceRef.set({
        'carer_name': 'Carer',
        'person_in_care': 'Loved One',
        'volume': 80,
        'voice': 'af_heart',
        'wake_up_time': 8,
        'turn_off_time': 21,
        'notifications_enabled': true,
      });
    }

    _deviceId = cleanedId;
    notifyListeners();
  }

  Future<void> signIn(String email, String password) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> signUp(String email, String password) async {
    await _auth.createUserWithEmailAndPassword(email: email, password: password);
  }

  // version 7.x.x compatible google signin
  Future<void> signInWithGoogle() async {
    try {
      final googleSignIn = GoogleSignIn.instance;
      
      // 1. Mandatory initialization in v7 (must only be called once)
      if (!_isGoogleInitialized) {
        await googleSignIn.initialize(
          serverClientId: '353479550210-mfj50be5nuddetml4iaiknb51q9vo8sg.apps.googleusercontent.com',
        );
        _isGoogleInitialized = true;
      }
      
      // 2. Trigger the new system-level Credential Manager sheet
      final GoogleSignInAccount? googleUser = await googleSignIn.authenticate();
      if (googleUser == null) return; // User canceled the sign-in

      // 3. Explicitly request scopes to generate an Access Token
      final clientAuth = await googleUser.authorizationClient.authorizeScopes([
        'email', 
        'profile'
      ]);

      // 4. Retrieve the ID token from the basic authentication object
      final googleAuth = await googleUser.authentication;
      
      // 5. Create the Firebase Credential by combining both tokens
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: clientAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // 6. Sign in to Firebase
      await _auth.signInWithCredential(credential);
    } catch (e) {
      debugPrint("Google sign-in error: $e");
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}