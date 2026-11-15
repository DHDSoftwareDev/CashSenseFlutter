// ignore_for_file: use_build_context_synchronously

import '../services/account_operations.dart';
import 'package:flutter/material.dart';
import '../services/cognito_service.dart';
import '../services/user_auth_service.dart';

class EditAccountScreen extends StatefulWidget {
  const EditAccountScreen({super.key});

  @override
  State<EditAccountScreen> createState() => _EditAccountScreenState();
}

class _EditAccountScreenState extends State<EditAccountScreen> {
  final int _accountGeneration = AccountOperations.generation;
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _currentPasswordController =
      TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _loading = false;
  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentAttributes();
  }

  Future<void> _loadCurrentAttributes() {
    return AccountOperations.bind(_accountGeneration, () async {
    try {
      final attrs = await CognitoService.getCurrentUserAttributes();

      if (!mounted) return;

      setState(() {
        _displayNameController.text =
            attrs['name'] ?? attrs['username'] ?? '';
        _emailController.text = attrs['email'] ?? '';
      });
    } catch (e) {
      // Ignore errors, leave fields blank.
    }
      });
  }

  Future<void> _saveAttributes() {
    return AccountOperations.bind(_accountGeneration, () async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      final updates = <String, String>{};
      final name = _displayNameController.text.trim();
      final email = _emailController.text.trim();

      // Fetch current attributes to detect email change.
      final currentAttrs =
          await CognitoService.getCurrentUserAttributes();
      final currentEmail = (currentAttrs['email'] ?? '').trim();

      if (name.isNotEmpty) updates['name'] = name;
      if (email.isNotEmpty) updates['email'] = email;

      if (updates.isNotEmpty) {
        await CognitoService.updateUserAttributes(updates);
      }

      final emailChanged =
          email.isNotEmpty && email != currentEmail;

      if (emailChanged) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: const Text('Verify Email'),
            content: const Text(
              'A verification code will be sent to the new email. '
              'Enter the code to confirm the change.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );

        final codeController = TextEditingController();

        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) {
            final colorScheme = Theme.of(ctx).colorScheme;

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              title: const Text('Enter Verification Code'),
              content: TextField(
                controller: codeController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: 'Verification code',
                  prefixIcon:
                      const Icon(Icons.verified_user_outlined),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.45),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: colorScheme.primary,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Submit'),
                ),
              ],
            );
          },
        );

        if (confirmed == true) {
          final code = codeController.text.trim();

          if (code.isNotEmpty) {
            await CognitoService.confirmAttributeVerification(
              'email',
              code,
            );

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Email verified'),
              ),
            );
          } else {
            throw Exception('Verification code required');
          }
        }
      }

      // If user requested password change.
      final currentPass =
          _currentPasswordController.text.trim();
      final newPass = _newPasswordController.text.trim();
      final confirm =
          _confirmPasswordController.text.trim();

      if (newPass.isNotEmpty || currentPass.isNotEmpty) {
        if (newPass != confirm) {
          throw Exception('New passwords do not match');
        }

        await CognitoService.updatePassword(
          oldPassword: currentPass,
          newPassword: newPass,
        );
      }

      // Persist updated attributes locally.
      try {
        final updatedAttrs =
            await CognitoService.getCurrentUserAttributes();

        await UserAuthService.saveUserInfo(
          userId: updatedAttrs['userId'] ?? '',
          email: updatedAttrs['email'] ?? '',
          displayName:
              updatedAttrs['name'] ??
              updatedAttrs['username'] ??
              '',
        );
      } catch (_) {}

      if (!mounted) return;

      ScaffoldMessenger.of(context).clearSnackBars();
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error updating account: ${e.toString()}',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
      });
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
    String? helperText,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return InputDecoration(
      labelText: label,
      helperText: helperText,
      prefixIcon: Icon(icon),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor:
          colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: colorScheme.primary,
          width: 1.5,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: colorScheme.error,
        ),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: colorScheme.error,
          width: 1.5,
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return BoxDecoration(
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color:
            colorScheme.outlineVariant.withValues(alpha: 0.35),
      ),
    );
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
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text(
          'Edit Account',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        backgroundColor: colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding:
                const EdgeInsets.fromLTRB(20, 20, 20, 32),
            children: [
              // ACCOUNT DETAILS
              Text(
                'ACCOUNT DETAILS',
                style:
                    Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.7,
                        ),
              ),

              const SizedBox(height: 8),

              Container(
                padding: const EdgeInsets.all(18),
                decoration: _cardDecoration(context),
                child: Column(
                  children: [
                    TextFormField(
                      controller: _displayNameController,
                      textCapitalization:
                          TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: _fieldDecoration(
                        label: 'Display Name',
                        icon: Icons.person_outline_rounded,
                      ),
                    ),

                    const SizedBox(height: 14),

                    TextFormField(
                      controller: _emailController,
                      keyboardType:
                          TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: _fieldDecoration(
                        label: 'Email',
                        icon: Icons.email_outlined,
                      ),
                      validator: (v) {
                        final s = v ?? '';

                        if (s.isEmpty) {
                          return 'Email cannot be empty';
                        }

                        if (!s.contains('@')) {
                          return 'Enter a valid email';
                        }

                        return null;
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // PASSWORD
              Text(
                'CHANGE PASSWORD',
                style:
                    Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.7,
                        ),
              ),

              const SizedBox(height: 8),

              Container(
                padding: const EdgeInsets.all(18),
                decoration: _cardDecoration(context),
                child: Column(
                  children: [
                    TextFormField(
                      controller: _currentPasswordController,
                      obscureText: _obscureCurrentPassword,
                      textInputAction: TextInputAction.next,
                      decoration: _fieldDecoration(
                        label: 'Current Password',
                        icon: Icons.lock_outline_rounded,
                        suffixIcon: IconButton(
                          tooltip: _obscureCurrentPassword
                              ? 'Show password'
                              : 'Hide password',
                          onPressed: () {
                            setState(() {
                              _obscureCurrentPassword =
                                  !_obscureCurrentPassword;
                            });
                          },
                          icon: Icon(
                            _obscureCurrentPassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    TextFormField(
                      controller: _newPasswordController,
                      obscureText: _obscureNewPassword,
                      textInputAction: TextInputAction.next,
                      decoration: _fieldDecoration(
                        label: 'New Password',
                        helperText: 'Minimum 8 characters',
                        icon: Icons.lock_reset_rounded,
                        suffixIcon: IconButton(
                          tooltip: _obscureNewPassword
                              ? 'Show password'
                              : 'Hide password',
                          onPressed: () {
                            setState(() {
                              _obscureNewPassword =
                                  !_obscureNewPassword;
                            });
                          },
                          icon: Icon(
                            _obscureNewPassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (v) {
                        final s = v ?? '';

                        if (s.isNotEmpty && s.length < 8) {
                          return 'Password must be at least 8 characters';
                        }

                        return null;
                      },
                    ),

                    const SizedBox(height: 14),

                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: _obscureConfirmPassword,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) {
                        if (!_loading) {
                          _saveAttributes();
                        }
                      },
                      decoration: _fieldDecoration(
                        label: 'Confirm New Password',
                        icon: Icons.lock_outline_rounded,
                        suffixIcon: IconButton(
                          tooltip: _obscureConfirmPassword
                              ? 'Show password'
                              : 'Hide password',
                          onPressed: () {
                            setState(() {
                              _obscureConfirmPassword =
                                  !_obscureConfirmPassword;
                            });
                          },
                          icon: Icon(
                            _obscureConfirmPassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Leave the password fields blank if you do not want to change your password.',
                  style:
                      Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                colorScheme.onSurfaceVariant,
                          ),
                ),
              ),

              const SizedBox(height: 24),

              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed:
                      _loading ? null : _saveAttributes,
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _loading
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.onPrimary,
                          ),
                        )
                      : const Text(
                          'Save Changes',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
