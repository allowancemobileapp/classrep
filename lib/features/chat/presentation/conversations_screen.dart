// lib/features/chat/presentation/conversations_screen.dart

import 'package:class_rep/features/chat/presentation/chat_screen.dart';
import 'package:class_rep/features/chat/presentation/new_chat_screen.dart';
import 'package:class_rep/shared/services/auth_service.dart';
import 'package:class_rep/shared/services/supabase_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

const Color darkSuedeNavy = Color(0xFF1A1B2C);
const Color lightSuedeNavy = Color(0xFF2A2C40);

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  // This single Future will hold all our data to prevent multiple loading states
  Future<
      (
        Map<String, dynamic>,
        List<Map<String, dynamic>>,
        List<Map<String, dynamic>>
      )>? _dataFuture;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  void _loadInitialData() {
    setState(() {
      _dataFuture = _fetchData();
    });
  }

  // This function now fetches everything we need in parallel
  Future<
      (
        Map<String, dynamic>,
        List<Map<String, dynamic>>,
        List<Map<String, dynamic>>
      )> _fetchData() async {
    final profileFuture = SupabaseService.instance
        .fetchUserProfile(AuthService.instance.currentUser!.id);
    final conversationsFuture = SupabaseService.instance.getConversations();
    final subscriptionsFuture = SupabaseService.instance.getMySharedUsers();

    // Await all three futures at the same time
    final results = await Future.wait(
        [profileFuture, conversationsFuture, subscriptionsFuture]);

    // Unpack the results
    final profile = results[0] as Map<String, dynamic>;
    final conversations = (results[1] as List).cast<Map<String, dynamic>>();
    final subscriptions = (results[2] as List).cast<Map<String, dynamic>>();

    // Return them as a single object (a Record/Tuple)
    return (profile, conversations, subscriptions);
  }

  Future<void> _togglePrivacy(
      bool isPublic, Map<String, dynamic> userProfile) async {
    final isPlus = userProfile['is_plus'] as bool? ?? false;
    final newStatus = isPublic ? 'public' : 'private';

    if (isPublic && !isPlus) {
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: lightSuedeNavy,
          title: const Text('Upgrade to Plus',
              style: TextStyle(color: Colors.white)),
          content: const Text(
              'You must be a Plus subscriber to make your chat public and discoverable by anyone.',
              style: TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK')),
          ],
        ),
      );
      return;
    }

    try {
      await SupabaseService.instance.updateChatPrivacy(newStatus);
      _loadInitialData(); // Re-fetch all data to ensure UI is consistent
    } catch (e) {
      // Handle error
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _dataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              backgroundColor: darkSuedeNavy,
              body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return Scaffold(
              backgroundColor: darkSuedeNavy,
              body: Center(
                  child: Text('Error: ${snapshot.error}',
                      style: const TextStyle(color: Colors.red))));
        }

        // Unpack all data from the single future's result
        final userProfile = snapshot.data!.$1;
        final allConversations = snapshot.data!.$2;
        final subscriptions = snapshot.data!.$3;

        final chatPrivacy = userProfile['chat_privacy'] as String? ?? 'private';
        final isPublic = chatPrivacy == 'public';

        return Scaffold(
          backgroundColor: darkSuedeNavy,
          appBar: AppBar(
            backgroundColor: darkSuedeNavy,
            title: const Text('Chit Chat'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: Row(
                  children: [
                    Text(
                      isPublic ? 'Public' : 'Private',
                      style: TextStyle(
                          color: isPublic ? Colors.cyanAccent : Colors.white70),
                    ),
                    const SizedBox(width: 4),
                    CupertinoSwitch(
                      value: isPublic,
                      onChanged: (value) => _togglePrivacy(value, userProfile),
                      activeColor: Colors.cyanAccent,
                    ),
                  ],
                ),
              ),
            ],
          ),
          body: isPublic
              ? _buildPublicView(allConversations, subscriptions)
              : _buildPrivateView(subscriptions),
          floatingActionButton: isPublic
              ? FloatingActionButton(
                  onPressed: () {
                    Navigator.of(context)
                        .push(
                      MaterialPageRoute(
                          builder: (context) => const NewChatScreen()),
                    )
                        .then((didStartChat) {
                      if (didStartChat == true) _loadInitialData();
                    });
                  },
                  backgroundColor: Colors.cyanAccent,
                  child: const Icon(Icons.add_comment_outlined,
                      color: Colors.black),
                )
              : null,
        );
      },
    );
  }

  Widget _buildPrivateView(List<Map<String, dynamic>> subscriptions) {
    if (subscriptions.isEmpty) {
      return const Center(
        child: Text('Your subscribed timetables will appear here.',
            style: TextStyle(color: Colors.white70)),
      );
    }
    return ListView.builder(
      itemCount: subscriptions.length,
      itemBuilder: (context, index) {
        final user = subscriptions[index];
        final username = user['username'] as String?;
        final avatarUrl = user['avatar_url'] as String?;

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: lightSuedeNavy,
            backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                ? NetworkImage(avatarUrl)
                : null,
            child: (avatarUrl == null || avatarUrl.isEmpty)
                ? Text(username?.isNotEmpty == true
                    ? username![0].toUpperCase()
                    : '?')
                : null,
          ),
          title: Text(username ?? 'User',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
          onTap: () async {
            final conversationId = await SupabaseService.instance
                .createOrGetConversation(user['id']);
            if (!mounted) return;
            final result = await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => ChatScreen(
                  conversationId: conversationId,
                  chatTitle: username ?? 'Chat',
                  otherParticipantId: user['id'],
                  otherParticipantUsername: username,
                  otherParticipantAvatarUrl: avatarUrl,
                ),
              ),
            );
            if (result == true) {
              _loadInitialData();
            }
          },
        );
      },
    );
  }

  Widget _buildPublicView(List<Map<String, dynamic>> allConversations,
      List<Map<String, dynamic>> subscriptions) {
    final subscriptionIds = subscriptions.map((s) => s['id'] as String).toSet();

    final publicChats = allConversations.where((c) {
      final otherId = c['other_participant_id'] as String?;
      final isGroup = c['is_group'] as bool? ?? false;
      return isGroup || (otherId != null && !subscriptionIds.contains(otherId));
    }).toList();

    if (publicChats.isEmpty) {
      return const Center(
        child: Text("Conversations with non-subscribers will appear here.",
            style: TextStyle(color: Colors.white70)),
      );
    }
    return ListView.builder(
      itemCount: publicChats.length,
      itemBuilder: (context, index) {
        return _buildConversationTile(publicChats[index]);
      },
    );
  }

  Widget _buildConversationTile(Map<String, dynamic> convo) {
    final isGroup = convo['is_group'] as bool? ?? false;
    final title = isGroup
        ? convo['group_name'] ?? 'Group Chat'
        : convo['other_participant_username'] ?? 'User';
    final avatarUrl = isGroup
        ? convo['group_avatar_url']
        : convo['other_participant_avatar_url'];
    final lastMessageTime = convo['last_message_at'] != null
        ? DateFormat.jm()
            .format(DateTime.parse(convo['last_message_at']).toLocal())
        : '';
    final otherParticipantId = isGroup ? null : convo['other_participant_id'];
    final otherParticipantUsername =
        isGroup ? null : convo['other_participant_username'];

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: lightSuedeNavy,
        backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
            ? NetworkImage(avatarUrl)
            : null,
        child: (avatarUrl == null || avatarUrl.isEmpty)
            ? Text(title.isNotEmpty ? title[0].toUpperCase() : '?')
            : null,
      ),
      title: Text(title,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold)),
      subtitle: Text('Last message...',
          style: const TextStyle(color: Colors.white70)),
      trailing: Text(lastMessageTime,
          style: const TextStyle(color: Colors.white38, fontSize: 12)),
      onTap: () async {
        final result = await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              conversationId: convo['conversation_id'],
              chatTitle: title,
              otherParticipantId: otherParticipantId,
              otherParticipantUsername: otherParticipantUsername,
              otherParticipantAvatarUrl: avatarUrl,
            ),
          ),
        );
        if (result == true) {
          _loadInitialData();
        }
      },
    );
  }
}
