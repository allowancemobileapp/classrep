// lib/main_screen.dart (or wherever your MainScreen is located)

import 'package:flutter/material.dart';
import 'package:class_rep/features/timetable/presentation/timetable_screen.dart';
import 'package:class_rep/features/x_analytics/presentation/x_analytics_screen.dart'; // Import X Screen
import 'package:class_rep/features/profile/presentation/profile_screen.dart'; // Import Profile Screen

// --- THEME COLORS ---
const Color darkSuedeNavy = Color(0xFF1A1B2C);

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  // UPDATE: Replaced placeholder Text widgets with the actual screens
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
    return Scaffold(
      backgroundColor: darkSuedeNavy,
      body: Center(child: _widgetOptions.elementAt(_selectedIndex)),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          // --- START OF ICON UPDATE ---
          BottomNavigationBarItem(
            // Use a Text widget for custom styling (boldness)
            icon: Text(
              '=',
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.bold,
                color: Colors.yellow, // Unselected color
              ),
            ),
            activeIcon: Text(
              '=',
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.bold,
                color: Colors.yellow, // Selected color is yellow
              ),
            ),
            label: '', // No label
          ),
          // --- END OF ICON UPDATE ---
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        backgroundColor: darkSuedeNavy,
        selectedItemColor: Colors.cyanAccent, // For Home and Profile
        unselectedItemColor: Colors.grey,
        showSelectedLabels: true,
        showUnselectedLabels: false,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}
