// lib/features/chat/presentation/chat_screen.dart

import 'dart:async';
import 'dart:io';
import 'package:class_rep/features/chat/presentation/group_details_screen.dart';
import 'package:class_rep/features/chat/presentation/image_viewer_screen.dart';
import 'package:class_rep/shared/services/auth_service.dart';
import 'package:class_rep/shared/services/supabase_service.dart';
import 'package:class_rep/shared/widgets/user_profile_card.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  bool _didUpdateOccur = false;
  RealtimeChannel? _messageSubscription;

  @override
  void initState() {
    super.initState();
    print(">>> CHAT SCREEN: initState()");
    _currentUserId = AuthService.instance.currentUser?.id;
    _fetchInitialMessages();
    _setupSubscription();
    _checkSubscriptionStatus();
    _markAsRead();
  }

  @override
  void dispose() {
    print(">>> CHAT SCREEN: dispose()");
    if (_messageSubscription != null) {
      supabase.removeChannel(_messageSubscription!);
    }
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _markAsRead() async {
    print(">>> CHAT SCREEN: Attempting to mark messages as read...");
    try {
      await SupabaseService.instance.markMessagesAsRead(widget.conversationId);
      print(
          ">>> CHAT SCREEN: Successfully called the reset function in database.");
      _didUpdateOccur = true;
    } catch (e) {
      print(">>> CHAT SCREEN: ERROR marking messages as read: $e");
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
    _messageSubscription = supabase
        .channel(
            'public:chat_messages:conversation_id=eq.${widget.conversationId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chat_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: widget.conversationId,
          ),
          callback: (payload) async {
            final eventType = payload.eventType;
            if (eventType == PostgresChangeEvent.insert) {
              final newMessage = payload.newRecord;
              if (mounted &&
                  !_messages.any((msg) => msg['id'] == newMessage['id'])) {
                if (newMessage['user_id'] != _currentUserId) {
                  _markAsRead();
                }
                final authorProfile = await SupabaseService.instance
                    .fetchUserProfile(newMessage['user_id']);
                newMessage['author'] = authorProfile;
                if (mounted) setState(() => _messages.insert(0, newMessage));
              }
            } else if (eventType == PostgresChangeEvent.update) {
              final updatedMessage = payload.newRecord;
              final index = _messages
                  .indexWhere((msg) => msg['id'] == updatedMessage['id']);
              if (index != -1 && mounted) {
                final author = _messages[index]['author'];
                setState(() {
                  _messages[index] = updatedMessage;
                  _messages[index]['author'] = author;
                });
              }
            }
          },
        )
        .subscribe();
  }

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
    String attachmentType = 'file';
    const maxSizeInBytes = 45 * 1024 * 1024;

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
    if (mounted) {
      setState(() => _messages.insert(0,
          {'id': tempMessageId, 'is_temp': true, 'user_id': _currentUserId}));
    }

    try {
      await SupabaseService.instance.uploadChatAttachment(
        conversationId: widget.conversationId,
        filePath: fileName,
        fileName: fileName,
        fileBytes: fileBytes,
        attachmentType: attachmentType,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().split(': ').last),
            backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) {
        setState(
            () => _messages.removeWhere((msg) => msg['id'] == tempMessageId));
      }
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
      if (mounted) {
        setState(() {
          _isSubscribed = true;
          _didUpdateOccur = true;
        });
      }
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
      if (mounted) {
        setState(() {
          _isSubscribed = false;
          _didUpdateOccur = true;
        });
      }
    } finally {
      if (mounted) setState(() => _isSubscribing = false);
    }
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  String _formatDateSeparator(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);

    if (_isSameDay(date, today)) {
      return 'Today';
    } else if (_isSameDay(date, yesterday)) {
      return 'Yesterday';
    } else {
      return DateFormat.yMMMd().format(date); // e.g., "Oct 7, 2025"
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        Navigator.of(context).pop(_didUpdateOccur);
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

                            bool showDateSeparator = false;
                            final messageDate =
                                DateTime.parse(message['created_at']).toLocal();

                            if (index == _messages.length - 1) {
                              showDateSeparator = true;
                            } else {
                              final previousMessage = _messages[index + 1];
                              final previousMessageDate =
                                  DateTime.parse(previousMessage['created_at'])
                                      .toLocal();
                              if (!_isSameDay(
                                  messageDate, previousMessageDate)) {
                                showDateSeparator = true;
                              }
                            }

                            return Column(
                              children: [
                                _MessageBubble(
                                    message: message, isMine: isMine),
                                if (showDateSeparator)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16.0),
                                    child: Center(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: lightSuedeNavy,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          _formatDateSeparator(messageDate),
                                          style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12),
                                        ),
                                      ),
                                    ),
                                  )
                              ],
                            );
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

// ... rest of the file

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
    final createdAt = DateTime.parse(message['created_at']).toLocal();
    final readAt =
        message['read_at'] != null ? DateTime.parse(message['read_at']) : null;

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
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
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
                    style: TextStyle(
                        color: isMine ? Colors.black : Colors.white,
                        fontSize: 16)),
              ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DateFormat.jm().format(createdAt),
                  style: TextStyle(
                    color: isMine ? Colors.black54 : Colors.white54,
                    fontSize: 10,
                  ),
                ),
                if (isMine) ...[
                  const SizedBox(width: 4),
                  Icon(
                    readAt != null ? Icons.done_all : Icons.done,
                    size: 14,
                    color: readAt != null
                        ? Colors.blue.shade700
                        : (isMine ? Colors.black54 : Colors.white54),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
