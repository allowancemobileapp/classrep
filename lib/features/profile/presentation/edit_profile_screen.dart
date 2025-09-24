// lib/features/profile/presentation/edit_profile_screen.dart

import 'dart:io';
import 'package:class_rep/shared/services/supabase_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

const Color darkSuedeNavy = Color(0xFF1A1B2C);

class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> profile;
  const EditProfileScreen({required this.profile, super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _displayNameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _bioController;
  late final TextEditingController _twitterController;
  late final TextEditingController _usdtWalletController; // Add this
  bool _isLoading = false;
  XFile? _pickedAvatar;

  @override
  void initState() {
    super.initState();
    _displayNameController =
        TextEditingController(text: widget.profile['display_name']);
    _usernameController =
        TextEditingController(text: widget.profile['username']);
    _bioController = TextEditingController(text: widget.profile['bio']);
    _twitterController =
        TextEditingController(text: widget.profile['twitter_handle']);
    _usdtWalletController = TextEditingController(
        text: widget.profile['usdt_wallet_address']); // Add this
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    _twitterController.dispose();
    _usdtWalletController.dispose(); // Add this
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
    if (image != null) {
      setState(() {
        _pickedAvatar = image;
      });
    }
  }

  Future<void> _saveProfile() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      try {
        String? newAvatarUrl = widget.profile['avatar_url'];
        if (_pickedAvatar != null) {
          newAvatarUrl =
              await SupabaseService.instance.uploadAvatar(_pickedAvatar!);
        }

        await SupabaseService.instance.updateUserProfile(
          displayName: _displayNameController.text.trim(),
          username: _usernameController.text.trim(),
          bio: _bioController.text.trim(),
          twitterHandle: _twitterController.text.trim(),
          avatarUrl: newAvatarUrl,
          usdtWalletAddress: _usdtWalletController.text.trim(), // Add this
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Profile saved successfully!'),
              backgroundColor: Colors.green));
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          final errorString = e.toString().toLowerCase();
          String errorMessage = 'Failed to save profile. Please try again.';

          // Check for the specific Supabase error for a unique constraint violation
          if (errorString.contains('duplicate key') &&
              errorString.contains('username')) {
            errorMessage =
                'This username is already taken. Please choose another.';
          }

          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.redAccent,
          ));
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: darkSuedeNavy,
      appBar: AppBar(
        backgroundColor: darkSuedeNavy,
        title: const Text('Edit Profile'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundImage: _pickedAvatar != null
                        ? FileImage(File(_pickedAvatar!.path))
                        : (widget.profile['avatar_url'] != null
                            ? NetworkImage(widget.profile['avatar_url'])
                            : null) as ImageProvider?,
                    child: (_pickedAvatar == null &&
                            widget.profile['avatar_url'] == null)
                        ? const Icon(Icons.person, size: 50)
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.cyanAccent,
                      child: IconButton(
                        icon: const Icon(Icons.edit,
                            color: Colors.black, size: 20),
                        onPressed: _pickImage,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            TextFormField(
              controller: _displayNameController,
              decoration: _buildInputDecoration(labelText: 'Display Name'),
              style: const TextStyle(color: Colors.white),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Display name cannot be empty.'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _usernameController,
              decoration: _buildInputDecoration(
                  labelText: 'Username (public, no spaces)'),
              style: const TextStyle(color: Colors.white),
              validator: (value) {
                if (value == null || value.trim().isEmpty)
                  return 'Username cannot be empty.';
                if (value.contains(' '))
                  return 'Username cannot contain spaces.';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _bioController,
              decoration: _buildInputDecoration(labelText: 'Bio'),
              style: const TextStyle(color: Colors.white),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _twitterController,
              decoration: _buildInputDecoration(
                  labelText: 'Twitter Handle (without @)'),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            // --- ADD THIS NEW TEXT FIELD ---
            TextFormField(
              controller: _usdtWalletController,
              decoration: _buildInputDecoration(
                  labelText: 'USDT Wallet Address (TRC-20)'),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent,
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    fontFamily: 'LeagueSpartan'),
              ),
              onPressed: _isLoading ? null : _saveProfile,
              child: _isLoading
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                          strokeWidth: 3, color: Colors.black))
                  : const Text('Save Changes',
                      style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration({required String labelText}) {
    return InputDecoration(
      labelText: labelText,
      labelStyle: const TextStyle(color: Colors.white70),
      filled: true,
      fillColor: Colors.white.withOpacity(0.1),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.cyanAccent, width: 1.5)),
    );
  }
}
