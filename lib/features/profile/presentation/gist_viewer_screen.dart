// lib/features/profile/presentation/gist_viewer_screen.dart

import 'dart:async';
import 'package:class_rep/shared/services/supabase_service.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:class_rep/shared/services/auth_service.dart';

const Color darkSuedeNavy = Color(0xFF1A1B2C);

class GistViewerScreen extends StatefulWidget {
  final String userId;
  final String username;
  final String avatarUrl;

  const GistViewerScreen({
    required this.userId,
    required this.username,
    required this.avatarUrl,
    super.key,
  });

  @override
  State<GistViewerScreen> createState() => _GistViewerScreenState();
}

class _GistViewerScreenState extends State<GistViewerScreen>
    with TickerProviderStateMixin {
  late Future<List<Map<String, dynamic>>> _gistsFuture;
  PageController? _pageController;
  AnimationController? _animationController;
  VideoPlayerController? _videoController;
  int _currentIndex = 0;
  final _replyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _gistsFuture = SupabaseService.instance.getGistsForUser(widget.userId);
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController?.dispose();
    _animationController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  void _onPageChanged(int index, List<Map<String, dynamic>> gists) {
    setState(() {
      _currentIndex = index;
    });
    _loadGist(gists[index]);
  }

  void _loadGist(Map<String, dynamic> gist) {
    _animationController?.dispose();
    _videoController?.dispose();
    _videoController = null;

    final type = gist['type'];
    final duration = type == 'video'
        ? const Duration(seconds: 30)
        : const Duration(seconds: 5);

    _animationController = AnimationController(vsync: this, duration: duration);
    _animationController!.forward(from: 0);
    _animationController!.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _nextGist();
      }
    });

    if (type == 'video') {
      _videoController =
          VideoPlayerController.networkUrl(Uri.parse(gist['media_url']))
            ..initialize().then((_) {
              setState(() {});
              if (_currentIndex == _pageController!.page?.round()) {
                _videoController!.play();
                _animationController!.duration = _videoController!
                    .value.duration; // Use actual video duration
                _animationController!.forward(from: 0);
              }
            });
    }
  }

  void _nextGist() {
    final gistsCount = _gistsFuture.then((gists) => gists.length);
    gistsCount.then((count) {
      if (_currentIndex + 1 < count) {
        _pageController!.nextPage(
            duration: const Duration(milliseconds: 300), curve: Curves.ease);
      } else {
        Navigator.of(context).pop();
      }
    });
  }

  void _previousGist() {
    if (_currentIndex - 1 >= 0) {
      _pageController!.previousPage(
          duration: const Duration(milliseconds: 300), curve: Curves.ease);
    } else {
      Navigator.of(context).pop();
    }
  }

  void _onTapDown(TapDownDetails details, int gistsCount) {
    _animationController?.stop();
    _videoController?.pause();
    final double screenWidth = MediaQuery.of(context).size.width;
    if (details.globalPosition.dx < screenWidth / 3) {
      _previousGist();
    } else if (details.globalPosition.dx > screenWidth * 2 / 3) {
      _nextGist();
    }
  }

  Future<void> _sendReply() async {
    final content = _replyController.text.trim();
    if (content.isEmpty) return;

    _replyController.clear();
    FocusScope.of(context).unfocus(); // Dismiss keyboard

    try {
      // Get or create a DM conversation with the Gist owner
      final conversationId =
          await SupabaseService.instance.createOrGetConversation(widget.userId);
      // Send the reply as a direct message
      await SupabaseService.instance
          .sendMessage(conversationId: conversationId, content: content);

      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Reply sent!'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Error sending reply.'),
            backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _gistsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            Navigator.of(context).pop();
            return const SizedBox.shrink();
          }
          final gists = snapshot.data!;
          if (_animationController == null) {
            _loadGist(gists.first);
          }

          return GestureDetector(
            onTapDown: (details) => _onTapDown(details, gists.length),
            onLongPress: () {
              _animationController?.stop();
              _videoController?.pause();
            },
            onLongPressUp: () {
              _animationController?.forward();
              _videoController?.play();
            },
            child: Stack(
              children: [
                PageView.builder(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: gists.length,
                  onPageChanged: (index) => _onPageChanged(index, gists),
                  itemBuilder: (context, index) {
                    final gist = gists[index];
                    final type = gist['type'];
                    if (type == 'image') {
                      return Image.network(gist['media_url'],
                          fit: BoxFit.fitWidth);
                    }
                    if (type == 'video' &&
                        _videoController != null &&
                        _videoController!.value.isInitialized &&
                        index == _currentIndex) {
                      return Center(
                        child: AspectRatio(
                          aspectRatio: _videoController!.value.aspectRatio,
                          child: VideoPlayer(_videoController!),
                        ),
                      );
                    }
                    if (type == 'text') {
                      return Container(
                        color: Colors.primaries[
                            (gist['content'] as String).length %
                                Colors.primaries.length],
                        padding: const EdgeInsets.all(24),
                        alignment: Alignment.center,
                        child: Text(gist['content'],
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold)),
                      );
                    }
                    return const Center(child: CircularProgressIndicator());
                  },
                ),
                Positioned(
                  top: 50, // Adjusted for safe area
                  left: 8,
                  right: 8,
                  child: Column(
                    children: [
                      Row(
                        children: List.generate(gists.length, (index) {
                          return Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 2.0),
                              child: AnimatedBuilder(
                                animation: _animationController!,
                                builder: (context, child) {
                                  return LinearProgressIndicator(
                                    value: (index == _currentIndex)
                                        ? _animationController!.value
                                        : (index < _currentIndex ? 1.0 : 0.0),
                                    backgroundColor: Colors.white38,
                                    valueColor:
                                        const AlwaysStoppedAnimation<Color>(
                                            Colors.white),
                                    minHeight: 2.5,
                                  );
                                },
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          CircleAvatar(
                              radius: 18,
                              backgroundImage: NetworkImage(widget.avatarUrl)),
                          const SizedBox(width: 8),
                          Text(widget.username,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  shadows: [Shadow(blurRadius: 3)])),
                          const Spacer(),
                          IconButton(
                              icon: const Icon(Icons.close,
                                  color: Colors.white,
                                  shadows: [Shadow(blurRadius: 3)]),
                              onPressed: () => Navigator.of(context).pop()),
                        ],
                      ),
                    ],
                  ),
                ),
                // THIS IS THE CORRECTED LINE
                if (widget.userId != AuthService.instance.currentUser?.id)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      child: Container(
                        padding: EdgeInsets.only(
                            left: 16,
                            right: 8,
                            top: 8,
                            bottom:
                                8 + MediaQuery.of(context).viewInsets.bottom),
                        child: TextField(
                          controller: _replyController,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _sendReply(),
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Send a message...',
                            hintStyle: const TextStyle(color: Colors.white70),
                            filled: true,
                            fillColor: Colors.black.withOpacity(0.5),
                            contentPadding: const EdgeInsets.symmetric(
                                vertical: 10, horizontal: 20),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: const BorderSide(color: Colors.white),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: const BorderSide(
                                  color: Colors.white, width: 2),
                            ),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.send, color: Colors.white),
                              onPressed: _sendReply,
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
              ],
            ),
          );
        },
      ),
    );
  }
}
