// lib/features/onboarding/presentation/splash_screen.dart

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
  bool _showContent = false;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _checkAuthStatusAndAnimate();
  }

  void _checkAuthStatusAndAnimate() {
    _isLoggedIn = AuthService.instance.currentUser != null;

    // After a delay, fade in the content
    Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _showContent = true);
      }
    });
  }

  void _navigateToNextScreen() {
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
        if (_isLoggedIn && _showContent) {
          _navigateToNextScreen();
        }
      },
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/images/welcome_background.png', // Make sure this path is correct
              fit: BoxFit.cover,
            ),
            Container(color: Colors.black.withOpacity(0.6)),

            // --- THIS IS THE NEW LAYOUT ---
            Padding(
              padding:
                  const EdgeInsets.only(bottom: 60.0, left: 24.0, right: 24.0),
              child: Column(
                mainAxisAlignment:
                    MainAxisAlignment.end, // Aligns content to the bottom
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Stylized App Title at the bottom
                  RichText(
                    textAlign: TextAlign.center,
                    text: const TextSpan(
                      style: TextStyle(
                          fontFamily: 'LeagueSpartan',
                          fontSize: 52,
                          fontWeight: FontWeight.bold,
                          fontStyle: FontStyle.italic,
                          shadows: [
                            Shadow(blurRadius: 10.0, color: Colors.black54)
                          ]),
                      children: <TextSpan>[
                        TextSpan(
                            text: 'Class',
                            style: TextStyle(color: Colors.white)),
                        TextSpan(
                            text: '-', style: TextStyle(color: Colors.yellow)),
                        TextSpan(
                            text: 'Rep', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 120), // Space between title and button

                  // Animated content that fades in
                  AnimatedOpacity(
                    opacity: _showContent ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 800),
                    child: _isLoggedIn
                        ? const Text(
                            'Tap anywhere to enter',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                shadows: [
                                  Shadow(blurRadius: 8.0, color: Colors.black87)
                                ]),
                          )
                        : ElevatedButton(
                            onPressed: _navigateToNextScreen,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.cyanAccent,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            child: const Text('Get Started'),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
