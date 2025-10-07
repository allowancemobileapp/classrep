// lib/features/timetable/presentation/manage_groups_screen.dart

import 'package:class_rep/shared/services/supabase_service.dart';
import 'package:class_rep/shared/widgets/glass_container.dart';
import 'package:flutter/material.dart';

// --- THEME COLORS ---
const Color darkSuedeNavy = Color(0xFF1A1B2C);
const Color lightSuedeNavy = Color(0xFF2A2C40);

class ManageGroupsScreen extends StatefulWidget {
  const ManageGroupsScreen({super.key});

  @override
  State<ManageGroupsScreen> createState() => _ManageGroupsScreenState();
}

class _ManageGroupsScreenState extends State<ManageGroupsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _groups = [];
  final _formKey = GlobalKey<FormState>();
  final _groupNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    super.dispose();
  }

  Future<void> _loadGroups() async {
    // ... This method remains exactly the same
    setState(() => _isLoading = true);
    try {
      final groups = await SupabaseService.instance.fetchEventGroups();
      if (mounted) {
        setState(() {
          _groups = groups;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error loading groups: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _addGroup() async {
    // ... This method remains exactly the same
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final groupName = _groupNameController.text.trim();
    setState(() => _isLoading = true);
    try {
      await SupabaseService.instance.createEventGroup(groupName);
      _groupNameController.clear();
      await _loadGroups(); // Refresh the list
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error adding group: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteGroup(String groupId) async {
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
              'Are you sure you want to delete this group? All events within it will become ungrouped.',
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
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 32),
                  ),
                  child: const Text('Delete',
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
        await SupabaseService.instance.deleteEventGroup(groupId);
        await _loadGroups();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Error deleting group: $e'),
                backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _toggleVisibility(
      String groupId, String currentVisibility) async {
    // ... This method remains exactly the same
    try {
      await SupabaseService.instance
          .toggleGroupVisibility(groupId, currentVisibility);
      await _loadGroups();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error updating visibility: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  // --- THIS METHOD IS NOW MUCH SIMPLER ---
  Future<void> _showGroupMembersSheet(String groupId, String groupName) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        // It now just calls our new, self-contained widget
        return _GroupMembersSheet(groupId: groupId, groupName: groupName);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // ... This method remains exactly the same
    return Scaffold(
      backgroundColor: darkSuedeNavy,
      appBar: AppBar(
        backgroundColor: darkSuedeNavy,
        title: const Text('Manage Groups'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _groupNameController,
                      style: const TextStyle(color: Colors.white),
                      decoration:
                          _buildInputDecoration(labelText: 'New group name'),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a group name';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyanAccent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(
                          vertical: 16, horizontal: 20),
                    ),
                    onPressed: _isLoading ? null : _addGroup,
                    child: const Text('Add',
                        style: TextStyle(
                            color: Colors.black, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.cyanAccent))
                : _groups.isEmpty
                    ? const Center(
                        child: Text('No groups created yet.',
                            style: TextStyle(color: Colors.white70)))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        itemCount: _groups.length,
                        itemBuilder: (context, index) {
                          final group = _groups[index];
                          final isPublic = group['visibility'] == 'public';
                          return Card(
                            color: lightSuedeNavy.withOpacity(0.5),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              title: Text(
                                group['group_name'],
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (!isPublic)
                                    IconButton(
                                      tooltip: 'Manage Members',
                                      icon: const Icon(
                                        Icons.manage_accounts_outlined,
                                        color: Colors.white70,
                                      ),
                                      onPressed: () => _showGroupMembersSheet(
                                          group['id'], group['group_name']),
                                    ),
                                  IconButton(
                                    tooltip: isPublic
                                        ? 'Visible to subscribers'
                                        : 'Private to you and members',
                                    icon: Icon(
                                      isPublic
                                          ? Icons.visibility
                                          : Icons.visibility_off,
                                      color: isPublic
                                          ? Colors.cyanAccent
                                          : Colors.white70,
                                    ),
                                    onPressed: () => _toggleVisibility(
                                        group['id'], group['visibility']),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        color: Colors.redAccent),
                                    onPressed: () => _deleteGroup(group['id']),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  InputDecoration _buildInputDecoration({required String labelText}) {
    // ... This method remains exactly the same
    return InputDecoration(
      labelText: labelText,
      labelStyle: const TextStyle(color: Colors.white70),
      filled: true,
      fillColor: Colors.white.withOpacity(0.1),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.cyanAccent, width: 1.5),
      ),
    );
  }
}

// --- NEW WIDGET FOR THE POP-UP ---
// This widget now manages its own state and controllers, fixing the errors.
class _GroupMembersSheet extends StatefulWidget {
  final String groupId;
  final String groupName;

  const _GroupMembersSheet({required this.groupId, required this.groupName});

  @override
  State<_GroupMembersSheet> createState() => __GroupMembersSheetState();
}

class __GroupMembersSheetState extends State<_GroupMembersSheet> {
  late final TextEditingController _searchController;
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _addableSubscribers = [];
  List<Map<String, dynamic>> _filteredAddable = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchController.addListener(_filterSubscribers);
    _refreshData();
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterSubscribers);
    _searchController.dispose();
    super.dispose();
  }

  void _filterSubscribers() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredAddable = _addableSubscribers.where((user) {
        final username = user['username'] as String? ?? '';
        return username.toLowerCase().contains(query);
      }).toList();
    });
  }

  Future<void> _refreshData() async {
    setState(() => _isLoading = true);
    final fetchedMembers =
        await SupabaseService.instance.getGroupMembers(widget.groupId);
    final fetchedAddable =
        await SupabaseService.instance.getAddableGroupMembers(widget.groupId);
    if (mounted) {
      setState(() {
        _members = fetchedMembers;
        _addableSubscribers = fetchedAddable;
        _filteredAddable = fetchedAddable;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return GlassContainer(
          borderRadius: 20.0,
          padding: EdgeInsets.only(
            top: 12,
            left: 16,
            right: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ... Handle and Title ...
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                      color: Colors.grey[700],
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              Center(
                child: Text('Manage Members for "${widget.groupName}"',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
              ),
              const Divider(color: lightSuedeNavy, height: 24),

              const Text('Add Subscribers to Group',
                  style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 8),
              TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Search your subscribers...',
                  labelStyle: const TextStyle(color: Colors.white70),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.1),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 8),

              // List of addable subscribers
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _addableSubscribers.isEmpty
                        ? const Center(
                            child: Text('All subscribers are in this group.',
                                style: TextStyle(color: Colors.white70)))
                        : _filteredAddable.isEmpty
                            ? const Center(
                                child: Text('No matching subscribers found.',
                                    style: TextStyle(color: Colors.white70)))
                            : ListView.builder(
                                itemCount: _filteredAddable.length,
                                itemBuilder: (ctx, i) {
                                  final user = _filteredAddable[i];
                                  return ListTile(
                                    title: Text(user['username'],
                                        style: const TextStyle(
                                            color: Colors.white)),
                                    trailing: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.cyanAccent),
                                      child: const Text('Add',
                                          style:
                                              TextStyle(color: Colors.black)),
                                      onPressed: () async {
                                        await SupabaseService.instance
                                            .addGroupMember(
                                                widget.groupId, user['id']);
                                        _refreshData();
                                      },
                                    ),
                                  );
                                },
                              ),
              ),

              const Divider(color: lightSuedeNavy, height: 24),
              const Text('Current Members',
                  style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 8),

              // List of current members
              Expanded(
                child: _isLoading
                    ? const Center(
                        child:
                            CircularProgressIndicator(color: Colors.cyanAccent))
                    : _members.isEmpty
                        ? const Center(
                            child: Text('No members in this group yet.',
                                style: TextStyle(color: Colors.white70)))
                        : ListView.builder(
                            controller: scrollController,
                            itemCount: _members.length,
                            itemBuilder: (context, index) {
                              final member = _members[index];
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundImage: member['avatar_url'] != null
                                      ? NetworkImage(member['avatar_url'])
                                      : null,
                                  child: member['avatar_url'] == null
                                      ? Text(member['username']?[0]
                                              .toUpperCase() ??
                                          '?')
                                      : null,
                                ),
                                title: Text(member['username'],
                                    style:
                                        const TextStyle(color: Colors.white)),
                                trailing: IconButton(
                                  icon: const Icon(Icons.remove_circle_outline,
                                      color: Colors.redAccent),
                                  onPressed: () async {
                                    await SupabaseService.instance
                                        .removeGroupMember(
                                            widget.groupId, member['id']);
                                    _refreshData();
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
  }
}
