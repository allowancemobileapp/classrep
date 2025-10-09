// lib/shared/services/supabase_service.dart

import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:class_rep/shared/services/auth_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// Helper to access the Supabase client easily.
final supabase = Supabase.instance.client;

class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  // Fetches the user's profile from the 'users' table.
  Future<Map<String, dynamic>> fetchUserProfile(String userId) async {
    final response =
        await supabase.from('users').select().eq('id', userId).single();
    return response;
  }

  // Fetches all events for the current user by calling the RPC function.
  Future<List<Map<String, dynamic>>> fetchEvents() async {
    final response = await supabase.rpc('get_timetable_events_for_user');
    return (response as List).cast<Map<String, dynamic>>();
  }

  // Creates a new event in the database.
  Future<void> createEvent({
    required String title,
    String? description,
    required DateTime startTime,
    required DateTime endTime,
    String? groupId,
    String? imageUrl,
    String? linkUrl,
    String? repeat,
  }) async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) throw Exception('User not logged in');

    await supabase.from('events').insert({
      'creator_user_id': userId,
      'title': title,
      'description': description,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime.toIso8601String(),
      'group_id': groupId,
      'image_url': imageUrl,
      'url': linkUrl,
      'repeat': repeat,
    });
  }

  // Updates an existing event in the database.
  Future<void> updateEvent({
    required String eventId,
    required String title,
    String? description,
    required DateTime startTime,
    required DateTime endTime,
    String? groupId,
    String? imageUrl,
    String? linkUrl,
    String? repeat,
  }) async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) throw Exception('User not logged in');

    await supabase.from('events').update({
      'title': title,
      'description': description,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime.toIso8601String(),
      'group_id': groupId,
      'image_url': imageUrl,
      'url': linkUrl,
      'repeat': repeat,
    }).eq('id', eventId);
  }

  // Deletes an event from the database.
  Future<void> deleteEvent(String eventId) async {
    await supabase.from('events').delete().eq('id', eventId);
  }

  // Fetches event groups created by the current user.
  Future<List<Map<String, dynamic>>> fetchEventGroups() async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) return [];

    final response = await supabase
        .from('event_groups')
        .select()
        .eq('owner_user_id', userId);
    return (response as List).cast<Map<String, dynamic>>();
  }

  // Creates a new event group.
  Future<void> createEventGroup(String groupName) async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) throw Exception('User not logged in');

    final random = Random();
    final color = Color.fromARGB(
      255,
      random.nextInt(156) + 100,
      random.nextInt(156) + 100,
      random.nextInt(156) + 100,
    );

    await supabase.from('event_groups').insert({
      'owner_user_id': userId,
      'group_name': groupName,
      'color': '#${color.value.toRadixString(16).substring(2)}',
    });
  }

  // Deletes an event group.
  Future<void> deleteEventGroup(String groupId) async {
    await supabase.from('event_groups').delete().eq('id', groupId);
  }

  // Toggles the visibility of an event group.
  Future<void> toggleGroupVisibility(
    String groupId,
    String currentVisibility,
  ) async {
    final newVisibility = currentVisibility == 'public' ? 'private' : 'public';
    await supabase
        .from('event_groups')
        .update({'visibility': newVisibility}).eq('id', groupId);
  }

  // Subscribes the current user to another user's timetable.
  Future<void> subscribeToTimetable(String username) async {
    await supabase.rpc(
      'subscribe_to_timetable',
      params: {'p_owner_username': username},
    );
  }

  // Fetches the list of users that the current user is subscribed to.
  Future<List<Map<String, dynamic>>> getMySharedUsers() async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) return [];

    final response = await supabase
        .from('timetable_subscriptions')
        // ADDED 'has_active_gist' to the selection
        .select(
            'owner:owner_id(id, username, display_name, avatar_url, has_active_gist)')
        .eq('subscriber_id', userId);

    return (response as List)
        .map((row) => row['owner'])
        .where((owner) => owner != null)
        .map((owner) => owner as Map<String, dynamic>)
        .toList();
  }

  // Unsubscribes from a user's timetable.
  Future<void> unsubscribeFromTimetable(String ownerId) async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) throw Exception('User not logged in');

    await supabase.from('timetable_subscriptions').delete().match({
      'owner_id': ownerId,
      'subscriber_id': userId,
    });
  }

  // Fetches creator stats (addon counts, rewards) for the current user.
  Future<Map<String, dynamic>> fetchCreatorStats() async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) throw Exception('User not logged in');

    final response = await supabase.rpc('fetch_creator_stats').maybeSingle();

    return response ??
        {
          'plus_addons_count': 0,
          'reward_balance': 0,
          'total_earned': 0,
          'total_subscriber_count': 0
        };
  }

  // Uploads a selected image file to the 'event_images' bucket.
  Future<String> uploadEventImage({
    required String filePath,
    required List<int> fileBytes,
  }) async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) throw Exception('User not logged in');

    final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final storagePath = '$userId/$fileName';

    await supabase.storage.from('event_images').uploadBinary(
          storagePath,
          Uint8List.fromList(fileBytes),
          fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
        );

    return supabase.storage.from('event_images').getPublicUrl(storagePath);
  }

  Future<Map<String, dynamic>> getPaystackCheckoutUrl(
      {required String email}) async {
    final response = await supabase.functions.invoke(
      'get-paystack-checkout-url',
      body: {'email': email},
    );

    if (response.data['error'] != null) {
      throw Exception(response.data['error']);
    }
    return response.data as Map<String, dynamic>;
  }

  Future<bool> verifyPayment(String reference) async {
    try {
      final response = await supabase.functions.invoke(
        'verify-paystack-payment',
        body: {'reference': reference},
      );

      final responseData = response.data;

      if (response.status != 200 ||
          (responseData is Map && responseData.containsKey('error'))) {
        final errorMsg = (responseData is Map && responseData['error'] != null)
            ? responseData['error'].toString()
            : 'An unknown verification error occurred.';
        throw Exception(errorMsg);
      }

      return true;
    } on FunctionException catch (e) {
      final details = e.details;
      String errorMessage = 'Verification failed.';
      if (details is Map && details.containsKey('error')) {
        errorMessage = details['error'].toString();
      }
      throw Exception(errorMessage);
    } catch (e) {
      throw Exception('An unexpected error occurred: ${e.toString()}');
    }
  }

  Future<void> cancelSubscription() async {
    try {
      final response =
          await supabase.functions.invoke('cancel-paystack-subscription');
      if (response.status != 200) {
        throw Exception(
            response.data['error'] ?? 'Failed to cancel subscription.');
      }
    } catch (e) {
      throw Exception('Error calling cancel-subscription function: $e');
    }
  }

  Future<bool> confirmSubscriptionRecord() async {
    try {
      final response =
          await supabase.functions.invoke('confirm-subscription-record');
      if (response.data['status'] == 'success') {
        return true;
      } else {
        throw Exception(response.data['error'] ?? 'Confirmation failed.');
      }
    } catch (e) {
      throw Exception('Error calling confirm-subscription-record function: $e');
    }
  }

  Future<bool> confirmCancellationState() async {
    try {
      final response =
          await supabase.functions.invoke('confirm-cancellation-state');
      if (response.data['status'] == 'success') {
        return true;
      } else {
        throw Exception(response.data['error'] ?? 'Confirmation failed.');
      }
    } catch (e) {
      throw Exception('Error calling confirm-cancellation-state function: $e');
    }
  }

  Future<String> uploadAvatar(XFile image) async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) throw Exception('User not logged in');

    final bytes = await image.readAsBytes();
    final fileExt = image.path.split('.').last;
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.$fileExt';
    final filePath = '$userId/$fileName';

    await supabase.storage.from('avatars').uploadBinary(
          filePath,
          bytes,
          fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
        );

    return supabase.storage.from('avatars').getPublicUrl(filePath);
  }

  Future<void> updateUserProfile({
    required String displayName,
    required String? username,
    required String? bio,
    required String? twitterHandle,
    String? avatarUrl,
    String? usdtWalletAddress,
    String? fcmToken, // ADD THIS NEW PARAMETER
  }) async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) throw Exception('User not logged in');

    final updates = {
      'display_name': displayName,
      'username': username,
      'bio': bio,
      'twitter_handle': twitterHandle,
      'usdt_wallet_address': usdtWalletAddress,
    };

    if (avatarUrl != null) {
      updates['avatar_url'] = avatarUrl;
    }
    // ADD THIS LOGIC
    if (fcmToken != null) {
      updates['fcm_token'] = fcmToken;
    }

    await supabase.from('users').update(updates).eq('id', userId);
  }

  Future<List<Map<String, dynamic>>> fetchNotifications() async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) return [];

    final response = await supabase
        .from('notifications')
        .select('*, actor:actor_user_id(username, avatar_url)')
        .eq('recipient_user_id', userId)
        .order('created_at', ascending: false);

    return (response as List).cast<Map<String, dynamic>>();
  }

  Future<int> getUnreadNotificationsCount() async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) return 0;

    final response = await supabase
        .from('notifications')
        .count(CountOption.exact)
        .eq('recipient_user_id', userId)
        .eq('is_read', false);

    return response;
  }

  Future<void> markNotificationsAsRead() async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) return;
    await supabase
        .from('notifications')
        .update({'is_read': true})
        .eq('recipient_user_id', userId)
        .eq('is_read', false);
  }

  Future<void> requestCancellation() async {
    try {
      final response = await supabase.functions.invoke('request-cancellation');
      if (response.status != 200) {
        final errorMsg =
            response.data?['error'] ?? 'Failed to submit cancellation request.';
        throw Exception(errorMsg);
      }
    } catch (e) {
      throw Exception(
          'Error calling request-cancellation function: ${e.toString()}');
    }
  }

  Future<bool> hasPendingCancellation() async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) return false;

    try {
      final response = await supabase
          .from('cancellation_requests')
          .select('id')
          .eq('user_id', userId)
          .eq('status', 'pending')
          .limit(1)
          .maybeSingle();
      return response != null;
    } catch (e) {
      debugPrint('Error checking for pending cancellation: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> fetchCommentsForEvent(
      String eventId) async {
    try {
      final response = await supabase.rpc(
        'get_comments_for_event',
        params: {'p_event_id': eventId},
      );

      final comments = (response as List).cast<Map<String, dynamic>>();

      final enriched = comments.map((c) {
        c['content'] = c['text'] ?? '';
        return c;
      }).toList();

      return enriched;
    } catch (e) {
      throw Exception('Error fetching comments: $e');
    }
  }

  Future<void> addComment({
    required String eventId,
    required String content,
    String? parentCommentId,
  }) async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) throw Exception('User not logged in');
    if (content.trim().isEmpty) throw Exception('Comment cannot be empty');

    try {
      await supabase.from('event_comments').insert({
        'event_id': eventId,
        'commenter_user_id': userId,
        'text': content.trim(),
        'parent_comment_id': parentCommentId,
      });
    } catch (e) {
      throw Exception('Error posting comment: $e');
    }
  }

  Future<void> deleteComment(String commentId) async {
    try {
      await supabase.from('event_comments').delete().eq('id', commentId);
    } catch (e) {
      throw Exception('Error deleting comment: $e');
    }
  }

  Future<void> likeComment(String commentId) async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) throw Exception('User not logged in');
    await supabase.from('comment_likes').insert({
      'comment_id': commentId,
      'user_id': userId,
    });
  }

  Future<void> unlikeComment(String commentId) async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) throw Exception('User not logged in');
    await supabase.from('comment_likes').delete().match({
      'comment_id': commentId,
      'user_id': userId,
    });
  }

  Future<void> initNotifications() async {
    final messaging = FirebaseMessaging.instance;

    await messaging.requestPermission();
    final fcmToken = await messaging.getToken();

    final userId = AuthService.instance.currentUser?.id;
    if (fcmToken != null && userId != null) {
      try {
        await supabase
            .from('users')
            .update({'fcm_token': fcmToken}).eq('id', userId);
      } catch (e) {
        debugPrint('Error saving FCM token: $e');
      }
    }
  }

  Future<List<Map<String, dynamic>>> getGroupMembers(String groupId) async {
    final response = await supabase
        .from('group_members')
        .select('users(*)')
        .eq('group_id', groupId);

    return (response as List)
        .map((row) => row['users'] as Map<String, dynamic>)
        .toList();
  }

  Future<List<Map<String, dynamic>>> findSubscribers(String searchText) async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) return [];

    final subsResponse = await supabase
        .from('timetable_subscriptions')
        .select('subscriber_id')
        .eq('owner_id', userId);

    final subscriberIds = (subsResponse as List)
        .map((row) => row['subscriber_id'] as String)
        .toList();

    if (subscriberIds.isEmpty) return [];

    final usersResponse = await supabase
        .from('users')
        .select()
        .inFilter('id', subscriberIds)
        .ilike('username', '%$searchText%');

    return (usersResponse as List).cast<Map<String, dynamic>>();
  }

  Future<void> removeGroupMember(String groupId, String userId) async {
    await supabase
        .from('group_members')
        .delete()
        .match({'group_id': groupId, 'user_id': userId});
  }

  Future<void> addGroupMember(String groupId, String userId) async {
    await supabase.from('group_members').insert({
      'group_id': groupId,
      'user_id': userId,
    });
  }

  Future<List<Map<String, dynamic>>> getAddableGroupMembers(
      String groupId) async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) return [];

    final subsResponse = await supabase
        .from('timetable_subscriptions')
        .select('subscriber_id')
        .eq('owner_id', userId);
    final subscriberIds = (subsResponse as List)
        .map((row) => row['subscriber_id'] as String)
        .toList();

    if (subscriberIds.isEmpty) return [];

    final membersResponse = await supabase
        .from('group_members')
        .select('user_id')
        .eq('group_id', groupId);
    final memberIds = (membersResponse as List)
        .map((row) => row['user_id'] as String)
        .toList();

    final addableIds =
        subscriberIds.where((id) => !memberIds.contains(id)).toList();

    if (addableIds.isEmpty) return [];

    final usersResponse = await supabase
        .from('users')
        .select('id, username, avatar_url')
        .inFilter('id', addableIds);

    return (usersResponse as List).cast<Map<String, dynamic>>();
  }

  Future<void> sendEventReminder(String eventId) async {
    await supabase.rpc(
      'send_event_reminder',
      params: {'event_id_to_remind': eventId},
    );
  }

  // --- NEW CHAT METHODS ---

  Future<List<Map<String, dynamic>>> getConversations() async {
    final response = await supabase.rpc('get_my_conversations');
    return (response as List).cast<Map<String, dynamic>>();
  }

  Future<String> createOrGetConversation(String otherUserId) async {
    final response = await supabase.rpc(
      'create_or_get_conversation',
      params: {'p_other_user_id': otherUserId},
    );
    return response as String;
  }

  Future<List<Map<String, dynamic>>> getMessages(String conversationId) async {
    final response = await supabase
        .from('chat_messages')
        .select('*, author:user_id(username, avatar_url)')
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true);
    return (response as List).cast<Map<String, dynamic>>();
  }

  Future<void> sendMessage({
    required String conversationId,
    required String content,
    String? attachmentUrl,
    String? attachmentType,
    String? fileName, // NEW
  }) async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) throw Exception('User not logged in');

    if (content.trim().isEmpty && attachmentUrl == null) return;

    await supabase.from('chat_messages').insert({
      'conversation_id': conversationId,
      'user_id': userId,
      'content': content,
      'attachment_url': attachmentUrl,
      'attachment_type': attachmentType,
      'file_name': fileName, // NEW
    });
  }

  // This sets up the real-time subscription
  RealtimeChannel subscribeToMessages(
      String conversationId, void Function(Map<String, dynamic>) onNewMessage) {
    final channel = supabase
        .channel('chat:$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) {
            // Before passing the new message, we need to fetch the author's details
            // because the real-time payload only contains the user_id.
            final newMessage = payload.newRecord;
            fetchUserProfile(newMessage['user_id']).then((authorProfile) {
              newMessage['author'] = authorProfile;
              onNewMessage(newMessage);
            });
          },
        )
        .subscribe();

    return channel;
  }

  Future<void> updateChatPrivacy(String newPrivacy) async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) throw Exception('User not logged in');

    await supabase
        .from('users')
        .update({'chat_privacy': newPrivacy}).eq('id', userId);
  }

  Future<List<Map<String, dynamic>>> searchAllUsers(String searchText) async {
    final userId = AuthService.instance.currentUser?.id;
    if (searchText.trim().isEmpty) return [];

    final response = await supabase
        .from('users')
        .select('id, username, avatar_url')
        .ilike('username', '%${searchText.trim()}%')
        .not('id', 'eq', userId) // Exclude the current user from search results
        .limit(10);

    return (response as List).cast<Map<String, dynamic>>();
  }

  Future<bool> isSubscribedTo(String ownerId) async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) return false;

    final response = await supabase
        .from('timetable_subscriptions')
        .select('id')
        .match({'owner_id': ownerId, 'subscriber_id': userId}).maybeSingle();

    return response != null;
  }

  Future<List<Map<String, dynamic>>> getSuggestedUsers(
      {int page = 1, int pageSize = 10}) async {
    final response = await supabase.rpc(
      'get_suggested_users',
      params: {
        'p_limit': pageSize,
        'p_offset': (page - 1) * pageSize,
      },
    );
    return (response as List).cast<Map<String, dynamic>>();
  }

  Future<void> uploadChatAttachment({
    required String conversationId,
    required String filePath,
    required String fileName,
    required List<int> fileBytes,
    required String attachmentType, // 'image' or 'file'
  }) async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) throw Exception('User not logged in');

    // 1. Check and increment the user's daily count.
    await supabase.rpc('check_and_increment_attachment_count');

    // 2. Proceed with the upload.
    final storagePath = '$conversationId/$userId/$fileName';

    await supabase.storage.from('chat_attachments').uploadBinary(
          storagePath,
          Uint8List.fromList(fileBytes),
          fileOptions: FileOptions(upsert: false),
        );

    // 3. Get the public URL.
    final attachmentUrl =
        supabase.storage.from('chat_attachments').getPublicUrl(storagePath);

    // 4. Send a new message with the attachment URL and file name.
    await sendMessage(
      conversationId: conversationId,
      content: '', // Optional: you could add a caption here later
      attachmentUrl: attachmentUrl,
      attachmentType: attachmentType,
      fileName: fileName,
    );
  }

  Future<String> createGroupConversation({
    required String groupName,
    required List<String> participantIds,
  }) async {
    final response = await supabase.rpc(
      'create_group_conversation',
      params: {
        'p_group_name': groupName,
        'p_participant_ids': participantIds,
      },
    );
    return response as String;
  }

  Future<List<Map<String, dynamic>>> getGroupParticipants(
      String conversationId) async {
    final response = await supabase.rpc(
      'chat_get_group_participants', // RENAMED
      params: {'p_conversation_id': conversationId},
    );
    return (response as List).cast<Map<String, dynamic>>();
  }

  Future<void> addGroupParticipant({
    required String conversationId,
    required String userIdToAdd,
  }) async {
    await supabase.rpc(
      'chat_add_group_participant', // RENAMED
      params: {
        'p_conversation_id': conversationId,
        'p_user_id_to_add': userIdToAdd,
      },
    );
  }

  Future<void> removeGroupParticipant({
    required String conversationId,
    required String userIdToRemove,
  }) async {
    await supabase.rpc(
      'chat_remove_group_participant', // RENAMED
      params: {
        'p_conversation_id': conversationId,
        'p_user_id_to_remove': userIdToRemove,
      },
    );
  }

  Future<void> deleteGroupConversation(String conversationId) async {
    await supabase.rpc(
      'chat_delete_group_conversation', // RENAMED
      params: {'p_conversation_id': conversationId},
    );
  }

  Future<List<Map<String, dynamic>>> getAddableChatGroupMembers({
    required String conversationId,
  }) async {
    // 1. Get all of the user's subscriptions
    final allSubscribers = await getMySharedUsers();
    // 2. Get the group's current participants
    final currentParticipants = await getGroupParticipants(conversationId);
    final currentParticipantIds =
        currentParticipants.map((p) => p['id']).toSet();

    // 3. Filter out users who are already in the group
    final addableMembers = allSubscribers.where((sub) {
      return !currentParticipantIds.contains(sub['id']);
    }).toList();

    return addableMembers;
  }

  Future<String> getOrCreateGroupInviteCode(String conversationId) async {
    final response = await supabase.rpc(
      'get_or_create_chat_invite_code',
      params: {'p_conversation_id': conversationId},
    );
    return response as String;
  }

  Future<String> joinGroupWithInviteCode(String inviteCode) async {
    final response = await supabase.rpc(
      'join_chat_group_with_invite_code',
      params: {'p_invite_code': inviteCode},
    );
    return response as String;
  }

  Future<String> uploadGistMedia(XFile file) async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) throw Exception('User not logged in');

    final fileBytes = await file.readAsBytes();
    final fileExt = file.path.split('.').last;
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.$fileExt';
    final filePath = '$userId/$fileName';

    await supabase.storage.from('gists_media').uploadBinary(
          filePath,
          fileBytes,
          fileOptions: FileOptions(contentType: file.mimeType),
        );

    return supabase.storage.from('gists_media').getPublicUrl(filePath);
  }

  Future<void> createGist({
    required String type,
    String? content,
    String? mediaUrl,
    String? caption, // New parameter
  }) async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) throw Exception('User not logged in');

    await supabase.rpc('check_and_increment_gist_count');

    await supabase.from('gists').insert({
      'user_id': userId,
      'type': type,
      'content': content,
      'media_url': mediaUrl,
      'caption': caption, // Add caption to the insert
    });

    await supabase.rpc('set_user_active_gist_status');
  }

  // Fetches all active gists for a specific user
  Future<List<Map<String, dynamic>>> getGistsForUser(String userId) async {
    final response = await supabase
        .from('gists')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: true);
    return (response as List).cast<Map<String, dynamic>>();
  }

  // Fetches a "feed" of users who have active gists, focusing on subscriptions
  Future<List<Map<String, dynamic>>> getGistFeed(
      {required bool onlySubscriptions}) async {
    final response = await supabase.rpc(
      'get_gist_feed_users',
      params: {
        'p_only_subscriptions': onlySubscriptions,
      },
    );
    return (response as List).cast<Map<String, dynamic>>();
  }

  Future<void> resetUnreadCount(String conversationId) async {
    await supabase.rpc(
      'reset_unread_count',
      params: {'p_conversation_id': conversationId},
    );
  }

  Future<int> getTotalUnreadConversationsCount() async {
    final response = await supabase.rpc('get_total_unread_conversations_count');
    return response as int;
  }

  Future<void> markMessagesAsRead(String conversationId) async {
    await supabase.rpc(
      'reset_unread_count',
      params: {'p_conversation_id': conversationId},
    );
  }

  Future<void> deleteGist(String gistId) async {
    await supabase.from('gists').delete().eq('id', gistId);
  }

  Future<void> likeGist(String gistId) async {
    await supabase.rpc('like_gist', params: {'p_gist_id': gistId});
  }

  Future<void> unlikeGist(String gistId) async {
    await supabase.rpc('unlike_gist', params: {'p_gist_id': gistId});
  }

  Future<void> incrementGistView(String gistId) async {
    await supabase.rpc('increment_gist_view', params: {'p_gist_id': gistId});
  }

  Future<void> initFcm() async {
    final messaging = FirebaseMessaging.instance;

    // Request Permission
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('User granted push notification permission');
    } else {
      debugPrint(
          'User declined or has not accepted push notification permission');
      return;
    }

    // Get and Save Token (use Supabase user directly)
    String? fcmToken = await messaging.getToken();
    final user = supabase.auth.currentUser;
    if (fcmToken != null && user != null) {
      try {
        await supabase
            .from('users')
            .update({'fcm_token': fcmToken}).eq('id', user.id);
        debugPrint('FCM token saved successfully: $fcmToken');
      } catch (e) {
        debugPrint('Error saving FCM token: $e');
      }
    }

    // Token Refresh Listener
    messaging.onTokenRefresh.listen((newToken) async {
      final currentUser = supabase.auth.currentUser;
      if (currentUser != null) {
        try {
          await supabase
              .from('users')
              .update({'fcm_token': newToken}).eq('id', currentUser.id);
          debugPrint('FCM token refreshed and stored: $newToken');
        } catch (e) {
          debugPrint('Error storing refreshed FCM token: $e');
        }
      }
    });
  }
}
