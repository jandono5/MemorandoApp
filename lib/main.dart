import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'providers/app_state.dart';
import 'screens/auth_screen.dart';
import 'screens/device_setup_screen.dart';
import 'screens/dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(
    ChangeNotifierProvider(
      create: (context) => AppState(),
      child: const MemorandoApp(),
    ),
  );
}

class MemorandoApp extends StatelessWidget {
  const MemorandoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Memorando App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: Consumer<AppState>(
        builder: (context, appState, child) {
          if (appState.isLoading) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }

          // 1. Not logged in -> Show Login/Register
          if (appState.user == null) {
            return const AuthScreen();
          }

          // 2. Logged in, but Pi serial number not linked -> Show Device Setup
          if (appState.deviceId == null) {
            return const DeviceSetupScreen();
          }

          // 3. Logged in and linked -> Show Main Dashboard
          return DashboardScreen(deviceId: appState.deviceId!);
        },
      ),
    );
  }
}