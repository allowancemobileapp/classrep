import 'dart:async';
import 'package:flutter/material.dart';
import 'package:class_rep/shared/services/auth_service.dart';
import 'package:class_rep/features/home/presentation/main_screen.dart';
import 'package:class_rep/features/onboarding/presentation/welcome_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _showButton = false;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _checkAuthStatusAndAnimate();
  }

  void _checkAuthStatusAndAnimate() {
    // Check if a user is already logged in
    _isLoggedIn = AuthService.instance.currentUser != null;

    // After 2 seconds, fade in the button or text
    Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _showButton = true);
      }
    });
  }

  void _navigateToNextScreen() {
    // If logged in, go to the main app. Otherwise, go to the welcome/login/signup flow.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) =>
            _isLoggedIn ? const MainScreen() : const WelcomeScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Only allow "tap anywhere" if the user is logged in and the prompt is visible
        if (_isLoggedIn && _showButton) {
          _navigateToNextScreen();
        }
      },
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Your background image
            Image.asset(
              'assets/images/welcome_background.png', // <-- IMPORTANT: Make sure your image is here
              fit: BoxFit.cover,
            ),
            // A dark overlay for better text visibility
            Container(color: Colors.black.withOpacity(0.5)),
            // The content that fades in
            Center(
              child: AnimatedOpacity(
                opacity: _showButton ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 500),
                child: _isLoggedIn
                    ? const Text(
                        'Tap anywhere to enter',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : ElevatedButton(
                        onPressed: _navigateToNextScreen,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyanAccent,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 40,
                            vertical: 15,
                          ),
                          textStyle: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        child: const Text('Get Started'),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
