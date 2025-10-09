// lib/main.dart

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'; // For background handler
import 'firebase_options.dart';

import 'package:class_rep/features/home/presentation/main_screen.dart';
import 'package:class_rep/features/onboarding/presentation/splash_screen.dart';
import 'package:class_rep/features/timetable/presentation/timetable_screen.dart';
import 'package:class_rep/shared/services/auth_service.dart';
import 'package:class_rep/shared/services/notification_service.dart'; // For showing push notifications
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// --- THEME COLORS ---
const Color darkSuedeNavy = Color(0xFF1A1B2C);
const Color lightSuedeNavy = Color(0xFF2A2C40);

// --- BACKGROUND HANDLER (Updated icon to match your notification_service) ---
// This handles notifications when the app is in the background or terminated.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Initialize local notifications for background (must be done in isolate)
  final notifications = FlutterLocalNotificationsPlugin();
  const AndroidInitializationSettings androidInit =
      AndroidInitializationSettings('@drawable/notification_icon');
  const DarwinInitializationSettings iosInit = DarwinInitializationSettings();
  const InitializationSettings initSettings =
      InitializationSettings(android: androidInit, iOS: iosInit);
  await notifications.initialize(initSettings);

  // Show the notification
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'push_channel',
    'Push Notifications',
    channelDescription: 'Notifications from Class Rep',
    importance: Importance.max,
    priority: Priority.high,
    icon: '@drawable/notification_icon',
  );
  const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();
  const NotificationDetails details = NotificationDetails(
    android: androidDetails,
    iOS: iosDetails,
  );

  await notifications.show(
    0,
    message.notification?.title ?? 'Class Rep',
    message.notification?.body ?? '',
    details,
  );

  debugPrint('Background message handled: ${message.messageId}');
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

  await NotificationService.instance.initialize();

  // --- REQUEST PERMISSION & GET TOKEN (Fixed: Use Supabase auth state change) ---
  // Request permission
  NotificationSettings settings =
      await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
    provisional: false,
    announcement: false,
    carPlay: false,
  );

  if (settings.authorizationStatus == AuthorizationStatus.authorized) {
    debugPrint('User granted permission');
  } else {
    debugPrint('User declined/denied permission');
  }

  // Get initial token
  // await FirebaseMessaging.instance.getToken();

  // Listen to Supabase auth changes to store token on sign-in
  supabase.auth.onAuthStateChange.listen((data) async {
    if (data.event == AuthChangeEvent.signedIn) {
      String? currentToken = await FirebaseMessaging.instance.getToken();
      if (currentToken != null && data.session?.user.id != null) {
        await supabase.from('users').update({'fcm_token': currentToken}).eq(
            'id', data.session!.user.id);
        debugPrint('FCM token stored for user: ${data.session!.user.id}');
      }
    }
  });

  // Listen for token refresh (using Supabase currentUser)
  FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
    final user = supabase.auth.currentUser;
    if (user != null) {
      await supabase
          .from('users')
          .update({'fcm_token': newToken}).eq('id', user.id);
      debugPrint('FCM token refreshed and stored: $newToken');
    }
  });
  // ----------------------------------------------------

  // --- SET UP NOTIFICATION HANDLERS (Updated for foreground display) ---
  // Set the background messaging handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Listen for incoming messages when the app is in the foreground
  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    debugPrint('Got a message whilst in the foreground!');
    debugPrint('Message data: ${message.data}');

    if (message.notification != null) {
      debugPrint(
          'Message also contained a notification: ${message.notification}');
      // Show as local notification
      await NotificationService.instance.showPushNotification(
        title: message.notification!.title ?? 'Class Rep',
        body: message.notification!.body ?? '',
        payload: message.data,
      );
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
        '/timetable': (context) => TimetableScreen(
              onNavigateToTab: (int tabIndex) {
                // Implement navigation logic here, e.g.:
                // Navigator.of(context).pushReplacementNamed('/main', arguments: tabIndex);
              },
            ),
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
