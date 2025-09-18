import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:class_rep/shared/services/auth_service.dart';
import 'package:class_rep/features/home/presentation/main_screen.dart';
import 'package:class_rep/features/onboarding/presentation/welcome_screen.dart';
import 'package:class_rep/features/onboarding/presentation/signup_screen.dart';
import 'package:class_rep/features/onboarding/presentation/login_screen.dart';
import 'package:class_rep/features/onboarding/presentation/splash_screen.dart'; // Corrected import

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // --- Supabase Initialization ---
  // IMPORTANT: You must run your app with --dart-define
  // For example:
  // flutter run -d chrome --dart-define=SUPABASE_URL=YOUR_URL --dart-define=SUPABASE_ANON_KEY=YOUR_KEY
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    runApp(
      const ConfigErrorApp(message: 'Supabase URL or Anon Key is missing.'),
    );
    return;
  }

  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);

  runApp(const ClassRepApp());
}

// Helper to access the Supabase client easily.
final supabase = Supabase.instance.client;

class ClassRepApp extends StatelessWidget {
  const ClassRepApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Class Rep',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        primaryColor: Colors.cyanAccent,
        // Add other theme properties as needed
      ),
      // The SplashScreen now handles the initial auth check.
      home: const SplashScreen(),
      routes: {
        // We can keep these routes for navigation from the WelcomeScreen
        SignupScreen.routeName: (ctx) => const SignupScreen(),
        LoginScreen.routeName: (ctx) => const LoginScreen(),
      },
    );
  }
}

// A simple widget to display configuration errors clearly.
class ConfigErrorApp extends StatelessWidget {
  final String message;
  const ConfigErrorApp({required this.message, super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'FATAL ERROR:\n\n$message\n\nPlease run your app with the required --dart-define flags.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ),
      ),
    );
  }
}
