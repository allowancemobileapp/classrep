// lib/features/timetable/presentation/timetable_screen.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:class_rep/features/chat/presentation/conversations_screen.dart';
import 'package:class_rep/features/profile/presentation/gist_viewer_screen.dart';
import 'package:class_rep/features/timetable/presentation/manage_groups_screen.dart';
import 'package:class_rep/shared/services/auth_service.dart';
import 'package:class_rep/shared/services/notification_service.dart';
import 'package:class_rep/shared/services/supabase_service.dart';
import 'package:class_rep/shared/widgets/gist_avatar.dart';
import 'package:class_rep/shared/widgets/glass_container.dart';
import 'package:class_rep/shared/widgets/user_profile_card.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
// THIS IS THE CRITICAL IMPORT THAT WAS MISSING
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:url_launcher/url_launcher.dart';

// --- THEME COLORS ---
const Color darkSuedeNavy = Color(0xFF1A1B2C);
const Color lightSuedeNavy = Color(0xFF2A2C40);

class TimetableScreen extends StatefulWidget {
  final Function(int) onNavigateToTab; // Add this parameter
  const TimetableScreen({required this.onNavigateToTab, super.key});

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<DateTime, List<Map<String, dynamic>>> _events = {};
  bool _isLoading = true;
  String? _currentUserId;
  List<Map<String, dynamic>> _addedTimetables = [];
  Map<String, dynamic>? _userProfile;
  int _unreadCount = 0;
  List<Map<String, dynamic>> _gistFeedUsers = [];

  // State for Unread Chat Count & Realtime
  int _unreadChatCount = 0;
  RealtimeChannel? _chatUpdateSubscription;

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
    _currentUserId = AuthService.instance.currentUser?.id;
    _loadAllData();
    _setupChatListener();
  }

  @override
  void dispose() {
    if (_chatUpdateSubscription != null) {
      supabase.removeChannel(_chatUpdateSubscription!);
    }
    super.dispose();
  }

  void _setupChatListener() {
    if (_currentUserId == null) return;
    _chatUpdateSubscription = supabase
        .channel('public:chat_participants:user_id=eq.$_currentUserId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chat_participants',
          // --- THIS IS THE FIX ---
          // Instead of a simple string, we build the filter object it's asking for.
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: _currentUserId,
          ),
          callback: (payload) {
            _refreshUnreadChatCount();
          },
        )
        .subscribe();
  }

  Future<void> _refreshUnreadChatCount() async {
    if (_currentUserId == null) return;
    try {
      final count =
          await SupabaseService.instance.getTotalUnreadConversationsCount();
      if (mounted) {
        setState(() {
          _unreadChatCount = count;
        });
      }
    } catch (e) {
      // fail silently
    }
  }

  Future<void> _loadAllData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      if (_currentUserId == null) throw Exception("User not logged in.");

      final results = await Future.wait([
        SupabaseService.instance.fetchEvents(),
        SupabaseService.instance.getMySharedUsers(),
        SupabaseService.instance.fetchUserProfile(_currentUserId!),
        SupabaseService.instance.getUnreadNotificationsCount(),
        SupabaseService.instance.getGistFeed(onlySubscriptions: false),
        SupabaseService.instance.getTotalUnreadConversationsCount(),
      ]);
      final rawEvents = (results[0] as List).cast<Map<String, dynamic>>();
      final sharedUsers = (results[1] as List).cast<Map<String, dynamic>>();
      _userProfile = results[2] as Map<String, dynamic>;
      _unreadCount = results[3] as int;
      final gistUsers = (results[4] as List).cast<Map<String, dynamic>>();
      final chatCount = results[5] as int;

      if (!mounted) return;
      setState(() {
        _events = _groupAndExpandEvents(rawEvents);
        _addedTimetables = sharedUsers;
        _gistFeedUsers = gistUsers;
        _unreadChatCount = chatCount;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not refresh timetable. Please check your internet and try again.',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Map<DateTime, List<Map<String, dynamic>>> _groupAndExpandEvents(
    List<Map<String, dynamic>> events,
  ) {
    Map<DateTime, List<Map<String, dynamic>>> data = {};
    for (var event in events) {
      final repeat = event['repeat'] as String? ?? 'none';
      final startTime = DateTime.parse(event['start_time']).toLocal();

      if (repeat == 'none') {
        final key = DateTime(startTime.year, startTime.month, startTime.day);
        if (data[key] == null) data[key] = [];
        data[key]!.add(event);
      } else {
        for (int i = 0; i < 90; i++) {
          DateTime occurrenceDate;
          if (repeat == 'daily') {
            occurrenceDate = startTime.add(Duration(days: i));
          } else if (repeat == 'weekly') {
            occurrenceDate = startTime.add(Duration(days: i * 7));
          } else {
            continue;
          }
          final key = DateTime(
            occurrenceDate.year,
            occurrenceDate.month,
            occurrenceDate.day,
          );
          if (data[key] == null) data[key] = [];
          data[key]!.add(event);
        }
      }
    }
    return data;
  }

  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    return _events[DateTime(day.year, day.month, day.day)] ?? [];
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    setState(() {
      _selectedDay = selectedDay;
      _focusedDay = focusedDay;
    });
  }

  @override
  Widget build(BuildContext context) {
    // This build method is fully updated and correct.
    return Scaffold(
      backgroundColor: darkSuedeNavy,
      appBar: AppBar(
        scrolledUnderElevation: 0.0,
        backgroundColor: darkSuedeNavy,
        elevation: 0,
        centerTitle: true,
        title: RichText(
          text: const TextSpan(
            style: TextStyle(
              fontFamily: 'LeagueSpartan',
              fontSize: 24,
              fontWeight: FontWeight.bold,
              fontStyle: FontStyle.italic,
            ),
            children: <TextSpan>[
              TextSpan(text: 'Class', style: TextStyle(color: Colors.white)),
              TextSpan(text: '-', style: TextStyle(color: Colors.yellow)),
              TextSpan(text: 'Rep', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
        actions: [
          IconButton(
            onPressed: _openNotificationsModal,
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications_none, color: Colors.white),
                if (_unreadCount > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      constraints:
                          const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Center(
                        child: Text(
                          '$_unreadCount',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: _openHamburgerMenu,
            icon: const Icon(Icons.menu, color: Colors.white),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.cyanAccent),
            )
          : Column(
              children: [
                _buildGistFeed(),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: GlassContainer(
                    borderRadius: 16,
                    padding: const EdgeInsets.all(8),
                    child: TableCalendar(
                      calendarFormat: CalendarFormat.week,
                      firstDay: DateTime.utc(2020, 1, 1),
                      lastDay: DateTime.utc(2035, 12, 31),
                      focusedDay: _focusedDay,
                      selectedDayPredicate: (day) =>
                          isSameDay(_selectedDay, day),
                      onDaySelected: _onDaySelected,
                      eventLoader: _getEventsForDay,
                      headerStyle: const HeaderStyle(
                        formatButtonVisible: false,
                        titleCentered: true,
                        titleTextStyle: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        leftChevronIcon: Icon(
                          Icons.chevron_left,
                          color: Colors.white,
                        ),
                        rightChevronIcon: Icon(
                          Icons.chevron_right,
                          color: Colors.white,
                        ),
                      ),
                      calendarStyle: const CalendarStyle(
                        defaultTextStyle: TextStyle(color: Colors.white),
                        weekendTextStyle: TextStyle(color: Colors.white70),
                        outsideTextStyle: TextStyle(color: Colors.white38),
                        selectedDecoration: BoxDecoration(
                          color: Colors.cyanAccent,
                          shape: BoxShape.circle,
                        ),
                        selectedTextStyle: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                        todayDecoration: BoxDecoration(
                          color: Colors.white24,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(child: _buildEventList()),
              ],
            ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              FloatingActionButton.small(
                heroTag: 'fab_chat',
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (c) => const ConversationsScreen()),
                  );
                  _refreshUnreadChatCount();
                },
                backgroundColor: Colors.amber,
                child: const Icon(CupertinoIcons.chat_bubble_2,
                    color: Colors.black),
              ),
              if (_unreadChatCount > 0)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints:
                        const BoxConstraints(minWidth: 20, minHeight: 20),
                    child: Center(
                      child: Text(
                        _unreadChatCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'fab_add',
            onPressed: () => _showAddEditEventModal(),
            backgroundColor: Colors.cyanAccent,
            child: const Icon(Icons.add, color: Colors.black),
          ),
        ],
      ),
    );
  }

  // This is a brand new method. Add it directly AFTER your build method.
  Widget _buildGistFeed() {
    if (_gistFeedUsers.isEmpty) return const SizedBox.shrink();

    final isPlusUser = _userProfile?['is_plus'] as bool? ?? false;
    final int gistLimit = 10;
    final bool hasMoreGists = _gistFeedUsers.length > gistLimit;
    final List<Map<String, dynamic>> visibleGists = isPlusUser || !hasMoreGists
        ? _gistFeedUsers
        : _gistFeedUsers.sublist(0, gistLimit);

    return Container(
      height: 100,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: lightSuedeNavy, width: 1)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: visibleGists.length + (hasMoreGists && !isPlusUser ? 1 : 0),
        itemBuilder: (context, index) {
          // --- NEW: "VIEW MORE" CARD ---
          if (!isPlusUser && hasMoreGists && index == visibleGists.length) {
            return GestureDetector(
              onTap: () {
                showModalBottomSheet(
                  context: context,
                  backgroundColor: Colors.transparent,
                  builder: (sheetContext) => GlassContainer(
                    borderRadius: 20,
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.workspace_premium_outlined,
                            color: Colors.amber, size: 48),
                        const SizedBox(height: 16),
                        const Text(
                          'Unlock All Gists',
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Upgrade to Class-Rep Plus to view all Gists from creators and get unlimited access to all features!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.cyanAccent,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(
                                vertical: 12, horizontal: 32),
                          ),
                          child: const Text('Upgrade Now',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          onPressed: () {
                            Navigator.of(context).pop();
                            // Here you would navigate to your subscription screen
                            // For now, it just closes the sheet.
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: SizedBox(
                  width: 70,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: lightSuedeNavy,
                        child: const Icon(Icons.arrow_forward_ios,
                            color: Colors.cyanAccent),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'View All',
                        style:
                            TextStyle(color: Colors.cyanAccent, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          final user = visibleGists[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: GestureDetector(
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => GistViewerScreen(
                          userId: user['id'],
                          username: user['username'],
                          avatarUrl: user['avatar_url'] ?? '',
                        )));
              },
              child: SizedBox(
                width: 70,
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GistAvatar(
                        radius: 30,
                        avatarUrl: user['avatar_url'],
                        fallbackText: user['username']?[0].toUpperCase() ?? '?',
                        hasActiveGist: true,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user['username'],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openNotificationsModal() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => NotificationSheet(
        onClosed: () {
          SupabaseService.instance.markNotificationsAsRead().then((_) {
            if (mounted) {
              setState(() => _unreadCount = 0);
            }
          });
        },
      ),
    );
  }

  // This helper method is needed by the Hamburger Menu, which was in my previous full-code version
  InputDecoration _buildInputDecoration({required String labelText}) {
    return InputDecoration(
      labelText: labelText,
      labelStyle: const TextStyle(color: Colors.white70),
      filled: true,
      fillColor: Colors.white.withOpacity(0.1),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.cyanAccent, width: 1.5),
      ),
    );
  }

  // --- HAMBURGER MENU & HELPERS ---
  // In lib/features/timetable/presentation/timetable_screen.dart

  // REPLACE your existing _openHamburgerMenu method with this one:
  Future<void> _openHamburgerMenu() async {
    final creatorStats = await SupabaseService.instance.fetchCreatorStats();
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) {
        final displayUsername = _userProfile?['username'] as String? ?? '...';
        final plusAddons = creatorStats['plus_addons_count'] as int? ?? 0;
        final expectedCashOut = (plusAddons ~/ 100) * 1000;
        final codeController = TextEditingController();

        return GlassContainer(
          borderRadius: 20.0,
          padding: EdgeInsets.only(
            top: 12,
            left: 12,
            right: 12,
            bottom: MediaQuery.of(modalContext).viewInsets.bottom + 12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: CircleAvatar(
                  radius: 24,
                  backgroundColor: lightSuedeNavy,
                  backgroundImage: _userProfile?['avatar_url'] != null
                      ? NetworkImage(_userProfile!['avatar_url'])
                      : null,
                  child: _userProfile?['avatar_url'] == null
                      ? Text(
                          displayUsername.isNotEmpty
                              ? displayUsername[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                        )
                      : null,
                ),
                title: Text(
                  '@$displayUsername',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  'Expected Payout: N$expectedCashOut',
                  style:
                      const TextStyle(color: Colors.amberAccent, fontSize: 12),
                ),
              ),
              const Divider(color: lightSuedeNavy),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: codeController,
                        style: const TextStyle(color: Colors.white),
                        decoration: _buildInputDecoration(
                                labelText: "Enter a username to add")
                            .copyWith(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.add_circle,
                          color: Colors.cyanAccent, size: 30),
                      onPressed: () async {
                        if (codeController.text.trim().isEmpty) return;
                        try {
                          await SupabaseService.instance
                              .subscribeToTimetable(codeController.text.trim());
                          await _loadAllData();
                          if (!mounted) return;
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Timetable added!'),
                                  backgroundColor: Colors.green));
                        } catch (e) {
                          final errorString = e.toString().toLowerCase();
                          if (errorString.contains('free users are limited')) {
                            Navigator.pop(context);
                            showDialog(
                              context: context,
                              builder: (dialogContext) => AlertDialog(
                                backgroundColor: lightSuedeNavy,
                                title: const Text('Upgrade to Plus',
                                    style: TextStyle(color: Colors.white)),
                                content: const Text(
                                    'Free users can only add 1 timetable. Upgrade to Class-Rep Plus to add unlimited timetables!',
                                    style: TextStyle(color: Colors.white70)),
                                actions: [
                                  TextButton(
                                    child: const Text('Maybe Later'),
                                    onPressed: () =>
                                        Navigator.of(dialogContext).pop(),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.cyanAccent),
                                    child: const Text('Upgrade Now',
                                        style: TextStyle(color: Colors.black)),
                                    onPressed: () {
                                      Navigator.of(modalContext)
                                          .pop(); // Close the bottom sheet
                                      widget.onNavigateToTab(
                                          1); // Tell MainScreen to switch to the 'X' tab
                                    },
                                  ),
                                ],
                              ),
                            );
                          } else {
                            String errorMessage;
                            Color errorColor = Colors.redAccent;
                            if (errorString.contains('already subscribed')) {
                              errorMessage =
                                  'You are already subscribed to this user.';
                              errorColor = Colors.orange;
                            } else if (errorString.contains('not found') ||
                                errorString.contains('no rows')) {
                              errorMessage =
                                  'Could not find a user with that username.';
                            } else {
                              errorMessage =
                                  'An unexpected error occurred. Please try again.';
                            }
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(errorMessage),
                                backgroundColor: errorColor,
                              ),
                            );
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),
              const Divider(color: lightSuedeNavy),
              ListTile(
                leading: const Icon(Icons.group, color: Colors.white70),
                title: const Text('Manage Groups',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context); // Close menu
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (c) => const ManageGroupsScreen()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.people_alt, color: Colors.white70),
                title: const Text('Manage Added Timetables',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _showAddedTimetables();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showAddedTimetables() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return GlassContainer(
              borderRadius: 20.0,
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Added Timetables',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  const Divider(color: lightSuedeNavy),
                  Flexible(
                    child: _addedTimetables.isEmpty
                        ? const Center(
                            child: Text('No timetables added yet.',
                                style: TextStyle(color: Colors.white70)))
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: _addedTimetables.length,
                            itemBuilder: (ctx, index) {
                              final user = _addedTimetables[index];
                              final avatarUrl = user['avatar_url'] as String?;

                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: lightSuedeNavy,
                                  backgroundImage: avatarUrl != null
                                      ? NetworkImage(avatarUrl)
                                      : null,
                                  child: avatarUrl == null
                                      ? Text(
                                          (user['username'] ?? '?')
                                              .substring(0, 1)
                                              .toUpperCase(),
                                          style: const TextStyle(
                                              color: Colors.white),
                                        )
                                      : null,
                                ),
                                title: Text(user['username'] ?? 'Unknown User',
                                    style:
                                        const TextStyle(color: Colors.white)),
                                trailing: IconButton(
                                  icon: const Icon(Icons.remove_circle_outline,
                                      color: Colors.redAccent),
                                  onPressed: () async {
                                    try {
                                      await SupabaseService.instance
                                          .unsubscribeFromTimetable(user['id']);
                                      await _loadAllData();
                                      setModalState(
                                          () {}); // Re-render the list
                                    } catch (e) {
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                              content: Text(
                                                  'Error removing timetable: $e'),
                                              backgroundColor: Colors.red));
                                    }
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // --- All other methods remain the same as your provided code ---

  Widget _buildEventList() {
    final selectedEvents =
        _selectedDay != null ? _getEventsForDay(_selectedDay!) : [];
    if (selectedEvents.isEmpty) {
      return const Center(
          child: Text('No events for this day.',
              style: TextStyle(color: Colors.white70)));
    }
    selectedEvents.sort((a, b) => DateTime.parse(a['start_time'])
        .compareTo(DateTime.parse(b['start_time'])));
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: selectedEvents.length,
      itemBuilder: (context, index) {
        final event = selectedEvents[index];
        final imageUrl = event['image_url'] as String?;
        return (imageUrl != null && imageUrl.isNotEmpty)
            ? _buildImageEventCard(event)
            : _buildSimpleEventCard(event);
      },
    );
  }

  Widget _buildImageEventCard(Map<String, dynamic> event) {
    final startTime =
        DateFormat.jm().format(DateTime.parse(event['start_time']).toLocal());
    final title = event['title'] as String? ?? 'No Title';
    final description = event['description'] as String?;
    final creatorUsername = event['creator_username'] as String?;
    final creatorAvatarUrl = event['creator_avatar_url'] as String?;
    final groupName = event['group_name'] as String?;
    final linkUrl = event['url'] as String?;
    final isMine = event['user_id'] == _currentUserId;
    final commentCount = event['comment_count'] as int? ?? 0;

    bool commentsEnabled = true;
    final metadata = event['metadata'];
    if (metadata is Map && metadata.containsKey('comments_enabled')) {
      commentsEnabled = metadata['comments_enabled'] == true;
    } else if (metadata is String) {
      try {
        final parsed = metadata.isNotEmpty
            ? Map<String, dynamic>.from(jsonDecode(metadata))
            : {};
        if (parsed.containsKey('comments_enabled')) {
          commentsEnabled = parsed['comments_enabled'] == true;
        }
      } catch (_) {}
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: isMine ? () => _showAddEditEventModal(event: event) : null,
        child: AspectRatio(
          // --- STYLE CHANGE: ASPECT RATIO IS NOW 1/1 (SQUARE) ---
          aspectRatio: 1 / 1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(event['image_url'],
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                      color: lightSuedeNavy,
                      child: const Center(child: Icon(Icons.broken_image)))),
              Container(
                decoration: BoxDecoration(
                  // --- STYLE CHANGE: GRADIENT FADES FROM THE BOTTOM ONLY ---
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.8),
                      Colors.black
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.4, 0.8, 1.0], // Start fade lower down
                  ),
                ),
              ),
              if (linkUrl != null && linkUrl.isNotEmpty)
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    icon: const Icon(Icons.link, color: Colors.white),
                    onPressed: () async {
                      final url = Uri.parse(linkUrl);
                      if (await canLaunchUrl(url)) {
                        await launchUrl(url,
                            mode: LaunchMode.externalApplication);
                      }
                    },
                  ),
                ),
              Positioned(
                bottom: 16,
                left: 16,
                right: 16,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(title,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  shadows: [
                                    Shadow(blurRadius: 8, color: Colors.black87)
                                  ])),
                          if (description != null && description.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Text(description,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
                                      shadows: [
                                        Shadow(
                                            blurRadius: 6,
                                            color: Colors.black87)
                                      ])),
                            ),
                          if (!isMine && creatorUsername != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 10,
                                    backgroundColor: lightSuedeNavy,
                                    backgroundImage: creatorAvatarUrl != null
                                        ? NetworkImage(creatorAvatarUrl)
                                        : null,
                                    child: creatorAvatarUrl == null
                                        ? const Icon(Icons.person, size: 12)
                                        : null,
                                  ),
                                  const SizedBox(width: 6),
                                  Text('by @$creatorUsername',
                                      style: const TextStyle(
                                          color: Colors.amberAccent,
                                          fontStyle: FontStyle.italic,
                                          fontSize: 12)),
                                ],
                              ),
                            ),
                          if (isMine &&
                              groupName != null &&
                              groupName.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Text('Group: $groupName',
                                  style: const TextStyle(
                                      color: Colors.white70,
                                      fontStyle: FontStyle.italic,
                                      fontSize: 12)),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isMine)
                          IconButton(
                            tooltip: 'Send Reminder to Subscribers',
                            icon: const Icon(Icons.campaign_outlined,
                                color: Colors.white70),
                            onPressed: () => _handleSendReminder(event['id']),
                          ),
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            IconButton(
                              icon: Icon(
                                CupertinoIcons.bubble_left,
                                color: commentsEnabled
                                    ? Colors.cyanAccent
                                    : Colors.white38,
                              ),
                              onPressed: commentsEnabled
                                  ? () => _openCommentsSheet(
                                      event['id'].toString(), title, event)
                                  : null,
                            ),
                            if (commentCount > 0)
                              Positioned(
                                right: 5,
                                top: 5,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  constraints: const BoxConstraints(
                                      minWidth: 16, minHeight: 16),
                                  child: Center(
                                    child: Text(
                                      '$commentCount',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        Text(startTime,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                shadows: [
                                  Shadow(blurRadius: 8, color: Colors.black87)
                                ])),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSimpleEventCard(Map<String, dynamic> event) {
    // ... This function remains unchanged ...
    final startTime =
        DateFormat.jm().format(DateTime.parse(event['start_time']).toLocal());
    final title = event['title'] as String? ?? 'No Title';
    final description = event['description'] as String?;
    final creatorUsername = event['creator_username'] as String?;
    final creatorAvatarUrl = event['creator_avatar_url'] as String?;
    final groupName = event['group_name'] as String?;
    final linkUrl = event['url'] as String?;
    final isMine = event['user_id'] == _currentUserId;
    final commentCount = event['comment_count'] as int? ?? 0;

    bool commentsEnabled = true;
    final metadata = event['metadata'];
    if (metadata is Map && metadata.containsKey('comments_enabled')) {
      commentsEnabled = metadata['comments_enabled'] == true;
    } else if (metadata is String) {
      try {
        final parsed = metadata.isNotEmpty
            ? Map<String, dynamic>.from(jsonDecode(metadata))
            : {};
        if (parsed.containsKey('comments_enabled')) {
          commentsEnabled = parsed['comments_enabled'] == true;
        }
      } catch (_) {}
    }

    return Card(
      color: lightSuedeNavy.withOpacity(0.5),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: (!isMine && creatorAvatarUrl != null)
            ? CircleAvatar(backgroundImage: NetworkImage(creatorAvatarUrl))
            : null,
        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        title: Text(title,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (description != null && description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(description,
                    style: const TextStyle(color: Colors.white70)),
              ),
            if (!isMine && creatorUsername != null)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text('by @$creatorUsername',
                    style: const TextStyle(
                        color: Colors.amberAccent,
                        fontStyle: FontStyle.italic,
                        fontSize: 12)),
              ),
            if (isMine && groupName != null && groupName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text('Group: $groupName',
                    style: const TextStyle(
                        color: Colors.white70,
                        fontStyle: FontStyle.italic,
                        fontSize: 12)),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (linkUrl != null && linkUrl.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.link, color: Colors.white70),
                onPressed: () async {
                  final url = Uri.parse(linkUrl);
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
              ),
            if (isMine)
              IconButton(
                tooltip: 'Send Reminder to Subscribers',
                icon:
                    const Icon(Icons.campaign_outlined, color: Colors.white70),
                onPressed: () => _handleSendReminder(event['id']),
              ),
            Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  icon: const Icon(CupertinoIcons.bubble_left),
                  color: commentsEnabled ? Colors.cyanAccent : Colors.white38,
                  onPressed: commentsEnabled
                      ? () => _openCommentsSheet(
                          event['id'].toString(), title, event)
                      : null,
                ),
                if (commentCount > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints:
                          const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Center(
                        child: Text(
                          '$commentCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            Text(startTime,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        onTap: isMine ? () => _showAddEditEventModal(event: event) : null,
      ),
    );
  }

  Future<void> _handleSendReminder(String eventId) async {
    final confirm = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => GlassContainer(
        borderRadius: 20,
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Send Reminder?',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
            ),
            const SizedBox(height: 16),
            const Text(
              'This will send a push notification to all of your subscribers about this event.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  child: const Text('Cancel',
                      style: TextStyle(color: Colors.white70, fontSize: 16)),
                  onPressed: () => Navigator.of(sheetContext).pop(false),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyanAccent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 32),
                  ),
                  child: const Text('Send',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      try {
        await SupabaseService.instance.sendEventReminder(eventId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Reminder sent to all subscribers!'),
                backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Error: ${e.toString()}'),
                backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _openCommentsSheet(
      String eventId, String eventTitle, Map<String, dynamic> event) async {
    // Changed 'Map event' to 'Map<String, dynamic> event' for type safety
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) {
        return _CommentsSheet(
          eventId: eventId,
          eventTitle: eventTitle,
          // --- NEW ---
          // We now pass the event creator's details and the description
          eventCreator: event['author'] as Map<String, dynamic>?,
          eventDescription: event['description'] as String?,
          onCommentPosted: () {
            _loadAllData();
          },
        );
      },
    );
  }

  Future<void> _showAddEditEventModal({Map<String, dynamic>? event}) async {
    final isEditing = event != null;
    final groups = await SupabaseService.instance.fetchEventGroups();
    if (!mounted) return;

    final formKey = GlobalKey<FormState>();
    final titleController =
        TextEditingController(text: isEditing ? event['title'] : '');
    final descriptionController =
        TextEditingController(text: isEditing ? event['description'] : '');
    final linkUrlController =
        TextEditingController(text: isEditing ? event['url'] : '');
    XFile? pickedImage;
    String? existingImageUrl = isEditing ? event['image_url'] : null;
    DateTime eventDate = isEditing
        ? DateTime.parse(event['start_time']).toLocal()
        : _selectedDay!;
    TimeOfDay startTime = TimeOfDay.fromDateTime(eventDate);
    TimeOfDay endTime = isEditing
        ? TimeOfDay.fromDateTime(DateTime.parse(event['end_time']).toLocal())
        : TimeOfDay(hour: startTime.hour + 1, minute: startTime.minute);
    String? selectedGroupId = isEditing ? event['group_id'] : null;
    String repeatValue = isEditing ? (event['repeat'] ?? 'none') : 'none';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (modalContext, setModalState) => GestureDetector(
          onTap: () => FocusScope.of(modalContext).unfocus(),
          child: DraggableScrollableSheet(
            initialChildSize: 0.9,
            minChildSize: 0.5,
            maxChildSize: 0.9,
            builder: (_, scrollController) => GlassContainer(
              borderRadius: 20.0,
              child: Form(
                key: formKey,
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(24.0),
                  children: [
                    Center(
                        child: Container(
                            width: 40,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                                color: Colors.grey[700],
                                borderRadius: BorderRadius.circular(10)))),
                    Text(isEditing ? 'Edit Event' : 'Add New Event',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 24),

                    // --- THIS IS THE UPDATED IMAGE PREVIEW WIDGET ---
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        GestureDetector(
                          onTap: () async {
                            final picker = ImagePicker();
                            final file = await picker.pickImage(
                                source: ImageSource.gallery);
                            if (file != null) {
                              setModalState(() {
                                pickedImage = file;
                                // If a new image is picked, it replaces any existing one
                                existingImageUrl = null;
                              });
                            }
                          },
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border:
                                    Border.all(color: Colors.white38, width: 2),
                                image: pickedImage != null
                                    ? DecorationImage(
                                        image:
                                            FileImage(File(pickedImage!.path)),
                                        fit: BoxFit.cover)
                                    : existingImageUrl != null
                                        ? DecorationImage(
                                            image:
                                                NetworkImage(existingImageUrl!),
                                            fit: BoxFit.cover)
                                        : null,
                              ),
                              child: (pickedImage == null &&
                                      existingImageUrl == null)
                                  ? const Center(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                              CupertinoIcons.photo_on_rectangle,
                                              color: Colors.white38,
                                              size: 40),
                                          SizedBox(height: 8),
                                          Text('Tap to add an image',
                                              style: TextStyle(
                                                  color: Colors.white38,
                                                  fontSize: 14)),
                                        ],
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                        ),
                        // --- THIS IS THE NEW "REMOVE IMAGE" BUTTON ---
                        if (pickedImage != null || existingImageUrl != null)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: GestureDetector(
                              onTap: () {
                                setModalState(() {
                                  pickedImage = null;
                                  existingImageUrl = null;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    TextFormField(
                        controller: titleController,
                        style: const TextStyle(color: Colors.white),
                        decoration: _buildInputDecoration(labelText: 'Title'),
                        validator: (val) =>
                            val!.isEmpty ? 'Title is required' : null),
                    const SizedBox(height: 16),
                    TextFormField(
                        controller: descriptionController,
                        style: const TextStyle(color: Colors.white),
                        decoration: _buildInputDecoration(
                            labelText: 'Description (Optional)')),
                    const SizedBox(height: 16),
                    TextFormField(
                        controller: linkUrlController,
                        style: const TextStyle(color: Colors.white),
                        decoration: _buildInputDecoration(
                            labelText: 'Link URL (Optional)')),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                            child: _buildTimePicker(
                                context: modalContext,
                                label: 'Starts',
                                time: startTime,
                                onTimeChanged: (newTime) =>
                                    setModalState(() => startTime = newTime))),
                        const SizedBox(width: 16),
                        Expanded(
                            child: _buildTimePicker(
                                context: modalContext,
                                label: 'Ends',
                                time: endTime,
                                onTimeChanged: (newTime) =>
                                    setModalState(() => endTime = newTime))),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (groups.isNotEmpty)
                      DropdownButtonFormField<String>(
                        value: selectedGroupId,
                        hint: const Text('Assign to a group (optional)',
                            style: TextStyle(color: Colors.white70)),
                        dropdownColor: darkSuedeNavy,
                        style: const TextStyle(color: Colors.white),
                        decoration: _buildInputDecoration(labelText: ''),
                        items: groups
                            .map<DropdownMenuItem<String>>((g) =>
                                DropdownMenuItem<String>(
                                    value: g['id'],
                                    child: Text(g['group_name'])))
                            .toList(),
                        onChanged: (val) =>
                            setModalState(() => selectedGroupId = val),
                      ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: repeatValue,
                      dropdownColor: darkSuedeNavy,
                      style: const TextStyle(color: Colors.white),
                      decoration: _buildInputDecoration(labelText: 'Repeat'),
                      items: const [
                        DropdownMenuItem(
                            value: 'none', child: Text('Does not repeat')),
                        DropdownMenuItem(
                            value: 'daily', child: Text('Every day')),
                        DropdownMenuItem(
                            value: 'weekly', child: Text('Every week')),
                      ],
                      onChanged: (val) =>
                          setModalState(() => repeatValue = val ?? 'none'),
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.cyanAccent,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
                        if (formKey.currentState!.validate()) {
                          final day = isEditing
                              ? DateTime.parse(event['start_time']).toLocal()
                              : _selectedDay!;

                          final startDateTime = DateTime(day.year, day.month,
                              day.day, startTime.hour, startTime.minute);
                          var endDateTime = DateTime(day.year, day.month,
                              day.day, endTime.hour, endTime.minute);
                          if (endDateTime.isBefore(startDateTime)) {
                            endDateTime =
                                endDateTime.add(const Duration(days: 1));
                          }

                          String? finalImageUrl = existingImageUrl;
                          if (pickedImage != null) {
                            final imageBytes = await pickedImage!.readAsBytes();
                            finalImageUrl = await SupabaseService.instance
                                .uploadEventImage(
                                    filePath: pickedImage!.path,
                                    fileBytes: imageBytes.toList());
                          }

                          try {
                            if (isEditing) {
                              await SupabaseService.instance.updateEvent(
                                eventId: event['id'],
                                title: titleController.text,
                                description: descriptionController.text,
                                startTime: startDateTime,
                                endTime: endDateTime,
                                groupId: selectedGroupId,
                                imageUrl:
                                    finalImageUrl, // Will be null if removed
                                linkUrl: linkUrlController.text,
                                repeat: repeatValue,
                              );
                            } else {
                              await SupabaseService.instance.createEvent(
                                title: titleController.text,
                                description: descriptionController.text,
                                startTime: startDateTime,
                                endTime: endDateTime,
                                groupId: selectedGroupId,
                                imageUrl: finalImageUrl,
                                linkUrl: linkUrlController.text,
                                repeat: repeatValue,
                              );
                            }

                            final notificationId =
                                (titleController.text.hashCode +
                                        startDateTime.millisecondsSinceEpoch)
                                    .remainder(2147483647);

                            await NotificationService.instance
                                .scheduleEventNotification(
                              id: notificationId,
                              title: titleController.text,
                              body: 'Your event is starting now!',
                              scheduledTime: startDateTime,
                            );

                            if (!mounted) return;
                            Navigator.of(context).pop();
                            await _loadAllData();
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(isEditing
                                      ? 'Could not save changes.'
                                      : 'Could not create event.'),
                                  backgroundColor: Colors.redAccent),
                            );
                          }
                        }
                      },
                      child: Text(isEditing ? 'Save Changes' : 'Create Event',
                          style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                    ),
                    if (isEditing)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: TextButton.icon(
                          onPressed: () async {
                            final confirm = await showModalBottomSheet<bool>(
                              context: context,
                              backgroundColor: Colors.transparent,
                              builder: (sheetContext) => GlassContainer(
                                borderRadius: 20,
                                padding: const EdgeInsets.all(24.0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      'Confirm Deletion',
                                      style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white),
                                    ),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'Are you sure you want to delete this event series? This action cannot be undone.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: Colors.white70, fontSize: 16),
                                    ),
                                    const SizedBox(height: 24),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceEvenly,
                                      children: [
                                        TextButton(
                                          child: const Text('Cancel',
                                              style: TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 16)),
                                          onPressed: () =>
                                              Navigator.of(sheetContext)
                                                  .pop(false),
                                        ),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.redAccent,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 12, horizontal: 32),
                                          ),
                                          child: const Text('Delete',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16)),
                                          onPressed: () =>
                                              Navigator.of(sheetContext)
                                                  .pop(true),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );

                            if (confirm == true) {
                              try {
                                final notificationId =
                                    (event['title'].hashCode +
                                            DateTime.parse(event['start_time'])
                                                .millisecondsSinceEpoch)
                                        .remainder(2147483647);
                                await NotificationService.instance
                                    .cancelNotification(notificationId);

                                if (!mounted) return;
                                Navigator.of(context)
                                    .pop(); // Close the edit modal
                                await SupabaseService.instance
                                    .deleteEvent(event['id']);
                                await _loadAllData();
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Could not delete event.'),
                                      backgroundColor: Colors.redAccent),
                                );
                              }
                            }
                          },
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.redAccent),
                          label: const Text('Delete Event',
                              style: TextStyle(color: Colors.redAccent)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimePicker(
      {required BuildContext context,
      required String label,
      required TimeOfDay time,
      required Function(TimeOfDay) onTimeChanged}) {
    // ... This function remains unchanged ...
    return InkWell(
      onTap: () async {
        final picked =
            await showTimePicker(context: context, initialTime: time);
        if (picked != null) onTimeChanged(picked);
      },
      child: InputDecorator(
        decoration: _buildInputDecoration(labelText: label),
        child: Text(time.format(context),
            style: const TextStyle(color: Colors.white, fontSize: 16)),
      ),
    );
  }
}

// --- NEW WIDGET: Replaces the old _openCommentsSheet logic ---
class _CommentsSheet extends StatefulWidget {
  final String eventId;
  final String eventTitle;
  final String? eventDescription; // New parameter
  final Map<String, dynamic>? eventCreator; // New parameter
  final VoidCallback onCommentPosted;

  const _CommentsSheet(
      {required this.eventId,
      required this.eventTitle,
      this.eventDescription,
      this.eventCreator,
      required this.onCommentPosted});

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  late Future<List<Map<String, dynamic>>> _commentsFuture;
  final TextEditingController _commentController = TextEditingController();
  bool _isPosting = false;

  String? _replyingToCommentId;
  String? _replyingToUsername;

  @override
  void initState() {
    super.initState();
    _commentsFuture =
        SupabaseService.instance.fetchCommentsForEvent(widget.eventId);
  }

  void _refreshComments() {
    setState(() {
      _commentsFuture =
          SupabaseService.instance.fetchCommentsForEvent(widget.eventId);
    });
    widget.onCommentPosted();
  }

  void _postComment() async {
    final content = _commentController.text.trim();
    if (content.isEmpty || _isPosting) return;

    setState(() => _isPosting = true);

    try {
      await SupabaseService.instance.addComment(
        eventId: widget.eventId,
        content: content,
        parentCommentId: _replyingToCommentId,
      );
      _commentController.clear();
      _cancelReply();
      _refreshComments();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error posting comment: ${e.toString()}'),
            backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) {
        setState(() => _isPosting = false);
      }
    }
  }

  void _setReplyTo(String commentId, String username) {
    setState(() {
      _replyingToCommentId = commentId;
      _replyingToUsername = username;
    });
  }

  void _cancelReply() {
    setState(() {
      _replyingToCommentId = null;
      _replyingToUsername = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return GlassContainer(
          borderRadius: 20.0,
          padding: EdgeInsets.only(
            top: 12,
            left: 12,
            right: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 12,
          ),
          child: Column(
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[700],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Comments — ${widget.eventTitle}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, color: Colors.white70),
                    )
                  ],
                ),
              ),
              const Divider(color: lightSuedeNavy),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _commentsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                          child: CircularProgressIndicator(
                              color: Colors.cyanAccent));
                    }
                    if (snapshot.hasError) {
                      return Center(
                          child: Text('Error: ${snapshot.error}',
                              style: const TextStyle(color: Colors.red)));
                    }
                    final flatComments = snapshot.data ?? [];
                    final commentsTree = _buildCommentTree(flatComments);

                    final hasDescription = widget.eventDescription != null &&
                        widget.eventDescription!.isNotEmpty;

                    if (!hasDescription && commentsTree.isEmpty) {
                      return const Center(
                          child: Text('No comments yet. Be the first!',
                              style: TextStyle(color: Colors.white70)));
                    }

                    return ListView.builder(
                      controller: scrollController,
                      itemCount: commentsTree.length + (hasDescription ? 1 : 0),
                      itemBuilder: (ctx, index) {
                        // If there is a description, show it as the first item
                        if (hasDescription && index == 0) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                            child: ListTile(
                              leading: const Icon(Icons.info_outline,
                                  color: Colors.white70),
                              title: Text(
                                widget.eventDescription!,
                                style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 15,
                                    fontStyle: FontStyle.italic),
                              ),
                            ),
                          );
                        }

                        // Adjust index for the actual comments
                        final commentIndex = hasDescription ? index - 1 : index;

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: CommentWidget(
                            commentData: commentsTree[commentIndex],
                            onReply: _setReplyTo,
                            onDeleted: _refreshComments,
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              const Divider(color: lightSuedeNavy),
              _buildCommentInputField(),
            ],
          ),
        );
      },
    );
  }

  List<Map<String, dynamic>> _buildCommentTree(
      List<Map<String, dynamic>> comments) {
    final Map<String, List<Map<String, dynamic>>> childrenMap = {};
    final List<Map<String, dynamic>> rootComments = [];

    for (var comment in comments) {
      final parentId = comment['parent_comment_id'] as String?;
      if (parentId == null) {
        rootComments.add(comment);
      } else {
        if (childrenMap[parentId] == null) {
          childrenMap[parentId] = [];
        }
        childrenMap[parentId]!.add(comment);
      }
    }

    for (var comment in rootComments) {
      comment['replies'] = _getReplies(comment['id'], childrenMap);
    }

    return rootComments;
  }

  List<Map<String, dynamic>> _getReplies(
      String commentId, Map<String, List<Map<String, dynamic>>> childrenMap) {
    final replies = childrenMap[commentId] ?? [];
    for (var reply in replies) {
      reply['replies'] = _getReplies(reply['id'], childrenMap);
    }
    return replies;
  }

  Widget _buildCommentInputField() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_replyingToUsername != null)
            Row(
              children: [
                Text('Replying to @$_replyingToUsername',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12)),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.close,
                        size: 16, color: Colors.white70),
                    onPressed: _cancelReply)
              ],
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commentController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Write a comment...',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.03),
                    border: OutlineInputBorder(
                      borderSide: BorderSide.none,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                  ),
                  minLines: 1,
                  maxLines: 4,
                ),
              ),
              const SizedBox(width: 8),
              _isPosting
                  ? const Padding(
                      padding: EdgeInsets.all(12.0),
                      child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2)))
                  : IconButton(
                      icon: const Icon(Icons.send),
                      color: Colors.cyanAccent,
                      onPressed: _postComment,
                    ),
            ],
          ),
        ],
      ),
    );
  }
}

// --- NEW WIDGET: Displays a single comment and its replies recursively ---

class CommentWidget extends StatefulWidget {
  final Map<String, dynamic> commentData;
  final Function(String commentId, String username) onReply;
  final VoidCallback onDeleted;

  const CommentWidget({
    super.key,
    required this.commentData,
    required this.onReply,
    required this.onDeleted,
  });

  @override
  State<CommentWidget> createState() => _CommentWidgetState();
}

class _CommentWidgetState extends State<CommentWidget> {
  late bool _userHasLiked;
  late int _likeCount;
  bool _isLikeProcessing = false;

  @override
  void initState() {
    super.initState();
    _userHasLiked = widget.commentData['user_has_liked'] ?? false;
    _likeCount = widget.commentData['like_count'] ?? 0;
  }

  // --- NEW HELPER FUNCTION ---
  Future<void> _showUserProfile(String userId) async {
    // Show a loading indicator immediately
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final profile = await SupabaseService.instance.fetchUserProfile(userId);
      if (!mounted) return;
      Navigator.of(context).pop(); // Close the loading indicator

      // Show the actual profile card in a dialog
      showDialog(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          child: UserProfileCard(userProfile: profile),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // Close the loading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Could not load profile: ${e.toString()}'),
            backgroundColor: Colors.red),
      );
    }
  }

  void _toggleLike() async {
    if (_isLikeProcessing) return;
    setState(() => _isLikeProcessing = true);

    try {
      if (_userHasLiked) {
        await SupabaseService.instance.unlikeComment(widget.commentData['id']);
        setState(() {
          _userHasLiked = false;
          _likeCount--;
        });
      } else {
        await SupabaseService.instance.likeComment(widget.commentData['id']);
        setState(() {
          _userHasLiked = true;
          _likeCount++;
        });
      }
    } catch (e) {
      setState(() {});
    } finally {
      if (mounted) {
        setState(() => _isLikeProcessing = false);
      }
    }
  }

  void _handleDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dc) => AlertDialog(
        backgroundColor: darkSuedeNavy,
        title: const Text('Delete comment?',
            style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dc).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(dc).pop(true),
              child: const Text('Delete',
                  style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await SupabaseService.instance.deleteComment(widget.commentData['id']);
        widget.onDeleted();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Error: ${e.toString()}'),
              backgroundColor: Colors.red));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.commentData['user'] as Map<String, dynamic>?;
    final commenterName = user?['username'] ?? 'Someone';
    final commenterAvatar = user?['avatar_url'] as String?;
    final commentText = widget.commentData['content'] ?? '';
    final createdAt = widget.commentData['created_at'] != null
        ? DateFormat.yMMMd()
            .add_jm()
            .format(DateTime.parse(widget.commentData['created_at']).toLocal())
        : '';
    final commentOwnerId = widget.commentData['commenter_user_id']?.toString();
    final currentUserId = AuthService.instance.currentUser?.id;

    final replies = (widget.commentData['replies'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- UPDATED: WRAPPED AVATAR IN A BUTTON ---
            GestureDetector(
              onTap: () {
                if (commentOwnerId != null) {
                  _showUserProfile(commentOwnerId);
                }
              },
              child: CircleAvatar(
                radius: 20,
                backgroundColor: lightSuedeNavy,
                backgroundImage: commenterAvatar != null
                    ? NetworkImage(commenterAvatar)
                    : null,
                child: commenterAvatar == null
                    ? Text(commenterName.isNotEmpty
                        ? commenterName[0].toUpperCase()
                        : '?')
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- UPDATED: WRAPPED USERNAME IN A BUTTON ---
                  GestureDetector(
                    onTap: () {
                      if (commentOwnerId != null) {
                        _showUserProfile(commentOwnerId);
                      }
                    },
                    child: Text('@$commenterName',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 4),
                  Text(commentText,
                      style: const TextStyle(color: Colors.white70)),
                ],
              ),
            ),
            if (commentOwnerId == currentUserId)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert,
                    color: Colors.white70, size: 20),
                color: lightSuedeNavy,
                onSelected: (value) {
                  if (value == 'delete') {
                    _handleDelete();
                  }
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  const PopupMenuItem<String>(
                    value: 'delete',
                    child: Text('Delete',
                        style: TextStyle(color: Colors.redAccent)),
                  ),
                ],
              )
            else
              const SizedBox(width: 48),
          ],
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 52),
          child: Row(
            children: [
              Text(createdAt,
                  style: const TextStyle(color: Colors.white38, fontSize: 12)),
              const SizedBox(width: 16),
              InkWell(
                onTap: () =>
                    widget.onReply(widget.commentData['id'], commenterName),
                child: const Text('Reply',
                    style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: 12)),
              ),
              const Spacer(),
              _isLikeProcessing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : InkWell(
                      onTap: _toggleLike,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                              _userHasLiked
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              color: _userHasLiked
                                  ? Colors.redAccent
                                  : Colors.white70,
                              size: 18),
                          if (_likeCount > 0)
                            Padding(
                              padding: const EdgeInsets.only(left: 4.0),
                              child: Text('$_likeCount',
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 14)),
                            )
                        ],
                      ),
                    ),
            ],
          ),
        ),
        if (replies.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 40, top: 12),
            child: Container(
              padding: const EdgeInsets.only(left: 12, top: 12),
              decoration: const BoxDecoration(
                  border: Border(
                      left: BorderSide(color: Colors.white12, width: 1))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: replies
                    .map((reply) => Padding(
                          padding: const EdgeInsets.only(bottom: 12.0),
                          child: CommentWidget(
                            commentData: reply,
                            onReply: widget.onReply,
                            onDeleted: widget.onDeleted,
                          ),
                        ))
                    .toList(),
              ),
            ),
          ),
      ],
    );
  }
}
// --- NEW WIDGET FOR THE NOTIFICATION SHEET ---
// Add this at the end of the file

class NotificationSheet extends StatefulWidget {
  final VoidCallback onClosed;
  const NotificationSheet({required this.onClosed, super.key});

  @override
  State<NotificationSheet> createState() => _NotificationSheetState();
}

class _NotificationSheetState extends State<NotificationSheet> {
  late Future<List<Map<String, dynamic>>> _notificationsFuture;

  @override
  void initState() {
    super.initState();
    _notificationsFuture = SupabaseService.instance.fetchNotifications();
  }

  @override
  void dispose() {
    widget.onClosed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      borderRadius: 20,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text("Notifications",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
            ),
            const Divider(color: lightSuedeNavy, height: 1),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _notificationsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator(
                            color: Colors.cyanAccent));
                  }
                  if (snapshot.hasError ||
                      !snapshot.hasData ||
                      snapshot.data!.isEmpty) {
                    return const Center(
                        child: Text("No notifications yet.",
                            style: TextStyle(color: Colors.white70)));
                  }
                  final notifications = snapshot.data!;
                  return ListView.builder(
                    itemCount: notifications.length,
                    itemBuilder: (context, index) {
                      final notification = notifications[index];
                      final actor =
                          notification['actor'] as Map<String, dynamic>?;
                      final actorUsername = actor?['username'] ?? 'Someone';
                      final actorAvatarUrl = actor?['avatar_url'] as String?;
                      final type = notification['type'];
                      final payload =
                          notification['payload'] as Map<String, dynamic>?;
                      final eventTitle = payload?['event_title'] as String?;
                      final eventStartTimeStr =
                          payload?['event_start_time'] as String?;
                      final commentPreview =
                          payload?['comment_preview'] as String?;

                      // --- START OF THE FIX ---
                      // Safely parse all dates with checks to prevent errors
                      String formattedEventTime = '';
                      if (eventStartTimeStr != null) {
                        try {
                          final eventTime =
                              DateTime.parse(eventStartTimeStr).toLocal();
                          formattedEventTime =
                              DateFormat.yMMMd().add_jm().format(eventTime);
                        } catch (_) {
                          // Handle cases where the date string is invalid
                          formattedEventTime = 'Invalid event time';
                        }
                      }

                      String formattedCreationTime = '';
                      final createdAtStr =
                          notification['created_at'] as String?;
                      if (createdAtStr != null) {
                        try {
                          formattedCreationTime = DateFormat.yMMMd()
                              .add_jm()
                              .format(DateTime.parse(createdAtStr).toLocal());
                        } catch (_) {
                          formattedCreationTime = ' awhile ago';
                        }
                      }
                      // --- END OF THE FIX ---

                      String message = 'did something.';
                      if (type == 'subscription') {
                        message = 'subscribed to your timetable.';
                      } else if (type == 'comment') {
                        message = 'commented on your event:';
                      } else if (type == 'event_created') {
                        message = 'created a new event:';
                      } else if (type == 'event_updated') {
                        message = 'updated an event:';
                      } else if (type == 'event_deleted') {
                        message = 'deleted an event:';
                      }

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: lightSuedeNavy,
                          backgroundImage: actorAvatarUrl != null
                              ? NetworkImage(actorAvatarUrl)
                              : null,
                          child: actorAvatarUrl == null
                              ? Text(actorUsername[0].toUpperCase())
                              : null,
                        ),
                        title: Text('@$actorUsername $message',
                            style: const TextStyle(color: Colors.white)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (eventTitle != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Text(eventTitle,
                                    style: const TextStyle(
                                        color: Colors.white70,
                                        fontWeight: FontWeight.bold)),
                              ),
                            if (commentPreview != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Text('"$commentPreview..."',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontStyle: FontStyle.italic)),
                              ),
                            if (formattedEventTime.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2.0),
                                child: Text(formattedEventTime,
                                    style: const TextStyle(
                                        color: Colors.cyanAccent,
                                        fontSize: 12)),
                              ),
                            Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Text(
                                formattedCreationTime,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
