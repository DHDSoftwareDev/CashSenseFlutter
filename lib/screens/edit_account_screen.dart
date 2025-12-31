// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import '../services/cognito_service.dart';
import '../services/user_auth_service.dart';

class EditAccountScreen extends StatefulWidget {
  const EditAccountScreen({super.key});

  @override
  State<EditAccountScreen> createState() => _EditAccountScreenState();
}

class _EditAccountScreenState extends State<EditAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _currentPasswordController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentAttributes();
  }

  Future<void> _loadCurrentAttributes() async {
    try {
      final attrs = await CognitoService.getCurrentUserAttributes();
      if (!mounted) return;
      setState(() {
        _displayNameController.text = attrs['name'] ?? attrs['username'] ?? '';
        _emailController.text = attrs['email'] ?? '';
      });
    } catch (e) {
      // ignore errors, leave fields blank
    }
  }

  Future<void> _saveAttributes() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final updates = <String, String>{};
      final name = _displayNameController.text.trim();
      final email = _emailController.text.trim();

      // Fetch current attributes to detect email change
      final currentAttrs = await CognitoService.getCurrentUserAttributes();
      final currentEmail = (currentAttrs['email'] ?? '').trim();

      if (name.isNotEmpty) updates['name'] = name;
      if (email.isNotEmpty) updates['email'] = email;

      if (updates.isNotEmpty) {
        await CognitoService.updateUserAttributes(updates);
      }

      bool emailChanged = email.isNotEmpty && email != currentEmail;
      if (emailChanged) {
        // Inform user a verification code will be sent
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Verify Email'),
            content: const Text('A verification code will be sent to the new email. Enter the code to confirm the change.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          ),
        );

        // Prompt for code (Cognito sends a code after the attribute update)
        final codeController = TextEditingController();
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Enter Verification Code'),
            content: TextField(
              controller: codeController,
              decoration: const InputDecoration(hintText: 'Verification code'),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Submit'),
              ),
            ],
          ),
        );

        if (confirmed == true) {
          final code = codeController.text.trim();
          if (code.isNotEmpty) {
            await CognitoService.confirmAttributeVerification('email', code);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email verified')));
          } else {
            throw Exception('Verification code required');
          }
        }
      }

      // If user requested password change
      final currentPass = _currentPasswordController.text.trim();
      final newPass = _newPasswordController.text.trim();
      final confirm = _confirmPasswordController.text.trim();
      if (newPass.isNotEmpty || currentPass.isNotEmpty) {
        if (newPass != confirm) throw Exception('New passwords do not match');
        await CognitoService.updatePassword(oldPassword: currentPass, newPassword: newPass);
      }

      // Persist updated attributes locally
      try {
        final updatedAttrs = await CognitoService.getCurrentUserAttributes();
        await UserAuthService.saveUserInfo(
          userId: updatedAttrs['userId'] ?? '',
          email: updatedAttrs['email'] ?? '',
          displayName: updatedAttrs['name'] ?? updatedAttrs['username'] ?? '',
        );
      } catch (_) {}

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account updated successfully')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error updating account: ${e.toString()}')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _emailController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Account'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _displayNameController,
                decoration: const InputDecoration(labelText: 'Display name'),
                textCapitalization: TextCapitalization.words,
                validator: (v) => null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  final s = v ?? '';
                  if (s.isEmpty) return 'Email cannot be empty';
                  if (!s.contains('@')) return 'Enter a valid email';
                  return null;
                },
              ),
              const SizedBox(height: 24),
              const Text('Change Password', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _currentPasswordController,
                decoration: const InputDecoration(labelText: 'Current password'),
                obscureText: true,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _newPasswordController,
                decoration: const InputDecoration(labelText: 'New password'),
                obscureText: true,
                validator: (v) {
                  final s = v ?? '';
                  if (s.isNotEmpty && s.length < 8) return 'Password must be at least 8 characters';
                  return null;
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _confirmPasswordController,
                decoration: const InputDecoration(labelText: 'Confirm new password'),
                obscureText: true,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loading ? null : _saveAttributes,
                child: _loading ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
