// lib/shared/widgets/gist_avatar.dart

import 'package:flutter/material.dart';

const Color lightSuedeNavy = Color(0xFF2A2C40);

class GistAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String fallbackText;
  final bool hasActiveGist;
  final double radius;

  const GistAvatar({
    this.avatarUrl,
    required this.fallbackText,
    this.hasActiveGist = false,
    this.radius = 50,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    // The ring is a Container with a gradient border, placed behind the avatar
    return Container(
      padding: const EdgeInsets.all(3.0), // This creates the space for the ring
      decoration: BoxDecoration(
        gradient: hasActiveGist
            ? const LinearGradient(
                colors: [Colors.greenAccent, Colors.cyanAccent])
            : null,
        shape: BoxShape.circle,
      ),
      child: CircleAvatar(
        radius: radius,
        backgroundColor: lightSuedeNavy,
        backgroundImage: (avatarUrl != null && avatarUrl!.isNotEmpty)
            ? NetworkImage(avatarUrl!)
            : null,
        child: (avatarUrl == null || avatarUrl!.isEmpty)
            ? Text(
                fallbackText,
                style: TextStyle(fontSize: radius * 0.8, color: Colors.white),
              )
            : null,
      ),
    );
  }
}
