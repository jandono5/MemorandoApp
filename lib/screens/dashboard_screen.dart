import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_database/firebase_database.dart';
import '../providers/app_state.dart'; // Ensure this import is present

class DashboardScreen extends StatefulWidget {
  final String deviceId; // We now pass this directly into the screen

  const DashboardScreen({super.key, required this.deviceId});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _morningController = TextEditingController();
  final _eveningController = TextEditingController();
  late DatabaseReference _messagesRef;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _setupDatabase();
  }

  Future<void> _setupDatabase() async {
    final db = FirebaseDatabase.instanceFor(
      app: FirebaseDatabase.instance.app,
      databaseURL: 'https://memorando-jba-default-rtdb.europe-west1.firebasedatabase.app',
    );
    
    // Use widget.deviceId directly instead of calling Provider
    _messagesRef = db.ref('users/${widget.deviceId}/messages');

    final snapshot = await _messagesRef.get();
    if (snapshot.exists) {
      final data = snapshot.value as Map<dynamic, dynamic>;
      _morningController.text = data['morning_text'] ?? '';
      _eveningController.text = data['evening_text'] ?? '';
    }
    
    // Check if the widget is still on screen before calling setState
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveMessages() async {
    await _messagesRef.update({
      'morning_text': _morningController.text,
      'evening_text': _eveningController.text,
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Messages updated successfully!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Memorando Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            // Use context.read for one-off actions like button presses
            onPressed: () => context.read<AppState>().signOut(),
          )
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : Padding(
            padding: const EdgeInsets.all(16.0),
            child: ListView(
              children: [
                const Text('Morning Message', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: _morningController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'e.g., Good morning! Remember to take your pills.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                const Text('Evening Message', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: _eveningController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'e.g., Good evening! Time to lock the doors.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _saveMessages,
                  icon: const Icon(Icons.save),
                  label: const Text('Save Messages'),
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                ),
              ],
            ),
          ),
    );
  }
}