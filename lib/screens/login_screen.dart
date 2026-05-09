// ignore_for_file: unnecessary_import, use_build_context_synchronously, unused_import

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:provider/provider.dart';
import '../services/cognito_service.dart';
import '../services/aws_api_service.dart';
import '../services/biometric_auth_service.dart';
import '../services/push_token_service.dart';
import '../services/remote_sync_service.dart';
import '../services/session_cleanup_service.dart';
import '../services/user_api_service.dart';
import '../providers/user_session_controller.dart';
import '../services/lookups_state.dart';
import 'verification_screen.dart';
import 'signup_screen.dart';
import 'dashboard_screen.dart';
import 'main_navigation_screen.dart';
import '../utils/root_scaffold.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _redirectIfSignedIn();
    });
  }

  Future<void> _redirectIfSignedIn() async {
    try {
      final signedIn = await CognitoService.isSignedIn();
      if (!signedIn || !mounted) return;

      final biometricEnabled = await BiometricAuthService.isBiometricEnabled();
      if (biometricEnabled) {
        final canUseBiometrics = await BiometricAuthService.canUseBiometrics();
        if (!canUseBiometrics) {
          await BiometricAuthService.setBiometricEnabled(false);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Biometrics unavailable on this device. Biometric lock disabled.',
              ),
            ),
          );
        } else {
          final unlocked = await BiometricAuthService.authenticate(
            reason: 'Authenticate to access your CashSense account',
          );
          if (!unlocked || !mounted) return;
        }
      }

      try {
        final idToken = await AwsApiService.getIdToken();
        if (idToken.isNotEmpty && mounted) {
          await context.read<UserSessionController>().refreshUser(
            idToken: idToken,
          );
        }
      } on BackendUserInvalidatedException {
        await _handleBackendUserInvalidated();
        return;
      } catch (_) {}

      final lookupsState = context.read<LookupsState>();
      try {
        await lookupsState.loadFromLocal();
      } catch (_) {}

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MainNavigationScreen(key: mainNavKey),
        ),
      );
      lookupsState.syncRemote().catchError((_) {});
    } catch (_) {}
  }

  Future<void> _handleBackendUserInvalidated() async {
    UserSessionController? userSession;
    try {
      userSession = context.read<UserSessionController>();
    } catch (_) {}

    await SessionCleanupService.clearInvalidatedBackendUser(
      userSession: userSession,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Your account is no longer available. Please sign in again.',
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final alreadySignedIn = await CognitoService.isSignedIn();
      if (alreadySignedIn) {
        await _redirectIfSignedIn();
        return;
      }
      final result = await CognitoService.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;

      if (result.isSignedIn) {
        TextInput.finishAutofillContext();
        try {
          final idToken = await AwsApiService.getIdToken();
          if (idToken.isNotEmpty && mounted) {
            await context.read<UserSessionController>().refreshUser(
              idToken: idToken,
            );
          }
        } on BackendUserInvalidatedException {
          await _handleBackendUserInvalidated();
          return;
        } catch (_) {}
        try {
          await PushTokenService.registerDeviceOnLogin();
        } catch (_) {}
        await RemoteSyncService.syncUserDataOnLogin();

        final lookupsState = context.read<LookupsState>();
        try {
          await lookupsState.loadFromLocal();
        } catch (_) {}

        // Login successful — go to dashboard
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Login successful!')));
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => MainNavigationScreen(key: mainNavKey),
          ),
        );
        lookupsState.syncRemote().catchError((_) {});
      } else if (result.nextStep.signInStep == AuthSignInStep.confirmSignUp) {
        // User needs to verify email
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) =>
                VerificationScreen(email: _emailController.text.trim()),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Next step: ${result.nextStep.signInStep}')),
        );
      }
    } on BackendUserInvalidatedException {
      await _handleBackendUserInvalidated();
    } on AuthException catch (e) {
      if (!mounted) return;
      final msg = CognitoService.getErrorMessage(e);
      if (msg.toLowerCase().contains('already signed in')) {
        await _redirectIfSignedIn();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Login failed: $e')));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showForgotPasswordRequestDialog() async {
    final emailController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = emailController.text.trim();
              if (email.isEmpty || !email.contains('@')) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a valid email')),
                );
                return;
              }

              // Show loading
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) =>
                    const Center(child: CircularProgressIndicator()),
              );

              try {
                await CognitoService.resetPassword(email);
                if (mounted) Navigator.pop(context); // close loading
                if (mounted) Navigator.pop(context); // close request dialog

                // Open confirmation dialog to enter code and new password
                if (mounted) _showForgotPasswordConfirmDialog(email);
              } on AuthException catch (e) {
                if (mounted) Navigator.pop(context);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(CognitoService.getErrorMessage(e))),
                  );
                }
              } catch (e) {
                if (mounted) Navigator.pop(context);
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Reset failed: $e')));
                }
              }
            },
            child: const Text('Send Code'),
          ),
        ],
      ),
    );
  }

  Future<void> _showForgotPasswordConfirmDialog(String email) async {
    final codeController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter Code & New Password'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('A verification code was sent to $email'),
              const SizedBox(height: 12),
              TextField(
                controller: codeController,
                decoration: const InputDecoration(
                  labelText: 'Verification Code',
                  prefixIcon: Icon(Icons.verified_user),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                decoration: const InputDecoration(
                  labelText: 'New Password',
                  prefixIcon: Icon(Icons.lock),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmController,
                decoration: const InputDecoration(
                  labelText: 'Confirm Password',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                obscureText: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final code = codeController.text.trim();
              final pw = passwordController.text;
              final confirm = confirmController.text;

              if (code.isEmpty || pw.isEmpty || confirm.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please fill all fields')),
                );
                return;
              }
              if (pw.length < 8) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Password must be at least 8 characters'),
                  ),
                );
                return;
              }
              if (pw != confirm) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Passwords do not match')),
                );
                return;
              }

              // Show loading
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) =>
                    const Center(child: CircularProgressIndicator()),
              );

              try {
                await CognitoService.confirmResetPassword(
                  email: email,
                  newPassword: pw,
                  confirmationCode: code,
                );
                if (mounted) Navigator.pop(context); // close loading
                if (mounted) Navigator.pop(context); // close confirm dialog
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Password reset successful — please login'),
                    ),
                  );
                }
              } on AuthException catch (e) {
                if (mounted) Navigator.pop(context);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(CognitoService.getErrorMessage(e))),
                  );
                }
              } catch (e) {
                if (mounted) Navigator.pop(context);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Reset confirmation failed: $e')),
                  );
                }
              }
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: AutofillGroup(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // App logo or title (use dashboard header icon)
                    Image.asset(
                      'assets/images/cash_icon.png',
                      width: 180,
                      height: 180,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Welcome Back',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Sign in to continue',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 48),

                    // Email field
                    TextFormField(
                      controller: _emailController,
                      autofillHints: const [
                        AutofillHints.username,
                        AutofillHints.email,
                      ],
                      decoration: InputDecoration(
                        labelText: 'Email',
                        prefixIcon: const Icon(Icons.email),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter your email';
                        }
                        if (!value.contains('@')) {
                          return 'Please enter a valid email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Password field
                    TextFormField(
                      controller: _passwordController,
                      autofillHints: const [AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () {
                            setState(
                              () => _obscurePassword = !_obscurePassword,
                            );
                          },
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _handleLogin(),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your password';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),

                    // Login button - match height to the Apple Sign-In button
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : () => _handleLogin(),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          padding: const EdgeInsets.symmetric(vertical: 0),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Login',
                                style: TextStyle(fontSize: 16),
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Forgot password link
                    TextButton(
                      onPressed: () {
                        if (_isLoading) return;
                        _showForgotPasswordRequestDialog();
                      },
                      child: const Text('Forgot Password?'),
                    ),
                    const SizedBox(height: 24),

                    // Sign up link
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("Don't have an account? "),
                        TextButton(
                          onPressed: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const SignUpScreen(),
                              ),
                            );
                          },
                          child: const Text(
                            'Sign Up',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
