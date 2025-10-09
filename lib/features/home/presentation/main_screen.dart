// lib/features/home/presentation/main_screen.dart (or wherever your MainScreen is located)

import 'package:flutter/material.dart';
import 'package:class_rep/features/timetable/presentation/timetable_screen.dart';
import 'package:class_rep/features/x_analytics/presentation/x_analytics_screen.dart';
import 'package:class_rep/features/profile/presentation/profile_screen.dart';
import 'package:class_rep/shared/services/auth_service.dart';
import 'package:class_rep/shared/services/supabase_service.dart';

// --- THEME COLORS ---
const Color darkSuedeNavy = Color(0xFF1A1B2C);

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  Map<String, dynamic>? _userProfile;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();

    // --- THIS IS THE NEW LINE ---
    // Get and save the user's notification token on startup
    SupabaseService.instance.initNotifications();
  }

  void navigateToTab(int index) {
    _onItemTapped(index);
  }

  Future<void> _loadUserProfile() async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) return;
    try {
      final profile = await SupabaseService.instance.fetchUserProfile(userId);
      if (mounted) {
        setState(() {
          _userProfile = profile;
        });
      }
    } catch (e) {
      debugPrint("Error loading user profile for nav bar: $e");
    }
  }

  List<Widget> get _widgetOptions => <Widget>[
        TimetableScreen(
            onNavigateToTab: navigateToTab), // Pass the function here
        const XAnalyticsScreen(),
        const ProfileScreen(),
      ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final avatarUrl = _userProfile?['avatar_url'] as String?;

    return Scaffold(
      backgroundColor: darkSuedeNavy,
      body: Center(child: _widgetOptions.elementAt(_selectedIndex)),
      bottomNavigationBar: BottomNavigationBar(
        items: <BottomNavigationBarItem>[
          const BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          const BottomNavigationBarItem(
            icon: Text(
              'X',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey),
            ),
            activeIcon: Text(
              'X',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.yellow),
            ),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: CircleAvatar(
              radius: 12,
              backgroundColor: Colors.grey,
              backgroundImage:
                  avatarUrl != null ? NetworkImage(avatarUrl) : null,
              child: avatarUrl == null
                  ? const Icon(Icons.person_outline,
                      size: 16, color: darkSuedeNavy)
                  : null,
            ),
            activeIcon: CircleAvatar(
              radius: 14,
              backgroundColor: Colors.cyanAccent,
              child: CircleAvatar(
                radius: 12,
                backgroundImage:
                    avatarUrl != null ? NetworkImage(avatarUrl) : null,
                child: avatarUrl == null
                    ? const Icon(Icons.person, size: 16, color: darkSuedeNavy)
                    : null,
              ),
            ),
            label: 'Profile',
          ),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }
}
