// lib/features/chat/presentation/chat_screen.dart

import 'dart:async';
import 'package:class_rep/features/chat/presentation/group_details_screen.dart';
import 'package:class_rep/shared/services/auth_service.dart';
import 'package:class_rep/shared/services/supabase_service.dart';
import 'package:class_rep/shared/widgets/user_profile_card.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'package:class_rep/features/chat/presentation/image_viewer_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

const Color darkSuedeNavy = Color(0xFF1A1B2C);
const Color lightSuedeNavy = Color(0xFF2A2C40);

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String chatTitle;
  final bool isGroup;
  final String? otherParticipantId;
  final String? otherParticipantUsername;
  final String? otherParticipantAvatarUrl;

  const ChatScreen({
    required this.conversationId,
    required this.chatTitle,
    this.isGroup = false,
    this.otherParticipantId,
    this.otherParticipantUsername,
    this.otherParticipantAvatarUrl,
    super.key,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  String? _currentUserId;
  bool? _isSubscribed;
  bool _isSubscribing = false;
  bool _didUpdateOccur = false; // Used for both subscriptions and unread counts

  RealtimeChannel? _messageSubscription;

  @override
  void initState() {
    super.initState();
    _currentUserId = AuthService.instance.currentUser?.id;
    _fetchInitialMessages();
    _setupSubscription();
    _checkSubscriptionStatus();
    _resetUnreadCount(); // --- CHANGE 1: RESET COUNT ON SCREEN ENTRY ---
  }

  // --- CHANGE 2: NEW METHOD TO RESET COUNT ---
  Future<void> _resetUnreadCount() async {
    try {
      await SupabaseService.instance.resetUnreadCount(widget.conversationId);
      _didUpdateOccur = true; // Mark that an update happened
    } catch (e) {
      // Fail silently, as it's not a critical error for the user
      debugPrint("Error resetting unread count: $e");
    }
  }

  @override
  void dispose() {
    if (_messageSubscription != null) {
      supabase.removeChannel(_messageSubscription!);
    }
    _messageController.dispose();
    super.dispose();
  }

  // ... (All other methods like _showAttachmentMenu, _sendMessage, etc. remain the same)
  // ... (No changes needed for the rest of this file)

  Future<void> _showAttachmentMenu() {
    return showModalBottomSheet(
      context: context,
      backgroundColor: lightSuedeNavy,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.image, color: Colors.white70),
                title:
                    const Text('Image', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.of(context).pop();
                  _handleFileUpload(AttachmentSource.image);
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.insert_drive_file, color: Colors.white70),
                title:
                    const Text('File', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.of(context).pop();
                  _handleFileUpload(AttachmentSource.file);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleFileUpload(AttachmentSource source) async {
    List<int>? fileBytes;
    String? fileName;
    String attachmentType = 'file'; // Default to file
    const maxSizeInBytes = 45 * 1024 * 1024; // 45MB

    if (source == AttachmentSource.image) {
      final picker = ImagePicker();
      final imageFile =
          await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (imageFile == null) return;
      fileBytes = await imageFile.readAsBytes();
      fileName = imageFile.name;
      attachmentType = 'image';
    } else {
      final result = await FilePicker.platform.pickFiles();
      if (result == null || result.files.single.path == null) return;
      final file = File(result.files.single.path!);
      fileBytes = await file.readAsBytes();
      fileName = result.files.single.name;
    }

    if (fileBytes.length > maxSizeInBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('File is too large. Max size is 45MB.'),
              backgroundColor: Colors.red),
        );
      }
      return;
    }

    final tempMessageId = DateTime.now().millisecondsSinceEpoch.toString();
    if (mounted)
      setState(() => _messages.insert(0,
          {'id': tempMessageId, 'is_temp': true, 'user_id': _currentUserId}));

    try {
      await SupabaseService.instance.uploadChatAttachment(
        conversationId: widget.conversationId,
        filePath: fileName,
        fileName: fileName,
        fileBytes: fileBytes,
        attachmentType: attachmentType,
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().split(': ').last),
            backgroundColor: Colors.red));
    } finally {
      if (mounted)
        setState(
            () => _messages.removeWhere((msg) => msg['id'] == tempMessageId));
    }
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;
    _messageController.clear();
    try {
      await SupabaseService.instance.sendMessage(
        conversationId: widget.conversationId,
        content: content,
      );
    } catch (e) {
      // Handle error if needed
    }
  }

  Future<void> _showUserProfile(String userId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final profile = await SupabaseService.instance.fetchUserProfile(userId);
      if (!mounted) return;
      Navigator.of(context).pop();
      showDialog(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          child: UserProfileCard(userProfile: profile),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Could not load profile: ${e.toString()}'),
            backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _checkSubscriptionStatus() async {
    if (widget.otherParticipantId == null) return;
    final status = await SupabaseService.instance
        .isSubscribedTo(widget.otherParticipantId!);
    if (mounted) setState(() => _isSubscribed = status);
  }

  Future<void> _handleSubscribe() async {
    if (_isSubscribing || widget.otherParticipantUsername == null) return;
    setState(() => _isSubscribing = true);
    try {
      await SupabaseService.instance
          .subscribeToTimetable(widget.otherParticipantUsername!);
      if (mounted)
        setState(() {
          _isSubscribed = true;
          _didUpdateOccur = true;
        });
    } finally {
      if (mounted) setState(() => _isSubscribing = false);
    }
  }

  Future<void> _handleUnsubscribe() async {
    if (_isSubscribing || widget.otherParticipantId == null) return;
    setState(() => _isSubscribing = true);
    try {
      await SupabaseService.instance
          .unsubscribeFromTimetable(widget.otherParticipantId!);
      if (mounted)
        setState(() {
          _isSubscribed = false;
          _didUpdateOccur = true;
        });
    } finally {
      if (mounted) setState(() => _isSubscribing = false);
    }
  }

  Future<void> _fetchInitialMessages() async {
    try {
      final messages =
          await SupabaseService.instance.getMessages(widget.conversationId);
      if (mounted) {
        setState(() {
          _messages.addAll(messages.reversed.toList());
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _setupSubscription() {
    _messageSubscription = SupabaseService.instance.subscribeToMessages(
      widget.conversationId,
      (newMessage) {
        if (mounted) {
          if (!_messages.any((msg) => msg['id'] == newMessage['id'])) {
            setState(() {
              _messages.insert(0, newMessage);
            });
          }
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // --- CHANGE 3: USE POPSCOPE TO PASS RESULT BACK ---
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        Navigator.of(context)
            .pop(_didUpdateOccur); // Pass back true if an update happened
      },
      child: Scaffold(
        backgroundColor: darkSuedeNavy,
        appBar: AppBar(
          backgroundColor: lightSuedeNavy,
          title: GestureDetector(
            onTap: () {
              if (widget.isGroup) {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => GroupDetailsScreen(
                        conversationId: widget.conversationId,
                        groupName: widget.chatTitle)));
              } else if (widget.otherParticipantId != null) {
                _showUserProfile(widget.otherParticipantId!);
              }
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: darkSuedeNavy,
                  backgroundImage: (widget.otherParticipantAvatarUrl != null &&
                          widget.otherParticipantAvatarUrl!.isNotEmpty)
                      ? NetworkImage(widget.otherParticipantAvatarUrl!)
                      : null,
                  child: (widget.otherParticipantAvatarUrl == null ||
                          widget.otherParticipantAvatarUrl!.isEmpty)
                      ? Text(widget.chatTitle.isNotEmpty
                          ? widget.chatTitle[0].toUpperCase()
                          : '?')
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(widget.chatTitle,
                        overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
          actions: [
            if (widget.otherParticipantId != null && _isSubscribed != null)
              _isSubscribing
                  ? const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white)))
                  : IconButton(
                      tooltip: _isSubscribed!
                          ? 'Unsubscribe from timetable'
                          : 'Subscribe to timetable',
                      icon: Icon(
                          _isSubscribed!
                              ? Icons.remove_circle
                              : Icons.add_circle_outline,
                          color: Colors.white),
                      onPressed: _isSubscribed!
                          ? _handleUnsubscribe
                          : _handleSubscribe,
                    ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                      ? const Center(
                          child: Text('Say hello!',
                              style: TextStyle(color: Colors.white70)))
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          reverse: true,
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final message = _messages[index];
                            final isMine = message['user_id'] == _currentUserId;
                            return _MessageBubble(
                                message: message, isMine: isMine);
                          },
                        ),
            ),
            _buildMessageInput(),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(8.0),
        color: lightSuedeNavy.withOpacity(0.5),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.add, color: Colors.cyanAccent),
              onPressed: _showAttachmentMenu,
            ),
            Expanded(
              child: TextField(
                controller: _messageController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.1),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                onSubmitted: (_) => _sendMessage(),
                textInputAction: TextInputAction.send,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send, color: Colors.cyanAccent),
              onPressed: _sendMessage,
            ),
          ],
        ),
      ),
    );
  }
}

// ... (_MessageBubble and AttachmentSource remain the same)
enum AttachmentSource { image, file }

class _MessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool isMine;
  const _MessageBubble({required this.message, required this.isMine});

  @override
  Widget build(BuildContext context) {
    final author = message['author'] as Map<String, dynamic>?;
    final authorName = author?['username'] ?? '...';
    final attachmentUrl = message['attachment_url'] as String?;
    final attachmentType = message['attachment_type'] as String?;
    final fileName = message['file_name'] as String?;
    final content = message['content'] as String?;

    if (message['is_temp'] == true) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: Colors.cyanAccent.withOpacity(0.5),
              borderRadius: BorderRadius.circular(16)),
          child: const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(color: Colors.black)),
        ),
      );
    }

    Widget attachmentWidget;
    if (attachmentUrl != null && attachmentType == 'image') {
      attachmentWidget = GestureDetector(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ImageViewerScreen(imageUrl: attachmentUrl))),
        child: Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.6,
                maxHeight: 250),
            child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(attachmentUrl, fit: BoxFit.cover)),
          ),
        ),
      );
    } else if (attachmentUrl != null && attachmentType == 'file') {
      attachmentWidget = GestureDetector(
        onTap: () async {
          final url = Uri.parse(attachmentUrl);
          if (await canLaunchUrl(url)) {
            await launchUrl(url, mode: LaunchMode.externalApplication);
          }
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: (isMine ? Colors.black : Colors.white).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.insert_drive_file,
                  color: isMine ? Colors.black : Colors.white, size: 30),
              const SizedBox(width: 8),
              Flexible(
                  child: Text(fileName ?? 'File',
                      style: TextStyle(
                          color: isMine ? Colors.black : Colors.white))),
            ],
          ),
        ),
      );
    } else {
      attachmentWidget = const SizedBox.shrink();
    }

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
            color: isMine ? Colors.cyanAccent : lightSuedeNavy,
            borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment:
              isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isMine)
              Text('@$authorName',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white70,
                      fontSize: 12)),
            if (!isMine) const SizedBox(height: 4),
            attachmentWidget,
            if (content != null && content.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: attachmentUrl != null ? 4.0 : 0),
                child: Text(content,
                    style:
                        TextStyle(color: isMine ? Colors.black : Colors.white)),
              ),
          ],
        ),
      ),
    );
  }
}
