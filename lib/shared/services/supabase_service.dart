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
        .select('owner:owner_id(id, username, display_name, avatar_url)')
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

    final response = await supabase
        .from('creator_metrics')
        .select()
        .eq('creator_user_id', userId)
        .maybeSingle();

    return response ??
        {'plus_addons_count': 0, 'reward_balance': 0, 'total_earned': 0};
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
    // This securely calls your server-side function.
    // The plan code and secret key are now handled on the server.
    final response = await supabase.functions.invoke(
      // <-- This was the fix
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

      // This is the robust fix. We safely check the response.
      final responseData = response.data;

      // If the function call itself fails (status != 200) or if it returns an error object,
      // we throw a clear exception that the UI can catch.
      if (response.status != 200 ||
          (responseData is Map && responseData.containsKey('error'))) {
        final errorMsg = (responseData is Map && responseData['error'] != null)
            ? responseData['error'].toString()
            : 'An unknown verification error occurred.';
        throw Exception(errorMsg);
      }

      // If we have a 200 status and no error key, it's a success.
      return true;
    } on FunctionException catch (e) {
      // This catches errors from the Supabase client itself.
      final details = e.details;
      String errorMessage = 'Verification failed.';
      if (details is Map && details.containsKey('error')) {
        errorMessage = details['error'].toString();
      }
      throw Exception(errorMessage);
    } catch (e) {
      // A general catch-all for other errors.
      throw Exception('An unexpected error occurred: ${e.toString()}');
    }
  }

  // --- ADDED: Calls the function to cancel a subscription ---
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

  // --- ADDED: Calls the function to confirm a subscription record exists ---
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

  // --- ADDED: Calls the function to confirm the user's state is cancelled ---
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
  }) async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) throw Exception('User not logged in');

    await supabase.from('users').update({
      'display_name': displayName,
      'username': username,
      'bio': bio,
      'twitter_handle': twitterHandle,
      'avatar_url': avatarUrl,
      'usdt_wallet_address': usdtWalletAddress,
    }).eq('id', userId);
  }

  Future<List<Map<String, dynamic>>> fetchNotifications() async {
    final userId = AuthService.instance.currentUser?.id;

    // If there's no logged-in user, return an empty list.
    if (userId == null) {
      return [];
    }

    final response = await supabase
        .from('notifications')
        .select('*, actor:actor_user_id(username, avatar_url)')
        .eq('recipient_user_id',
            userId) // <-- THE FIX: Only get notifications for the current user.
        .order('created_at', ascending: false);

    return (response as List).cast<Map<String, dynamic>>();
  }

  Future<int> getUnreadNotificationsCount() async {
    final response = await supabase
        .from('notifications')
        .count(CountOption.exact)
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
        // Try to get a more specific error message from the function if it exists
        final errorMsg =
            response.data?['error'] ?? 'Failed to submit cancellation request.';
        throw Exception(errorMsg);
      }
    } catch (e) {
      // Re-throw with a more helpful message for the UI
      throw Exception(
          'Error calling request-cancellation function: ${e.toString()}');
    }
  }

  Future<bool> hasPendingCancellation() async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) return false; // If no user, no pending request.

    try {
      final response = await supabase
          .from('cancellation_requests')
          .select('id')
          .eq('user_id', userId)
          .eq('status', 'pending')
          .limit(1)
          .maybeSingle();

      // If the response is not null, a pending request was found.
      return response != null;
    } catch (e) {
      // If there's an error, log it and return false to prevent blocking the UI.
      print('Error checking for pending cancellation: $e');
      return false;
    }
  }

  // --- NEW METHODS FOR THE COMMENT FEATURE ---

// 1. Fetches all comments for a given event ID.
// --- COMMENT FEATURE: use event_comments and commenter_user_id ---

// 1. Fetch all comments for an event and attach commenter profile as `user`
  Future<List<Map<String, dynamic>>> fetchCommentsForEvent(
      String eventId) async {
    try {
      // 1) get comments
      final commentsResponse = await supabase
          .from('event_comments')
          .select()
          .eq('event_id', eventId)
          .order('created_at', ascending: true);

      final comments = (commentsResponse as List).cast<Map<String, dynamic>>();

      // 2) collect unique commenter ids
      final Set<String> userIdSet = {};
      for (final c in comments) {
        final id = c['commenter_user_id'];
        if (id != null) userIdSet.add(id.toString());
      }
      final userIds = userIdSet.toList();

      // 3) fetch user profiles in one go (if any)
      Map<String, Map<String, dynamic>> usersMap = {};
      if (userIds.isNotEmpty) {
        // IMPORTANT: for UUID columns, don't wrap ids in single quotes here.
        // Build a parenthesized list like (uuid1,uuid2,uuid3)
        final idsString = userIds.join(',');

        final usersResponse = await supabase
            .from('users')
            .select('id, username, avatar_url')
            .filter('id', 'in', '($idsString)');

        final users = (usersResponse as List).cast<Map<String, dynamic>>();
        for (final u in users) {
          usersMap[u['id'].toString()] = u;
        }
      }

      // 4) attach user data to comments and normalize field names for UI
      final enriched = comments.map((c) {
        final commenterId = c['commenter_user_id']?.toString();
        c['user'] = commenterId != null ? usersMap[commenterId] : null;
        // normalize content name expected by your UI
        c['content'] = c['text'] ?? c['content'] ?? '';
        return c;
      }).toList();

      return enriched;
    } catch (e) {
      throw Exception('Error fetching comments: $e');
    }
  }

// 2. Add a comment into event_comments (uses commenter_user_id)
  Future<void> addComment({
    required String eventId,
    required String content,
  }) async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) throw Exception('User not logged in');
    if (content.trim().isEmpty) throw Exception('Comment cannot be empty');

    try {
      await supabase.from('event_comments').insert({
        'event_id': eventId,
        'commenter_user_id': userId,
        'text': content.trim(),
      });
    } catch (e) {
      throw Exception('Error posting comment: $e');
    }
  }

// 3. Delete a specific comment from event_comments
  Future<void> deleteComment(String commentId) async {
    try {
      await supabase.from('event_comments').delete().eq('id', commentId);
    } catch (e) {
      throw Exception('Error deleting comment: $e');
    }
  }

  // Method to get a public URL for a file in Supabase Storage
  String getPublicUrl(String filePath) {
    // Assuming files are in a bucket named 'event_media' (adjust if different)
    try {
      final publicUrl =
          supabase.storage.from('event_media').getPublicUrl(filePath);
      return publicUrl;
    } catch (e) {
      print('Error getting public URL for $filePath: $e');
      throw Exception('Could not get public URL for $filePath');
    }
  }

  Future<void> requestPayout(double amount) async {
    try {
      final response = await supabase.functions.invoke(
        'request-payout',
        body: {'amount': amount},
      );
      if (response.status != 200) {
        final errorMsg =
            response.data?['error'] ?? 'Failed to submit payout request.';
        throw Exception(errorMsg);
      }
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  Future<void> initNotifications() async {
    final messaging = FirebaseMessaging.instance;

    // Request permission from the user to show notifications (required for iOS and Android 13+)
    await messaging.requestPermission();

    // Get the unique FCM token for this device
    final fcmToken = await messaging.getToken();

    // Save the token to your Supabase database
    final userId = AuthService.instance.currentUser?.id;
    if (fcmToken != null && userId != null) {
      try {
        await supabase
            .from('users')
            .update({'fcm_token': fcmToken}).eq('id', userId);
      } catch (e) {
        // It's good practice to handle potential errors,
        // but we don't want to block the user if it fails.
        debugPrint('Error saving FCM token: $e');
      }
    }
  }

  Future<List<Map<String, dynamic>>> getGroupMembers(String groupId) async {
    final response = await supabase
        .from('group_members')
        .select('users(*)') // This joins and fetches the full user profile
        .eq('group_id', groupId);

    // The result is a list of objects like [{ "users": { ... } }].
    // We need to extract just the user data.
    return (response as List)
        .map((row) => row['users'] as Map<String, dynamic>)
        .toList();
  }

  // In lib/shared/services/supabase_service.dart

  Future<List<Map<String, dynamic>>> findSubscribers(String searchText) async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) return [];

    // Step 1: Get all IDs of users who subscribe to you
    final subsResponse = await supabase
        .from('timetable_subscriptions')
        .select('subscriber_id')
        .eq('owner_id', userId);

    final subscriberIds = (subsResponse as List)
        .map((row) => row['subscriber_id'] as String)
        .toList();

    if (subscriberIds.isEmpty) return [];

    // Step 2: Search for users within that list of IDs by username
    // THIS IS THE CORRECTED QUERY SYNTAX
    final usersResponse = await supabase
        .from('users')
        .select()
        .filter(
            'id', 'in', subscriberIds) // Use .filter() for the 'in' operator
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

    // Step 1: Get all IDs of users who subscribe to you
    final subsResponse = await supabase
        .from('timetable_subscriptions')
        .select('subscriber_id')
        .eq('owner_id', userId);
    final subscriberIds = (subsResponse as List)
        .map((row) => row['subscriber_id'] as String)
        .toList();

    if (subscriberIds.isEmpty) return [];

    // Step 2: Get all IDs of users who are already in the group
    final membersResponse = await supabase
        .from('group_members')
        .select('user_id')
        .eq('group_id', groupId);
    final memberIds = (membersResponse as List)
        .map((row) => row['user_id'] as String)
        .toList();

    // Step 3: Find the subscribers who are not already members
    final addableIds =
        subscriberIds.where((id) => !memberIds.contains(id)).toList();

    if (addableIds.isEmpty) return [];

    // Step 4: Fetch the profiles for the addable subscribers
    final usersResponse = await supabase
        .from('users')
        .select('id, username, avatar_url')
        .filter('id', 'in', addableIds); // <-- THE CORRECTED LINE

    return (usersResponse as List).cast<Map<String, dynamic>>();
  }

  Future<void> sendEventReminder(String eventId) async {
    await supabase.rpc(
      'send_event_reminder',
      params: {'event_id_to_remind': eventId},
    );
  }
}
