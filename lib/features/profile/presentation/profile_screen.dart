// lib/features/profile/presentation/profile_screen.dart

import 'package:class_rep/features/onboarding/presentation/splash_screen.dart';
import 'package:class_rep/features/profile/presentation/create_gist_screen.dart';
import 'package:class_rep/features/profile/presentation/edit_profile_screen.dart';
import 'package:class_rep/features/profile/presentation/gist_viewer_screen.dart';
import 'package:class_rep/shared/services/auth_service.dart';
import 'package:class_rep/shared/services/supabase_service.dart';
import 'package:class_rep/shared/widgets/glass_container.dart';
import 'package:class_rep/shared/widgets/gist_avatar.dart'; // Make sure this import is here
import 'package:flutter/material.dart';

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
    if (!mounted) return;
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
          const SnackBar(
            content: Text(
                'Could not load your profile. Please check your connection.'),
            backgroundColor: Colors.redAccent,
          ),
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
        automaticallyImplyLeading: false,
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
                    Column(
                      children: [
                        // --- THIS IS THE FULLY CORRECTED WIDGET ---
                        SizedBox(
                          width: 110,
                          height: 110,
                          child: Stack(
                            clipBehavior: Clip.none,
                            fit: StackFit.expand,
                            children: [
                              GestureDetector(
                                onTap: () {
                                  final bool hasGist =
                                      _userProfile?['has_active_gist'] ?? false;
                                  if (hasGist) {
                                    Navigator.of(context)
                                        .push(MaterialPageRoute(
                                            builder: (_) => GistViewerScreen(
                                                  userId: _userProfile!['id'],
                                                  username:
                                                      _userProfile!['username'],
                                                  avatarUrl: _userProfile![
                                                          'avatar_url'] ??
                                                      '',
                                                )));
                                  } else {
                                    // If no gist, tap also goes to create screen
                                    Navigator.of(context)
                                        .push(MaterialPageRoute(
                                            builder: (_) =>
                                                const CreateGistScreen()))
                                        .then((_) => _loadProfile());
                                  }
                                },
                                child: GistAvatar(
                                  radius: 50,
                                  avatarUrl: _userProfile?['avatar_url'],
                                  fallbackText: _userProfile?['display_name']
                                          ?.substring(0, 1)
                                          .toUpperCase() ??
                                      '?',
                                  hasActiveGist:
                                      _userProfile?['has_active_gist'] ?? false,
                                ),
                              ),
                              Positioned(
                                bottom: 0,
                                right: -5,
                                child: GestureDetector(
                                  onTap: () {
                                    Navigator.of(context)
                                        .push(MaterialPageRoute(
                                            builder: (_) =>
                                                const CreateGistScreen()))
                                        .then((_) => _loadProfile());
                                  },
                                  child: const CircleAvatar(
                                    radius: 18,
                                    backgroundColor: Colors.cyanAccent,
                                    child: Icon(Icons.add,
                                        color: Colors.black, size: 22),
                                  ),
                                ),
                              ),
                            ],
                          ),
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
                            icon: Icons.alternate_email,
                            title: 'Twitter',
                            subtitle: _userProfile?['twitter_handle'] != null
                                ? '@${_userProfile!['twitter_handle']}'
                                : 'Not connected.',
                          ),
                          const Divider(color: lightSuedeNavy),
                          _buildInfoTile(
                            icon: Icons.account_balance_wallet_outlined,
                            title: 'USDT Wallet (TRC-20)',
                            subtitle: _userProfile?['usdt_wallet_address'] ??
                                'No wallet set.',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
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
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) =>
                                  EditProfileScreen(profile: _userProfile!)),
                        );
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
