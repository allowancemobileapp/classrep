// lib/features/profile/presentation/create_gist_screen.dart

import 'dart:io';
import 'package:class_rep/shared/services/supabase_service.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

const Color darkSuedeNavy = Color(0xFF1A1B2C);
const Color lightSuedeNavy = Color(0xFF2A2C40);

class CreateGistScreen extends StatefulWidget {
  const CreateGistScreen({super.key});

  @override
  State<CreateGistScreen> createState() => _CreateGistScreenState();
}

class _CreateGistScreenState extends State<CreateGistScreen> {
  String _gistType = 'text';
  final _textController = TextEditingController();
  final _captionController = TextEditingController();
  XFile? _mediaFile;
  VideoPlayerController? _videoController;
  bool _isUploading = false;

  @override
  void dispose() {
    _textController.dispose();
    _captionController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file != null) {
      _videoController?.dispose();
      _videoController = null;
      setState(() {
        _mediaFile = file;
        _gistType = 'image';
      });
    }
  }

  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final file = await picker.pickVideo(
        source: ImageSource.gallery, maxDuration: const Duration(seconds: 30));
    if (file != null) {
      _videoController?.dispose();
      _videoController = VideoPlayerController.file(File(file.path))
        ..initialize().then((_) {
          if (mounted) {
            setState(() {
              _mediaFile = file;
              _gistType = 'video';
            });
            _videoController?.play();
            _videoController?.setLooping(true);
          }
        });
    }
  }

  Future<void> _postGist() async {
    if (_isUploading) return;
    setState(() => _isUploading = true);

    try {
      if (_gistType == 'text') {
        if (_textController.text.trim().isEmpty) {
          throw Exception('Text cannot be empty.');
        }
        await SupabaseService.instance.createGist(
          type: 'text',
          content: _textController.text.trim(),
        );
      } else if (_mediaFile != null) {
        final mediaUrl =
            await SupabaseService.instance.uploadGistMedia(_mediaFile!);
        await SupabaseService.instance.createGist(
          type: _gistType,
          mediaUrl: mediaUrl,
          caption: _captionController.text.trim(),
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().split(': ').last),
            backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: darkSuedeNavy,
      appBar: AppBar(
        backgroundColor: darkSuedeNavy,
        title: const Text('Create a Gist'),
        actions: [
          TextButton(
            onPressed: _isUploading ? null : _postGist,
            child: _isUploading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Post',
                    style: TextStyle(color: Colors.cyanAccent, fontSize: 16)),
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    color: Colors.black,
                    width: double.infinity,
                    child: _buildPreview(),
                  ),
                  if (_gistType != 'text')
                    Positioned(
                      bottom: 20,
                      left: 20,
                      right: 20,
                      child: TextField(
                        controller: _captionController,
                        textAlign: TextAlign.center,
                        maxLength: 50,
                        maxLines: null,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                        ),
                        decoration: InputDecoration(
                          hintText: 'Add a caption...',
                          hintStyle:
                              TextStyle(color: Colors.white.withOpacity(0.7)),
                          border: InputBorder.none,
                          counterText: '',
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Container(
            color: lightSuedeNavy,
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IconButton(
                  icon: Icon(Icons.text_fields,
                      color: _gistType == 'text'
                          ? Colors.cyanAccent
                          : Colors.white),
                  onPressed: () => setState(() {
                    _gistType = 'text';
                    _mediaFile = null;
                    _videoController?.dispose();
                    _videoController = null;
                  }),
                ),
                IconButton(
                  icon: Icon(Icons.image,
                      color: _gistType == 'image'
                          ? Colors.cyanAccent
                          : Colors.white),
                  onPressed: _pickImage,
                ),
                IconButton(
                  icon: Icon(Icons.videocam,
                      color: _gistType == 'video'
                          ? Colors.cyanAccent
                          : Colors.white),
                  onPressed: _pickVideo,
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildPreview() {
    if (_gistType == 'image' && _mediaFile != null) {
      return Image.file(File(_mediaFile!.path), fit: BoxFit.contain);
    }
    if (_gistType == 'video' &&
        _videoController != null &&
        _videoController!.value.isInitialized) {
      return Center(
        child: AspectRatio(
          aspectRatio: _videoController!.value.aspectRatio,
          child: VideoPlayer(_videoController!),
        ),
      );
    }
    // Default to text input
    return Container(
      alignment: Alignment.center,
      color: Colors
          .primaries[(_textController.text.length % Colors.primaries.length)]
          .withOpacity(0.8),
      padding: const EdgeInsets.all(24),
      child: TextField(
        controller: _textController,
        textAlign: TextAlign.center,
        maxLines: null,
        style: const TextStyle(
            fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold),
        decoration: const InputDecoration(
          border: InputBorder.none,
          hintText: 'Type something...',
          hintStyle: TextStyle(color: Colors.white54),
        ),
      ),
    );
  }
}
