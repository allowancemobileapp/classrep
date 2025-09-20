import 'package:class_rep/features/home/presentation/main_screen.dart';
import 'package:class_rep/features/onboarding/presentation/splash_screen.dart';
import 'package:class_rep/features/timetable/presentation/timetable_screen.dart';
import 'package:class_rep/shared/services/auth_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  if (!kIsWeb) {
    await dotenv.load(fileName: ".env");
  }

  // Get Supabase credentials
  final supabaseUrl = kIsWeb
      ? const String.fromEnvironment('SUPABASE_URL')
      : dotenv.env['SUPABASE_URL'];
  final supabaseAnonKey = kIsWeb
      ? const String.fromEnvironment('SUPABASE_ANON_KEY')
      : dotenv.env['SUPABASE_ANON_KEY'];

  if (supabaseUrl == null || supabaseAnonKey == null) {
    runApp(
      const ConfigErrorApp(
        message:
            'Supabase URL/Key not found. Make sure you have a .env file or are using --dart-define for web.',
      ),
    );
    return;
  }

  // Initialize Supabase
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);

  runApp(const ClassRepApp());
}

// Helper to access the Supabase client easily from anywhere
final supabase = Supabase.instance.client;

class ClassRepApp extends StatelessWidget {
  const ClassRepApp({super.key});

  // In your ClassRepApp widget's build method

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Class Rep',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        primaryColor: Colors.cyanAccent,
        // ... any other theme settings
      ),
      // --- ADD THESE LINES ---
      routes: {
        '/main': (context) => const MainScreen(),
        '/timetable': (context) => const TimetableScreen(),
      },
      // --- END OF ADDED LINES ---
      home: StreamBuilder<AuthState>(
        stream: AuthService.instance.authStateChanges,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              backgroundColor: Colors.black,
              body: Center(child: CircularProgressIndicator()),
            );
          }

          // Your SplashScreen will handle if the user is logged in or not
          return const SplashScreen();
        },
      ),
    );
  }
}

// A simple widget to display configuration errors cleanly
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
              message,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
