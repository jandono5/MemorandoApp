import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class AppState extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseDatabase _db = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: 'https://memorando-jba-default-rtdb.europe-west1.firebasedatabase.app',
  );

  User? _user;
  String? _deviceId;
  bool _isLoading = true;

  User? get user => _user;
  String? get deviceId => _deviceId;
  bool get isLoading => _isLoading;

  AppState() {
    // Listen for authentication changes (login/logout)
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

  // Fetch the Pi serial number linked to this carer's UID
  Future<void> _fetchDeviceId() async {
    if (_user == null) return;
    try {
      final snapshot = await _db.ref('carers/${_user!.uid}/device_id').get();
      if (snapshot.exists) {
        _deviceId = snapshot.value as String?;
      } else {
        _deviceId = null;
      }
    } catch (e) {
      debugPrint("Error fetching device_id: $e");
    }
  }

  // Link a Pi Serial Number to this carer's account
  Future<void> linkDeviceId(String serialNumber) async {
    if (_user == null) return;
    final cleanedId = serialNumber.trim();
    
    // 1. Save link under carer profile
    await _db.ref('carers/${_user!.uid}').set({
      'device_id': cleanedId,
      'email': _user!.email,
    });

    // 2. Ensure initial node exists under /users/{device_id} for the Pi
    final deviceRef = _db.ref('users/$cleanedId/basic_info');
    final snapshot = await deviceRef.get();
    if (!snapshot.exists) {
      await deviceRef.set({
        'carer_name': 'Carer',
        'person_in_care': 'Loved One',
        'volume': 80,
        'voice': 'af_heart',
        'wake_up_time': 8,
        'turn_off_time': 21,
      });
    }

    _deviceId = cleanedId;
    notifyListeners();
  }

  // Auth helper methods
  Future<void> signIn(String email, String password) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> signUp(String email, String password) async {
    await _auth.createUserWithEmailAndPassword(email: email, password: password);
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}