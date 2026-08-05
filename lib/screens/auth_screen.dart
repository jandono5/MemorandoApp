import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/app_state.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSignUp = false;
  String? _errorMessage;

  final Color _primaryGreen = Colors.green.shade800;

  Future<void> _submit() async {
    setState(() => _errorMessage = null);
    final appState = Provider.of<AppState>(context, listen: false);
    
    try {
      if (_isSignUp) {
        await appState.signUp(_emailController.text.trim(), _passwordController.text.trim());
      } else {
        await appState.signIn(_emailController.text.trim(), _passwordController.text.trim());
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    }
  }

  Future<void> _googleSignIn() async {
    setState(() => _errorMessage = null);
    final appState = Provider.of<AppState>(context, listen: false);
    
    try {
      await appState.signInWithGoogle();
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Stylized Logo
                Text(
                  'MemorAndo',
                  style: GoogleFonts.rubikSprayPaint(
                    fontSize: 48,
                    color: _primaryGreen,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isSignUp ? 'Create a Carer Account' : 'Carer Login',
                  style: TextStyle(fontSize: 18, color: Colors.grey.shade700, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 32),
                
                TextField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: 'Email', 
                    prefixIcon: const Icon(Icons.email_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _primaryGreen, width: 2),
                    ),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: 'Password', 
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _primaryGreen, width: 2),
                    ),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 24),
                
                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Text(_errorMessage!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                  ),
                  
                ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryGreen,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(_isSignUp ? 'Register' : 'Log In', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 16),
                
                Row(
                  children: [
                    Expanded(child: Divider(color: Colors.grey.shade400)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text('OR', style: TextStyle(color: Colors.grey.shade600)),
                    ),
                    Expanded(child: Divider(color: Colors.grey.shade400)),
                  ],
                ),
                const SizedBox(height: 16),

                OutlinedButton.icon(
                  onPressed: _googleSignIn,
                  icon: const Icon(Icons.g_mobiledata, size: 32),
                  label: const Text('Continue with Google', style: TextStyle(fontSize: 16)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black87,
                    minimumSize: const Size.fromHeight(50),
                    side: BorderSide(color: Colors.grey.shade400),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => setState(() => _isSignUp = !_isSignUp),
                  child: Text(
                    _isSignUp ? 'Already have an account? Log In' : 'Need an account? Register',
                    style: TextStyle(color: _primaryGreen),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}