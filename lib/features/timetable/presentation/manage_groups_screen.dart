// lib/features/timetable/presentation/manage_groups_screen.dart

import 'package:class_rep/shared/services/supabase_service.dart';
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: darkSuedeNavy,
        title: const Text('Confirm Deletion',
            style: TextStyle(color: Colors.white)),
        content: const Text(
            'Are you sure you want to delete this group? All events within it will become ungrouped.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete',
                  style: TextStyle(color: Colors.redAccent))),
        ],
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

  // --- NEW METHOD TO HANDLE VISIBILITY TOGGLE ---
  Future<void> _toggleVisibility(
      String groupId, String currentVisibility) async {
    try {
      await SupabaseService.instance
          .toggleGroupVisibility(groupId, currentVisibility);
      // Refresh the list to show the new icon state immediately
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

  @override
  Widget build(BuildContext context) {
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
                          // --- START OF UI UPDATE ---
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
                                  IconButton(
                                    tooltip: isPublic
                                        ? 'Visible to subscribers'
                                        : 'Private to you',
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
                          // --- END OF UI UPDATE ---
                        },
                      ),
          ),
        ],
      ),
    );
  }

  InputDecoration _buildInputDecoration({required String labelText}) {
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
