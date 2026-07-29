import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';

class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  String? _currentFilePath;

  // Starts recording and returns true if successful
  Future startRecording(String deviceId, String timeOfDay) async {
    try {
      // 1. Request microphone permission
      final status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) return false;

      // 2. Ensure recorder is ready
      if (await _recorder.hasPermission()) {
        final dir = await getApplicationDocumentsDirectory();
        // Naming convention matches your Pi script exactly, just as .m4a
        _currentFilePath = '${dir.path}/${deviceId}_$timeOfDay.m4a';
        
        // Start recording in M4A (AAC) format
        await _recorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: _currentFilePath!,
        );
        return true;
      }
    } catch (e) {
      debugPrint("Recording start error: $e");
    }
    return false;
  }

  // Stops recording, uploads to Firebase, and deletes local cache
  Future stopAndUpload(String deviceId, String timeOfDay) async {
    try {
      final path = await _recorder.stop();
      
      if (path != null) {
        final file = File(path);
        // Push to root of bucket: e.g., "1000000abc_morning.m4a"
        final storageRef = FirebaseStorage.instance.ref().child('${deviceId}_$timeOfDay.m4a');
        
        await storageRef.putFile(file);
        
        // Clean up local file to save space on the carer's phone
        if (await file.exists()) {
          await file.delete();
        }
        return true;
      }
    } catch (e) {
      debugPrint("Upload error: $e");
    }
    return false;
  }
  
  // Cleanup when dashboard is closed
  void dispose() {
    _recorder.dispose();
  }
}