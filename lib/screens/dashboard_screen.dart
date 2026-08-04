import 'dart:async';
import 'dart:math'; 
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart'; 
import 'package:audioplayers/audioplayers.dart'; 
import 'package:record/record.dart';
import 'package:google_fonts/google_fonts.dart'; // NEW IMPORT
import '../providers/app_state.dart';
import '../services/audio_service.dart';
import 'settings_screen.dart';

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
  final AudioPlayer _cloudAudioPlayer = AudioPlayer(); 

  bool _isLoading = true;
  int _wakeUpTime = 8;
  int _turnOffTime = 21;
  
  String _morningStatus = 'pending';
  String _eveningStatus = 'pending';

  Map<String, String> _scheduledMessages = {};
  Set<String> _availableCloudAudio = {};
  
  final List<String> _staticKeys = [
    "morning_text", "evening_text", 
    "morning_status", "evening_status"
  ];

  final Color _primaryGreen = Colors.green.shade800;
  final Color _accentGreen = Colors.green.shade600;

  @override
  void initState() {
    super.initState();
    _setupDatabase();
    _fetchAvailableAudio(); 
  }

  @override
  void dispose() {
    _messagesSubscription?.cancel();
    _basicInfoSubscription?.cancel();
    _morningController.dispose();
    _eveningController.dispose();
    _audioService.dispose(); 
    _cloudAudioPlayer.dispose();
    super.dispose();
  }

  Widget _buildPlayedBlock(String slotTitle, String status, {required bool isMorning}) {
    bool showTomorrowButton = false;
    final currentHour = DateTime.now().hour;
    final slotKey = isMorning ? 'morning' : 'evening';
    final controller = isMorning ? _morningController : _eveningController;

    if (isMorning && currentHour >= 17) {
      showTomorrowButton = true;
    } else if (!isMorning && currentHour >= _turnOffTime) {
      showTomorrowButton = true;
    }

    String buttonText = 'Schedule Tomorrow\'s Message';
    bool hasTomorrowContent = _availableCloudAudio.contains('${widget.deviceId}_$slotKey.m4a') || controller.text.isNotEmpty;
    if (hasTomorrowContent) {
      buttonText = 'View/Edit Tomorrow\'s Message';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _primaryGreen,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            '$slotTitle Message $status', 
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          if (showTomorrowButton) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: Icon(hasTomorrowContent ? Icons.visibility : Icons.edit_calendar, color: _primaryGreen),
              label: Text(buttonText),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: _primaryGreen,
              ),
              onPressed: () {
                _showTomorrowDialog(slotTitle, isMorning);
              },
            )
          ]
        ],
      ),
    );
  }

  void _showTomorrowDialog(String slotTitle, bool isMorning) {
    final slotKey = isMorning ? 'morning' : 'evening';
    final mainController = isMorning ? _morningController : _eveningController;
    final tempController = TextEditingController(text: mainController.text);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final hasCloudAudio = _availableCloudAudio.contains('${widget.deviceId}_$slotKey.m4a');

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text("Tomorrow's $slotTitle Message", style: TextStyle(color: _primaryGreen, fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Because the status resets at midnight, any text/audio you upload now will be primed and ready for tomorrow.", 
                    style: TextStyle(fontSize: 12, color: Colors.grey)
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: hasCloudAudio
                          ? _buildDisabledAudioBox()
                          : TextField(
                              controller: tempController,
                              maxLines: 2,
                              maxLength: 250,
                              decoration: InputDecoration(
                                hintText: isMorning 
                                    ? "You do not have anything on today - you can take the day to relax!"
                                    : "There's nothing for you to do tonight. Relax and have a lovely night's sleep!",
                                hintMaxLines: 2,
                                labelText: 'Text Message',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: _primaryGreen, width: 2),
                                ),
                              ),
                            ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        children: [
                          if (!hasCloudAudio)
                            IconButton(
                              icon: Icon(Icons.mic, color: _primaryGreen, size: 28),
                              tooltip: "Record Audio",
                              onPressed: () async {
                                bool uploaded = await _recordAudioFlow(slotKey);
                                if (uploaded) {
                                  await _messagesRef.child('${slotKey}_text').set("[Voice message recorded]");
                                  setDialogState(() {}); 
                                }
                              },
                            ),
                          if (hasCloudAudio) ...[
                            IconButton(
                              icon: Icon(Icons.play_circle_outline, color: _accentGreen, size: 28),
                              tooltip: 'Play Cloud Audio',
                              onPressed: () => _playCloudMessage(slotKey),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 28),
                              tooltip: 'Delete Voice Recording',
                              onPressed: () async {
                                await _deleteCloudAudio(slotKey);
                                setDialogState(() {
                                  tempController.text = ""; 
                                });
                              },
                            ),
                          ]
                        ],
                      )
                    ],
                  ),
                ],
              ),
              actions: [
                 TextButton(
                   onPressed: () => Navigator.pop(context), 
                   child: Text("Cancel", style: TextStyle(color: Colors.grey.shade700))
                 ),
                 ElevatedButton(
                   style: ElevatedButton.styleFrom(backgroundColor: _primaryGreen, foregroundColor: Colors.white),
                   onPressed: () async {
                     if (!hasCloudAudio) {
                       await _messagesRef.update({
                         '${slotKey}_text': tempController.text.trim(),
                       });
                     }
                     if (context.mounted) Navigator.pop(context);
                     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Scheduled for tomorrow!')));
                   },
                   child: const Text("Save Content"),
                 )
              ],
            );
          }
        );
      }
    );
  }

  Future<void> _fetchAvailableAudio() async {
    try {
      final result = await FirebaseStorage.instance.ref().listAll();
      if (!mounted) return;
      
      setState(() {
        _availableCloudAudio = result.items
            .where((ref) => ref.name.startsWith(widget.deviceId))
            .map((ref) => ref.name)
            .toSet();
      });
    } catch (e) {
      debugPrint("Error fetching storage list: $e");
    }
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
      } else {
        if (!FocusScope.of(context).hasPrimaryFocus) {
          _morningController.text = data['morning_text'] ?? '';
          _eveningController.text = data['evening_text'] ?? '';
        }
      }

      _morningStatus = data['morning_status']?.toString() ?? 'pending';
      _eveningStatus = data['evening_status']?.toString() ?? 'pending';

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
    Map<String, dynamic> updates = {
      'morning_text': _morningController.text,
      'evening_text': _eveningController.text,
    };

    if (!_morningStatus.startsWith('Played')) updates['morning_status'] = 'pending';
    if (!_eveningStatus.startsWith('Played')) updates['evening_status'] = 'pending';

    await _messagesRef.update(updates);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text('Daily text messages saved!'), backgroundColor: _primaryGreen),
      );
    }
  }

  Future<void> _playCloudMessage(String slot) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fetching audio...'), duration: Duration(seconds: 1)),
      );
      
      await _cloudAudioPlayer.stop();

      final ref = FirebaseStorage.instance.ref().child('${widget.deviceId}_$slot.m4a');
      final url = await ref.getDownloadURL();
      
      await _cloudAudioPlayer.play(UrlSource(url));
    } catch (e) {
      debugPrint("Error playing cloud audio: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to play audio.'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteCloudAudio(String slot) async {
    final fileName = '${widget.deviceId}_$slot.m4a';
    try {
      await FirebaseStorage.instance.ref().child(fileName).delete();
      setState(() {
        _availableCloudAudio.remove(fileName);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Voice recording deleted.'), backgroundColor: Colors.grey),
        );
      }
    } catch (e) {
      debugPrint("Error deleting cloud audio: $e");
    }
  }

  Future<bool> _recordAudioFlow(String slot) async {
    bool hasStarted = await _audioService.startRecording(widget.deviceId, slot);
    if (!hasStarted) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not start recording.')));
      return false;
    }

    if (!mounted) return false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        bool isRecording = true;
        String? localPath;
        final AudioPlayer previewPlayer = AudioPlayer();

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text(isRecording ? 'Recording Voice Note...' : 'Review Recording'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isRecording) ...[
                    Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: AudioVisualizer(amplitudeStream: _audioService.amplitudeStream.cast()),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop Recording'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red, 
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)
                      ),
                      onPressed: () async {
                        final path = await _audioService.stopRecording();
                        setDialogState(() {
                          isRecording = false;
                          localPath = path;
                        });
                      },
                    )
                  ] else ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          icon: Icon(Icons.play_circle_fill, size: 48, color: _primaryGreen),
                          onPressed: () async {
                            if (localPath != null) await previewPlayer.play(DeviceFileSource(localPath!));
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.stop_circle, size: 48, color: Colors.grey),
                          onPressed: () async => await previewPlayer.stop(),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              actions: isRecording ? null : [
                TextButton(
                  onPressed: () async {
                    await previewPlayer.dispose();
                    if (localPath != null) await _audioService.deleteLocalAudio(localPath!);
                    if (context.mounted) Navigator.pop(context, false);
                  },
                  child: const Text('Discard', style: TextStyle(color: Colors.red)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _primaryGreen, foregroundColor: Colors.white),
                  onPressed: () async {
                    await previewPlayer.dispose();

                    if (localPath != null) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Uploading voice message...')));
                      final success = await _audioService.uploadAudio(widget.deviceId, slot, localPath!);
                      
                      if (mounted) {
                        if (success) {
                           setState(() {
                             _availableCloudAudio.add('${widget.deviceId}_$slot.m4a');
                           });
                           ScaffoldMessenger.of(context).showSnackBar(
                             SnackBar(content: const Text('Voice message saved!'), backgroundColor: _accentGreen),
                           );
                           Navigator.pop(context, true);
                        } else {
                           ScaffoldMessenger.of(context).showSnackBar(
                             const SnackBar(content: Text('Failed to upload.'), backgroundColor: Colors.red),
                           );
                           Navigator.pop(context, false);
                        }
                      }
                    } else {
                      Navigator.pop(context, false);
                    }
                  },
                  child: const Text('Upload & Save'),
                ),
              ],
            );
          },
        );
      },
    );
    
    return result ?? false;
  }

  Widget _buildDisabledAudioBox() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          const Icon(Icons.mic, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Audio recording has been uploaded',
              style: TextStyle(color: Colors.grey.shade700, fontStyle: FontStyle.italic),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _showScheduledMessageDialog({String? existingTimeKey, String? existingMessage}) {
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

    if (existingTimeKey != null) {
      final parts = existingTimeKey.split('_');
      if (parts.length == 2 && hours.contains(parts[0])) {
        selectedHour = parts[0];
        selectedMinute = parts[1];
      }
    }

    final messageController = TextEditingController();
    if (existingMessage != null) {
      messageController.text = existingMessage == "[Voice message recorded]" ? "" : existingMessage;
    }

    final minutes = ['00', '05', '10', '15', '20', '25', '30', '35', '40', '45', '50', '55'];

    String? currentAudioLocation = (existingTimeKey != null && _availableCloudAudio.contains('${widget.deviceId}_$existingTimeKey.m4a'))
        ? existingTimeKey
        : null;
    
    bool isExistingTTS = existingTimeKey != null && currentAudioLocation == null;
    bool isExistingAudio = existingTimeKey != null && currentAudioLocation != null;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final currentTimeKey = "${selectedHour}_$selectedMinute";
            final hasAudio = currentAudioLocation != null;
            
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text(
                existingTimeKey == null ? 'New Time-Based Message' : 'Edit Message',
                style: TextStyle(color: _primaryGreen, fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _primaryGreen.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DropdownButton<String>(
                          value: selectedHour,
                          underline: const SizedBox(),
                          items: hours.map((h) => DropdownMenuItem(value: h, child: Text(h, style: const TextStyle(fontSize: 20)))).toList(),
                          onChanged: (val) => setDialogState(() => selectedHour = val!),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8.0),
                          child: Text(":", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                        ),
                        DropdownButton<String>(
                          value: selectedMinute,
                          underline: const SizedBox(),
                          items: minutes.map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 20)))).toList(),
                          onChanged: (val) => setDialogState(() => selectedMinute = val!),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: hasAudio 
                          ? _buildDisabledAudioBox()
                          : TextField(
                              controller: messageController,
                              maxLines: 2,
                              maxLength: 250,
                              decoration: InputDecoration(
                                hintText: "Enter a custom message here...",
                                labelText: 'Text Message',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: _primaryGreen, width: 2),
                                ),
                              ),
                            ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        children: [
                          if (!hasAudio && !isExistingTTS)
                            IconButton(
                              icon: Icon(Icons.mic, color: _primaryGreen),
                              tooltip: "Record Audio",
                              onPressed: () async {
                                bool uploaded = await _recordAudioFlow(currentTimeKey);
                                
                                if (uploaded) {
                                  if (existingTimeKey != null && existingTimeKey != currentTimeKey) {
                                    await _messagesRef.child(existingTimeKey).remove();
                                    await _messagesRef.child('${existingTimeKey}_audio_trigger').remove();
                                  }
                                  
                                  await _messagesRef.child(currentTimeKey).set("[Voice message recorded]");
                                  
                                  if (context.mounted) Navigator.pop(context);
                                } 
                              },
                            ),
                          if (hasAudio) ...[
                            IconButton(
                              icon: Icon(Icons.play_circle_outline, color: _accentGreen),
                              tooltip: "Play Cloud Audio",
                              onPressed: () => _playCloudMessage(currentAudioLocation!),
                            ),
                            if (!isExistingAudio)
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                tooltip: "Delete Voice Note",
                                onPressed: () async {
                                  await _deleteCloudAudio(currentAudioLocation!);
                                  setDialogState(() {
                                    currentAudioLocation = null;
                                    messageController.text = ""; 
                                  });
                                },
                              ),
                          ]
                        ],
                      )
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isExistingTTS 
                      ? 'Edit your text message below.' 
                      : 'Record a voice note or type a message.', 
                    style: const TextStyle(fontSize: 12, color: Colors.grey)
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel', style: TextStyle(color: Colors.grey.shade700)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _primaryGreen, foregroundColor: Colors.white),
                  onPressed: () async {
                    String textToSave = messageController.text.trim();
                    if (hasAudio) textToSave = "[Voice message recorded]";
                    
                    if (existingTimeKey != null && existingTimeKey != currentTimeKey) {
                      await _messagesRef.child(existingTimeKey).remove();
                    }
                    
                    if (hasAudio && currentAudioLocation != currentTimeKey) {
                      try {
                        final oldFileName = '${widget.deviceId}_$currentAudioLocation.m4a';
                        final newFileName = '${widget.deviceId}_$currentTimeKey.m4a';
                        
                        final oldRef = FirebaseStorage.instance.ref().child(oldFileName);
                        final newRef = FirebaseStorage.instance.ref().child(newFileName);
                        
                        final data = await oldRef.getData();
                        if (data != null) {
                          await newRef.putData(data);
                          await oldRef.delete();
                          
                          this.setState(() {
                            _availableCloudAudio.remove(oldFileName);
                            _availableCloudAudio.add(newFileName);
                          });
                        }
                      } catch (e) {
                        debugPrint("Error migrating cloud audio: $e");
                      }
                    }
                    
                    if (hasAudio) {
                      await _messagesRef.update({
                        '${currentTimeKey}_audio_trigger': DateTime.now().millisecondsSinceEpoch,
                      });
                      if (existingTimeKey != null && existingTimeKey != currentTimeKey) {
                        await _messagesRef.child('${existingTimeKey}_audio_trigger').remove();
                      }
                    }
                    
                    await _messagesRef.child(currentTimeKey).set(textToSave);
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
    await _deleteCloudAudio(timeKey);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100, 
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          'MemorAndo',
          style: GoogleFonts.rubikSprayPaint(
            fontSize: 28,
            color: Colors.white,
          ),
        ),
        backgroundColor: _primaryGreen,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Device Settings',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => SettingsScreen(deviceId: widget.deviceId))),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AppState>().signOut(),
          )
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showScheduledMessageDialog(),
        backgroundColor: _primaryGreen,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Time-Based Message'),
      ),
      body: _isLoading 
        ? Center(child: CircularProgressIndicator(color: _primaryGreen))
        : ListView(
            padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 16.0, bottom: 80.0), 
            children: [
              Text('Daily Schedule', style: TextStyle(fontSize: 20, color: _primaryGreen, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      
                      const Text(
                        'Morning',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                      ),
                      const SizedBox(height: 8),
                      // --- CONDITIONAL MORNING UI ---
                      _morningStatus.startsWith('Played')
                        ? _buildPlayedBlock('Morning', _morningStatus, isMorning: true)
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _availableCloudAudio.contains('${widget.deviceId}_morning.m4a')
                                  ? _buildDisabledAudioBox()
                                  : TextField(
                                      controller: _morningController,
                                      maxLines: 2,
                                      maxLength: 250,
                                      decoration: InputDecoration(
                                        hintText: "(Default) You do not have anything on today - you can take the day to relax!",
                                        hintMaxLines: 2,
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          borderSide: BorderSide(color: _primaryGreen, width: 2),
                                        ),
                                      ),
                                    ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                children: [
                                  if (!_availableCloudAudio.contains('${widget.deviceId}_morning.m4a'))
                                    IconButton(
                                      icon: Icon(Icons.mic, color: _primaryGreen, size: 28),
                                      onPressed: () => _recordAudioFlow('morning'),
                                    ),
                                  if (_availableCloudAudio.contains('${widget.deviceId}_morning.m4a')) ...[
                                    IconButton(
                                      icon: Icon(Icons.play_circle_outline, color: _accentGreen, size: 28),
                                      tooltip: 'Play Cloud Audio',
                                      onPressed: () => _playCloudMessage('morning'),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.red, size: 28),
                                      tooltip: 'Delete Voice Recording',
                                      onPressed: () => _deleteCloudAudio('morning'),
                                    ),
                                  ]
                                ],
                              )
                            ],
                          ),
                      
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12.0),
                        child: Divider(),
                      ),
                      
                      const Text(
                        'Evening',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                      ),
                      const SizedBox(height: 8),
                      // --- CONDITIONAL EVENING UI ---
                      _eveningStatus.startsWith('Played')
                        ? _buildPlayedBlock('Evening', _eveningStatus, isMorning: false)
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _availableCloudAudio.contains('${widget.deviceId}_evening.m4a')
                                  ? _buildDisabledAudioBox()
                                  : TextField(
                                      controller: _eveningController,
                                      maxLines: 2,
                                      maxLength: 250,
                                      decoration: InputDecoration(
                                        hintText: "(Default) There's nothing for you to do tonight. Relax and have a lovely night's sleep!",
                                        hintMaxLines: 2,
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          borderSide: BorderSide(color: _primaryGreen, width: 2),
                                        ),
                                      ),
                                    ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                children: [
                                  if (!_availableCloudAudio.contains('${widget.deviceId}_evening.m4a'))
                                    IconButton(
                                      icon: Icon(Icons.mic, color: _primaryGreen, size: 28),
                                      onPressed: () => _recordAudioFlow('evening'),
                                    ),
                                  if (_availableCloudAudio.contains('${widget.deviceId}_evening.m4a')) ...[
                                    IconButton(
                                      icon: Icon(Icons.play_circle_outline, color: _accentGreen, size: 28),
                                      tooltip: 'Play Cloud Audio',
                                      onPressed: () => _playCloudMessage('evening'),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.red, size: 28),
                                      tooltip: 'Delete Voice Recording',
                                      onPressed: () => _deleteCloudAudio('evening'),
                                    ),
                                  ]
                                ],
                              )
                            ],
                          ),
                      
                      // --- CONDITIONAL SAVE BUTTON ---
                      if (!(_morningStatus.startsWith('Played') && _eveningStatus.startsWith('Played'))) ...[
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _saveDailyMessages,
                            icon: const Icon(Icons.save),
                            label: const Text('Save Text Updates'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryGreen,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12)
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 24),

              Text('Upcoming Time-Based Messages', style: TextStyle(fontSize: 20, color: _primaryGreen, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              
              if (_scheduledMessages.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24.0),
                  alignment: Alignment.center,
                  child: Column(
                    children: [
                      Icon(Icons.event_note, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 8),
                      Text('No time-based events.', style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
                    ],
                  ),
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
                    
                    final isVoiceNote = message == "[Voice message recorded]";
                    final hasCloudAudio = _availableCloudAudio.contains('${widget.deviceId}_$timeKey.m4a');

                    return Card(
                      elevation: 1,
                      margin: const EdgeInsets.only(bottom: 8.0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      child: ListTile(
                        onTap: () => _showScheduledMessageDialog(existingTimeKey: timeKey, existingMessage: message),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _primaryGreen.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.access_time, color: _primaryGreen),
                        ),
                        title: Text(displayTime, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Row(
                            children: [
                              if (isVoiceNote) Icon(Icons.mic, size: 16, color: _accentGreen),
                              if (isVoiceNote) const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  isVoiceNote ? "Voice Message" : message, 
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: isVoiceNote ? _accentGreen : Colors.black87, fontStyle: isVoiceNote ? FontStyle.italic : FontStyle.normal),
                                )
                              ),
                            ],
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (hasCloudAudio)
                              IconButton(
                                icon: Icon(Icons.play_circle_fill, color: _accentGreen),
                                onPressed: () => _playCloudMessage(timeKey),
                              ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () => _deleteScheduledMessage(timeKey),
                            ),
                          ],
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

class AudioVisualizer extends StatefulWidget {
  final Stream<Amplitude> amplitudeStream;

  const AudioVisualizer({super.key, required this.amplitudeStream});

  @override
  State<AudioVisualizer> createState() => _AudioVisualizerState();
}

class _AudioVisualizerState extends State<AudioVisualizer> {
  double _normalizedAmplitude = 0.0;
  StreamSubscription<Amplitude>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.amplitudeStream.listen((Amplitude amp) {
      double normalized = (amp.current + 50) / 50;
      normalized = normalized.clamp(0.0, 1.0);
      
      if (mounted) {
        setState(() {
          _normalizedAmplitude = normalized;
        });
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 80,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(7, (index) {
          final randomScale = 0.3 + (Random().nextDouble() * 0.7);
          final height = 10 + (70 * _normalizedAmplitude * randomScale);
          
          return AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            margin: const EdgeInsets.symmetric(horizontal: 4.0),
            width: 12,
            height: height,
            decoration: BoxDecoration(
              color: Colors.red.shade400, 
              borderRadius: BorderRadius.circular(6),
            ),
          );
        }),
      ),
    );
  }
}