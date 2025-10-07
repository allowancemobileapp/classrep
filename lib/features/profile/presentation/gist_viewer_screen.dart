// lib/features/profile/presentation/gist_viewer_screen.dart

import 'dart:async';
import 'package:class_rep/shared/services/supabase_service.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; // Import for PostgrestException
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

  // State variables for subscription
  String? _currentUserId;
  bool? _isSubscribed;
  bool _isProcessingSubscription = false;

  @override
  void initState() {
    super.initState();
    _gistsFuture = SupabaseService.instance.getGistsForUser(widget.userId);
    _pageController = PageController();
    _currentUserId = AuthService.instance.currentUser?.id;

    // Check subscription status only if viewing someone else's gist
    if (widget.userId != _currentUserId) {
      _checkSubscriptionStatus();
    }
  }

  @override
  void dispose() {
    _pageController?.dispose();
    _animationController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _checkSubscriptionStatus() async {
    try {
      final status =
          await SupabaseService.instance.isSubscribedTo(widget.userId);
      if (mounted) {
        setState(() => _isSubscribed = status);
      }
    } catch (e) {
      // Fail silently, the button just won't appear
    }
  }

  Future<void> _handleSubscriptionToggle() async {
    if (_isProcessingSubscription || _isSubscribed == null) return;
    setState(() => _isProcessingSubscription = true);

    try {
      if (_isSubscribed!) {
        await SupabaseService.instance.unsubscribeFromTimetable(widget.userId);
        if (mounted) setState(() => _isSubscribed = false);
      } else {
        await SupabaseService.instance.subscribeToTimetable(widget.username);
        if (mounted) setState(() => _isSubscribed = true);
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.redAccent),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.toString()), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessingSubscription = false);
    }
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
              if (mounted) {
                setState(() {});
                if (_currentIndex == _pageController!.page?.round()) {
                  _videoController!.play();
                  _animationController!.duration =
                      _videoController!.value.duration;
                  _animationController!.forward(from: 0);
                }
              }
            });
    }
  }

  void _nextGist() {
    _gistsFuture.then((gists) {
      if (_currentIndex + 1 < gists.length) {
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
    final double tapPosition = details.globalPosition.dx;

    if (tapPosition < screenWidth / 3) {
      _previousGist();
    } else if (tapPosition > screenWidth * 2 / 3) {
      _nextGist();
    }
    // If tapped in the middle, we just pause. The long press up will resume.
  }

  Future<void> _sendReply() async {
    final content = _replyController.text.trim();
    if (content.isEmpty) return;

    // --- THIS IS THE NEW LOGIC ---
    // Get the details of the specific gist being viewed
    final gists = await _gistsFuture;
    final currentGist = gists[_currentIndex];
    final gistType = currentGist['type'];
    String gistReference;

    if (gistType == 'text') {
      gistReference =
          '"${(currentGist['content'] as String).substring(0, (currentGist['content'] as String).length > 20 ? 20 : (currentGist['content'] as String).length)}..."';
    } else {
      gistReference = "your ${gistType} Gist";
    }

    final finalMessage = "[Replying to ${gistReference}]: $content";
    // --- END OF NEW LOGIC ---

    _replyController.clear();
    FocusScope.of(context).unfocus(); // Dismiss keyboard

    try {
      // Get or create a DM conversation with the Gist owner
      final conversationId =
          await SupabaseService.instance.createOrGetConversation(widget.userId);
      // Send the reply as a direct message WITH the new context
      await SupabaseService.instance
          .sendMessage(conversationId: conversationId, content: finalMessage);

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
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                Navigator.of(context).pop();
              }
            });
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
                  top: 50,
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
                          const SizedBox(width: 12),
                          if (widget.userId != _currentUserId &&
                              _isSubscribed != null)
                            _isProcessingSubscription
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : TextButton(
                                    onPressed: _handleSubscriptionToggle,
                                    style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        minimumSize: const Size(50, 30),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        alignment: Alignment.centerLeft),
                                    child: Text(
                                      _isSubscribed!
                                          ? '• Subscribed'
                                          : '+ Subscribe',
                                      style: TextStyle(
                                          color: _isSubscribed!
                                              ? Colors.grey
                                              : Colors.cyanAccent,
                                          fontWeight: FontWeight.bold,
                                          shadows: const [
                                            Shadow(blurRadius: 3)
                                          ]),
                                    ),
                                  ),
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
