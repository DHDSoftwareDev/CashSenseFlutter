// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:provider/provider.dart';
import '../services/cognito_service.dart';
import '../services/aws_api_service.dart';
import '../services/push_token_service.dart';
import '../providers/user_session_controller.dart';
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

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Email verified! Signing you in...'),
        ),
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
              final idToken = await AwsApiService.getIdToken();

              if (idToken.isNotEmpty && mounted) {
                await context
                    .read<UserSessionController>()
                    .refreshUser(idToken: idToken);
              }
            } catch (_) {}

            try {
              await PushTokenService.registerDeviceOnLogin();
            } catch (_) {}

            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder: (_) => MainNavigationScreen(
                  key: mainNavKey,
                ),
              ),
              (route) => false,
            );

            return;
          }
        } catch (e) {
          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Auto sign-in failed: $e'),
            ),
          );
        }
      }

      // Navigate back to login screen as a fallback
      Navigator.pushReplacementNamed(
        context,
        '/login',
      );
    } on AuthException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            CognitoService.getErrorMessage(e),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Verification failed: $e'),
        ),
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
      await CognitoService.resendConfirmationCode(
        widget.email,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Verification code resent!'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to resend code: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isResending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,

      // APP BAR
      appBar: AppBar(
        title: const Text(
          'Verify Email',
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            20,
            28,
            20,
            32,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // EMAIL ICON
                Center(
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer
                          .withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.mark_email_read_outlined,
                      size: 44,
                      color: colorScheme.primary,
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                Text(
                  'Check Your Email',
                  textAlign: TextAlign.center,
                  style:
                      Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                ),

                const SizedBox(height: 8),

                Text(
                  'We sent a verification code to',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),

                const SizedBox(height: 5),

                Text(
                  widget.email,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                ),

                const SizedBox(height: 28),

                // VERIFICATION CARD
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: colorScheme.outlineVariant
                          .withValues(alpha: 0.35),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'VERIFICATION CODE',
                        style: Theme.of(context)
                            .textTheme
                            .labelLarge
                            ?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.7,
                            ),
                      ),

                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _codeController,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [
                          AutofillHints.oneTimeCode,
                        ],
                        onFieldSubmitted: (_) {
                          if (!_isLoading) {
                            _handleVerification();
                          }
                        },
                        decoration: InputDecoration(
                          labelText: 'Verification Code',
                          hintText: 'Enter your code',
                          prefixIcon: const Icon(
                            Icons.verified_user_outlined,
                          ),
                          filled: true,
                          fillColor: colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.45),
                          contentPadding:
                              const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 18,
                          ),
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: colorScheme.primary,
                              width: 1.5,
                            ),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: colorScheme.error,
                            ),
                          ),
                          focusedErrorBorder:
                              OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: colorScheme.error,
                              width: 1.5,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if (value == null ||
                              value.trim().isEmpty) {
                            return 'Please enter the verification code';
                          }

                          return null;
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 22),

                // VERIFY BUTTON
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed:
                        _isLoading ? null : _handleVerification,
                    style: FilledButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor:
                          colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.onPrimary,
                            ),
                          )
                        : const Text(
                            'Verify Email',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 12),

                // RESEND BUTTON
                SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed:
                        _isResending ? null : _resendCode,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: colorScheme.outlineVariant,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(12),
                      ),
                    ),
                    icon: _isResending
                        ? const SizedBox.shrink()
                        : const Icon(
                            Icons.refresh_rounded,
                            size: 20,
                          ),
                    label: _isResending
                        ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.primary,
                            ),
                          )
                        : const Text(
                            'Resend Code',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 18),

                Text(
                  'Didn’t receive the code? Check your spam folder or tap Resend Code.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}