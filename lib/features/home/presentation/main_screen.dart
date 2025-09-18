import 'package:flutter/material.dart';
import 'package:class_rep/features/timetable/presentation/timetable_screen.dart'; // We will create this next

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  // The pages that correspond to the navigation bar items
  static const List<Widget> _widgetOptions = <Widget>[
    TimetableScreen(), // Home Icon
    Text(
      'X Screen (Analytics)',
      style: TextStyle(color: Colors.white),
    ), // X Icon
    Text(
      'Profile Screen',
      style: TextStyle(color: Colors.white),
    ), // Profile Icon
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(child: _widgetOptions.elementAt(_selectedIndex)),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.close), // Using 'close' as a placeholder for 'X'
            activeIcon: Icon(Icons.close),
            label: 'X',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        backgroundColor: Colors.black,
        selectedItemColor: Colors.cyanAccent,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: false,
        type: BottomNavigationBarType
            .fixed, // Ensures background color is applied
      ),
    );
  }
}
