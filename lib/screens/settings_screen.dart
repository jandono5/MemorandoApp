import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dashboard_screen.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

class SettingsScreen extends StatefulWidget {
  final String deviceId;
  final bool isSetupMode; // Flag to determine if this is first-time setup

  const SettingsScreen({
    super.key, 
    required this.deviceId,
    this.isSetupMode = false, // Defaults to false for normal dashboard usage
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late DatabaseReference _infoRef;
  bool _isLoading = true;

  final _carerController = TextEditingController();
  final _personController = TextEditingController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  String _selectedVoice = 'bf_isabella'; 
  double _volume = 80;
  int _wakeUpTime = 8;
  int _turnOffTime = 21;

  // Forest green theme colors matching dashboard_screen.dart
  final Color _primaryGreen = Colors.green.shade800;
  final Color _accentGreen = Colors.green.shade600;

  final Map<String, String> _availableVoices = {
    'bf_isabella': 'Sarah (British Female)',
    'bm_george': 'Barrie (British Male)',
    'af_heart': 'Janet (American Female)',
    'am_michael': 'Frank (American Male)'
  };

  @override
  void initState() {
    super.initState();
    _setupDatabaseAndFetch();
  }

  @override
  void dispose() {
    _carerController.dispose();
    _personController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  // Handles audio playback of example voice recordings
  Future<void> _playVoiceSample(String voiceKey) async {
    try {
      await _audioPlayer.play(AssetSource('audio/$voiceKey.wav'));
    } catch (e) {
      debugPrint("Error playing audio: $e");
    }
  }

  int _parseTime(dynamic value, int fallback) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  Future<void> _setupDatabaseAndFetch() async {
    final db = FirebaseDatabase.instanceFor(
      app: FirebaseDatabase.instance.app,
      databaseURL: 'https://memorando-jba-default-rtdb.europe-west1.firebasedatabase.app',
    );
    _infoRef = db.ref('devices/${widget.deviceId}/basic_info');

    final snapshot = await _infoRef.get();
    if (snapshot.exists) {
      final data = snapshot.value as Map<dynamic, dynamic>;
      setState(() {
        _carerController.text = data['carer_name'] ?? '';
        _personController.text = data['person_in_care'] ?? '';
        
        final fetchedVoice = data['voice']?.toString() ?? 'bf_isabella';
        _selectedVoice = _availableVoices.containsKey(fetchedVoice) ? fetchedVoice : 'bf_isabella';
        
        _volume = (data['volume'] ?? 80).toDouble();
        _wakeUpTime = _parseTime(data['wake_up_time'], 8);
        _turnOffTime = _parseTime(data['turn_off_time'], 21);
      });
    }
    setState(() => _isLoading = false);
  }

  Future<void> _saveSettings() async {
    setState(() => _isLoading = true);
    
    await _infoRef.update({
      'carer_name': _carerController.text.trim(),
      'person_in_care': _personController.text.trim(),
      'voice': _selectedVoice,
      'volume': _volume.toInt(),
      'wake_up_time': _wakeUpTime,
      'turn_off_time': _turnOffTime,
    });

    if (mounted) {
      if (widget.isSetupMode) {
        await context.read<AppState>().linkDeviceId(widget.deviceId);
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Device settings updated successfully!'),
            backgroundColor: _primaryGreen,
          ),
        );
        Navigator.pop(context); 
      }
    }
  }

  // Reusable decoration matching dashboard design
  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: _primaryGreen, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.grey.shade100,
        body: Center(child: CircularProgressIndicator(color: _primaryGreen)),
      );
    }

    final hours = List.generate(24, (index) => index);

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text(widget.isSetupMode ? 'Device Setup' : 'Device Settings'),
        backgroundColor: _primaryGreen,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: !widget.isSetupMode, 
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _saveSettings,
            tooltip: widget.isSetupMode ? 'Complete Setup' : 'Save Settings',
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // --- PEOPLE CARD ---
          Text(
            'People', 
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _primaryGreen)
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  TextField(
                    controller: _carerController,
                    decoration: _inputDecoration('Carer Name'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _personController,
                    decoration: _inputDecoration('Person in Care'),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 20),

          // --- AUDIO SETTINGS CARD ---
          Text(
            'Audio Settings', 
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _primaryGreen)
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          decoration: _inputDecoration('Device Voice'),
                          value: _selectedVoice,
                          items: _availableVoices.entries.map((entry) {
                            return DropdownMenuItem<String>(
                              value: entry.key,
                              child: Text(entry.value),
                            );
                          }).toList(),
                          onChanged: (val) => setState(() => _selectedVoice = val!),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(Icons.play_circle_fill, color: _accentGreen),
                        iconSize: 40,
                        tooltip: 'Listen to example',
                        onPressed: () => _playVoiceSample(_selectedVoice),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Device Volume (${_volume.toInt()}%)', 
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey.shade700)
                  ),
                  Slider(
                    value: _volume,
                    min: 0,
                    max: 100,
                    divisions: 10,
                    label: '${_volume.toInt()}%',
                    activeColor: _primaryGreen,
                    inactiveColor: Colors.grey.shade300,
                    thumbColor: _primaryGreen,
                    onChanged: (val) => setState(() => _volume = val),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // --- ACTIVE HOURS CARD ---
          Text(
            'Active Hours', 
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _primaryGreen)
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      decoration: _inputDecoration('Wake Up Time'),
                      value: _wakeUpTime,
                      items: hours.map((h) => DropdownMenuItem<int>(
                        value: h, 
                        child: Text('${h.toString().padLeft(2, '0')}:00')
                      )).toList(),
                      onChanged: (val) => setState(() => _wakeUpTime = val!),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      decoration: _inputDecoration('Turn Off Time'),
                      value: _turnOffTime,
                      items: hours.map((h) => DropdownMenuItem<int>(
                        value: h, 
                        child: Text('${h.toString().padLeft(2, '0')}:00')
                      )).toList(),
                      onChanged: (val) => setState(() => _turnOffTime = val!),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 28),

          // --- SAVE BUTTON ---
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saveSettings,
              icon: widget.isSetupMode ? const Icon(Icons.arrow_forward) : const Icon(Icons.save),
              label: Text(
                widget.isSetupMode ? 'Complete Setup' : 'Save Settings',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}