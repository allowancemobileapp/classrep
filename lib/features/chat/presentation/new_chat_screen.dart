// lib/features/chat/presentation/new_chat_screen.dart

import 'dart:async';
import 'package:class_rep/features/chat/presentation/chat_screen.dart';
import 'package:class_rep/shared/services/supabase_service.dart';
import 'package:class_rep/shared/widgets/glass_container.dart';
import 'package:flutter/material.dart';

const Color darkSuedeNavy = Color(0xFF1A1B2C);
const Color lightSuedeNavy = Color(0xFF2A2C40);

class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _suggestedUsers = [];
  Timer? _debounce;
  bool _isLoadingSuggestions = true;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadSuggestions();
  }

  Future<void> _loadSuggestions() async {
    setState(() => _isLoadingSuggestions = true);
    try {
      final results = await SupabaseService.instance.getSuggestedUsers();
      if (mounted) {
        setState(() {
          _suggestedUsers = results;
          _isLoadingSuggestions = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingSuggestions = false);
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch();
    });
  }

  Future<void> _performSearch() async {
    if (_searchController.text.trim().isEmpty) {
      if (mounted) setState(() => _searchResults = []);
      return;
    }
    setState(() => _isSearching = true);
    try {
      final results =
          await SupabaseService.instance.searchAllUsers(_searchController.text);
      if (mounted) {
        setState(() => _searchResults = results);
      }
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _startChatWithUser(Map<String, dynamic> user) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final conversationId =
          await SupabaseService.instance.createOrGetConversation(user['id']);
      if (!mounted) return;

      Navigator.of(context).pop();
      Navigator.of(context)
          .pop(true); // Pop this screen and signal that a new chat was started.

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ChatScreen(
            conversationId: conversationId,
            chatTitle: user['username'] ?? 'Chat',
            otherParticipantId: user['id'],
            otherParticipantUsername: user['username'],
            otherParticipantAvatarUrl: user['avatar_url'],
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error starting chat: ${e.toString()}'),
            backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool showSuggestions = _searchController.text.trim().isEmpty;

    return Scaffold(
      backgroundColor: darkSuedeNavy,
      appBar: AppBar(
        backgroundColor: darkSuedeNavy,
        title: const Text('Start New Chat'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search by username...',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white70),
                filled: true,
                fillColor: lightSuedeNavy,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: showSuggestions
                ? _buildSuggestionsList()
                : _buildSearchResultsList(),
          ),
        ],
      ),
    );
  }

  // UPDATED: This now builds a GridView of cards
  Widget _buildSuggestionsList() {
    if (_isLoadingSuggestions) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_suggestedUsers.isEmpty) {
      return const Center(
          child: Text('No users to suggest.',
              style: TextStyle(color: Colors.white70)));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0),
          child: Text('Suggestions',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 0.8,
            ),
            itemCount: _suggestedUsers.length,
            itemBuilder: (context, index) {
              final user = _suggestedUsers[index];
              return _SuggestedUserCard(
                userProfile: user,
                onTap: () => _startChatWithUser(user),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSearchResultsList() {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_searchResults.isEmpty) {
      return const Center(
          child:
              Text('No users found.', style: TextStyle(color: Colors.white70)));
    }
    return ListView.builder(
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final user = _searchResults[index];
        final avatarUrl = user['avatar_url'] as String?;
        final username = user['username'] ?? '...';
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: lightSuedeNavy,
            backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
            child: avatarUrl == null
                ? Text(username.isNotEmpty ? username[0].toUpperCase() : '?')
                : null,
          ),
          title: Text(username, style: const TextStyle(color: Colors.white)),
          onTap: () => _startChatWithUser(user),
        );
      },
    );
  }
}

// --- NEW WIDGET FOR DISPLAYING SUGGESTED USER CARDS ---
class _SuggestedUserCard extends StatelessWidget {
  final Map<String, dynamic> userProfile;
  final VoidCallback onTap;

  const _SuggestedUserCard({required this.userProfile, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final avatarUrl = userProfile['avatar_url'] as String?;
    final displayName = userProfile['display_name'] as String? ?? 'No Name';
    final username = userProfile['username'] as String? ?? '...';
    final bio = userProfile['bio'] as String?;

    return GestureDetector(
      onTap: onTap,
      child: GlassContainer(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 35,
              backgroundColor: darkSuedeNavy,
              backgroundImage:
                  avatarUrl != null ? NetworkImage(avatarUrl) : null,
              child: avatarUrl == null
                  ? Text(
                      displayName.isNotEmpty
                          ? displayName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(fontSize: 30, color: Colors.white),
                    )
                  : null,
            ),
            const SizedBox(height: 12),
            Text(
              displayName,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16),
            ),
            Text(
              '@$username',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            if (bio != null && bio.isNotEmpty)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    bio,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.8), fontSize: 12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
