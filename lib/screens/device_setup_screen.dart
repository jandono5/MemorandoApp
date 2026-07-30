import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import 'settings_screen.dart'; // ADDED: Import the settings screen

class DeviceSetupScreen extends StatefulWidget {
  const DeviceSetupScreen({super.key});

  @override
  State<DeviceSetupScreen> createState() => _DeviceSetupScreenState();
}

class _DeviceSetupScreenState extends State<DeviceSetupScreen> {
  final _serialController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Link Raspberry Pi'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => appState.signOut(),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter Device Serial Number',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Find the serial number from your Raspberry Pi (/sys/firmware/devicetree/base/serial-number).',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _serialController,
              decoration: const InputDecoration(
                labelText: 'Pi Serial Number',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.memory),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                // NEW ROUTING: Push to settings setup BEFORE officially linking in AppState
                if (_serialController.text.trim().isNotEmpty) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SettingsScreen(
                        deviceId: _serialController.text.trim(),
                        isSetupMode: true,
                      ),
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              child: const Text('Continue to Setup'),
            ),
          ],
        ),
      ),
    );
  }
}