// lib/shared/widgets/user_profile_card.dart

import 'package:class_rep/shared/widgets/glass_container.dart';
import 'package:flutter/material.dart';

const Color lightSuedeNavy = Color(0xFF2A2C40);

class UserProfileCard extends StatelessWidget {
  final Map<String, dynamic> userProfile;

  const UserProfileCard({required this.userProfile, super.key});

  @override
  Widget build(BuildContext context) {
    final avatarUrl = userProfile['avatar_url'] as String?;
    final displayName = userProfile['display_name'] as String? ?? 'No Name';
    final username = userProfile['username'] as String? ?? '...';
    final bio = userProfile['bio'] as String?;

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
        ],
      ),
    );
  }
}
