// lib/main_screen.dart (or wherever your MainScreen is located)

import 'package:flutter/material.dart';
import 'package:class_rep/features/timetable/presentation/timetable_screen.dart';
import 'package:class_rep/features/x_analytics/presentation/x_analytics_screen.dart'; // Import X Screen
import 'package:class_rep/features/profile/presentation/profile_screen.dart'; // Import Profile Screen
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
  Map<String, dynamic>? _userProfile; // Add this

  @override
  void initState() {
    super.initState();
    _loadUserProfile(); // Add this
  }

  // Add this new method to fetch the user's data
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
      // Handle error if needed
      debugPrint("Error loading user profile for nav bar: $e");
    }
  }

  // UPDATE: This list remains the same but will now be used by the updated BottomNavBar
  static const List<Widget> _widgetOptions = <Widget>[
    TimetableScreen(),
    XAnalyticsScreen(),
    ProfileScreen(),
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
          // --- START OF PROFILE ICON UPDATE ---
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
          // --- END OF PROFILE ICON UPDATE ---
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }
}
