import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';

class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  
  // Exposes a stream of amplitude data (dB) updated every 100ms
  Stream<Amplitude> get amplitudeStream => _recorder.onAmplitudeChanged(const Duration(milliseconds: 100));

  // Starts recording and returns true if successful
  Future<bool> startRecording(String deviceId, String timeOfDay) async {
    try {
      final status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) return false;

      if (await _recorder.hasPermission()) {
        final dir = await getApplicationDocumentsDirectory();
        final filePath = '${dir.path}/${deviceId}_$timeOfDay.m4a';
        
        await _recorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: filePath,
        );
        return true;
      }
    } catch (e) {
      debugPrint("Recording start error: $e");
    }
    return false;
  }

  // Stops recording and returns the local file path for playback
  Future<String?> stopRecording() async {
    try {
      return await _recorder.stop();
    } catch (e) {
      debugPrint("Stop recording error: $e");
      return null;
    }
  }

  // Uploads the reviewed audio to Firebase and deletes the local cache
  Future<bool> uploadAudio(String deviceId, String timeOfDay, String localPath) async {
    try {
      final file = File(localPath);
      final storageRef = FirebaseStorage.instance.ref().child('${deviceId}_$timeOfDay.m4a');
      
      await storageRef.putFile(file);
      
      if (await file.exists()) {
        await file.delete();
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
  Future<void> deleteLocalAudio(String localPath) async {
    try {
      final file = File(localPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint("Delete error: $e");
    }
  }
  
  void dispose() {
    _recorder.dispose();
  }
}