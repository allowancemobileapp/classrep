import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:class_rep/shared/services/auth_service.dart';
import 'package:class_rep/shared/services/supabase_service.dart';
import 'package:class_rep/features/timetable/presentation/manage_groups_screen.dart';
import 'package:class_rep/shared/widgets/glass_container.dart';

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
  bool _isPremium = false;
  String? _currentUserId;
  Map<String, dynamic>? _userProfile;
  List<Map<String, dynamic>> _addedTimetables = [];

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
      if (_currentUserId == null) throw Exception("User is not logged in.");

      // Fetch all data concurrently
      final results = await Future.wait([
        SupabaseService.instance.fetchUserProfile(_currentUserId!),
        SupabaseService.instance.fetchEvents(),
        SupabaseService.instance.getMySharedUsers(),
      ]);

      // Safely cast the results from the Future.wait
      final profile = results[0] as Map<String, dynamic>;
      final rawEvents = (results[1] as List).cast<Map<String, dynamic>>();
      final sharedUsers = (results[2] as List).cast<Map<String, dynamic>>();

      if (!mounted) return;

      setState(() {
        _userProfile = profile;
        _isPremium = profile['is_plus'] as bool? ?? false;
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
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Map<DateTime, List<Map<String, dynamic>>> _groupAndExpandEvents(
    List<Map<String, dynamic>> events,
  ) {
    Map<DateTime, List<Map<String, dynamic>>> data = {};
    final now = DateTime.now();
    final horizonEnd = now.add(const Duration(days: 365));

    for (var event in events) {
      final utcStart = DateTime.parse(event['start_time']);
      final duration = DateTime.parse(event['end_time']).difference(utcStart);
      final repeat = event['repeat'] ?? 'none';

      void addOccurrence(DateTime occurrenceStart, {bool isSynthetic = false}) {
        final localDay = occurrenceStart.toLocal();
        final key = DateTime(localDay.year, localDay.month, localDay.day);
        if (data[key] == null) data[key] = [];

        final eventData = Map<String, dynamic>.from(event);
        eventData['start_time'] = occurrenceStart.toIso8601String();
        eventData['end_time'] = occurrenceStart.add(duration).toIso8601String();
        if (isSynthetic) {
          eventData['id'] = '${event['id']}_${localDay.toIso8601String()}';
        }
        data[key]!.add(eventData);
      }

      if (repeat == 'none' || repeat == '') {
        addOccurrence(utcStart);
      } else {
        DateTime cursor = utcStart;
        int count = 0;
        while (cursor.isBefore(horizonEnd) && count < 365) {
          addOccurrence(cursor, isSynthetic: count > 0);
          count++;
          if (repeat == 'daily') {
            cursor = cursor.add(const Duration(days: 1));
          } else if (repeat == 'weekly') {
            cursor = cursor.add(const Duration(days: 7));
          } else if (repeat == 'monthly') {
            cursor = DateTime.utc(
              cursor.year,
              cursor.month + 1,
              cursor.day,
              cursor.hour,
              cursor.minute,
            );
          } else {
            break;
          }
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

  Future<void> _showAddEditEventModal({Map<String, dynamic>? event}) async {
    final bool isEditing = event != null;
    final formKey = GlobalKey<FormState>();

    final titleController = TextEditingController(
      text: isEditing ? event['title'] : '',
    );
    final descriptionController = TextEditingController(
      text: isEditing ? event['description'] : '',
    );
    final imageUrlController = TextEditingController(
      text: isEditing ? event['image_url'] : '',
    );
    final linkUrlController = TextEditingController(
      text: isEditing ? event['url'] : '',
    );

    DateTime parsedStart = isEditing
        ? DateTime.parse(event['start_time']).toLocal()
        : DateTime.now();
    DateTime parsedEnd = isEditing
        ? DateTime.parse(event['end_time']).toLocal()
        : DateTime.now().add(const Duration(hours: 1));

    TimeOfDay startTime = TimeOfDay.fromDateTime(parsedStart);
    TimeOfDay endTime = TimeOfDay.fromDateTime(parsedEnd);

    String? selectedGroupId = isEditing ? event['group_id'] : null;
    String repeatValue = isEditing ? (event['repeat'] ?? 'none') : 'none';

    final groups = await SupabaseService.instance.fetchEventGroups();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (modalContext, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(modalContext).viewInsets.bottom,
          ),
          child: GlassContainer(
            borderRadius: 20.0,
            padding: const EdgeInsets.all(16),
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isEditing ? 'Edit Event' : 'Add New Event',
                      style: const TextStyle(
                        color: Colors.cyanAccent,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: titleController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        labelStyle: TextStyle(color: Colors.white70),
                      ),
                      validator: (val) =>
                          val!.isEmpty ? 'Title is required' : null,
                    ),
                    TextFormField(
                      controller: descriptionController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Description (Optional)',
                        labelStyle: TextStyle(color: Colors.white70),
                      ),
                    ),
                    TextFormField(
                      controller: imageUrlController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Image URL (Optional)',
                        labelStyle: TextStyle(color: Colors.white70),
                      ),
                    ),
                    TextFormField(
                      controller: linkUrlController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Link URL (Optional)',
                        labelStyle: TextStyle(color: Colors.white70),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton.icon(
                          icon: const Icon(
                            Icons.timer_outlined,
                            color: Colors.white70,
                          ),
                          label: Text(
                            'Starts: ${startTime.format(context)}',
                            style: const TextStyle(color: Colors.cyanAccent),
                          ),
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: context,
                              initialTime: startTime,
                            );
                            if (picked != null)
                              setModalState(() => startTime = picked);
                          },
                        ),
                        TextButton.icon(
                          icon: const Icon(
                            Icons.timer_off_outlined,
                            color: Colors.white70,
                          ),
                          label: Text(
                            'Ends: ${endTime.format(context)}',
                            style: const TextStyle(color: Colors.cyanAccent),
                          ),
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: context,
                              initialTime: endTime,
                            );
                            if (picked != null)
                              setModalState(() => endTime = picked);
                          },
                        ),
                      ],
                    ),
                    DropdownButtonFormField<String>(
                      value: selectedGroupId,
                      hint: const Text(
                        'Assign to a group (optional)',
                        style: TextStyle(color: Colors.white70),
                      ),
                      dropdownColor: Colors.grey[900],
                      style: const TextStyle(color: Colors.white),
                      items: groups
                          .map<DropdownMenuItem<String>>(
                            (g) => DropdownMenuItem<String>(
                              value: g['id'] as String,
                              child: Text(g['group_name'] as String),
                            ),
                          )
                          .toList(),
                      onChanged: (val) =>
                          setModalState(() => selectedGroupId = val),
                    ),

                    DropdownButtonFormField<String>(
                      value: repeatValue,
                      items: const [
                        DropdownMenuItem(
                          value: 'none',
                          child: Text('Does not repeat'),
                        ),
                        DropdownMenuItem(
                          value: 'daily',
                          child: Text('Repeats Daily'),
                        ),
                        DropdownMenuItem(
                          value: 'weekly',
                          child: Text('Repeats Weekly'),
                        ),
                        DropdownMenuItem(
                          value: 'monthly',
                          child: Text('Repeats Monthly'),
                        ),
                      ],
                      onChanged: (val) =>
                          setModalState(() => repeatValue = val ?? 'none'),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () async {
                        if (formKey.currentState!.validate()) {
                          final startDateTime = DateTime(
                            _selectedDay!.year,
                            _selectedDay!.month,
                            _selectedDay!.day,
                            startTime.hour,
                            startTime.minute,
                          );
                          final endDateTime = DateTime(
                            _selectedDay!.year,
                            _selectedDay!.month,
                            _selectedDay!.day,
                            endTime.hour,
                            endTime.minute,
                          );

                          if (endDateTime.isBefore(startDateTime)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'End time must be after start time.',
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
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
                                imageUrl: imageUrlController.text,
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
                                imageUrl: imageUrlController.text,
                                linkUrl: linkUrlController.text,
                                repeat: repeatValue,
                              );
                            }

                            Navigator.of(context).pop();
                            await _loadAllData();
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error saving event: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                      child: Text(
                        isEditing ? 'Save Changes' : 'Create Event',
                        style: const TextStyle(color: Colors.black),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.cyanAccent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 50,
                          vertical: 15,
                        ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text(
          'Timetable',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () {
              /* TODO: Hamburger menu logic */
            },
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
                      calendarBuilders: CalendarBuilders(
                        markerBuilder: (context, date, events) {
                          if (events.isEmpty) return null;

                          // Accept only Map<String, dynamic> items and collect group_color strings safely
                          final eventMaps = events
                              .where((e) => e is Map<String, dynamic>)
                              .map((e) => e as Map<String, dynamic>)
                              .toList();

                          final List<String> colors = eventMaps
                              .map((m) => m['group_color'])
                              .whereType<String>()
                              .toSet()
                              .toList();

                          if (colors.isEmpty) return null;

                          final int dotCount = colors.length > 3
                              ? 3
                              : colors.length;

                          return Positioned(
                            bottom: 1,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: List.generate(dotCount, (index) {
                                final colorHex = colors[index];
                                // Safely parse hex color; fallback to cyan if parse fails
                                int colorValue;
                                try {
                                  final hex = colorHex.startsWith('#')
                                      ? colorHex.substring(1)
                                      : colorHex;
                                  // ensure we only keep first 6 chars if someone passed longer
                                  final cleanHex = hex.length >= 6
                                      ? hex.substring(0, 6)
                                      : hex;
                                  colorValue =
                                      int.parse(cleanHex, radix: 16) |
                                      0xFF000000;
                                } catch (_) {
                                  colorValue = 0xFF00BCD4; // cyan-ish fallback
                                }

                                return Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 1.5,
                                  ),
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color(colorValue),
                                  ),
                                );
                              }),
                            ),
                          );
                        },
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

  Widget _buildEventList() {
    final selectedEvents = _selectedDay != null
        ? _getEventsForDay(_selectedDay!)
        : [];

    if (selectedEvents.isEmpty) {
      return const Center(
        child: Text(
          'No events for this day.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    selectedEvents.sort(
      (a, b) => DateTime.parse(
        a['start_time'],
      ).compareTo(DateTime.parse(b['start_time'])),
    );

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: selectedEvents.length,
      itemBuilder: (context, index) {
        final event = selectedEvents[index];
        final startTime = DateFormat.jm().format(
          DateTime.parse(event['start_time']).toLocal(),
        );
        final isMine = event['creator_user_id'] == _currentUserId;
        final eventId = event['id'] as String;
        final isSynthetic = eventId.contains('_');

        final title = event['title'] as String? ?? 'No Title';
        final description = event['description'] as String? ?? '';

        return Card(
          color: Colors.white10,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            title: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: description.isNotEmpty
                ? Text(
                    description,
                    style: const TextStyle(color: Colors.white70),
                  )
                : null,
            trailing: Text(
              startTime,
              style: const TextStyle(
                color: Colors.cyanAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
            onTap: isMine && !isSynthetic
                ? () => _showAddEditEventModal(event: event)
                : null,
          ),
        );
      },
    );
  }
}
