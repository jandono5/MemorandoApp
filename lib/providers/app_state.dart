import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_sign_in/google_sign_in.dart';

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
        
        // FCM is only executed on physical mobile devices (Android/iOS)
        if (_deviceId != null && !kIsWeb) {
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

  Future<void> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        // WEB FLOW: Use Firebase's native browser popup
        // Bypasses google_sign_in package bugs on the web completely
        final googleProvider = GoogleAuthProvider();
        await _auth.signInWithPopup(googleProvider);
      } else {
        // MOBILE FLOW: google_sign_in v7.x.x
        final googleSignIn = GoogleSignIn.instance;
        
        if (!_isGoogleInitialized) {
          await googleSignIn.initialize(
            serverClientId: '353479550210-mfj50be5nuddetml4iaiknb51q9vo8sg.apps.googleusercontent.com',
          );
          _isGoogleInitialized = true;
        }
        
        final GoogleSignInAccount googleUser = await googleSignIn.authenticate();

        final clientAuth = await googleUser.authorizationClient.authorizeScopes([
          'email', 
          'profile'
        ]);

        final googleAuth = googleUser.authentication;
        
        final OAuthCredential credential = GoogleAuthProvider.credential(
          accessToken: clientAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        await _auth.signInWithCredential(credential);
      }
    } catch (e) {
      debugPrint("Google sign-in error: $e");
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}