// lib/features/timetable/presentation/timetable_screen.dart

import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:image_picker/image_picker.dart';
import 'package:class_rep/shared/services/auth_service.dart';
import 'package:class_rep/shared/services/supabase_service.dart';
import 'package:class_rep/shared/widgets/glass_container.dart';
import 'manage_groups_screen.dart'; // Assuming this screen exists for managing groups

class TimetableScreen extends StatefulWidget {
  const TimetableScreen({super.key});

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  String? _selectedUserId; // used when selecting an added user's events
  Map<DateTime, List<Map<String, dynamic>>> _events = {};
  bool _loading = true;
  bool _isPremium = false;
  List<Map<String, dynamic>> _addedTimetables = []; // shared users
  String? _currentUserId;
  List<Map<String, dynamic>> _notifications = [];
  int _unreadCount = 0;
  bool _notifLoading = false;
  Timer? _notifTimer;

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    _currentUserId = AuthService.instance.currentUser?.id;
    _initAll();
    _initNotifications();
  }

  // Helper: returns true if the id looks like a synthetic expanded occurrence (e.g. "<uuid>_r3")
  bool _isSyntheticOccurrenceId(String? id) {
    if (id == null) return false;
    return id.contains('_r');
  }

  // Centralized SnackBar for synthetic-occurrence edit/delete attempts
  void _showCannotEditOccurrenceSnack() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'This is a single instance of a recurring event and cannot be edited or deleted individually. '
          'Open the original event to edit the series.',
        ),
        backgroundColor: Colors.orange,
      ),
    );
  }

  Future<void> _initAll() async {
    await _checkPremium();
    await _loadSharedUsers();
    await _loadEvents();
  }

  @override
  void dispose() {
    try {
      _notifTimer?.cancel();
    } catch (_) {}
    super.dispose();
  }

  // ---------- DATA LOADING ----------

  Future<void> _checkPremium() async {
    final uid = _currentUserId;
    if (uid == null) return;
    try {
      final profile = await SupabaseService.instance.fetchUserProfile(uid);
      if (!mounted) return;
      setState(() {
        _isPremium = profile['is_plus'] as bool? ?? false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isPremium = false);
    }
  }

  Future<void> _loadSharedUsers() async {
    try {
      final users = await SupabaseService.instance.getMySharedUsers();
      if (!mounted) return;
      setState(() {
        _addedTimetables = users;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load added timetables: $e')),
        );
      }
    }
  }

  Future<void> _loadEvents() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final allEvents = await SupabaseService.instance.fetchEvents();

      final Map<DateTime, List<Map<String, dynamic>>> temp = {};

      for (final event in allEvents) {
        // Accept String or DateTime for start_time and end_time
        final rawStart = event['start_time'];
        final rawEnd = event['end_time'];

        if (rawStart == null || rawEnd == null) continue; // skip malformed

        DateTime utcStart;
        DateTime utcEnd;
        if (rawStart is String) {
          utcStart = DateTime.parse(rawStart).toUtc();
        } else if (rawStart is DateTime) {
          utcStart = rawStart.toUtc();
        } else {
          continue; // skip malformed
        }

        if (rawEnd is String) {
          utcEnd = DateTime.parse(rawEnd).toUtc();
        } else if (rawEnd is DateTime) {
          utcEnd = rawEnd.toUtc();
        } else {
          // fallback: assume 1-hour event
          utcEnd = utcStart.add(const Duration(hours: 1));
        }

        final repeat = (event['repeat'] as String?) ?? 'none';

        // --- Determine owner info (try several places) ---
        String? ownerId;
        String? ownerUsername;
        String? ownerAvatarUrl;

        final ownerRaw =
            event['event_owner'] ?? event['owner'] ?? event['user'];

        if (ownerRaw is Map) {
          final ownerMap = Map<String, dynamic>.from(ownerRaw);
          ownerId = ownerMap['id']?.toString();
          ownerUsername = ownerMap['username']?.toString();
          ownerAvatarUrl = ownerMap['avatar_url']?.toString();
        } else if (ownerRaw is String) {
          ownerId = ownerRaw;
        }

        // fallback to dedicated owner_id/user_id field if present and ownerId still null
        if (ownerId == null &&
            (event['owner_id'] is String ||
                event['creator_user_id'] is String)) {
          ownerId =
              (event['owner_id'] as String?) ??
              (event['creator_user_id'] as String?);
        }

        // If username/avatar still not found, try matching against the loaded _addedTimetables
        if ((ownerUsername == null || ownerAvatarUrl == null) &&
            ownerId != null) {
          try {
            final match = _addedTimetables.firstWhere(
              (u) => (u['id']?.toString() ?? '') == ownerId,
              orElse: () => <String, dynamic>{},
            );
            if (match.isNotEmpty) {
              ownerUsername ??= match['username'] as String?;
              ownerAvatarUrl ??= match['avatar_url'] as String?;
            }
          } catch (_) {
            // ignore
          }
        }

        // Helper to add an occurrence to the map (using a copy so original data isn't mutated)
        void addOccurrence(
          DateTime occurrenceStartUtc,
          DateTime occurrenceEndUtc,
          int occurrenceIndex,
        ) {
          final local = occurrenceStartUtc.toLocal();
          final key = DateTime(local.year, local.month, local.day);

          // Make a shallow copy and choose id carefully:
          // - If this is the first occurrence (index 0), keep the original DB id so edits/deletes work.
          // - For expanded repeated occurrences (index > 0), append _rN to avoid collisions.
          final copy = Map<String, dynamic>.from(event);
          final originalId = event['id']?.toString() ?? '';

          if (occurrenceIndex == 0) {
            // keep exact DB id for first occurrence
            copy['id'] = originalId;
          } else {
            // synthetic id for expanded occurrences only
            copy['id'] = '${originalId}_r$occurrenceIndex';
          }

          copy['start_time'] = occurrenceStartUtc.toIso8601String();
          copy['end_time'] = occurrenceEndUtc.toIso8601String();

          // Attach owner metadata for easier rendering later
          if (ownerId != null) copy['owner_id'] = ownerId;
          if (ownerUsername != null) copy['owner_username'] = ownerUsername;
          if (ownerAvatarUrl != null) copy['owner_avatar_url'] = ownerAvatarUrl;

          temp.putIfAbsent(key, () => []).add(copy);
        }

        if (repeat == 'none' || repeat.trim().isEmpty) {
          // single occurrence
          addOccurrence(utcStart, utcEnd, 0);
        } else {
          // expand recurring occurrences between now and horizonEnd (simple, no past)
          final now = DateTime.now();
          final horizonEnd = now.add(const Duration(days: 365));
          DateTime current = utcStart;
          int idx = 0;
          DateTime occStart = current;
          DateTime occEnd = utcEnd.add(occStart.difference(utcStart));

          while (occStart.toLocal().isBefore(horizonEnd)) {
            addOccurrence(occStart, occEnd, idx);

            if (repeat == 'daily') {
              occStart = occStart.add(const Duration(days: 1));
              occEnd = occEnd.add(const Duration(days: 1));
            } else if (repeat == 'weekly') {
              occStart = occStart.add(const Duration(days: 7));
              occEnd = occEnd.add(const Duration(days: 7));
            } else if (repeat == 'monthly') {
              final nextStartLocal = DateTime.utc(
                occStart.year,
                occStart.month + 1,
                occStart.day,
                occStart.hour,
                occStart.minute,
                occStart.second,
              );
              final dur = occEnd.difference(occStart);
              occStart = nextStartLocal;
              occEnd = occStart.add(dur);
            } else {
              break;
            }
            idx++;
            if (idx > 500) break;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _events = temp;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not load events: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------- HELPERS ----------

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    setState(() {
      _selectedDay = DateTime(
        selectedDay.year,
        selectedDay.month,
        selectedDay.day,
      );
      _focusedDay = focusedDay;
      _selectedUserId = null; // clear filter when user selects a new day
    });
  }

  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    final key = DateTime(day.year, day.month, day.day);
    return _events[key] ?? [];
  }

  /// Builds a consistent drag handle for the top of modal sheets.
  Widget _buildDragHandle() {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey[700],
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  DateTime _parseToLocal(dynamic raw) {
    if (raw is String) return DateTime.parse(raw).toLocal();
    if (raw is DateTime) return raw.toLocal();
    return DateTime.now();
  }

  // ---------- NOTIFICATIONS (Supabase Polling Only) ----------

  Future<void> _initNotifications() async {
    // Initial fetch of both list & unread count
    await _fetchNotificationsAndCount();

    // Periodic refresh: every 10 seconds (simple and reliable).
    _notifTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      try {
        await _fetchUnreadCount();
      } catch (_) {}
    });
  }

  Future<void> _fetchNotificationsAndCount() async {
    try {
      setState(() => _notifLoading = true);
      // TODO: Implement fetchNotifications and fetchUnreadCount in SupabaseService
      final list = <Map<String, dynamic>>[]; // Placeholder
      final unread = 0; // Placeholder
      if (!mounted) return;
      setState(() {
        _notifications = list;
        _unreadCount = unread;
        _notifLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _notifLoading = false;
      });
      debugPrint('Notification fetch failed: $e');
    }
  }

  Future<void> _fetchUnreadCount() async {
    try {
      // TODO: Implement in SupabaseService
      final unread = 0; // Placeholder
      if (!mounted) return;
      setState(() => _unreadCount = unread);
    } catch (e) {
      debugPrint('Unread count fetch failed: $e');
    }
  }

  Future<void> _markNotificationRead(int id) async {
    try {
      // TODO: Implement markNotificationRead in SupabaseService
      await _fetchNotificationsAndCount(); // fallback: refresh
    } catch (e) {
      debugPrint('Mark read failed: $e');
    }
  }

  Future<void> _markAllNotificationsRead() async {
    try {
      // TODO: Implement markAllNotificationsRead in SupabaseService
      await _fetchNotificationsAndCount();
    } catch (e) {
      debugPrint('Mark all read failed: $e');
    }
  }

  // ---------- Notifications modal ----------
  Future<void> _openNotificationsModal() async {
    // Ensure latest notifications are loaded before opening
    await _fetchNotificationsAndCount();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: GlassContainer(
            borderRadius: 20.0,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.75,
              child: Column(
                children: [
                  _buildDragHandle(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Notifications',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _markAllNotificationsRead,
                          child: const Text('Mark all read'),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white24, height: 1),
                  Expanded(
                    child: _notifications.isEmpty
                        ? const Center(
                            child: Text(
                              'No notifications',
                              style: TextStyle(color: Colors.white70),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(8),
                            itemCount: _notifications.length,
                            separatorBuilder: (_, __) =>
                                const Divider(color: Colors.white10),
                            itemBuilder: (ctx, i) {
                              final n = _notifications[i];
                              final actor =
                                  (n['actor_username'] as String?) ??
                                  (n['actor_id'] as String? ?? 'Someone');
                              final avatar = n['actor_avatar_url'] as String?;
                              final action =
                                  (n['action'] as String?) ?? 'did something';
                              final created = n['created_at'] != null
                                  ? DateTime.parse(n['created_at']).toLocal()
                                  : null;
                              final read = (n['read'] == true);

                              // --- extract payload details
                              final payload = n['payload'];
                              String? eventTitle;
                              String? eventWhen;
                              if (payload != null && payload is Map) {
                                eventTitle = payload['title'] as String?;
                                final startRaw = payload['start_time'];
                                if (startRaw != null) {
                                  try {
                                    final dt = DateTime.parse(
                                      startRaw,
                                    ).toLocal();
                                    eventWhen = DateFormat.yMMMd()
                                        .add_jm()
                                        .format(dt);
                                  } catch (_) {}
                                }
                              }

                              String title = '@$actor ';
                              if (action == 'created') {
                                title += 'created an event';
                              } else if (action == 'updated') {
                                title += 'updated an event';
                              } else if (action == 'deleted') {
                                title += 'deleted an event';
                              } else {
                                title += action;
                              }

                              return ListTile(
                                leading: avatar != null
                                    ? CircleAvatar(
                                        backgroundImage: NetworkImage(avatar),
                                      )
                                    : const CircleAvatar(
                                        child: Icon(Icons.person),
                                      ),
                                title: Text(
                                  title,
                                  style: TextStyle(
                                    color: read ? Colors.white70 : Colors.white,
                                    fontWeight: read
                                        ? FontWeight.normal
                                        : FontWeight.bold,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (eventTitle != null)
                                      Text(
                                        eventTitle,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13,
                                        ),
                                      ),
                                    if (eventWhen != null)
                                      Text(
                                        eventWhen,
                                        style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 12,
                                        ),
                                      ),
                                    if (created != null)
                                      Text(
                                        'Notified: ${DateFormat.yMMMd().add_jm().format(created)}',
                                        style: const TextStyle(
                                          color: Colors.white38,
                                          fontSize: 11,
                                        ),
                                      ),
                                  ],
                                ),
                                trailing: read
                                    ? null
                                    : IconButton(
                                        icon: const Icon(
                                          Icons.mark_email_read,
                                          color: Colors.cyanAccent,
                                        ),
                                        onPressed: () {
                                          final id = n['id'] as int?;
                                          if (id != null) {
                                            _markNotificationRead(id);
                                            setState(() {
                                              n['read'] = true;
                                            });
                                          }
                                        },
                                      ),
                                onTap: () {
                                  final id = n['id'] as int?;
                                  if (id != null) {
                                    _markNotificationRead(id);
                                    setState(() {
                                      n['read'] = true;
                                    });
                                  }
                                  Navigator.of(context).pop();
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------- ADD / EDIT / DELETE ----------

  Future<void> _addEvent() async {
    if (_selectedDay == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a date first to add an event.')),
      );
      return;
    }

    final groups = await SupabaseService.instance.fetchEventGroups();
    if (!mounted) return;

    final formKey = GlobalKey<FormState>();
    String? title;
    String? description;
    String? selectedGroupId;
    TimeOfDay startTime = const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay endTime = const TimeOfDay(hour: 10, minute: 0);
    String repeat = 'none';
    XFile? pickedImage;
    String? imageUrl;
    String? linkUrl;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext modalContext, StateSetter setModalState) {
            final groupItems = groups
                .where((g) => g['id'] != null && g['id'].toString().isNotEmpty)
                .map<DropdownMenuItem<String>>((g) {
                  final id = g['id'].toString();
                  final name = g['group_name']?.toString() ?? 'Group';
                  return DropdownMenuItem<String>(value: id, child: Text(name));
                })
                .toList();

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(modalContext).viewInsets.bottom,
              ),
              child: GlassContainer(
                borderRadius: 20.0,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.75,
                  child: Column(
                    children: [
                      _buildDragHandle(),
                      Expanded(
                        child: Form(
                          key: formKey,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                  'New Event',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.cyanAccent,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  decoration: const InputDecoration(
                                    labelText: 'Title',
                                    labelStyle: TextStyle(
                                      color: Colors.white70,
                                    ),
                                  ),
                                  style: const TextStyle(color: Colors.white),
                                  validator: (v) => (v == null || v.isEmpty)
                                      ? 'Enter a title'
                                      : null,
                                  onSaved: (v) => title = v,
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  decoration: const InputDecoration(
                                    labelText: 'Description (optional)',
                                    labelStyle: TextStyle(
                                      color: Colors.white70,
                                    ),
                                  ),
                                  style: const TextStyle(color: Colors.white),
                                  maxLines: 2,
                                  onSaved: (v) => description = v,
                                ),
                                const SizedBox(height: 12),
                                if (groupItems.isNotEmpty)
                                  DropdownButtonFormField<String>(
                                    value: selectedGroupId,
                                    hint: const Text(
                                      'Assign to a group (optional)',
                                      style: TextStyle(color: Colors.white70),
                                    ),
                                    dropdownColor: const Color.fromRGBO(
                                      30,
                                      30,
                                      30,
                                      1,
                                    ),
                                    style: const TextStyle(color: Colors.white),
                                    items: groupItems,
                                    onChanged: (v) => setModalState(
                                      () => selectedGroupId = v,
                                    ),
                                    onSaved: (v) => selectedGroupId = v,
                                  ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        const Text(
                                          'Starts at:',
                                          style: TextStyle(
                                            color: Colors.white70,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        TextButton(
                                          onPressed: () async {
                                            final picked = await showTimePicker(
                                              context: modalContext,
                                              initialTime: startTime,
                                            );
                                            if (picked != null) {
                                              setModalState(
                                                () => startTime = picked,
                                              );
                                            }
                                          },
                                          child: Text(
                                            startTime.format(modalContext),
                                            style: const TextStyle(
                                              color: Colors.cyanAccent,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        const Text(
                                          'Ends at:',
                                          style: TextStyle(
                                            color: Colors.white70,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        TextButton(
                                          onPressed: () async {
                                            final picked = await showTimePicker(
                                              context: modalContext,
                                              initialTime: endTime,
                                            );
                                            if (picked != null) {
                                              setModalState(
                                                () => endTime = picked,
                                              );
                                            }
                                          },
                                          child: Text(
                                            endTime.format(modalContext),
                                            style: const TextStyle(
                                              color: Colors.cyanAccent,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                DropdownButtonFormField<String>(
                                  value: repeat,
                                  decoration: const InputDecoration(
                                    labelText: 'Repeat',
                                    labelStyle: TextStyle(
                                      color: Colors.white70,
                                    ),
                                  ),
                                  dropdownColor: const Color.fromRGBO(
                                    30,
                                    30,
                                    30,
                                    1,
                                  ),
                                  style: const TextStyle(color: Colors.white),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'none',
                                      child: Text('Does not repeat'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'daily',
                                      child: Text('Every day'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'weekly',
                                      child: Text('Every week'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'monthly',
                                      child: Text('Every month'),
                                    ),
                                  ],
                                  onChanged: (v) =>
                                      setModalState(() => repeat = v ?? 'none'),
                                  onSaved: (v) => repeat = v ?? 'none',
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  decoration: const InputDecoration(
                                    labelText: 'URL (optional)',
                                    labelStyle: TextStyle(
                                      color: Colors.white70,
                                    ),
                                  ),
                                  style: const TextStyle(color: Colors.white),
                                  onSaved: (v) => linkUrl = v,
                                ),
                                const SizedBox(height: 12),
                                ListTile(
                                  title: const Text(
                                    'Pick Image (optional)',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  leading:
                                      pickedImage != null || imageUrl != null
                                      ? const Icon(
                                          Icons.image,
                                          color: Colors.cyanAccent,
                                        )
                                      : null,
                                  onTap: () async {
                                    final picker = ImagePicker();
                                    final image = await picker.pickImage(
                                      source: ImageSource.gallery,
                                    );
                                    if (image != null) {
                                      setModalState(() => pickedImage = image);
                                    }
                                  },
                                ),
                                if (pickedImage != null)
                                  Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Image.file(
                                      File(pickedImage!.path),
                                      height: 100,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                if (imageUrl != null && pickedImage == null)
                                  Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Image.network(
                                      imageUrl,
                                      height: 100,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              const Icon(
                                                Icons.broken_image,
                                                size: 50,
                                                color: Colors.white70,
                                              ),
                                    ),
                                  ),
                                const SizedBox(height: 24),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.cyanAccent,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: () async {
                                    if (!(formKey.currentState?.validate() ??
                                        false)) {
                                      return;
                                    }
                                    formKey.currentState?.save();

                                    final startDT = DateTime(
                                      _selectedDay!.year,
                                      _selectedDay!.month,
                                      _selectedDay!.day,
                                      startTime.hour,
                                      startTime.minute,
                                    );
                                    final endDT = DateTime(
                                      _selectedDay!.year,
                                      _selectedDay!.month,
                                      _selectedDay!.day,
                                      endTime.hour,
                                      endTime.minute,
                                    );

                                    try {
                                      String? newImageUrl = imageUrl;
                                      if (pickedImage != null) {
                                        final bytes = await File(
                                          pickedImage!.path,
                                        ).readAsBytes();
                                        newImageUrl = await SupabaseService
                                            .instance
                                            .uploadEventImage(
                                              filePath: pickedImage!.path,
                                              fileBytes: bytes.toList(),
                                            );
                                      }
                                      await SupabaseService.instance
                                          .createEvent(
                                            groupId: selectedGroupId,
                                            title: title!,
                                            description: description,
                                            startTime: startDT,
                                            endTime: endDT,
                                            // repeat: repeat == 'none'
                                            // ? ''
                                            // : repeat,
                                            imageUrl: newImageUrl,
                                            linkUrl: linkUrl,
                                          );
                                      if (!mounted) return;
                                      Navigator.of(modalContext).pop();
                                      await _loadEvents();
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('Event saved'),
                                          backgroundColor: Colors.green,
                                        ),
                                      );
                                    } catch (e) {
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Error saving event: $e',
                                          ),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  },
                                  child: const Text(
                                    'Save Event',
                                    style: TextStyle(color: Colors.black),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _editEvent(Map<String, dynamic> event) async {
    final groups = await SupabaseService.instance.fetchEventGroups();
    if (!mounted) return;

    final String? rawEventId = event['id']?.toString();
    if (rawEventId == null || rawEventId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Event ID missing — cannot edit this event.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Block editing of synthetic recurring-instance ids (those with _r suffix)
    if (_isSyntheticOccurrenceId(rawEventId)) {
      _showCannotEditOccurrenceSnack();
      return;
    }

    final String eventId = rawEventId;

    final formKey = GlobalKey<FormState>();
    String title = event['title'] ?? '';
    String? description = event['description'];
    String? selectedGroupId = event['group_id'];
    DateTime parsedStart = _parseToLocal(event['start_time']);
    DateTime parsedEnd = _parseToLocal(event['end_time']);
    TimeOfDay startTime = TimeOfDay.fromDateTime(parsedStart);
    TimeOfDay endTime = TimeOfDay.fromDateTime(parsedEnd);
    String repeat = (event['repeat'] as String?) ?? 'none';
    String? imageUrl = event['image_url'];
    String? linkUrl = event['url'];
    XFile? pickedImage;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext modalContext, StateSetter setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(modalContext).viewInsets.bottom,
              ),
              child: GlassContainer(
                borderRadius: 20.0,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.75,
                  child: Column(
                    children: [
                      _buildDragHandle(),
                      Expanded(
                        child: Form(
                          key: formKey,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                  'Edit Event',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.cyanAccent,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  initialValue: title,
                                  decoration: const InputDecoration(
                                    labelText: 'Title',
                                    labelStyle: TextStyle(
                                      color: Colors.white70,
                                    ),
                                  ),
                                  style: const TextStyle(color: Colors.white),
                                  validator: (v) => (v == null || v.isEmpty)
                                      ? 'Enter a title'
                                      : null,
                                  onSaved: (v) => title = v ?? '',
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  initialValue: description,
                                  decoration: const InputDecoration(
                                    labelText: 'Description (optional)',
                                    labelStyle: TextStyle(
                                      color: Colors.white70,
                                    ),
                                  ),
                                  style: const TextStyle(color: Colors.white),
                                  maxLines: 2,
                                  onSaved: (v) => description = v,
                                ),
                                const SizedBox(height: 12),
                                if (groups.isNotEmpty)
                                  DropdownButtonFormField<String>(
                                    value: selectedGroupId,
                                    hint: const Text(
                                      'Assign to a group (optional)',
                                      style: TextStyle(color: Colors.white70),
                                    ),
                                    dropdownColor: const Color.fromRGBO(
                                      30,
                                      30,
                                      30,
                                      1,
                                    ),
                                    style: const TextStyle(color: Colors.white),
                                    items: groups
                                        .map(
                                          (group) => DropdownMenuItem(
                                            value: group['id'] as String,
                                            child: Text(
                                              group['group_name'] as String,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (v) => setModalState(
                                      () => selectedGroupId = v,
                                    ),
                                    onSaved: (v) => selectedGroupId = v,
                                  ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        const Text(
                                          'Starts at:',
                                          style: TextStyle(
                                            color: Colors.white70,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        TextButton(
                                          onPressed: () async {
                                            final picked = await showTimePicker(
                                              context: modalContext,
                                              initialTime: startTime,
                                            );
                                            if (picked != null)
                                              setModalState(
                                                () => startTime = picked,
                                              );
                                          },
                                          child: Text(
                                            startTime.format(modalContext),
                                            style: const TextStyle(
                                              color: Colors.cyanAccent,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        const Text(
                                          'Ends at:',
                                          style: TextStyle(
                                            color: Colors.white70,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        TextButton(
                                          onPressed: () async {
                                            final picked = await showTimePicker(
                                              context: modalContext,
                                              initialTime: endTime,
                                            );
                                            if (picked != null)
                                              setModalState(
                                                () => endTime = picked,
                                              );
                                          },
                                          child: Text(
                                            endTime.format(modalContext),
                                            style: const TextStyle(
                                              color: Colors.cyanAccent,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                DropdownButtonFormField<String>(
                                  value: repeat,
                                  decoration: const InputDecoration(
                                    labelText: 'Repeat',
                                    labelStyle: TextStyle(
                                      color: Colors.white70,
                                    ),
                                  ),
                                  dropdownColor: const Color.fromRGBO(
                                    30,
                                    30,
                                    30,
                                    1,
                                  ),
                                  style: const TextStyle(color: Colors.white),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'none',
                                      child: Text('Does not repeat'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'daily',
                                      child: Text('Every day'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'weekly',
                                      child: Text('Every week'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'monthly',
                                      child: Text('Every month'),
                                    ),
                                  ],
                                  onChanged: (v) =>
                                      setModalState(() => repeat = v ?? 'none'),
                                  onSaved: (v) => repeat = v ?? 'none',
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  initialValue: linkUrl,
                                  decoration: const InputDecoration(
                                    labelText: 'URL (optional)',
                                    labelStyle: TextStyle(
                                      color: Colors.white70,
                                    ),
                                  ),
                                  style: const TextStyle(color: Colors.white),
                                  onSaved: (v) => linkUrl = v,
                                ),
                                const SizedBox(height: 12),
                                ListTile(
                                  title: const Text(
                                    'Pick Image (optional)',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  leading:
                                      pickedImage != null || imageUrl != null
                                      ? const Icon(
                                          Icons.image,
                                          color: Colors.cyanAccent,
                                        )
                                      : null,
                                  onTap: () async {
                                    final picker = ImagePicker();
                                    final image = await picker.pickImage(
                                      source: ImageSource.gallery,
                                    );
                                    if (image != null) {
                                      setModalState(() => pickedImage = image);
                                    }
                                  },
                                ),
                                if (pickedImage != null)
                                  Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Image.file(
                                      File(pickedImage!.path),
                                      height: 100,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                if (imageUrl != null && pickedImage == null)
                                  Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Image.network(
                                      imageUrl,
                                      height: 100,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              const Icon(
                                                Icons.broken_image,
                                                size: 50,
                                                color: Colors.white70,
                                              ),
                                    ),
                                  ),
                                const SizedBox(height: 24),
                                Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete,
                                        color: Colors.redAccent,
                                      ),
                                      onPressed: () async {
                                        final confirm = await showDialog<bool>(
                                          context: modalContext,
                                          builder: (dialogCtx) => AlertDialog(
                                            backgroundColor:
                                                const Color.fromRGBO(
                                                  30,
                                                  30,
                                                  30,
                                                  0.9,
                                                ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
                                            title: const Text(
                                              'Confirm Deletion',
                                              style: TextStyle(
                                                color: Colors.white,
                                              ),
                                            ),
                                            content: const Text(
                                              'Are you sure you want to delete this event?',
                                              style: TextStyle(
                                                color: Colors.white70,
                                              ),
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.of(
                                                  dialogCtx,
                                                ).pop(false),
                                                child: const Text('Cancel'),
                                              ),
                                              TextButton(
                                                onPressed: () => Navigator.of(
                                                  dialogCtx,
                                                ).pop(true),
                                                child: const Text(
                                                  'Delete',
                                                  style: TextStyle(
                                                    color: Colors.red,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );

                                        if (confirm == true) {
                                          try {
                                            await SupabaseService.instance
                                                .deleteEvent(eventId);
                                            if (!mounted) return;
                                            Navigator.of(modalContext).pop();
                                            await _loadEvents();
                                            if (!mounted) return;
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text('Event deleted'),
                                                backgroundColor: Colors.green,
                                              ),
                                            );
                                          } catch (e) {
                                            if (!mounted) return;
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Error deleting: $e',
                                                ),
                                                backgroundColor: Colors.red,
                                              ),
                                            );
                                          }
                                        }
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.cyanAccent,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 16,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                        ),
                                        onPressed: () async {
                                          if (!(formKey.currentState
                                                  ?.validate() ??
                                              false)) {
                                            return;
                                          }
                                          formKey.currentState?.save();

                                          final startDT = DateTime(
                                            _selectedDay!.year,
                                            _selectedDay!.month,
                                            _selectedDay!.day,
                                            startTime.hour,
                                            startTime.minute,
                                          );
                                          final endDT = DateTime(
                                            _selectedDay!.year,
                                            _selectedDay!.month,
                                            _selectedDay!.day,
                                            endTime.hour,
                                            endTime.minute,
                                          );

                                          try {
                                            String? newImageUrl = imageUrl;
                                            if (pickedImage != null) {
                                              final bytes = await File(
                                                pickedImage!.path,
                                              ).readAsBytes();
                                              newImageUrl =
                                                  await SupabaseService.instance
                                                      .uploadEventImage(
                                                        filePath:
                                                            pickedImage!.path,
                                                        fileBytes: bytes
                                                            .toList(),
                                                      );
                                            }
                                            await SupabaseService.instance
                                                .updateEvent(
                                                  eventId: eventId,
                                                  title: title,
                                                  description: description,
                                                  groupId: selectedGroupId,
                                                  startTime: startDT,
                                                  endTime: endDT,
                                                  // repeat: repeat,
                                                  imageUrl: newImageUrl,
                                                  linkUrl: linkUrl,
                                                );
                                            if (!mounted) return;
                                            Navigator.of(modalContext).pop();
                                            await _loadEvents();
                                            if (!mounted) return;
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text('Event updated'),
                                                backgroundColor: Colors.green,
                                              ),
                                            );
                                          } catch (e) {
                                            if (!mounted) return;
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Error updating: $e',
                                                ),
                                                backgroundColor: Colors.red,
                                              ),
                                            );
                                          }
                                        },
                                        child: const Text(
                                          'Save Changes',
                                          style: TextStyle(color: Colors.black),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _deleteEvent(String eventId) async {
    try {
      await SupabaseService.instance.deleteEvent(eventId);
      await _loadEvents();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Event deleted')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }

  // ---------- HAMBURGER / ADDED TIMETABLES ----------

  /// Shows the bottom sheet hamburger with username, addons, manage groups, added timetables
  Future<void> _openHamburger() async {
    final codeController = TextEditingController();
    String displayUsername = '';
    int totalAddons = 0;
    int plusAddons = 0;
    int addedTimetablesCount = 0;

    // initial fetches (before showing sheet)
    try {
      final uid = _currentUserId;
      if (uid != null) {
        try {
          final profile = await SupabaseService.instance.fetchUserProfile(uid);
          displayUsername =
              profile['username'] as String? ??
              profile['display_name'] as String? ??
              '';
        } catch (e) {
          debugPrint('[_openHamburger] fetch profile failed: $e');
        }

        if (displayUsername.isNotEmpty) {
          // TODO: Implement fetchTimetableAddonStats in SupabaseService
          totalAddons = 0; // Placeholder
          plusAddons = 0; // Placeholder
        }

        try {
          final myAdded = await SupabaseService.instance.getMySharedUsers();
          addedTimetablesCount = myAdded.length;
        } catch (_) {
          addedTimetablesCount = 0;
        }
      }
    } catch (e) {
      debugPrint('[_openHamburger] pre-sheet error: $e');
    }

    try {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (modalContext) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(modalContext).viewInsets.bottom,
            ),
            child: GlassContainer(
              borderRadius: 20.0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Container(
                child: DraggableScrollableSheet(
                  initialChildSize: 0.6,
                  minChildSize: 0.4,
                  maxChildSize: 0.9,
                  expand: false,
                  builder: (context, scrollController) {
                    return StatefulBuilder(
                      builder: (context, setModalState) {
                        bool subscribing = false;

                        // compute expected cashout from the current plusAddons
                        int expectedCashOutLocal() =>
                            (plusAddons ~/ 100) * 1000;

                        Future<void> refreshAddonStats() async {
                          // TODO: Implement in SupabaseService
                          if (displayUsername.isEmpty) return;
                          // Placeholder
                        }

                        Future<void> doSubscribe(String usernameToAdd) async {
                          final toAdd = usernameToAdd.trim();
                          if (toAdd.isEmpty) return;

                          if (!_isPremium && addedTimetablesCount >= 1) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Free users can only add one timetable. Upgrade to add more.',
                                  ),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                            }
                            return;
                          }

                          setModalState(() => subscribing = true);
                          try {
                            await SupabaseService.instance.subscribeToTimetable(
                              toAdd,
                            );

                            // refresh global lists
                            await _loadSharedUsers();
                            await _loadEvents();

                            // refresh local added count
                            try {
                              final myAdded = await SupabaseService.instance
                                  .getMySharedUsers();
                              if (mounted) {
                                setModalState(() {
                                  addedTimetablesCount = myAdded.length;
                                });
                              }
                            } catch (_) {}

                            // refresh the user's addon stats as well (so badges update)
                            await refreshAddonStats();

                            codeController.clear();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Subscribed'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Subscribe failed: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          } finally {
                            if (mounted)
                              setModalState(() => subscribing = false);
                          }
                        }

                        return ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.all(16.0),
                          children: [
                            _buildDragHandle(),
                            Row(
                              children: [
                                const CircleAvatar(
                                  radius: 28,
                                  backgroundColor: Colors.white12,
                                  child: Icon(
                                    Icons.person,
                                    color: Colors.white70,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        displayUsername.isNotEmpty
                                            ? '@$displayUsername'
                                            : 'No username',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.white10,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(
                                                  Icons.group,
                                                  size: 14,
                                                  color: Colors.white70,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  '$totalAddons addons',
                                                  style: const TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.white10,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(
                                                  Icons.star,
                                                  size: 14,
                                                  color: Colors.amberAccent,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  '$plusAddons plus • N${expectedCashOutLocal()}',
                                                  style: const TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.white10,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(
                                                  Icons.person_add,
                                                  size: 14,
                                                  color: Colors.white70,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  'Added: $addedTimetablesCount',
                                                  style: const TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            Card(
                              color: Colors.white.withOpacity(0.05),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    const Text(
                                      'Add another timetable',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _isPremium
                                          ? 'Premium users can add multiple timetables.'
                                          : 'Free users: 1 added timetable allowed.',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: codeController,
                                            style: const TextStyle(
                                              color: Colors.white,
                                            ),
                                            decoration: const InputDecoration(
                                              hintText:
                                                  'Enter username (e.g. alice123)',
                                              hintStyle: TextStyle(
                                                color: Colors.white38,
                                              ),
                                              isDense: true,
                                              border: OutlineInputBorder(),
                                              contentPadding:
                                                  EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 10,
                                                  ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Material(
                                          color: Colors.cyanAccent,
                                          shape: const CircleBorder(),
                                          child: InkWell(
                                            customBorder: const CircleBorder(),
                                            onTap: subscribing
                                                ? null
                                                : () => doSubscribe(
                                                    codeController.text,
                                                  ),
                                            child: Padding(
                                              padding: const EdgeInsets.all(
                                                10.0,
                                              ),
                                              child: subscribing
                                                  ? const SizedBox(
                                                      width: 18,
                                                      height: 18,
                                                      child:
                                                          CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                            color: Colors.black,
                                                          ),
                                                    )
                                                  : const Icon(
                                                      Icons.add,
                                                      color: Colors.black,
                                                    ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    icon: const Icon(
                                      Icons.group,
                                      color: Colors.white70,
                                    ),
                                    label: const Text(
                                      'Manage groups',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(
                                        color: Colors.white10,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                    ),
                                    onPressed: () {
                                      Navigator.of(context).pop();
                                      Navigator.of(context)
                                          .push(
                                            MaterialPageRoute(
                                              builder: (c) =>
                                                  const ManageGroupsScreen(),
                                            ),
                                          )
                                          .then(
                                            (_) async => await _loadEvents(),
                                          );
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    icon: const Icon(
                                      Icons.person_add,
                                      color: Colors.white70,
                                    ),
                                    label: const Text(
                                      'Added timetables',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(
                                        color: Colors.white10,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                    ),
                                    onPressed: () {
                                      Navigator.of(context).pop();
                                      _showAddedTimetables();
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            const Text(
                              'Manage the timetables you’ve added above. Removing a timetable will stop its events from appearing.',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          );
        },
      );
    } finally {
      // clean up and refresh
      try {
        codeController.dispose();
      } catch (_) {}
      try {
        await _loadSharedUsers();
        await _loadEvents();
      } catch (_) {}
    }
  }

  // --- "Added Timetables" bottom sheet ---
  Future<void> _showAddedTimetables() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: GlassContainer(
            borderRadius: 20.0,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Container(
              color: Colors.transparent,
              child: StatefulBuilder(
                builder: (context, setModal) {
                  bool isLoading = false;
                  List<Map<String, dynamic>> sharedUsers = List.from(
                    _addedTimetables,
                  );

                  Future<void> refresh() async {
                    setModal(() => isLoading = true);
                    try {
                      final u = await SupabaseService.instance
                          .getMySharedUsers();
                      if (!mounted) return;
                      setModal(() {
                        sharedUsers = List<Map<String, dynamic>>.from(u);
                        _addedTimetables = sharedUsers;
                        isLoading = false;
                      });
                    } catch (e) {
                      if (mounted) {
                        setModal(() => isLoading = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  }

                  Future<void> removeShare(String ownerId) async {
                    try {
                      await SupabaseService.instance.unsubscribeFromTimetable(
                        ownerId,
                      );
                      await refresh(); // refresh local list inside sheet
                      await _loadEvents(); // refresh calendar events
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Removed'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error removing: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  }

                  return DraggableScrollableSheet(
                    initialChildSize: 0.6,
                    minChildSize: 0.3,
                    maxChildSize: 0.9,
                    expand: false,
                    builder: (_, scrollController) {
                      return Column(
                        children: [
                          _buildDragHandle(),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                              vertical: 8.0,
                            ),
                            child: Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'Added Timetables',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Refresh',
                                  onPressed: refresh,
                                  icon: const Icon(
                                    Icons.refresh,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Divider(color: Colors.white24, height: 1),
                          Expanded(
                            child: isLoading
                                ? const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                : sharedUsers.isEmpty
                                ? const Center(
                                    child: Text(
                                      'You have not added any timetables.',
                                      style: TextStyle(color: Colors.white70),
                                    ),
                                  )
                                : ListView.separated(
                                    controller: scrollController,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    itemCount: sharedUsers.length,
                                    separatorBuilder: (_, __) => const Divider(
                                      color: Colors.white10,
                                      height: 1,
                                    ),
                                    itemBuilder: (ctx, index) {
                                      final user = sharedUsers[index];
                                      final avatarUrl =
                                          user['avatar_url'] as String?;
                                      final id = user['id'] as String? ?? '';
                                      final username =
                                          user['username'] as String? ?? '...';
                                      return ListTile(
                                        leading: CircleAvatar(
                                          backgroundImage: avatarUrl != null
                                              ? NetworkImage(avatarUrl)
                                              : null,
                                          child: avatarUrl == null
                                              ? const Icon(Icons.person)
                                              : null,
                                        ),
                                        title: Text(
                                          user['display_name'] ?? 'No name',
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                        ),
                                        subtitle: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '@$username',
                                              style: const TextStyle(
                                                color: Colors.white70,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                if ((user['owner_total_addons'] ??
                                                        0) >
                                                    0)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          right: 8.0,
                                                        ),
                                                    child: Text(
                                                      '${user['owner_total_addons']} addons',
                                                      style: const TextStyle(
                                                        color: Colors.white54,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ),
                                                Text(
                                                  '${user['owner_plus_addons'] ?? 0} plus',
                                                  style: const TextStyle(
                                                    color: Colors.amberAccent,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                        trailing: IconButton(
                                          tooltip: 'Remove timetable',
                                          onPressed: () async {
                                            final confirm = await showDialog<bool>(
                                              context: context,
                                              builder: (dctx) => AlertDialog(
                                                backgroundColor:
                                                    const Color.fromRGBO(
                                                      30,
                                                      30,
                                                      30,
                                                      0.9,
                                                    ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                ),
                                                title: const Text(
                                                  'Remove timetable',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                content: const Text(
                                                  'Are you sure you want to remove this added timetable? This will stop its events from appearing on your calendar.',
                                                  style: TextStyle(
                                                    color: Colors.white70,
                                                  ),
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.of(
                                                          dctx,
                                                        ).pop(false),
                                                    child: const Text('Cancel'),
                                                  ),
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.of(
                                                          dctx,
                                                        ).pop(true),
                                                    child: const Text(
                                                      'Remove',
                                                      style: TextStyle(
                                                        color: Colors.red,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );

                                            if (confirm == true) {
                                              await removeShare(id);
                                            }
                                          },
                                          icon: const Icon(
                                            Icons.delete,
                                            color: Colors.redAccent,
                                          ),
                                        ),
                                        onTap: () {
                                          Navigator.of(context).pop();
                                          setState(() => _selectedUserId = id);
                                        },
                                      );
                                    },
                                  ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
        );
      },
    ).then((_) async {
      await _loadSharedUsers();
      await _loadEvents();
    });
  }

  // ---------- DAY EVENTS SHEET ----------

  Future<void> _showDayEventsSheet(List<Map<String, dynamic>> events) async {
    if (_selectedDay == null) return;

    final filtered = _selectedUserId == null
        ? events
        : events.where((e) => e['creator_user_id'] == _selectedUserId).toList();

    filtered.sort((a, b) {
      final aTime = _parseToLocal(a['start_time']);
      final bTime = _parseToLocal(b['start_time']);
      return aTime.compareTo(bTime);
    });

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: GlassContainer(
          borderRadius: 20.0,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.75,
            child: DraggableScrollableSheet(
              initialChildSize: 0.6,
              minChildSize: 0.3,
              maxChildSize: 0.9,
              expand: false,
              builder: (context, scrollController) {
                return Column(
                  children: [
                    _buildDragHandle(),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 8.0,
                      ),
                      child: Text(
                        'Events for ${DateFormat.yMMMd().format(_selectedDay!)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const Divider(color: Colors.white24, height: 1),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(
                              child: Text(
                                'No events for this day.',
                                style: TextStyle(color: Colors.white70),
                              ),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              padding: const EdgeInsets.all(16),
                              itemCount: filtered.length,
                              itemBuilder: (context, i) {
                                final ev = filtered[i];
                                final start = DateFormat.jm().format(
                                  _parseToLocal(ev['start_time']),
                                );
                                final isMine =
                                    (ev['creator_user_id'] as String?) ==
                                    _currentUserId;

                                return Card(
                                  color: Colors.white.withOpacity(0.06),
                                  margin: const EdgeInsets.only(bottom: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: ListTile(
                                    title: Text(
                                      ev['title'] ?? '',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    subtitle: Text(
                                      ev['description'] ?? '',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                      ),
                                    ),
                                    trailing: Text(
                                      start,
                                      style: const TextStyle(
                                        color: Colors.cyanAccent,
                                      ),
                                    ),
                                    onTap: isMine ? () => _editEvent(ev) : null,
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // ---------- COMMENTS MODAL (from init prompt) ----------

  Future<void> _showCommentsModal(String eventId) async {
    // TODO: Implement fetchEventComments and addEventComment in SupabaseService
    final comments = <Map<String, dynamic>>[]; // Placeholder
    final commentController = TextEditingController();

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => GlassContainer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Comments',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: comments.length,
                itemBuilder: (ctx, i) {
                  final com = comments[i];
                  return ListTile(
                    title: Text(com['text'] as String),
                    subtitle: Text(
                      'By @${com['commenter_username'] ?? 'unknown'}',
                    ), // Assume enriched data
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: commentController,
                      decoration: const InputDecoration(
                        labelText: 'Add Comment',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () async {
                      if (commentController.text.isNotEmpty) {
                        // TODO: await SupabaseService.instance.addEventComment(eventId, commentController.text);
                        commentController.clear();
                        // Refresh comments
                      }
                    },
                    icon: const Icon(Icons.send, color: Colors.cyanAccent),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- BUILD ----------

  @override
  Widget build(BuildContext context) {
    final dayEvents = _selectedDay != null
        ? _getEventsForDay(_selectedDay!)
        : <Map<String, dynamic>>[];
    final todaysEvents = _selectedUserId == null
        ? dayEvents
        : dayEvents
              .where((e) => e['creator_user_id'] == _selectedUserId)
              .toList();

    todaysEvents.sort((a, b) {
      final aTime = _parseToLocal(a['start_time']);
      final bTime = _parseToLocal(b['start_time']);
      return aTime.compareTo(bTime);
    });

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Timetable',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 22,
            color: Colors.white,
          ),
        ),
        actions: [
          // ---------- notifications bell with badge ----------
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: IconButton(
              onPressed: () async {
                // refresh then open modal
                await _fetchNotificationsAndCount();
                await _openNotificationsModal();
              },
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.notifications_none, color: Colors.white),
                  if (_unreadCount > 0)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _unreadCount > 99 ? '99+' : '$_unreadCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // menu button
          IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: _openHamburger,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.cyanAccent),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: Colors.white10,
                          border: Border.all(color: Colors.white24),
                        ),
                        child: TableCalendar(
                          firstDay: DateTime.utc(2020, 1, 1),
                          lastDay: DateTime.utc(2035, 12, 31),
                          focusedDay: _focusedDay,
                          selectedDayPredicate: (d) =>
                              isSameDay(_selectedDay, d),
                          eventLoader: _getEventsForDay,
                          onDaySelected: (sel, foc) => _onDaySelected(sel, foc),
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
                          calendarBuilders: CalendarBuilders(
                            markerBuilder: (context, day, events) {
                              if (events.isEmpty) return null;

                              // Collect up to 3 distinct colors from the day's events
                              final List<Color> colors = [];

                              for (final evRaw in events) {
                                // Guard: ensure each item is a map
                                final Map<String, dynamic>? ev = (evRaw is Map)
                                    ? Map<String, dynamic>.from(evRaw)
                                    : null;
                                if (ev == null) continue;

                                String? colorHex;

                                // Safely coerce timetable_groups into a Map<String, dynamic> if present
                                final tgRaw = ev['timetable_groups'];
                                final Map<String, dynamic>? tgMap =
                                    (tgRaw is Map)
                                    ? Map<String, dynamic>.from(tgRaw)
                                    : null;

                                if (tgMap != null &&
                                    tgMap['group_color'] is String) {
                                  colorHex = tgMap['group_color'] as String;
                                } else if (ev['group_color'] is String) {
                                  colorHex = ev['group_color'] as String;
                                }

                                Color col = Colors.pinkAccent; // fallback color
                                if (colorHex != null) {
                                  try {
                                    col = Color(
                                      int.parse(
                                        colorHex.replaceFirst('#', '0xff'),
                                      ),
                                    );
                                  } catch (_) {
                                    col = Colors.pinkAccent;
                                  }
                                }

                                if (!colors.contains(col)) {
                                  colors.add(col);
                                  if (colors.length >= 3) break;
                                }
                              }

                              return Align(
                                alignment: Alignment.bottomCenter,
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 4.0),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: List.generate(colors.length, (i) {
                                      return Container(
                                        width: 6,
                                        height: 6,
                                        margin: EdgeInsets.only(
                                          left: i == 0 ? 0 : 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: colors[i],
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: colors[i].withOpacity(0.4),
                                              blurRadius: 4,
                                              spreadRadius: 0.5,
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                  ),
                                ),
                              );
                            },
                          ),
                          calendarStyle: const CalendarStyle(
                            defaultTextStyle: TextStyle(color: Colors.white),
                            weekendTextStyle: TextStyle(color: Colors.white70),
                            outsideTextStyle: TextStyle(color: Colors.white38),
                            selectedDecoration: BoxDecoration(
                              color: Colors.cyanAccent,
                              borderRadius: const BorderRadius.all(
                                Radius.circular(6),
                              ),
                            ),
                            selectedTextStyle: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                            ),
                            todayDecoration: BoxDecoration(
                              color: Colors.white12,
                              borderRadius: const BorderRadius.all(
                                Radius.circular(6),
                              ),
                            ),
                            todayTextStyle: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Tappable header to open full list for the day
                if (_selectedDay != null)
                  GestureDetector(
                    onTap: () => _showDayEventsSheet(todaysEvents),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Events for: ${DateFormat.yMMMd().format(_selectedDay!)}${_selectedUserId != null ? ' (filtered)' : ''}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                // Inline list or fallback
                Expanded(
                  child: todaysEvents.isEmpty
                      ? const Center(
                          child: Text(
                            'No events scheduled for this day.',
                            style: TextStyle(color: Colors.white70),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: todaysEvents.length,
                          itemBuilder: (ctx, i) {
                            final ev = todaysEvents[i];
                            final start = DateFormat.jm().format(
                              _parseToLocal(ev['start_time']),
                            );

                            // owner: prefer the enriched owner_username / owner_avatar_url
                            final ownerUsername =
                                (ev['owner_username'] as String?) ??
                                ((ev['event_owner'] is Map)
                                    ? (ev['event_owner']['username'] as String?)
                                    : null) ??
                                (ev['username'] as String?) ??
                                (ev['creator_username'] as String?);

                            final ownerAvatar =
                                (ev['owner_avatar_url'] as String?) ??
                                ((ev['event_owner'] is Map)
                                    ? (ev['event_owner']['avatar_url']
                                          as String?)
                                    : null);

                            // isMine (safe)
                            final evUserId = ev['creator_user_id'] as String?;
                            final isMine =
                                evUserId != null && evUserId == _currentUserId;

                            // group info (safe)
                            final tgRaw = ev['timetable_groups'];
                            Map<String, dynamic>? tg;
                            if (tgRaw is Map) {
                              tg = Map<String, dynamic>.from(tgRaw);
                            } else {
                              tg = null;
                            }
                            final groupName = tg != null
                                ? (tg['group_name'] as String?)
                                : (ev['group_name'] as String?);

                            // description (safe)
                            final desc = ev['description'] as String?;

                            final imageUrl = ev['image_url'] as String?;
                            final linkUrl = ev['url'] as String?;

                            return Card(
                              color: const Color.fromRGBO(255, 255, 255, 0.06),
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (imageUrl != null)
                                    ClipRRect(
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(12),
                                      ),
                                      child: Stack(
                                        children: [
                                          Image.network(
                                            imageUrl,
                                            height: 150,
                                            width: double.infinity,
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (context, error, stackTrace) =>
                                                    Container(
                                                      height: 150,
                                                      color: Colors.grey[800],
                                                      child: const Icon(
                                                        Icons.broken_image,
                                                        size: 50,
                                                        color: Colors.white70,
                                                      ),
                                                    ),
                                          ),
                                          Container(
                                            height: 150,
                                            width: double.infinity,
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                begin: Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                                colors: [
                                                  Colors.transparent,
                                                  Colors.black.withOpacity(0.3),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ListTile(
                                    contentPadding: const EdgeInsets.all(12),
                                    leading: (!isMine && ownerAvatar != null)
                                        ? CircleAvatar(
                                            backgroundImage: NetworkImage(
                                              ownerAvatar,
                                            ),
                                            radius: 20,
                                          )
                                        : null,
                                    title: Text(
                                      ev['title'] ?? '',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (desc?.isNotEmpty == true)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 6,
                                            ),
                                            child: Text(
                                              desc!,
                                              style: const TextStyle(
                                                color: Colors.white70,
                                              ),
                                            ),
                                          ),
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 6,
                                          ),
                                          child: Text(
                                            '${DateFormat.jm().format(_parseToLocal(ev['start_time']))} - ${DateFormat.jm().format(_parseToLocal(ev['end_time']))}',
                                            style: const TextStyle(
                                              color: Colors.cyanAccent,
                                            ),
                                          ),
                                        ),
                                        if (groupName != null)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 6,
                                            ),
                                            child: Text(
                                              'Group: $groupName',
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        // show "by @username" for non-owned events
                                        if (!isMine && ownerUsername != null)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 6,
                                            ),
                                            child: Text(
                                              'by @$ownerUsername',
                                              style: const TextStyle(
                                                color: Colors.amberAccent,
                                                fontStyle: FontStyle.italic,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        if (linkUrl != null)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 6,
                                            ),
                                            child: GestureDetector(
                                              onTap: () {
                                                // TODO: Launch URL using url_launcher
                                                debugPrint('Launch $linkUrl');
                                              },
                                              child: Text(
                                                linkUrl,
                                                style: const TextStyle(
                                                  color: Colors.blue,
                                                  decoration:
                                                      TextDecoration.underline,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (!isMine)
                                          IconButton(
                                            icon: const Icon(
                                              Icons.comment,
                                              color: Colors.white70,
                                            ),
                                            onPressed: () => _showCommentsModal(
                                              ev['id'] as String,
                                            ),
                                          ),
                                        if (isMine)
                                          IconButton(
                                            icon: const Icon(
                                              Icons.edit,
                                              color: Colors.cyanAccent,
                                            ),
                                            onPressed: () => _editEvent(ev),
                                          ),
                                        if (isMine)
                                          IconButton(
                                            icon: const Icon(
                                              Icons.delete,
                                              color: Colors.red,
                                            ),
                                            onPressed: () => _deleteEvent(
                                              ev['id'] as String,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: _selectedDay != null
          ? FloatingActionButton(
              onPressed: _addEvent,
              backgroundColor: Colors.cyanAccent,
              tooltip: 'Add Event',
              shape: const CircleBorder(), // explicit circular FAB
              child: const Icon(Icons.add, color: Colors.black),
            )
          : null,
    );
  }
}
