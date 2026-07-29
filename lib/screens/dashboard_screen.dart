import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_database/firebase_database.dart';
import '../providers/app_state.dart';
import '../services/audio_service.dart'; // Import the new audio service

class DashboardScreen extends StatefulWidget {
  final String deviceId;

  const DashboardScreen({super.key, required this.deviceId});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _morningController = TextEditingController();
  final _eveningController = TextEditingController();
  
  late DatabaseReference _messagesRef;
  StreamSubscription<DatabaseEvent>? _messagesSubscription;
  StreamSubscription<DatabaseEvent>? _basicInfoSubscription;
  
  final AudioService _audioService = AudioService();
  bool _isRecording = false;
  String? _recordingSlot; // Tracks which slot is currently recording ('morning', 'evening', or 'HH_MM')

  bool _isLoading = true;
  int _wakeUpTime = 8;
  int _turnOffTime = 21;

  Map<String, String> _scheduledMessages = {};
  
  final List<String> _staticKeys = [
    "morning_text", "evening_text", 
    "morning_status", "evening_status"
  ];

  @override
  void initState() {
    super.initState();
    _setupDatabase();
  }

  @override
  void dispose() {
    _messagesSubscription?.cancel();
    _basicInfoSubscription?.cancel();
    _morningController.dispose();
    _eveningController.dispose();
    _audioService.dispose(); // Clean up recorder
    super.dispose();
  }

  int _parseTime(dynamic value, int fallback) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  void _setupDatabase() {
    final db = FirebaseDatabase.instanceFor(
      app: FirebaseDatabase.instance.app,
      databaseURL: 'https://memorando-jba-default-rtdb.europe-west1.firebasedatabase.app',
    );
    
    _messagesRef = db.ref('devices/${widget.deviceId}/messages');
    final basicInfoRef = db.ref('devices/${widget.deviceId}/basic_info');

    _basicInfoSubscription = basicInfoRef.onValue.listen((event) {
      if (!mounted) return;
      final data = event.snapshot.value as Map<dynamic, dynamic>? ?? {};
      setState(() {
        _wakeUpTime = _parseTime(data['wake_up_time'], 8);
        _turnOffTime = _parseTime(data['turn_off_time'], 21);
      });
    });

    _messagesSubscription = _messagesRef.onValue.listen((event) {
      if (!mounted) return;
      final data = event.snapshot.value as Map<dynamic, dynamic>? ?? {};
      
      if (_isLoading) {
        _morningController.text = data['morning_text'] ?? '';
        _eveningController.text = data['evening_text'] ?? '';
      }

      final Map<String, String> parsedScheduled = {};
      data.forEach((key, value) {
        final stringKey = key.toString();
        if (!_staticKeys.contains(stringKey) && value is String) {
          parsedScheduled[stringKey] = value;
        }
      });

      final sortedKeys = parsedScheduled.keys.toList()..sort();
      final Map<String, String> sortedScheduled = {
        for (var k in sortedKeys) k: parsedScheduled[k]!
      };

      setState(() {
        _scheduledMessages = sortedScheduled;
        _isLoading = false;
      });
    });
  }

  Future<void> _saveDailyMessages() async {
    await _messagesRef.update({
      'morning_text': _morningController.text,
      'evening_text': _eveningController.text,
      'morning_status': 'pending', 
      'evening_status': 'pending',
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Daily text messages saved!')),
      );
    }
  }

  // --- NEW RECORDING TOGGLE LOGIC ---
  Future<void> _toggleRecording(String slot, {StateSetter? dialogSetState}) async {
    if (_isRecording) {
      // Stop recording
      if (dialogSetState != null) dialogSetState(() => _isRecording = false);
      setState(() {
        _isRecording = false;
        _recordingSlot = null;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Uploading voice message...')),
      );
      
      final success = await _audioService.stopAndUpload(widget.deviceId, slot);
      
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Voice message uploaded successfully!')),
        );
      }
    } else {
      // Start recording
      final success = await _audioService.startRecording(widget.deviceId, slot);
      if (success) {
        if (dialogSetState != null) dialogSetState(() => _isRecording = true);
        setState(() {
          _isRecording = true;
          _recordingSlot = slot;
        });
      }
    }
  }

  // Helper widget to build the microphone button
  Widget _buildRecordButton(String slot, {StateSetter? dialogSetState}) {
    final isCurrentlyRecordingThis = _isRecording && _recordingSlot == slot;
    return IconButton(
      icon: Icon(
        isCurrentlyRecordingThis ? Icons.stop_circle : Icons.mic,
        color: isCurrentlyRecordingThis ? Colors.red : Colors.deepPurple,
        size: 32,
      ),
      onPressed: () => _toggleRecording(slot, dialogSetState: dialogSetState),
    );
  }

  void _showAddScheduledMessageDialog() {
    List<String> hours = [];
    
    if (_wakeUpTime < _turnOffTime) {
      for (int i = _wakeUpTime; i < _turnOffTime; i++) hours.add(i.toString().padLeft(2, '0'));
    } else {
      for (int i = _wakeUpTime; i < 24; i++) hours.add(i.toString().padLeft(2, '0'));
      for (int i = 0; i < _turnOffTime; i++) hours.add(i.toString().padLeft(2, '0'));
    }
    
    if (hours.isEmpty) hours = ["12"]; 

    String selectedHour = hours.first;
    String selectedMinute = "00";
    final messageController = TextEditingController();

    final minutes = ['00', '05', '10', '15', '20', '25', '30', '35', '40', '45', '50', '55'];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final timeKey = "${selectedHour}_$selectedMinute";
            
            return AlertDialog(
              title: const Text('New Scheduled Message'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      DropdownButton<String>(
                        value: selectedHour,
                        items: hours.map((h) => DropdownMenuItem(value: h, child: Text(h))).toList(),
                        onChanged: (val) => setDialogState(() => selectedHour = val!),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8.0),
                        child: Text(":", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      ),
                      DropdownButton<String>(
                        value: selectedMinute,
                        items: minutes.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                        onChanged: (val) => setDialogState(() => selectedMinute = val!),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: messageController,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Text Message',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Add Record button directly in the dialog
                      _buildRecordButton(timeKey, dialogSetState: setDialogState),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('Record a voice note or type a message.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    // Save text to database (or a placeholder if they only recorded audio)
                    String textToSave = messageController.text.trim();
                    if (textToSave.isEmpty) textToSave = "[Voice message recorded]";
                    
                    await _messagesRef.child(timeKey).set(textToSave);
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('Save Event'),
                ),
              ],
            );
          }
        );
      },
    );
  }

  Future<void> _deleteScheduledMessage(String timeKey) async {
    await _messagesRef.child(timeKey).remove();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Memorando Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AppState>().signOut(),
          )
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              const Text('Daily Messages', style: TextStyle(fontSize: 20, color: Colors.deepPurple, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              
              // Morning TextField with Record Button
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _morningController,
                      maxLines: 2,
                      decoration: const InputDecoration(labelText: 'Morning Message', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildRecordButton('morning'),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // Evening TextField with Record Button
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _eveningController,
                      maxLines: 2,
                      decoration: const InputDecoration(labelText: 'Evening Message', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildRecordButton('evening'),
                ],
              ),
              
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _saveDailyMessages,
                icon: const Icon(Icons.save),
                label: const Text('Save Daily Text Messages'),
              ),
              
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24.0),
                child: Divider(thickness: 2),
              ),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Scheduled Messages', style: TextStyle(fontSize: 20, color: Colors.deepPurple, fontWeight: FontWeight.bold)),
                  IconButton(
                    onPressed: _showAddScheduledMessageDialog,
                    icon: const Icon(Icons.add_circle, color: Colors.deepPurple, size: 32),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              
              if (_scheduledMessages.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('No scheduled messages. Tap the + icon to add one.', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _scheduledMessages.length,
                  itemBuilder: (context, index) {
                    final timeKey = _scheduledMessages.keys.elementAt(index);
                    final message = _scheduledMessages[timeKey]!;
                    final displayTime = timeKey.replaceFirst('_', ':');

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8.0),
                      child: ListTile(
                        leading: const Icon(Icons.access_time),
                        title: Text(displayTime, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(message),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteScheduledMessage(timeKey),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
    );
  }
}