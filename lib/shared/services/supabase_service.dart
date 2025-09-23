// lib/shared/services/supabase_service.dart

import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:class_rep/shared/services/auth_service.dart';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

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

  Future<Map<String, dynamic>> getPaystackCheckoutUrl(String email) async {
    final secretKey = dotenv.env['PAYSTACK_SECRET_KEY'];
    final planCode = dotenv.env['PAYSTACK_PLAN_CODE'];

    if (secretKey == null || planCode == null) {
      throw Exception('Paystack keys or plan code not found in .env file.');
    }

    final url = Uri.parse('https://api.paystack.co/transaction/initialize');

    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $secretKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'email': email,
        'amount': 500 * 100,
        'plan': planCode,
      }),
    );

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      return {
        'authorization_url': body['data']['authorization_url'],
        'reference': body['data']['reference'],
      };
    } else {
      throw Exception(
          'Failed to initialize Paystack transaction: ${response.body}');
    }
  }

  Future<bool> verifyPayment(String reference) async {
    try {
      final response = await supabase.functions.invoke(
        'verify-paystack-payment',
        body: {'reference': reference},
      );
      if (response.data['status'] == 'success') {
        return true;
      } else {
        throw Exception(response.data['error'] ?? 'Verification failed.');
      }
    } catch (e) {
      throw Exception('Error calling verification function: $e');
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
    final response = await supabase
        .from('notifications')
        .select('*, actor:actor_user_id(username, avatar_url)')
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
}
