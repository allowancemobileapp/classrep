// lib/features/chat/presentation/conversations_screen.dart

import 'dart:async';
import 'package:class_rep/features/chat/presentation/chat_screen.dart';
import 'package:class_rep/features/chat/presentation/new_chat_screen.dart';
import 'package:class_rep/features/chat/presentation/new_group_screen.dart';
import 'package:class_rep/features/profile/presentation/gist_viewer_screen.dart';
import 'package:class_rep/shared/services/auth_service.dart';
import 'package:class_rep/shared/services/supabase_service.dart';
import 'package:class_rep/shared/widgets/gist_avatar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const Color darkSuedeNavy = Color(0xFF1A1B2C);
const Color lightSuedeNavy = Color(0xFF2A2C40);

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});
  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  Future<
      (
        Map<String, dynamic>,
        List<Map<String, dynamic>>,
        List<Map<String, dynamic>>,
        List<Map<String, dynamic>>
      )>? _dataFuture;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  RealtimeChannel? _realtimeSubscription;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _setupRealtimeListener();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    if (_realtimeSubscription != null) {
      supabase.removeChannel(_realtimeSubscription!);
    }
    super.dispose();
  }

  // --- THIS IS THE CORRECTED METHOD ---
  void _setupRealtimeListener() {
    final currentUserId = AuthService.instance.currentUser?.id;
    if (currentUserId == null) return;

    _realtimeSubscription = supabase
        .channel('public:chat_participants:user_id=eq.$currentUserId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all, // Correct Enum for '*'
          schema: 'public',
          table: 'chat_participants',
          filter: PostgresChangeFilter(
            // Correct Filter Class
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: currentUserId,
          ),
          callback: (payload) {
            // When unread_count updates, reload all data to refresh the UI
            if (mounted) {
              _loadInitialData();
            }
          },
        )
        .subscribe();
  }

  void _loadInitialData() {
    if (mounted) {
      setState(() {
        _dataFuture = _fetchData();
      });
    }
  }

  Future<
      (
        Map<String, dynamic>,
        List<Map<String, dynamic>>,
        List<Map<String, dynamic>>,
        List<Map<String, dynamic>>
      )> _fetchData() async {
    final profile = await SupabaseService.instance
        .fetchUserProfile(AuthService.instance.currentUser!.id);
    final isPublic =
        (profile['chat_privacy'] as String? ?? 'private') == 'public';

    final conversationsFuture = SupabaseService.instance.getConversations();
    final subscriptionsFuture = SupabaseService.instance.getMySharedUsers();
    final gistFeedFuture =
        SupabaseService.instance.getGistFeed(onlySubscriptions: !isPublic);

    final results = await Future.wait(
        [conversationsFuture, subscriptionsFuture, gistFeedFuture]);

    final conversations = (results[0] as List).cast<Map<String, dynamic>>();
    final subscriptions = (results[1] as List).cast<Map<String, dynamic>>();
    final gistFeedUsers = (results[2] as List).cast<Map<String, dynamic>>();

    return (profile, conversations, subscriptions, gistFeedUsers);
  }

  // ... (the rest of your file is exactly the same as the last version I sent)
  // ...

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
              'You must be a Plus subscriber to make your chat public.',
              style: TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK'))
          ],
        ),
      );
      return;
    }
    try {
      await SupabaseService.instance.updateChatPrivacy(newStatus);
      _loadInitialData();
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

        final userProfile = snapshot.data!.$1;
        final allConversations = snapshot.data!.$2;
        final subscriptions = snapshot.data!.$3;
        final gistFeedUsers = snapshot.data!.$4;

        final isPublic =
            (userProfile['chat_privacy'] as String? ?? 'private') == 'public';

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
                    Text(isPublic ? 'Public' : 'Private',
                        style: TextStyle(
                            color:
                                isPublic ? Colors.cyanAccent : Colors.white70)),
                    const SizedBox(width: 4),
                    CupertinoSwitch(
                        value: isPublic,
                        onChanged: (value) =>
                            _togglePrivacy(value, userProfile),
                        activeColor: Colors.cyanAccent),
                  ],
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              if (isPublic)
                _buildGistFeed(gistFeedUsers)
              else
                _buildSearchBar(),
              Expanded(
                child: isPublic
                    ? _buildPublicView(allConversations, subscriptions)
                    : _buildPrivateView(allConversations, subscriptions),
              ),
            ],
          ),
          floatingActionButton: isPublic
              ? FloatingActionButton(
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: lightSuedeNavy,
                      builder: (context) {
                        return SafeArea(
                          child: Wrap(
                            children: <Widget>[
                              ListTile(
                                leading: const Icon(Icons.person_add,
                                    color: Colors.white70),
                                title: const Text('New Chat',
                                    style: TextStyle(color: Colors.white)),
                                onTap: () {
                                  Navigator.of(context).pop();
                                  Navigator.of(context)
                                      .push(
                                    MaterialPageRoute(
                                        builder: (context) =>
                                            const NewChatScreen()),
                                  )
                                      .then((didStartChat) {
                                    if (didStartChat == true)
                                      _loadInitialData();
                                  });
                                },
                              ),
                              ListTile(
                                leading: const Icon(Icons.group_add,
                                    color: Colors.white70),
                                title: const Text('New Group',
                                    style: TextStyle(color: Colors.white)),
                                onTap: () {
                                  Navigator.of(context).pop();
                                  Navigator.of(context)
                                      .push(
                                    MaterialPageRoute(
                                        builder: (context) =>
                                            const NewGroupScreen()),
                                  )
                                      .then((didCreateGroup) {
                                    if (didCreateGroup == true)
                                      _loadInitialData();
                                  });
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                  backgroundColor: Colors.cyanAccent,
                  child: const Icon(Icons.add, color: Colors.black),
                )
              : null,
        );
      },
    );
  }

  Widget _buildGistFeed(List<Map<String, dynamic>> gistFeedUsers) {
    if (gistFeedUsers.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 100,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: lightSuedeNavy, width: 1)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: gistFeedUsers.length,
        itemBuilder: (context, index) {
          final user = gistFeedUsers[index];
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

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Search your conversations...',
          hintStyle: const TextStyle(color: Colors.white38),
          prefixIcon: const Icon(Icons.search, color: Colors.white70),
          filled: true,
          fillColor: lightSuedeNavy,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _buildPrivateView(List<Map<String, dynamic>> conversations,
      List<Map<String, dynamic>> subscriptions) {
    final Map<String, Map<String, dynamic>> subscriptionMap = {
      for (var sub in subscriptions) sub['id']: sub
    };
    final Map<String, Map<String, dynamic>> conversationMap = {
      for (var convo in conversations)
        if (convo['other_participant_id'] != null &&
            subscriptionMap.containsKey(convo['other_participant_id']))
          convo['other_participant_id']: convo
    };

    final combinedList = subscriptions.map((sub) {
      final conversationData = conversationMap[sub['id']];
      if (conversationData != null) {
        return conversationData..['has_active_gist'] = sub['has_active_gist'];
      } else {
        return {
          'is_group': false,
          'other_participant_id': sub['id'],
          'other_participant_username': sub['username'],
          'other_participant_avatar_url': sub['avatar_url'],
          'has_active_gist': sub['has_active_gist'],
          'last_message_at': null,
          'unread_count': 0, // Assume 0 if no conversation exists
        };
      }
    }).toList();

    combinedList.sort((a, b) {
      final aTime = a['last_message_at'] != null
          ? DateTime.parse(a['last_message_at'])
          : DateTime(1970);
      final bTime = b['last_message_at'] != null
          ? DateTime.parse(b['last_message_at'])
          : DateTime(1970);
      return bTime.compareTo(aTime);
    });

    final filteredList = _searchQuery.isEmpty
        ? combinedList
        : combinedList.where((convo) {
            final title = (convo['is_group']
                    ? convo['group_name']
                    : convo['other_participant_username']) as String? ??
                '';
            return title.toLowerCase().contains(_searchQuery.toLowerCase());
          }).toList();

    if (filteredList.isEmpty) {
      return Center(
        child: Text(
          _searchQuery.isEmpty
              ? 'Your subscribed timetables will appear here.'
              : 'No conversations found.',
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }

    return ListView.builder(
      itemCount: filteredList.length,
      itemBuilder: (context, index) {
        return _buildConversationTile(filteredList[index]);
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
        child: Text("Use the '+' button to find and chat with new users.",
            style: TextStyle(color: Colors.white70),
            textAlign: TextAlign.center),
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
    final hasActiveGist = convo['has_active_gist'] as bool? ?? false;
    final unreadCount = convo['unread_count'] as int? ?? 0;

    return ListTile(
      leading: GestureDetector(
        onTap: () {
          if (hasActiveGist && otherParticipantId != null) {
            Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => GistViewerScreen(
                      userId: otherParticipantId,
                      username: otherParticipantUsername ?? 'User',
                      avatarUrl: avatarUrl ?? '',
                    )));
          }
        },
        child: GistAvatar(
          radius: 24,
          avatarUrl: avatarUrl,
          hasActiveGist: hasActiveGist,
          fallbackText: title.isNotEmpty ? title[0].toUpperCase() : '?',
        ),
      ),
      title: Text(title,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold)),
      subtitle: Text(
        convo['last_message_at'] != null
            ? 'Last message...'
            : 'Start the conversation!',
        style: const TextStyle(color: Colors.white70),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(lastMessageTime,
              style: const TextStyle(color: Colors.white38, fontSize: 12)),
          if (unreadCount > 0) ...[
            const SizedBox(height: 4),
            CircleAvatar(
              radius: 10,
              backgroundColor: Colors.cyanAccent,
              child: Text(
                unreadCount.toString(),
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ]
        ],
      ),
      onTap: () async {
        final conversationId = convo['conversation_id'] ??
            await SupabaseService.instance
                .createOrGetConversation(otherParticipantId!);
        if (!mounted) return;

        final result = await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              conversationId: conversationId,
              chatTitle: title,
              isGroup: isGroup,
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
