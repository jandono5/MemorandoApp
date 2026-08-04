import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http; // NEW IMPORT

class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  
  // Exposes a stream of amplitude data (dB) updated every 100ms
  Stream get amplitudeStream => _recorder.onAmplitudeChanged(const Duration(milliseconds: 100));

  // Starts recording and returns true if successful
  Future startRecording(String deviceId, String timeOfDay) async {
    try {
      // 1. Skip permission_handler on the Web, it causes issues.
      if (!kIsWeb) {
        final status = await Permission.microphone.request();
        if (status != PermissionStatus.granted) return false;
      }

      // 2. The record package has its own web-safe permission checker
      if (await _recorder.hasPermission()) {
        String path = ''; 
        AudioEncoder encoder = AudioEncoder.opus; // Web browsers prefer Opus

        // 3. Only use local paths and AAC encoding if NOT on the web
        if (!kIsWeb) {
          final dir = await getApplicationDocumentsDirectory();
          path = '${dir.path}/${deviceId}_$timeOfDay.m4a';
          encoder = AudioEncoder.aacLc;
        }
        
        await _recorder.start(
          RecordConfig(encoder: encoder),
          path: path, // On web, an empty string tells it to generate a virtual Blob URL
        );
        return true;
      }
    } catch (e) {
      debugPrint("Recording start error: $e");
    }
    return false;
  }

  // Stops recording and returns the local file path for playback
  Future stopRecording() async {
    try {
      return await _recorder.stop();
    } catch (e) {
      debugPrint("Stop recording error: $e");
      return null;
    }
  }

  // Uploads the reviewed audio to Firebase and deletes the local cache
  Future uploadAudio(String deviceId, String timeOfDay, String localPath) async {
    try {
      final storageRef = FirebaseStorage.instance.ref().child('${deviceId}_$timeOfDay.m4a');
      
      if (kIsWeb) {
        // WEB UPLOAD: Fetch the virtual blob URL data and push it as bytes
        final response = await http.get(Uri.parse(localPath));
        await storageRef.putData(response.bodyBytes, SettableMetadata(contentType: 'audio/webm'));
      } else {
        // MOBILE UPLOAD: Read the physical file from the hard drive
        final file = File(localPath);
        await storageRef.putFile(file);
        
        if (await file.exists()) {
          await file.delete();
        }
      }

      // Tell the Pi to download this file immediately
      final dbRef = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: 'https://memorando-jba-default-rtdb.europe-west1.firebasedatabase.app'
      ).ref('devices/$deviceId/messages');
      
      // Update a trigger key with a timestamp so the Pi notices a change
      await dbRef.update({
        '${timeOfDay}_audio_trigger': DateTime.now().millisecondsSinceEpoch
      });

      return true;
    } catch (e) {
      debugPrint("Upload error: $e");
      return false;
    }
  }

  // Deletes the local file if the user chooses to discard the recording
  Future deleteLocalAudio(String localPath) async {
    try {
      // Web Blob URLs are automatically deleted by the browser when closed,
      // so we only need to delete physical files on mobile.
      if (!kIsWeb) {
        final file = File(localPath);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (e) {
      debugPrint("Delete error: $e");
    }
  }
  
  void dispose() {
    _recorder.dispose();
  }
}