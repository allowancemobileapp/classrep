// lib/features/chat/presentation/new_group_screen.dart

import 'package:class_rep/features/chat/presentation/chat_screen.dart';
import 'package:class_rep/shared/services/supabase_service.dart';
import 'package:flutter/material.dart';

const Color darkSuedeNavy = Color(0xFF1A1B2C);
const Color lightSuedeNavy = Color(0xFF2A2C40);

class NewGroupScreen extends StatefulWidget {
  const NewGroupScreen({super.key});

  @override
  State<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends State<NewGroupScreen> {
  final _groupNameController = TextEditingController();
  late final Future<List<Map<String, dynamic>>> _subscribersFuture;
  final Set<String> _selectedUserIds = {};
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _subscribersFuture = SupabaseService.instance.getMySharedUsers();
  }

  void _toggleSelection(String userId) {
    setState(() {
      if (_selectedUserIds.contains(userId)) {
        _selectedUserIds.remove(userId);
      } else {
        _selectedUserIds.add(userId);
      }
    });
  }

  Future<void> _createGroup() async {
    final groupName = _groupNameController.text.trim();
    if (groupName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please enter a group name.'),
          backgroundColor: Colors.orange));
      return;
    }
    if (_selectedUserIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please select at least one member.'),
          backgroundColor: Colors.orange));
      return;
    }

    setState(() => _isCreating = true);

    try {
      final conversationId =
          await SupabaseService.instance.createGroupConversation(
        groupName: groupName,
        participantIds: _selectedUserIds.toList(),
      );

      if (!mounted) return;

      // Pop this screen and signal that a new chat was started.
      Navigator.of(context).pop(true);

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => ChatScreen(
            conversationId: conversationId,
            chatTitle: groupName,
          ),
        ),
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error creating group: ${e.toString()}'),
            backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: darkSuedeNavy,
      appBar: AppBar(
        title: const Text('Create New Group'),
        backgroundColor: darkSuedeNavy,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _groupNameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Group Name',
                labelStyle: const TextStyle(color: Colors.white70),
                filled: true,
                fillColor: lightSuedeNavy,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Text('Select Members (from your subscribers)',
                style: TextStyle(color: Colors.white70)),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _subscribersFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final subscribers = snapshot.data ?? [];
                if (subscribers.isEmpty) {
                  return const Center(
                      child: Text('You have no subscribers to add.',
                          style: TextStyle(color: Colors.white70)));
                }

                return ListView.builder(
                  itemCount: subscribers.length,
                  itemBuilder: (context, index) {
                    final user = subscribers[index];
                    final isSelected = _selectedUserIds.contains(user['id']);
                    return CheckboxListTile(
                      activeColor: Colors.cyanAccent,
                      checkColor: Colors.black,
                      title: Text(user['username'],
                          style: const TextStyle(color: Colors.white)),
                      value: isSelected,
                      onChanged: (_) => _toggleSelection(user['id']),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isCreating ? null : _createGroup,
        backgroundColor: Colors.cyanAccent,
        icon: _isCreating
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: Colors.black))
            : const Icon(Icons.check, color: Colors.black),
        label: Text(_isCreating ? 'Creating...' : 'Create Group',
            style: const TextStyle(
                color: Colors.black, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
