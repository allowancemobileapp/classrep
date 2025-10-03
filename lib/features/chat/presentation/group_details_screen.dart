// lib/features/chat/presentation/group_details_screen.dart

import 'package:class_rep/features/chat/presentation/add_members_screen.dart';
import 'package:class_rep/shared/services/supabase_service.dart';
import 'package:flutter/material.dart';

const Color darkSuedeNavy = Color(0xFF1A1B2C);
const Color lightSuedeNavy = Color(0xFF2A2C40);

class GroupDetailsScreen extends StatefulWidget {
  final String conversationId;
  final String groupName;

  const GroupDetailsScreen({
    required this.conversationId,
    required this.groupName,
    super.key,
  });

  @override
  State<GroupDetailsScreen> createState() => _GroupDetailsScreenState();
}

class _GroupDetailsScreenState extends State<GroupDetailsScreen> {
  late Future<List<Map<String, dynamic>>> _participantsFuture;

  @override
  void initState() {
    super.initState();
    _refreshParticipants();
  }

  void _refreshParticipants() {
    setState(() {
      _participantsFuture =
          SupabaseService.instance.getGroupParticipants(widget.conversationId);
    });
  }

  Future<void> _removeMember(String userId) async {
    final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: lightSuedeNavy,
            title: const Text('Remove Member?',
                style: TextStyle(color: Colors.white)),
            content: const Text(
                'Are you sure you want to remove this member from the group?',
                style: TextStyle(color: Colors.white70)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel')),
              TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Remove',
                      style: TextStyle(color: Colors.redAccent))),
            ],
          ),
        ) ??
        false;

    if (confirm) {
      try {
        await SupabaseService.instance.removeGroupParticipant(
            conversationId: widget.conversationId, userIdToRemove: userId);
        _refreshParticipants();
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Error: ${e.toString().split(': ').last}'),
              backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _deleteGroup() async {
    final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: lightSuedeNavy,
            title: const Text('Delete Group?',
                style: TextStyle(color: Colors.white)),
            content: const Text(
                'Are you sure you want to permanently delete this group? This action cannot be undone.',
                style: TextStyle(color: Colors.white70)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel')),
              TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Delete',
                      style: TextStyle(color: Colors.red))),
            ],
          ),
        ) ??
        false;

    if (confirm) {
      try {
        await SupabaseService.instance
            .deleteGroupConversation(widget.conversationId);
        if (mounted) {
          // Pop back two screens to the main conversation list
          int count = 0;
          Navigator.of(context).popUntil((_) => count++ >= 2);
        }
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Error: ${e.toString().split(': ').last}'),
              backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: darkSuedeNavy,
      appBar: AppBar(
        title: Text(widget.groupName),
        backgroundColor: darkSuedeNavy,
        actions: [
          IconButton(
            tooltip: 'Add Members',
            icon: const Icon(Icons.group_add_outlined),
            onPressed: () async {
              final result = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                    builder: (_) => AddMembersScreen(
                        conversationId: widget.conversationId)),
              );
              // If we get 'true' back, it means members were added, so refresh the list
              if (result == true) {
                _refreshParticipants();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _participantsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                      child: Text('Error: ${snapshot.error}',
                          style: const TextStyle(color: Colors.red)));
                }
                final participants = snapshot.data ?? [];

                return ListView.builder(
                  itemCount: participants.length,
                  itemBuilder: (context, index) {
                    final user = participants[index];
                    final avatarUrl = user['avatar_url'] as String?;
                    final username = user['username'] as String?;
                    final isAdmin = user['is_admin'] as bool? ?? false;

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: lightSuedeNavy,
                        backgroundImage:
                            avatarUrl != null ? NetworkImage(avatarUrl) : null,
                        child: avatarUrl == null
                            ? Text(username?.isNotEmpty == true
                                ? username![0].toUpperCase()
                                : '?')
                            : null,
                      ),
                      title: Text(username ?? 'User',
                          style: const TextStyle(color: Colors.white)),
                      subtitle: isAdmin
                          ? const Text('Admin',
                              style: TextStyle(
                                  color: Colors.cyanAccent,
                                  fontStyle: FontStyle.italic))
                          : null,
                      trailing: isAdmin
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.remove_circle_outline,
                                  color: Colors.redAccent),
                              onPressed: () => _removeMember(user['id']),
                            ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextButton.icon(
              icon: const Icon(Icons.delete_forever, color: Colors.red),
              label: const Text('Delete Group',
                  style: TextStyle(color: Colors.red)),
              onPressed: _deleteGroup,
            ),
          )
        ],
      ),
    );
  }
}
