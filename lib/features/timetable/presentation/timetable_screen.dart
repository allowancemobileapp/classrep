// lib/features/timetable/presentation/timetable_screen.dart

import 'dart:io';
import 'dart:ui';
import 'package:class_rep/features/timetable/presentation/manage_groups_screen.dart';
import 'package:class_rep/shared/services/auth_service.dart';
import 'package:class_rep/shared/services/supabase_service.dart';
import 'package:class_rep/shared/widgets/glass_container.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:url_launcher/url_launcher.dart';

// --- THEME COLORS ---
const Color darkSuedeNavy = Color(0xFF1A1B2C);
const Color lightSuedeNavy = Color(0xFF2A2C40);

class TimetableScreen extends StatefulWidget {
  const TimetableScreen({super.key});

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
  Map<String, dynamic>? _userProfile; // For hamburger menu
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
    _currentUserId = AuthService.instance.currentUser?.id;
    _loadAllData();
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
        SupabaseService.instance
            .getUnreadNotificationsCount(), // Fetch unread count
      ]);
      final rawEvents = (results[0] as List).cast<Map<String, dynamic>>();
      final sharedUsers = (results[1] as List).cast<Map<String, dynamic>>();
      _userProfile = results[2] as Map<String, dynamic>;
      _unreadCount = results[3] as int; // Store the count

      if (!mounted) return;
      setState(() {
        _events = _groupAndExpandEvents(rawEvents);
        _addedTimetables = sharedUsers;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error loading data: $e'),
              backgroundColor: Colors.red),
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
    return Scaffold(
      backgroundColor: darkSuedeNavy,
      appBar: AppBar(
        scrolledUnderElevation: 0.0,
        // automaticallyImplyLeading: false,
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
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: GlassContainer(
                    borderRadius: 16,
                    padding: const EdgeInsets.all(8),
                    child: TableCalendar(
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEditEventModal(),
        backgroundColor: Colors.cyanAccent,
        child: const Icon(Icons.add, color: Colors.black),
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
              // User Profile Section
              ListTile(
                leading: CircleAvatar(
                  radius: 24,
                  backgroundColor: lightSuedeNavy,
                  // --- START OF UPDATE ---
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
                  // --- END OF UPDATE ---
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

              // Add Timetable Section
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
                          Navigator.pop(context); // Close the menu on success
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Timetable added!'),
                                  backgroundColor: Colors.green));
                        } catch (e) {
                          if (!mounted) return;
                          // --- START OF THE FIX ---
                          // Check for our specific error message
                          if (e.toString().contains('Already subscribed')) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(const SnackBar(
                              content: Text(
                                  'You are already subscribed to this user.'),
                              backgroundColor: Colors.orange,
                            ));
                          } else {
                            // Show a generic error for other issues
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text('Error: $e'),
                              backgroundColor: Colors.red,
                            ));
                          }
                          // --- END OF THE FIX ---
                        }
                      },
                    ),
                  ],
                ),
              ),
              const Divider(color: lightSuedeNavy),

              // Management Buttons
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
                  Navigator.pop(context); // Close the main menu first
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
                              final avatarUrl = user['avatar_url']
                                  as String?; // Get avatar URL

                              return ListTile(
                                // --- START OF UPDATE ---
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
                                // --- END OF UPDATE ---
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

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: isMine ? () => _showAddEditEventModal(event: event) : null,
        child: AspectRatio(
          aspectRatio: 16 / 9,
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
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withOpacity(0.8),
                      Colors.transparent,
                      Colors.black.withOpacity(0.8)
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.5, 1.0],
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
                    const SizedBox(width: 16),
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSimpleEventCard(Map<String, dynamic> event) {
    final startTime =
        DateFormat.jm().format(DateTime.parse(event['start_time']).toLocal());
    final title = event['title'] as String? ?? 'No Title';
    final description = event['description'] as String?;
    final creatorUsername = event['creator_username'] as String?;
    final creatorAvatarUrl = event['creator_avatar_url'] as String?;
    final groupName = event['group_name'] as String?;
    final linkUrl = event['url'] as String?;
    final isMine = event['user_id'] == _currentUserId;

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
            Text(startTime,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        onTap: isMine ? () => _showAddEditEventModal(event: event) : null,
      ),
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
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
        ),
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
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    Text(isEditing ? 'Edit Event' : 'Add New Event',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 24),
                    GestureDetector(
                      onTap: () async {
                        final picker = ImagePicker();
                        final file =
                            await picker.pickImage(source: ImageSource.gallery);
                        if (file != null) {
                          setModalState(() => pickedImage = file);
                        }
                      },
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white38, width: 2),
                            image: pickedImage != null
                                ? DecorationImage(
                                    image: FileImage(File(pickedImage!.path)),
                                    fit: BoxFit.cover)
                                : existingImageUrl != null
                                    ? DecorationImage(
                                        image: NetworkImage(existingImageUrl),
                                        fit: BoxFit.cover)
                                    : null,
                          ),
                          child: (pickedImage == null &&
                                  existingImageUrl == null)
                              ? const Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(CupertinoIcons.photo_on_rectangle,
                                          color: Colors.white38, size: 40),
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
                          final day = _selectedDay!;
                          final startDateTime = DateTime(day.year, day.month,
                              day.day, startTime.hour, startTime.minute);

                          // --- START OF FIX ---
                          var endDateTime = DateTime(day.year, day.month,
                              day.day, endTime.hour, endTime.minute);

                          if (endDateTime.isBefore(startDateTime)) {
                            endDateTime =
                                endDateTime.add(const Duration(days: 1));
                          }
                          // --- END OF FIX ---

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
                                  endTime: endDateTime, // Use corrected time
                                  groupId: selectedGroupId,
                                  imageUrl: finalImageUrl,
                                  linkUrl: linkUrlController.text,
                                  repeat: repeatValue);
                            } else {
                              await SupabaseService.instance.createEvent(
                                  title: titleController.text,
                                  description: descriptionController.text,
                                  startTime: startDateTime,
                                  endTime: endDateTime, // Use corrected time
                                  groupId: selectedGroupId,
                                  imageUrl: finalImageUrl,
                                  linkUrl: linkUrlController.text,
                                  repeat: repeatValue);
                            }
                            if (!mounted) return;
                            Navigator.of(context).pop();
                            await _loadAllData();
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text('Error: $e'),
                                backgroundColor: Colors.red));
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
                      TextButton.icon(
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.redAccent),
                        label: const Text('Delete Event',
                            style: TextStyle(color: Colors.redAccent)),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (dialogContext) => AlertDialog(
                              backgroundColor: darkSuedeNavy,
                              title: const Text('Confirm Deletion',
                                  style: TextStyle(color: Colors.white)),
                              content: const Text(
                                  'Are you sure you want to delete this event series?',
                                  style: TextStyle(color: Colors.white70)),
                              actions: [
                                TextButton(
                                    onPressed: () =>
                                        Navigator.of(dialogContext).pop(false),
                                    child: const Text('Cancel')),
                                TextButton(
                                    onPressed: () =>
                                        Navigator.of(dialogContext).pop(true),
                                    child: const Text('Delete',
                                        style: TextStyle(
                                            color: Colors.redAccent))),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            try {
                              Navigator.of(context).pop();
                              await SupabaseService.instance
                                  .deleteEvent(event['id']);
                              await _loadAllData();
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text('Error deleting event: $e'),
                                      backgroundColor: Colors.red));
                            }
                          }
                        },
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

                      // --- START OF UPDATE ---
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
                              Text(eventTitle,
                                  style: const TextStyle(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.bold)),
                            Text(
                              DateFormat.yMMMd().add_jm().format(
                                  DateTime.parse(notification['created_at'])
                                      .toLocal()),
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      );
                      // --- END OF UPDATE ---
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
