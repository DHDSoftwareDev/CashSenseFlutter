// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import '../services/cognito_service.dart';
import '../services/push_token_service.dart';
import 'main_navigation_screen.dart';
import '../utils/root_scaffold.dart';

class VerificationScreen extends StatefulWidget {
  final String email;
  final String? password;

  const VerificationScreen({
    super.key,
    required this.email,
    this.password,
  });

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  bool _isLoading = false;
  bool _isResending = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _handleVerification() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      await CognitoService.confirmSignUp(
        email: widget.email,
        confirmationCode: _codeController.text.trim(),
      );

      if (!mounted) return;

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email verified! Signing you in...')),
      );

      // If we have the password (from signup flow), attempt auto sign-in
      if (widget.password != null && widget.password!.isNotEmpty) {
        try {
          final signInResult = await CognitoService.signIn(
            email: widget.email,
            password: widget.password!,
          );

          if (!mounted) return;

          if (signInResult.isSignedIn) {
            try {
              await PushTokenService.registerDeviceOnLogin();
            } catch (_) {}
            // Navigate to main app (dashboard)
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => MainNavigationScreen(key: mainNavKey)),
              (route) => false,
            );
            return;
          }
        } catch (e) {
          // Fall back to login screen if auto sign-in fails
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Auto sign-in failed: $e')),
          );
        }
      }

      // Navigate back to login screen as a fallback
      Navigator.pushReplacementNamed(context, '/login');
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(CognitoService.getErrorMessage(e))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Verification failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _resendCode() async {
    setState(() => _isResending = true);

    try {
      await CognitoService.resendConfirmationCode(widget.email);
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verification code resent!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to resend code: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isResending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Email'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Icon
                  Icon(
                    Icons.mark_email_read,
                    size: 80,
                    color: Theme.of(context).primaryColor,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Check Your Email',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'We sent a verification code to',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.grey[600],
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.email,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),

                  // Verification code field
                  TextFormField(
                    controller: _codeController,
                    decoration: InputDecoration(
                      labelText: 'Verification Code',
                      prefixIcon: const Icon(Icons.verified_user),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _handleVerification(),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter the verification code';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),

                  // Verify button
                  ElevatedButton(
                    onPressed: _isLoading ? null : _handleVerification,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            'Verify',
                            style: TextStyle(fontSize: 16),
                          ),
                  ),
                  const SizedBox(height: 16),

                  // Resend code button
                  OutlinedButton(
                    onPressed: _isResending ? null : _resendCode,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isResending
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            'Resend Code',
                            style: TextStyle(fontSize: 16),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
