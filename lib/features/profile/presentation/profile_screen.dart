// lib/features/profile/presentation/profile_screen.dart

import 'package:class_rep/features/onboarding/presentation/splash_screen.dart';
import 'package:class_rep/features/profile/presentation/edit_profile_screen.dart';
import 'package:class_rep/shared/services/auth_service.dart';
import 'package:class_rep/shared/services/supabase_service.dart';
import 'package:class_rep/shared/widgets/glass_container.dart';
import 'package:flutter/material.dart';

// --- THEME COLORS ---
const Color darkSuedeNavy = Color(0xFF1A1B2C);
const Color lightSuedeNavy = Color(0xFF2A2C40);

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _userProfile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    try {
      final userId = AuthService.instance.currentUser?.id;
      if (userId == null) throw Exception("User not logged in");
      final profile = await SupabaseService.instance.fetchUserProfile(userId);
      if (mounted) {
        setState(() {
          _userProfile = profile;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error loading profile: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: darkSuedeNavy,
      appBar: AppBar(
        backgroundColor: darkSuedeNavy,
        title: const Text('Profile'),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.cyanAccent))
          : _userProfile == null
              ? const Center(
                  child: Text('Profile not found.',
                      style: TextStyle(color: Colors.white70)))
              : ListView(
                  padding: const EdgeInsets.all(16.0),
                  children: [
                    // --- Profile Header ---
                    Column(
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: lightSuedeNavy,
                          // --- THIS IS THE FIX ---
                          // It now correctly checks for an avatar_url and displays it
                          backgroundImage: _userProfile?['avatar_url'] != null
                              ? NetworkImage(_userProfile!['avatar_url'])
                              : null,
                          child: _userProfile?['avatar_url'] == null
                              ? Text(
                                  _userProfile?['display_name']
                                          ?.substring(0, 1)
                                          .toUpperCase() ??
                                      '?',
                                  style: const TextStyle(
                                      fontSize: 40, color: Colors.white),
                                )
                              : null,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _userProfile?['display_name'] ?? 'No Name',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '@${_userProfile?['username'] ?? 'nousername'}',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 16),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // --- Profile Details ---
                    GlassContainer(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _buildInfoTile(
                            icon: Icons.info_outline,
                            title: 'Bio',
                            subtitle: _userProfile?['bio'] ?? 'No bio set.',
                          ),
                          const Divider(color: lightSuedeNavy),
                          _buildInfoTile(
                            icon: Icons
                                .alternate_email, // Placeholder for Twitter icon
                            title: 'Twitter',
                            subtitle: _userProfile?['twitter_handle'] != null
                                ? '@${_userProfile!['twitter_handle']}'
                                : 'Not connected.',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // --- Action Buttons ---
                    ElevatedButton.icon(
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit Profile'),
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.black,
                        backgroundColor: Colors.cyanAccent,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            fontFamily: 'LeagueSpartan'),
                      ),
                      onPressed: () async {
                        // Navigate to the edit screen and wait for it to close
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                EditProfileScreen(profile: _userProfile!),
                          ),
                        );
                        // After returning, reload the profile data to show changes
                        _loadProfile();
                      },
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.logout),
                      label: const Text('Log Out'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            fontFamily: 'LeagueSpartan'),
                      ),
                      onPressed: () async {
                        await AuthService.instance.signOut();
                        if (mounted) {
                          // Navigate back to the splash screen to handle re-routing
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                                builder: (context) => const SplashScreen()),
                            (route) => false,
                          );
                        }
                      },
                    ),
                  ],
                ),
    );
  }

  Widget _buildInfoTile(
      {required IconData icon,
      required String title,
      required String subtitle}) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70),
      title: Text(title, style: const TextStyle(color: Colors.white70)),
      subtitle: Text(subtitle,
          style: const TextStyle(color: Colors.white, fontSize: 16)),
    );
  }
}
