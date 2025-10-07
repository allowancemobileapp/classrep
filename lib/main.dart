// lib/main.dart

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; // Add this import
import 'firebase_options.dart';

import 'package:class_rep/features/home/presentation/main_screen.dart';
import 'package:class_rep/features/onboarding/presentation/splash_screen.dart';
import 'package:class_rep/features/timetable/presentation/timetable_screen.dart';
import 'package:class_rep/shared/services/auth_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// import 'package:class_rep/shared/services/notification_service.dart';

// --- THEME COLORS ---
const Color darkSuedeNavy = Color(0xFF1A1B2C);
const Color lightSuedeNavy = Color(0xFF2A2C40);

// --- ADD THIS FUNCTION (Must be a top-level function) ---
// This handles notifications when the app is in the background or terminated.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint("Handling a background message: ${message.messageId}");
}
// ---------------------------------------------------------

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb) {
    await dotenv.load(fileName: ".env");
  }

  final supabaseUrl = kIsWeb
      ? const String.fromEnvironment('SUPABASE_URL')
      : dotenv.env['SUPABASE_URL'];
  final supabaseAnonKey = kIsWeb
      ? const String.fromEnvironment('SUPABASE_ANON_KEY')
      : dotenv.env['SUPABASE_ANON_KEY'];

  if (supabaseUrl == null || supabaseAnonKey == null) {
    runApp(
      const ConfigErrorApp(
        message: 'Supabase URL/Key not found. Make sure you have a .env file.',
      ),
    );
    return;
  }

  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // await NotificationService.instance.initialize();

  // --- ADD THIS BLOCK TO SET UP NOTIFICATION HANDLERS ---
  // Set the background messaging handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Listen for incoming messages when the app is in the foreground
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    debugPrint('Got a message whilst in the foreground!');
    debugPrint('Message data: ${message.data}');

    if (message.notification != null) {
      debugPrint(
          'Message also contained a notification: ${message.notification}');
      // Here you could show an in-app dialog or a snackbar.
    }
  });
  // ----------------------------------------------------

  runApp(const ClassRepApp());
}

// Helper to access the Supabase client easily from anywhere
final supabase = Supabase.instance.client;

// ... The rest of your file (ClassRepApp, ConfigErrorApp) remains exactly the same ...
class ClassRepApp extends StatelessWidget {
  const ClassRepApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Class Rep',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'LeagueSpartan',
        brightness: Brightness.dark,
        scaffoldBackgroundColor: darkSuedeNavy,
        primaryColor: Colors.cyanAccent,
        appBarTheme: const AppBarTheme(
          backgroundColor: darkSuedeNavy,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontFamily: 'LeagueSpartan',
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: darkSuedeNavy,
          selectedItemColor: Colors.cyanAccent,
          unselectedItemColor: Colors.grey,
          showSelectedLabels: true,
          showUnselectedLabels: false,
          type: BottomNavigationBarType.fixed,
        ),
      ),
      routes: {
        '/main': (context) => const MainScreen(),
        '/timetable': (context) => const TimetableScreen(),
      },
      home: StreamBuilder<AuthState>(
        stream: AuthService.instance.authStateChanges,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              backgroundColor: darkSuedeNavy,
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return const SplashScreen();
        },
      ),
    );
  }
}

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
