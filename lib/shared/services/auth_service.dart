import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  AuthService._();
  static final instance = AuthService._();

  final _supabase = Supabase.instance.client;

  // --- Core Auth Properties ---

  /// A stream that emits the current authentication state whenever it changes.
  /// Use this in a StreamBuilder to reactively update your UI.
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  /// The current logged-in user, or null if nobody is logged in.
  User? get currentUser => _supabase.auth.currentUser;

  // --- Auth Methods ---

  /// Signs up a new user with email and password.
  /// Supabase handles email verification automatically if enabled in your project settings.
  Future<void> signUp({
    required String email,
    required String password,
    String? username,
  }) async {
    try {
      await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          // You can pass extra data here to populate the user's row on signup.
          // The 'username' will be stored in the 'raw_user_meta_data' column.
          if (username != null) 'username': username,
        },
      );
    } on AuthException catch (e) {
      // Provide a more user-friendly error message.
      throw Exception('Sign up failed: ${e.message}');
    } catch (e) {
      throw Exception('An unknown error occurred during sign up.');
    }
  }

  /// Logs in a user with their email and password.
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    try {
      await _supabase.auth.signInWithPassword(email: email, password: password);
    } on AuthException catch (e) {
      throw Exception('Login failed: ${e.message}');
    } catch (e) {
      throw Exception('An unknown error occurred during login.');
    }
  }

  /// Signs the current user out.
  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
    } catch (e) {
      // Sign out should ideally never fail, but we catch errors just in case.
      throw Exception('Failed to sign out.');
    }
  }
}
