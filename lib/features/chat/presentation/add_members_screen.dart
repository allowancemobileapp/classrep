// lib/features/chat/presentation/add_members_screen.dart

import 'package:class_rep/shared/services/supabase_service.dart';
import 'package:flutter/material.dart';

const Color darkSuedeNavy = Color(0xFF1A1B2C);

class AddMembersScreen extends StatefulWidget {
  final String conversationId;
  const AddMembersScreen({required this.conversationId, super.key});

  @override
  State<AddMembersScreen> createState() => _AddMembersScreenState();
}

class _AddMembersScreenState extends State<AddMembersScreen> {
  late final Future<List<Map<String, dynamic>>> _addableMembersFuture;
  final Set<String> _selectedUserIds = {};
  bool _isAdding = false;

  @override
  void initState() {
    super.initState();
    // Use the new, specific function name to avoid the clash
    _addableMembersFuture = SupabaseService.instance
        .getAddableChatGroupMembers(conversationId: widget.conversationId);
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

  Future<void> _addMembers() async {
    if (_selectedUserIds.isEmpty) return;
    setState(() => _isAdding = true);

    try {
      // We can add members one by one by calling the function in a loop
      for (final userId in _selectedUserIds) {
        await SupabaseService.instance.addGroupParticipant(
          conversationId: widget.conversationId,
          userIdToAdd: userId,
        );
      }
      if (mounted)
        Navigator.of(context).pop(true); // Pop with 'true' to signal a refresh
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error adding members: ${e.toString()}'),
            backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: darkSuedeNavy,
      appBar: AppBar(
        title: const Text('Add Members'),
        backgroundColor: darkSuedeNavy,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _addableMembersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final addableMembers = snapshot.data ?? [];
          if (addableMembers.isEmpty) {
            return const Center(
                child: Text(
                    'All of your subscribers are already in this group.',
                    style: TextStyle(color: Colors.white70)));
          }

          return ListView.builder(
            itemCount: addableMembers.length,
            itemBuilder: (context, index) {
              final user = addableMembers[index];
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isAdding || _selectedUserIds.isEmpty ? null : _addMembers,
        backgroundColor:
            _selectedUserIds.isNotEmpty ? Colors.cyanAccent : Colors.grey,
        icon: _isAdding
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: Colors.black))
            : const Icon(Icons.check, color: Colors.black),
        label: Text(_isAdding ? 'Adding...' : 'Add Members',
            style: const TextStyle(
                color: Colors.black, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
