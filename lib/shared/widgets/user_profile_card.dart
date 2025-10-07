// lib/shared/widgets/user_profile_card.dart

// --- THIS IS THE FIX: ADD THIS IMPORT ---
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:class_rep/shared/services/auth_service.dart';
import 'package:class_rep/shared/services/supabase_service.dart';
import 'package:class_rep/shared/widgets/glass_container.dart';
import 'package:flutter/material.dart';

const Color lightSuedeNavy = Color(0xFF2A2C40);

class UserProfileCard extends StatefulWidget {
  final Map<String, dynamic> userProfile;

  const UserProfileCard({required this.userProfile, super.key});

  @override
  State<UserProfileCard> createState() => _UserProfileCardState();
}

class _UserProfileCardState extends State<UserProfileCard> {
  bool? _isSubscribed;
  bool _isLoading = true;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _checkSubscriptionStatus();
  }

  Future<void> _checkSubscriptionStatus() async {
    setState(() => _isLoading = true);
    try {
      final status = await SupabaseService.instance
          .isSubscribedTo(widget.userProfile['id']);
      if (mounted) {
        setState(() {
          _isSubscribed = status;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSubscriptionToggle() async {
    if (_isProcessing || _isSubscribed == null) return;
    setState(() => _isProcessing = true);

    try {
      if (_isSubscribed!) {
        // Unsubscribe logic
        await SupabaseService.instance
            .unsubscribeFromTimetable(widget.userProfile['id']);
        if (mounted) setState(() => _isSubscribed = false);
      } else {
        // Subscribe logic
        await SupabaseService.instance
            .subscribeToTimetable(widget.userProfile['username']);
        if (mounted) setState(() => _isSubscribed = true);
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatarUrl = widget.userProfile['avatar_url'] as String?;
    final displayName =
        widget.userProfile['display_name'] as String? ?? 'No Name';
    final username = widget.userProfile['username'] as String? ?? '...';
    final bio = widget.userProfile['bio'] as String?;
    final isCurrentUser =
        widget.userProfile['id'] == AuthService.instance.currentUser?.id;

    return GlassContainer(
      borderRadius: 20,
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: lightSuedeNavy,
            backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
            child: avatarUrl == null
                ? Text(
                    displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                    style: const TextStyle(fontSize: 40, color: Colors.white),
                  )
                : null,
          ),
          const SizedBox(height: 16),
          Text(
            displayName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '@$username',
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
          if (bio != null && bio.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                bio,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
          if (!isCurrentUser)
            Padding(
              padding: const EdgeInsets.only(top: 24.0),
              child: _isLoading || _isSubscribed == null
                  ? const SizedBox(
                      height: 36,
                      child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2)))
                  : _isSubscribed!
                      ? OutlinedButton.icon(
                          icon: const Icon(Icons.check),
                          label: const Text('Subscribed'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.grey,
                            side: const BorderSide(color: Colors.grey),
                          ),
                          onPressed:
                              _isProcessing ? null : _handleSubscriptionToggle,
                        )
                      : ElevatedButton.icon(
                          icon: const Icon(Icons.add),
                          label: const Text('Subscribe'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.cyanAccent,
                            foregroundColor: Colors.black,
                          ),
                          onPressed:
                              _isProcessing ? null : _handleSubscriptionToggle,
                        ),
            ),
        ],
      ),
    );
  }
}
