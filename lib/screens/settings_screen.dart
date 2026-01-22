// ignore_for_file: deprecated_member_use, unnecessary_to_list_in_spreads, use_build_context_synchronously, unused_element, unnecessary_import, unused_local_variable, await_only_futures, unused_import, unused_field

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../services/database_service.dart';
import '../models/transaction.dart';
import '../models/category.dart' as models;
import '../models/account.dart';
import '../models/bill.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/app_color_picker.dart';
import 'subscriptions_screen.dart';
import 'notifications_screen.dart';
import 'backup_restore_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/cognito_service.dart';
import '../services/user_auth_service.dart';
import 'login_screen.dart';
import 'signup_screen.dart';
import 'edit_account_screen.dart';
import '../services/auto_backup_service.dart';
import 'package:amplify_flutter/amplify_flutter.dart' hide Category;
import '../services/bill_reminder_service.dart';
import '../utils/root_scaffold.dart';





class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _userEmail = '';
  bool _isLoggedIn = false;
  bool _authUIEnabled = true;
  String _versionLabel = '';
  bool _autoBackupEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _loadVersion();
    _autoBackupEnabled = DatabaseService.getSetting<bool>('autoBackupEnabled', false) ?? false;
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _versionLabel = '${info.version} (${info.buildNumber})';
      });
    } catch (e) {
      debugPrint('Failed to load package info: $e');
    }
  }

  Future<void> _loadUserInfo() async {
    // Check Cognito auth status first
    final isLoggedIn = await CognitoService.isSignedIn();
    String email = '';
    // Load whether auth UI should be shown
    final enabled = DatabaseService.getSetting<bool>('enableAuthUI', true) ?? true;
    _authUIEnabled = enabled;
    
    if (isLoggedIn) {
      try {
        final attributes = await CognitoService.getCurrentUserAttributes();
        email = attributes['email'] ?? '';
      } catch (e) {
        debugPrint('Error loading user attributes: $e');
      }
    }
    
    setState(() {
      _isLoggedIn = isLoggedIn;
      _userEmail = email;
    });
  }

  void _shareFCMToken() {
    // Firebase Messaging removed
    debugPrint('FCM sharing disabled');
  }

  void _showAutoBackupHistoryPopup() async {
    // Get the CashSense folder in appropriate directory based on platform
    Directory dir;
    if (Platform.isIOS) {
      // iOS: Use app's documents directory
      final docsDir = await getApplicationDocumentsDirectory();
      dir = Directory('${docsDir.path}/CashSense');
    } else {
      // Android/Desktop: Use Downloads directory
      final downloadsDir = await getDownloadsDirectory();
      if (downloadsDir == null) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Automatic Backups'),
            content: const Text('Downloads directory not available.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
        return;
      }
      dir = Directory('${downloadsDir.path}/CashSense');
    }
    
    List<File> files = [];
    if (await dir.exists()) {
      files = dir.listSync().whereType<File>().where((f) => f.path.contains('cashsense_auto_backup_')).toList();
      files.sort((a, b) => b.path.compareTo(a.path)); // newest first
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Automatic Backups'),
        content: SizedBox(
          width: 350,
          child: files.isEmpty
              ? const Text('No automatic backups found.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: files.length,
                  itemBuilder: (context, idx) {
                    final file = files[idx];
                    final name = file.path.split('/').last;
                    final ts = name.replaceAll('cashsense_auto_backup_', '').replaceAll('.json', '').replaceAll('-', ':');
                    return ListTile(
                      title: Text('Backup: $ts'),
                      subtitle: Text(file.path),
                      trailing: TextButton(
                        child: const Text('Restore'),
                        onPressed: () async {
                          Navigator.pop(context);
                          final jsonString = await file.readAsString();
                          await _performRestore(jsonString);
                        },
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
  void _showBackupRestorePopup() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Backup/Restore'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.backup),
              title: const Text('Backup Data'),
              subtitle: const Text('Export your data'),
              onTap: () {
                Navigator.pop(context);
                _showBackupDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.restore),
              title: const Text('Restore Data'),
              subtitle: const Text('Import your data'),
              onTap: () {
                Navigator.pop(context);
                _showRestoreDialog();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
  void _showSubscriptionModeDialog() {
    showDialog(
      context: context,
      builder: (context) {
  String currentMode = DatabaseService.subscriptionVersion.value;
        return AlertDialog(
          title: const Text('Change Subscription Mode'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<String>(
                title: const Text('Free'),
                value: 'Free',
                groupValue: currentMode,
                onChanged: (val) async {
                  await DatabaseService.setSubscriptionPlan(val!);
                  if (mounted) setState(() {});
                  Navigator.pop(context);
                },
              ),
              RadioListTile<String>(
                title: const Text('Monthly'),
                value: 'Monthly',
                groupValue: currentMode,
                onChanged: (val) async {
                  await DatabaseService.setSubscriptionPlan(val!);
                  if (mounted) setState(() {});
                  Navigator.pop(context);
                },
              ),
              RadioListTile<String>(
                title: const Text('Premium'),
                value: 'Premium',
                groupValue: currentMode,
                onChanged: (val) async {
                  await DatabaseService.setSubscriptionPlan(val!);
                  if (mounted) setState(() {});
                  Navigator.pop(context);
                },
              ),
              RadioListTile<String>(
                title: const Text('Lifetime'),
                value: 'Lifetime',
                groupValue: currentMode,
                onChanged: (val) async {
                  await DatabaseService.setSubscriptionPlan(val!);
                  if (mounted) setState(() {});
                  Navigator.pop(context);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: openRootDrawer,
        ),
  title: const Text('Settings'),
  centerTitle: true,
  backgroundColor: Theme.of(context).colorScheme.primary,
  foregroundColor: Colors.white,
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              children: [
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  child: ListTile(
                    leading: const Icon(Icons.workspace_premium, color: Colors.amber),
                    title: Text('Subscription'),
                    subtitle: Text(DatabaseService.subscriptionVersion.value),
                    trailing: TextButton(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SubscriptionsScreen())),
                      child: const Text('Manage'),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Authentication card — render unconditionally (show status and actions)
                _buildAuthCard(context),
                const SizedBox(height: 12),
              ],
            ),
          ),
          _buildSection('Appearance', [
            Consumer<ThemeProvider>(
              builder: (context, provider, _) {
                String subtitle;
                switch (provider.themeMode) {
                  case ThemeMode.light:
                    subtitle = 'Light';
                    break;
                  case ThemeMode.dark:
                    subtitle = 'Dark';
                    break;
                  case ThemeMode.system:
                    subtitle = 'System';
                    break;
                }
                return Column(
                  children: [
                    _buildSettingsTile(
                      'Theme',
                      subtitle,
                      Icons.color_lens,
                      () => _showThemeDialog(),
                    ),
                    _buildSettingsTile(
                      'Accent Color',
                      'Tap to choose',
                      Icons.palette,
                      () => _showColorPicker(),
                      trailing: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: provider.primaryColor,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.black12),
                        ),
                      ),
                    ),
                    // 'Widget' setting removed
                  ],
                );
              },
            ),
          ]),
          _buildSection('General', [
            _buildSettingsTile(
              'Notifications',
              _getNotificationSummary(),
              Icons.notifications,
              () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
              trailing: null,
            ),
            // Login/Sign Up UI setting removed — auth UI controlled elsewhere
          ]),
          _buildSection('Data', [
            if (_hasActiveSubscription()) _buildAutoBackupCard(),
            _buildSettingsTile(
              'Backup/Restore',
              'Backup or restore your data',
              Icons.backup,
              () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BackupRestoreScreen())),
            ),
            _buildSettingsTile(
              'Archived Accounts',
              'View and restore archived accounts',
              Icons.archive,
              () => _showArchivedAccountsDialog(),
            ),
            _buildSettingsTile(
              'Clear All Data',
              'Delete all transactions and categories',
              Icons.delete_forever,
              () => _showClearDataDialog(),
              trailing: const Icon(Icons.warning, color: Colors.red),
            ),
          ]),
          _buildSection('About', [
            _buildSettingsTile(
              'Version',
              _versionLabel.isEmpty ? 'Loading...' : _versionLabel,
              Icons.info,
              () => _showVersionDialog(),
              trailing: null,
            ),
            _buildSettingsTile(
              'Privacy Policy',
              'View privacy policy',
              Icons.privacy_tip,
              () => _showPrivacyDialog(),
            ),
            // Rate App moved to bottom under Help & Support
            _buildSettingsTile(
              'Terms of Service',
              'View terms',
              Icons.description,
              () => _showTermsDialog(),
            ),
            ]),
          // Help & Support card at the bottom
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              child: ListTile(
                leading: const Icon(Icons.help_outline),
                title: const Text('Help & Support'),
                subtitle: const Text('Contact support or view help docs'),
                onTap: () => _showHelpSupportDialog(),
              ),
            ),
          ),
          // Rate App card beneath Help & Support
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              child: ListTile(
                leading: const Icon(Icons.star_rate, color: Colors.amber),
                title: const Text('Rate App'),
                subtitle: const Text('Leave a review on the app store'),
                onTap: () => _showRateAppDialog(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _hasActiveSubscription() {
    final plan = DatabaseService.subscriptionVersion.value;
    return plan != 'Free';
  }

  Widget _buildAutoBackupCard() {
    final subtitle = _autoBackupEnabled ? 'Automatic backups enabled' : 'Automatic backups disabled';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.cloud_upload),
              title: const Text('Auto Backup'),
              subtitle: Text(subtitle),
              trailing: Switch(
                value: _autoBackupEnabled,
                onChanged: (value) async {
                  await DatabaseService.setSetting('autoBackupEnabled', value);
                  await AutoBackupService.configurePeriodicTaskFromSettings();
                  if (!mounted) return;
                  setState(() => _autoBackupEnabled = value);
                },
              ),
              onTap: () => _showAutoBackupHistoryPopup(),
            ),
            const Divider(height: 1),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _runAutoBackupNow,
                icon: const Icon(Icons.backup),
                label: const Text('Backup Now'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showHelpSupportDialog() {
  const supportEmail = 'support@dhdsoftware.com';
  const helpUrl = 'https://dhdsoftware.com/HelpDocsCashSense';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Help & Support'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: ListTile(
                leading: const Icon(Icons.email),
                title: const Text('Email Support'),
                subtitle: const Text(
                  'support@dhdsoftware.com',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                  maxLines: 1,
                  softWrap: false,
                ),
                // Remove trailing to maximize space
                onTap: () async {
                  final Uri emailUri = Uri(
                    scheme: 'mailto',
                    path: supportEmail,
                    query: 'subject=CashSense Support Request',
                  );
                  if (await canLaunchUrl(emailUri)) {
                    await launchUrl(emailUri);
                  } else {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Could not open email app'),
                          backgroundColor: Colors.blueGrey[400],
                        ),
                      );
                    }
                  }
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Help Center'),
              subtitle: const Text('Open help docs'),
              onTap: () async {
                final Uri url = Uri.parse(helpUrl);
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Could not open help docs URL'),
                      backgroundColor: Colors.blueGrey[400],
                    ),
                  );
                }
              },
            ),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  void _showLoginDialog() {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Login'),
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
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(
                labelText: 'Password',
                prefixIcon: Icon(Icons.lock),
              ),
              obscureText: true,
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
              final password = passwordController.text;

              if (email.isEmpty || password.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please fill in all fields')),
                );
                return;
              }

              try {
                // Show loading indicator
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => const Center(child: CircularProgressIndicator()),
                );

                // Sign in with Cognito
                final result = await CognitoService.signIn(
                  email: email,
                  password: password,
                );

                // Close loading indicator
                if (mounted) Navigator.pop(context);

                if (result.isSignedIn) {
                  // Close login dialog
                  Navigator.pop(context);
                  await _loadUserInfo();
                  
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Login successful!')),
                    );
                  }
                } else if (result.nextStep.signInStep == AuthSignInStep.confirmSignUp) {
                  // User needs to verify email
                  Navigator.pop(context);
                  _showVerificationDialog(email);
                } else {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Next step: ${result.nextStep.signInStep}')),
                    );
                  }
                }
              } on AuthException catch (e) {
                // Close loading indicator
                if (mounted) Navigator.pop(context);
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(CognitoService.getErrorMessage(e))),
                  );
                }
              } catch (e) {
                // Close loading indicator
                if (mounted) Navigator.pop(context);
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Login failed: $e')),
                  );
                }
              }
            },
            child: const Text('Login'),
          ),
        ],
      ),
    );
  }

  void _showSignUpDialog() {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final displayNameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Up'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: displayNameController,
                decoration: const InputDecoration(
                  labelText: 'Display Name',
                  prefixIcon: Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                decoration: const InputDecoration(
                  labelText: 'Password (min 8 characters)',
                  prefixIcon: Icon(Icons.lock),
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
              final email = emailController.text.trim();
              final password = passwordController.text;
              final displayName = displayNameController.text.trim();

              if (email.isEmpty || password.isEmpty || displayName.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please fill in all fields')),
                );
                return;
              }

              if (password.length < 8) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Password must be at least 8 characters')),
                );
                return;
              }

              try {
                // Show loading indicator
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => const Center(child: CircularProgressIndicator()),
                );

                // Sign up with Cognito
                final result = await CognitoService.signUp(
                  email: email,
                  password: password,
                  displayName: displayName,
                );

                // Close loading indicator
                if (mounted) Navigator.pop(context);

                if (result.isSignUpComplete) {
                  // Auto sign-in if no verification needed
                  Navigator.pop(context);
                  await _loadUserInfo();
                  
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Account created successfully!')),
                    );
                  }
                } else {
                  // Need email verification
                  Navigator.pop(context);
                  _showVerificationDialog(email);
                }
              } on AuthException catch (e) {
                // Close loading indicator
                if (mounted) Navigator.pop(context);
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(CognitoService.getErrorMessage(e))),
                  );
                }
              } catch (e) {
                // Close loading indicator
                if (mounted) Navigator.pop(context);
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Sign up failed: $e')),
                  );
                }
              }
            },
            child: const Text('Sign Up'),
          ),
        ],
      ),
    );
  }

  void _showVerificationDialog(String email) {
    final codeController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Verify Email'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Please enter the verification code sent to $email'),
            const SizedBox(height: 16),
            TextField(
              controller: codeController,
              decoration: const InputDecoration(
                labelText: 'Verification Code',
                prefixIcon: Icon(Icons.verified_user),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              try {
                await CognitoService.resendConfirmationCode(email);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Code resent!')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to resend code: $e')),
                  );
                }
              }
            },
            child: const Text('Resend Code'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final code = codeController.text.trim();

              if (code.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter the code')),
                );
                return;
              }

              try {
                // Show loading
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => const Center(child: CircularProgressIndicator()),
                );

                await CognitoService.confirmSignUp(
                  email: email,
                  confirmationCode: code,
                );

                // Close loading
                if (mounted) Navigator.pop(context);
                // Close verification dialog
                if (mounted) Navigator.pop(context);

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Email verified! Please login.')),
                  );
                }
              } on AuthException catch (e) {
                // Close loading
                if (mounted) Navigator.pop(context);
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(CognitoService.getErrorMessage(e))),
                  );
                }
              } catch (e) {
                // Close loading
                if (mounted) Navigator.pop(context);
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Verification failed: $e')),
                  );
                }
              }
            },
            child: const Text('Verify'),
          ),
        ],
      ),
    );
  }

  void _showLogoutConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await CognitoService.signOut();
                Navigator.pop(context);

                // Navigate to LoginScreen and clear navigation stack
                if (mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
                  );
                }
              } catch (e) {
                Navigator.pop(context);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Logout failed: $e')),
                  );
                }
              }
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  void _showThemeDialog() {
    final provider = Provider.of<ThemeProvider>(context, listen: false);
    showDialog(
      context: context,
      builder: (context) {
        final current = provider.themeMode;
        return AlertDialog(
          title: const Text('Select Theme'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('System'),
                trailing: current == ThemeMode.system ? const Icon(Icons.check) : null,
                onTap: () async {
                  final nav = Navigator.of(context);
                  await provider.setThemeMode(ThemeMode.system);
                  if (!mounted) return;
                  nav.pop();
                  setState(() {});
                },
              ),
              ListTile(
                title: const Text('Light'),
                trailing: current == ThemeMode.light ? const Icon(Icons.check) : null,
                onTap: () async {
                  final nav = Navigator.of(context);
                  await provider.setThemeMode(ThemeMode.light);
                  if (!mounted) return;
                  nav.pop();
                  setState(() {});
                },
              ),
              ListTile(
                title: const Text('Dark'),
                trailing: current == ThemeMode.dark ? const Icon(Icons.check) : null,
                onTap: () async {
                  final nav = Navigator.of(context);
                  await provider.setThemeMode(ThemeMode.dark);
                  if (!mounted) return;
                  nav.pop();
                  setState(() {});
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showColorPicker() {
    final provider = Provider.of<ThemeProvider>(context, listen: false);
    _showColorPickerHSV(context, provider);
  }

  void _showColorPickerHSV(BuildContext context, ThemeProvider provider) {
    Color base = provider.primaryColor;
    showAppColorPicker(
      context: context,
      initialColor: base,
      title: 'Pick Accent Color',
    ).then((picked) async {
      if (picked != null) {
        await provider.setPrimaryColor(picked);
        if (mounted) setState(() {});
      }
    });
  }

  

  Widget _buildSection(String title, List<Widget> tiles) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16.0),
          childrenPadding: const EdgeInsets.only(bottom: 12.0),
          title: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          children: [
            ...tiles,
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsTile(
    String title,
    String subtitle,
    IconData icon,
    VoidCallback onTap, {
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: trailing ?? const Icon(Icons.chevron_right),
          onTap: onTap,
          onLongPress: title == 'Version' ? () => _showSubscriptionModeDialog() : null,
        ),
      ),
    );
  }

  Future<void> _signOut() async {
    try {
      // Attempt Cognito sign out (clears server-side session)
      await CognitoService.signOut();
    } catch (e) {
      // Don't block local cleanup if remote sign-out fails
      debugPrint('Cognito signOut error: $e');
    } finally {
      // Ensure any locally stored user info is cleared
      try {
        await UserAuthService.logout();
        await UserAuthService.clearDeviceToken();
        await UserAuthService.clearEndpointArn();
      } catch (e) {
        debugPrint('Error clearing local user data: $e');
      }

      if (mounted) {
        setState(() {
          _isLoggedIn = false;
          _userEmail = '';
        });

        // Navigate to login and clear navigation stack
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  Widget _buildAuthCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Account',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),

              // Show status
              Text(
                _isLoggedIn
                    ? 'Signed in as ${_userEmail.isEmpty ? 'your account' : _userEmail}'
                    : 'You are not signed in.',
              ),
              const SizedBox(height: 12),

              // Buttons depend on sign-in state
              if (_isLoggedIn) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      await _signOut();
                    },
                    child: const Text('Log out'),
                  ),
                ),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                      );
                    },
                    child: const Text('Log in'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SignUpScreen()),
                      );
                    },
                    child: const Text('Sign up'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showBackupDialog() async {
    try {
      // Gather all data
      final transactions = DatabaseService.getAllTransactions();
      final categories = DatabaseService.getAllCategories();
      final accounts = DatabaseService.getAllAccounts();
      final bills = DatabaseService.getAllBills();

      // Create backup data structure
      final payees = DatabaseService.getAllPayees();
      final settings = DatabaseService.exportAllSettings();
      final billOccurrences = DatabaseService.exportBillOccurrenceStatuses();
      
      final backupData = {
        'version': '1.0.0',
        'timestamp': DateTime.now().toIso8601String(),
        'transactions': transactions.map((t) => t.toJson()).toList(),
        'categories': categories.map((c) => c.toJson()).toList(),
        'accounts': accounts.map((a) => {
          'id': a.id,
          'name': a.name,
          'type': a.type.toString().split('.').last,
          'balance': a.balance,
          'isActive': a.isActive,
          'currency': a.currency,
          'description': a.description,
          'accountNumber': a.accountNumber,
          'availableBalance': a.availableBalance,
          'customType': a.customType,
        }).toList(),
        'bills': bills.map((b) => {
          'id': b.id,
          'amount': b.amount,
          'description': b.description,
          'dueDate': b.dueDate.toIso8601String(),
          'recurrence': b.recurrence.toString().split('.').last,
          'recurrenceInterval': b.recurrenceInterval,
          'recurrenceWeekdays': b.recurrenceWeekdays,
          'customDays': b.customDays,
          'recurrenceEndDate': b.recurrenceEndDate?.toIso8601String(),
          'categoryId': b.categoryId,
          'type': b.type.toString().split('.').last,
          'isPaid': b.isPaid,
          'paymentStatus': b.paymentStatus?.toString().split('.').last,
          'payeeId': b.payeeId,
          'accountId': b.accountId,
          'fromAccountId': b.fromAccountId,
          'toAccountId': b.toAccountId,
        }).toList(),
        'payees': payees,
        'settings': settings,
        'bill_occurrence_status': billOccurrences,
      };

      // Convert to JSON
      final jsonString = const JsonEncoder.withIndent('  ').convert(backupData);
      
      // Get the default filename with timestamp
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
      final defaultFileName = 'cashsense_backup_$timestamp.json';
      
      // Let user choose where to save the file
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Backup File',
        fileName: defaultFileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: utf8.encode(jsonString),
      );
      
      if (outputFile != null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Backup saved successfully!\n$outputFile'),
              backgroundColor: Colors.blueGrey[400],
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating backup: $e'),
            backgroundColor: Colors.blueGrey[400],
          ),
        );
      }
    }
  }

  void _showRestoreDialog() async {
    try {
      // Let user pick a backup file
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Select Backup File',
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: false,
        withReadStream: false,
      );
      
      if (result != null && result.files.single.path != null) {
        // Read the file
        final file = File(result.files.single.path!);
        final jsonString = await file.readAsString();
        
        // Perform restore
        await _performRestore(jsonString);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error reading backup file: $e'),
            backgroundColor: Colors.blueGrey[400],
          ),
        );
      }
    }
  }

  Future<void> _runAutoBackupNow() async {
    // Show a simple progress dialog while backup runs
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: const [
            SizedBox(width: 24, height: 24, child: CircularProgressIndicator()),
            SizedBox(width: 16),
            Expanded(child: Text('Performing backup...')),
          ],
        ),
      ),
    );

    try {
      final path = await AutoBackupService.performBackup();
      if (context.mounted) Navigator.pop(context); // close progress

      if (path != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup created: $path'), backgroundColor: Colors.blueGrey[400]),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('Backup failed'), backgroundColor: Colors.redAccent),
        );
      }
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup error: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _performRestore(String jsonData) async {
    try {
      // Parse JSON
      final Map<String, dynamic> backupData = jsonDecode(jsonData);
      
      // Validate backup data
      if (!backupData.containsKey('version') || !backupData.containsKey('transactions')) {
        throw Exception('Invalid backup data format');
      }

      // Show confirmation
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm Restore'),
          content: Text(
            'This will replace all current data with the backup from ${backupData['timestamp'] ?? 'unknown date'}.\n\n'
            'Transactions: ${(backupData['transactions'] as List).length}\n'
            'Categories: ${(backupData['categories'] as List).length}\n'
            'Accounts: ${(backupData['accounts'] as List).length}\n'
            'Bills: ${(backupData['bills'] as List).length}\n\n'
            'This action cannot be undone. Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Restore', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      // Clear existing data
      await DatabaseService.clearAllData();


      // Restore payees (if present)
      if (backupData.containsKey('payees')) {
        final payees = backupData['payees'] as List;
        for (var payee in payees) {
          if (payee is Map<String, dynamic>) {
            await DatabaseService.addPayee(payee);
          } else if (payee is Map) {
            await DatabaseService.addPayee(Map<String, dynamic>.from(payee));
          }
        }
      }

      // Restore categories first
      for (var catData in backupData['categories'] as List) {
        final category = models.Category(
          id: catData['id'],
          name: catData['name'],
          iconCodePoint: catData['iconCodePoint'] ?? '0xe88a',
          colorValue: catData['colorValue'] ?? '0xFF4CAF50',
          type: catData['type'] == 'income' ? models.CategoryType.income : models.CategoryType.expense,
          isDefault: catData['isDefault'] ?? false,
          budgetLimit: catData['budgetLimit']?.toDouble(),
        );
        await DatabaseService.addCategory(category);
      }

      // Restore accounts
      for (var accData in backupData['accounts'] as List) {
        final account = Account(
          id: accData['id'],
          name: accData['name'],
          type: AccountType.values.firstWhere(
            (e) => e.toString().split('.').last == accData['type'],
            orElse: () => AccountType.bank,
          ),
          balance: accData['balance'].toDouble(),
          isActive: accData['isActive'] ?? true,
          currency: accData['currency'] ?? 'USD',
          description: accData['description'],
          accountNumber: accData['accountNumber'],
          availableBalance: accData['availableBalance'] == null ? null : (accData['availableBalance'] as num).toDouble(),
          customType: accData['customType'],
        );
        await DatabaseService.addAccount(account);
      }

      // Restore transactions
      for (var txData in backupData['transactions'] as List) {
        final transaction = Transaction(
          id: txData['id'],
          amount: txData['amount'].toDouble(),
          type: txData['type'] == 'income' ? TransactionType.income : TransactionType.expense,
          categoryId: txData['categoryId'],
          date: DateTime.parse(txData['date']),
          description: txData['description'],
          note: txData['note'],
          accountId: txData['accountId'],
          billId: txData['billId'],
          payeeId: txData['payeeId'],
          payerId: txData['payerId'],
          cleared: txData['cleared'],
          createdAt: txData['createdAt'] != null ? DateTime.parse(txData['createdAt']) : DateTime.now(),
          isArchived: txData['isArchived'] ?? false,
        );
        await DatabaseService.addTransaction(transaction);
      }

      // Restore bills
      for (var billData in backupData['bills'] as List) {
        final bill = Bill(
          id: billData['id'],
          description: billData['description'],
          amount: billData['amount'].toDouble(),
          dueDate: DateTime.parse(billData['dueDate']),
          recurrence: billData['recurrence'] != null
              ? Recurrence.values.firstWhere(
                  (e) => e.toString().split('.').last == billData['recurrence'],
                  orElse: () => Recurrence.none,
                )
              : Recurrence.none,
          customDays: billData['customDays'] != null ? List<int>.from(billData['customDays']) : null,
          recurrenceEndDate: billData['recurrenceEndDate'] != null ? DateTime.tryParse(billData['recurrenceEndDate']) : null,
          recurrenceInterval: billData['recurrenceInterval'] ?? 1,
          recurrenceWeekdays: billData['recurrenceWeekdays'] != null ? List<int>.from(billData['recurrenceWeekdays']) : null,
          categoryId: billData['categoryId'],
          type: billData['type'] != null
              ? BillType.values.firstWhere(
                  (e) => e.toString().split('.').last == billData['type'],
                  orElse: () => BillType.expense,
                )
              : BillType.expense,
          fromAccountId: billData['fromAccountId'],
          toAccountId: billData['toAccountId'],
          payeeId: billData['payeeId'],
          accountId: billData['accountId'],
          isPaid: billData['isPaid'] ?? false,
          paymentStatus: billData['paymentStatus'] != null
              ? PaymentStatus.values.firstWhere(
                  (e) => e.toString().split('.').last == billData['paymentStatus'],
                  orElse: () => PaymentStatus.unpaid,
                )
              : PaymentStatus.unpaid,
          // per-bill reminder flag removed; global setting controls reminders
        );
        await DatabaseService.addBill(bill);
      }

      // Restore settings (if included)
      if (backupData.containsKey('settings')) {
        final settings = backupData['settings'] as Map<String, dynamic>;
        for (var entry in settings.entries) {
          await DatabaseService.setSetting(entry.key, entry.value);
        }
      }

      // Restore bill occurrence statuses (if included)
      if (backupData.containsKey('bill_occurrence_status')) {
        try {
          final occ = backupData['bill_occurrence_status'] as Map<String, dynamic>;
          await DatabaseService.importBillOccurrenceStatuses(occ);
        } catch (e) {
          // ignore restore failures for occurrence statuses
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Data restored successfully!'),
            backgroundColor: Colors.blueGrey[400],
          ),
        );
        // Refresh the UI
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error restoring data: $e'),
            backgroundColor: Colors.blueGrey[400],
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  void _showClearDataDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Data'),
        content: const Text(
          'This will permanently delete all your transactions, categories, and settings. This action cannot be undone.\n\nAre you sure you want to continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => _confirmClearData(),
            child: const Text(
              'Clear All Data',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmClearData() {
    Navigator.pop(context); // Close the dialog

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Final Confirmation'),
        content: const Text(
          'This is your final warning. All data will be permanently deleted. Are you absolutely sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _clearAllData();
            },
            child: const Text(
              'Yes, Delete Everything',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _clearAllData() async {
    try {
      await DatabaseService.clearAllData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('All data has been cleared'),
            backgroundColor: Colors.blueGrey[400],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error clearing data: $e'),
            backgroundColor: Colors.blueGrey[400],
          ),
        );
      }
    }
  }

  void _showVersionDialog() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final version = packageInfo.version;
    final buildNumber = packageInfo.buildNumber;
    
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About CashSense'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('CashSense'),
            Text('Version $version (Build $buildNumber)'),
            const SizedBox(height: 16),
            const Text('A simple and elegant personal finance tracker designed to help you stay organized and in control of your money.'),
            const SizedBox(height: 16),
            const Text('Features:'),
            const Text('• Transaction tracking'),
            const Text('• Bill tracking & reminders'),
            const Text('• Payment tracking'),
            const Text('• Account management'),
            const Text('• Category management'),
            const Text('• Payee & payer management'),
            const Text('• Financial reports & insights'),
            const Text('• Local data storage'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showPrivacyDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Privacy Policy'),
        content: const SingleChildScrollView(
          child: Text(
            'CashSense Privacy Policy\n\n'
            'Effective Date: 7/20/25\n\n'
            '1. Information We Collect\n\n'
            'CashSense Money Management is designed to help you manage your finances while maintaining the highest level of privacy and security. We collect minimal information necessary to provide our services:\n\n'
            '• Financial Data: Transactions, accounts, budgets, categories, and financial goals you create within the app\n'
            '• Device Information: Basic device identifiers for synchronization across your devices\n'
            '• Usage Analytics: Anonymous data about app features used to improve functionality\n'
            '• Account Information: Basic profile information for app personalization\n\n'
            '2. How We Use Your Information\n\n'
            'Your information is used solely to:\n\n'
            '• Synchronize your financial data across your devices\n'
            '• Provide budgeting insights and spending analysis\n'
            '• Generate financial reports and trends\n'
            '• Improve app performance and user experience\n'
            '• Provide customer support when requested\n\n'
            '3. Data Storage and Security\n\n'
            'We implement the highest level of security measures to protect your sensitive financial data:\n\n'
            '• All data is encrypted using bank-level encryption both in transit and at rest\n'
            '• Your financial data is stored securely on your device and our encrypted servers\n'
            '• We use secure authentication protocols including biometric authentication\n'
            '• Regular security audits and penetration testing ensure ongoing protection\n'
            '• We never store banking credentials or login information\n'
            '• All sensitive data is tokenized for additional security\n\n'
            '4. Data Sharing\n\n'
            'We do not sell, rent, or share your personal financial information with third parties, except:\n\n'
            '• When required by law or legal process\n'
            '• To protect our rights or the safety of our users\n'
            '• With your explicit consent for specific financial institution integrations you choose to enable\n'
            '• With trusted service providers who assist in app functionality (all under strict confidentiality agreements)\n\n'
            '5. Your Rights and Choices\n\n'
            'You have the right to:\n\n'
            '• Access, modify, or delete your personal financial data at any time\n'
            '• Opt out of analytics collection\n'
            '• Request a copy of all data we have about you\n'
            '• Delete your account and all associated data\n'
            '• Control which financial institutions you connect to the app\n'
            '• Export your financial data in standard formats\n\n'
            '6. Data Retention\n\n'
            'We retain your financial data only as long as necessary to provide our services or as required by financial regulations. When you delete your account, all associated data is permanently removed from our servers within 30 days, unless retention is required by law.\n\n'
            '7. Children\'s Privacy\n\n'
            'CashSense Money Management is intended for users 13 years and older. We do not knowingly collect personal financial information from children under 13. If we become aware that we have collected such information, we will take immediate steps to delete it.\n\n'
            '8. Third-Party Integrations\n\n'
            'CashSense may integrate with financial institutions and third-party services to import transaction data. These integrations:\n\n'
            '• Are entirely optional and require your explicit consent\n'
            '• Use read-only access to your financial accounts\n'
            '• Are secured using industry-standard encryption and authentication\n'
            '• Can be revoked at any time through the app settings\n\n'
            '9. International Users\n\n'
            'CashSense complies with applicable privacy laws including GDPR for European users and CCPA for California residents. Users outside the United States should be aware that data may be transferred to and processed in the United States under appropriate safeguards.\n\n'
            '10. Changes to This Policy\n\n'
            'We may update this privacy policy from time to time. We will notify you of any material changes through the app or via email. Your continued use of CashSense after such changes constitutes acceptance of the updated policy.\n\n'
            '11. Contact Us\n\n'
            'If you have any questions about this privacy policy or our data practices, please contact us:\n\n'
            '• Email: support@dhdsoftware.com\n'
            '• Phone: (336)223-5046\n'
            '• Address: DHD Software Development, LLC\n\n'
            'This privacy policy was last updated on 7/20/25. We encourage you to review this policy periodically to stay informed about how we protect your financial information.\n\n'
            '═══════════════════════════════════════════\n\n'
            'APPLE END USER LICENSE AGREEMENT\n\n'
            'Licensed Application End User License Agreement\n\n'
            'This Licensed Application End User License Agreement ("Agreement") is between you and DHD Software Development, LLC ("Application Provider") and governs use of this application made available via the Apple App Store. By installing the CashSense Money Management application, you agree to be bound by this Agreement and understand that there is no tolerance for objectionable content. If you do not agree with the terms and conditions of this Agreement, you are not entitled to use the Application.\n\n'
            '1. Parties\n'
            'This Agreement is between you and Application Provider only, and not Apple, Inc. ("Apple"). Notwithstanding the foregoing, you acknowledge that Apple and its subsidiaries are third-party beneficiaries of this Agreement and Apple has the right to enforce this Agreement against you. Application Provider, not Apple, is solely responsible for the Licensed Application and its content.\n\n'
            '2. Privacy\n'
            'Application Provider may collect and use information about your usage of the Licensed Application, including certain types of information from and about your device. Application Provider may use this information, as long as it is in a form that does not personally identify you, to measure the use and performance of the Licensed Application.\n\n'
            '3. Limited License\n'
            'Application Provider grants you a limited, non-exclusive, non-transferable, revocable license to use the Licensed Application for your personal, non-commercial purposes. You may only use the Licensed Application on Apple devices that you own or control and as permitted by the App Store Terms of Service.\n\n'
            '4. Age Restrictions\n'
            'By using the Licensed Application, you represent and warrant that (a) you are 13 years of age or older and you agree to be bound by this Agreement; (b) if you are under 13 years of age, you have obtained verifiable consent from a parent or legal guardian; and (c) your use of the Licensed Application does not violate any applicable law or regulation. Your access to the Licensed Application may be terminated without warning if Application Provider believes, in its sole discretion, that you are under the age of 13 years and have not obtained verifiable consent from a parent or legal guardian.\n\n'
            '5. Objectionable Content Policy\n'
            'Content may not be submitted to Licensed Application, who will moderate all content and ultimately decide whether or not to post a submission to the extent such content includes, is in conjunction with, or alongside any, Objectionable Content. Objectionable Content includes, but is not limited to: (i) sexually explicit materials; (ii) obscene, defamatory, libelous, slanderous, violent and/or unlawful content or profanity; (iii) content that infringes upon the rights of any third party, including copyright, trademark, privacy, publicity or other personal or proprietary right, or that is deceptive or fraudulent; (iv) content that promotes the use or sale of illegal or regulated substances, tobacco products, ammunition and/or firearms; and (v) gambling, including without limitation, any online casino, sports books, bingo or poker.\n\n'
            '6. Warranty\n'
            'Application Provider warrants that the Licensed Application will function substantially in accordance with the specifications described in the documentation for ninety (90) days from the date of purchase. The Application Provider\'s sole obligation and your exclusive remedy under this warranty shall be, at the Application Provider\'s option, to either (i) attempt to correct any defects or (ii) refund the purchase price, if any. This warranty does not apply to defects caused by abuse, misuse, alteration, or problems with third-party services.\n\n'
            '7. Product Claims\n'
            'Application Provider, not Apple, is responsible for addressing any claims relating to the Licensed Application or use of it, including but not limited to: (i) product liability claims; (ii) any claim that the Licensed Application fails to conform to any applicable legal or regulatory requirement; and (iii) claims arising under consumer protection, privacy, or similar legislation. Nothing in this Agreement shall be deemed an admission that you may have such claims.\n\n'
            '8. Third Party Intellectual Property Claims\n'
            'Application Provider shall not be obligated to indemnify or defend you with respect to any third party claim arising out or relating to the Licensed Application. To the extent Application Provider is required to provide indemnification by applicable law, Application Provider, not Apple, shall be solely responsible for the investigation, defense, settlement and discharge of any claim that the Licensed Application or your use of it infringes any third party intellectual property right.\n\n'
            '9. Maintenance and Support\n'
            'Application Provider is responsible for providing any maintenance and support services with respect to the Licensed Application, as specified in this Agreement, or as required under applicable law. Application Provider and you acknowledge that Apple has no obligation whatsoever to furnish any maintenance and support services with respect to the Licensed Application.\n\n'
            '10. Legal Compliance\n'
            'You represent and warrant that (i) you are not located in a country that is subject to a U.S. Government embargo, or that has been designated by the U.S. Government as a "terrorist supporting" country; and (ii) you are not listed on any U.S. Government list of prohibited or restricted parties.\n\n'
            '11. Contact Information\n'
            'For questions, complaints, or claims with respect to the Licensed Application, please contact:\n\n'
            'DHD Software Development, LLC\n'
            'Email: support@dhdsoftware.com\n'
            'Phone: (336)223-5046\n\n'
            '12. Termination\n'
            'The license is valid until terminated by you or Application Provider. Your rights under this license will terminate automatically and without notice from Application Provider if you fail to adhere to any term(s) of this Agreement. Upon termination of the license, you shall cease all use of the Licensed Application and destroy all copies, full or partial, of the Licensed Application.\n\n'
            '13. Third-Party Terms of Agreement\n'
            'You must comply with applicable third-party terms of agreement when using the Licensed Application, e.g., if you have a VoIP application, then you must not be in violation of their wireless data service agreement when using the Licensed Application.\n\n'
            '14. Third-Party Beneficiary\n'
            'Application Provider and you acknowledge and agree that Apple, and Apple\'s subsidiaries, are third-party beneficiaries of this Agreement, and that, upon your acceptance of the terms and conditions of this Agreement, Apple will have the right (and will be deemed to have accepted the right) to enforce this Agreement against you as a third-party beneficiary thereof.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showTermsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Terms of Service'),
        content: const SingleChildScrollView(
          child: Text(
            'CashSense Money Management Terms of Service\n\n'
            'Effective Date: 7/20/25\n\n'
            'Welcome to CashSense Money Management ("CashSense," "the App," "we," "us," or "our"). These Terms of Service ("Terms") govern your use of the CashSense mobile application and related services provided by DHD Software Development, LLC. By downloading, installing, or using CashSense, you agree to be bound by these Terms.\n\n'
            '1. Acceptance of Terms\n\n'
            'By accessing or using CashSense, you confirm that:\n\n'
            '• You are at least 13 years of age (or the minimum age required in your jurisdiction)\n'
            '• You have the legal capacity to enter into these Terms\n'
            '• You agree to comply with all applicable laws and regulations\n'
            '• If using on behalf of an organization, you have authority to bind that organization to these Terms\n\n'
            '2. Description of Service\n\n'
            'CashSense is a financial management application that allows you to:\n\n'
            '• Track expenses and income transactions\n'
            '• Create and manage budgets and financial goals\n'
            '• Categorize and organize financial data\n'
            '• Generate financial reports and insights\n'
            '• Synchronize financial data across multiple devices\n'
            '• Manage accounts, payees, and payers\n'
            '• Set up watchlists and financial alerts\n'
            '• Use additional features as they become available\n\n'
            'We reserve the right to modify, suspend, or discontinue any aspect of the service at any time with reasonable notice.\n\n'
            '3. User Account and Responsibilities\n\n'
            'When using CashSense, you are responsible for:\n\n'
            '• Providing accurate and complete financial information\n'
            '• Maintaining the security of your account credentials\n'
            '• All activities that occur under your account\n'
            '• Notifying us immediately of any unauthorized use\n'
            '• Using the service only for lawful financial management purposes\n'
            '• Keeping your financial data current and accurate\n'
            '• Safeguarding any linked financial account information\n\n'
            '4. Acceptable Use\n\n'
            'You agree not to use CashSense to:\n\n'
            '• Violate any applicable laws or regulations\n'
            '• Engage in fraudulent or illegal financial activities\n'
            '• Infringe upon the rights of others\n'
            '• Upload or transmit harmful, offensive, or inappropriate content\n'
            '• Attempt to gain unauthorized access to our systems or other users\' data\n'
            '• Interfere with or disrupt the service\n'
            '• Use the service for commercial purposes without authorization\n'
            '• Reverse engineer, decompile, or modify the application\n'
            '• Share or distribute sensitive financial information inappropriately\n\n'
            '5. Financial Data and Privacy\n\n'
            'Your financial privacy is of utmost importance to us. Our collection, use, and protection of your personal financial information is governed by our Privacy Policy, which is incorporated into these Terms by reference. By using CashSense, you also agree to our Privacy Policy.\n\n'
            '• We use bank-level encryption to protect your sensitive financial data\n'
            '• Your financial information is never sold or shared with third parties for marketing purposes\n'
            '• Any financial institution integrations require your explicit consent\n'
            '• You maintain control over your financial data at all times\n\n'
            '6. Intellectual Property Rights\n\n'
            'CashSense and all related content, features, and functionality are owned by DHD Software Development, LLC and are protected by intellectual property laws. You are granted a limited, non-exclusive, non-transferable license to use the application for personal financial management purposes only.\n\n'
            '• You retain ownership of your financial data and content\n'
            '• We retain all rights to the CashSense application and related technology\n'
            '• You may not reproduce, distribute, or create derivative works without permission\n'
            '• The CashSense name, logo, and branding are our exclusive property\n\n'
            '7. Financial Institution Integrations\n\n'
            'CashSense may offer integrations with financial institutions and third-party services:\n\n'
            '• All integrations are optional and require your explicit consent\n'
            '• We use read-only access and industry-standard security protocols\n'
            '• You can revoke access to any integration at any time\n'
            '• We are not responsible for the actions or policies of third-party financial institutions\n'
            '• Integration availability may vary based on your location and financial institution\n\n'
            '8. Service Availability\n\n'
            'While we strive to provide reliable service, we cannot guarantee that CashSense will be available at all times. The service may be subject to:\n\n'
            '• Scheduled maintenance and updates\n'
            '• Technical difficulties or outages\n'
            '• Third-party service dependencies\n'
            '• Financial institution connectivity issues\n'
            '• Force majeure events beyond our control\n\n'
            '9. Financial Disclaimers\n\n'
            'IMPORTANT FINANCIAL DISCLAIMERS:\n\n'
            '• CashSense is a financial management tool, not financial advice\n'
            '• We do not provide investment, tax, or legal advice\n'
            '• You are responsible for verifying the accuracy of all financial data\n'
            '• We recommend consulting with qualified financial professionals for important decisions\n'
            '• Past performance data does not guarantee future results\n'
            '• We are not responsible for financial decisions made based on app data\n\n'
            '10. Limitation of Liability\n\n'
            'TO THE MAXIMUM EXTENT PERMITTED BY LAW:\n\n'
            '• CashSense is provided "as is" without warranties of any kind\n'
            '• We disclaim all warranties, express or implied, including merchantability and fitness for a particular purpose\n'
            '• We are not liable for any indirect, incidental, special, or consequential damages\n'
            '• Our total liability shall not exceed the amount you paid for the service in the past 12 months\n'
            '• We are not responsible for financial losses resulting from app use or data inaccuracies\n'
            '• We implement reasonable backup measures but are not liable for data loss\n\n'
            '11. Indemnification\n\n'
            'You agree to indemnify and hold harmless DHD Software Development, LLC from any claims, damages, or expenses arising from your use of CashSense, your violation of these Terms, your financial decisions, or your violation of any rights of another party.\n\n'
            '12. Data Security and Backup\n\n'
            'We implement industry-leading security measures to protect your financial data:\n\n'
            '• Bank-level encryption for all data transmission and storage\n'
            '• Regular security audits and penetration testing\n'
            '• Secure authentication protocols including biometric options\n\n'
            'However, you are responsible for maintaining secure backups of your important financial data. We recommend regularly exporting your data for your own records.\n\n'
            '13. Termination\n\n'
            'These Terms remain in effect until terminated by either party. We may terminate or suspend your access to CashSense at any time for any reason, including violation of these Terms. You may stop using the service at any time. Upon termination:\n\n'
            '• Your right to use CashSense will cease immediately\n'
            '• You should remove the application from your devices\n'
            '• Data retention will be governed by our Privacy Policy\n'
            '• You may export your financial data before termination\n'
            '• Any linked financial institution connections will be revoked\n\n'
            '14. Updates and Modifications\n\n'
            'We may update these Terms from time to time to reflect changes in our service, legal requirements, or financial regulations. We will notify you of material changes through the app or other reasonable means. Continued use of CashSense after changes constitutes acceptance of the updated Terms.\n\n'
            '15. Governing Law and Dispute Resolution\n\n'
            'These Terms are governed by the laws of [Your State/Country]. Any disputes arising from these Terms or your use of CashSense will be resolved through binding arbitration in accordance with the rules of the American Arbitration Association, except for claims that may be brought in small claims court.\n\n'
            '16. Severability\n\n'
            'If any provision of these Terms is found to be unenforceable or invalid, the remaining provisions will continue in full force and effect. The unenforceable provision will be replaced with an enforceable provision that most closely matches the intent of the original.\n\n'
            '17. Contact Information\n\n'
            'If you have any questions about these Terms of Service, please contact us:\n\n'
            '• Email: support@dhdsoftware.com\n'
            '• Phone: (336) 223-5046\n'
            '• Address: DHD Software Development, LLC\n\n'
            'These Terms of Service were last updated on 7/20/25. We encourage you to review these Terms periodically to stay informed about your rights and obligations when using CashSense Money Management.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // Subscription dialog removed — navigation now opens SubscriptionsScreen.

  // Widget settings dialog removed

  String _getNotificationSummary() {
    // Get notification preferences
    final billReminders = DatabaseService.getSetting<bool>('notif_billReminders', false) ?? false;
  // Only bill reminders are shown in the app for now
  final lowBalance = false;
  final weeklyReports = false;
  final monthlyReports = false;

    // Count enabled notifications
    int enabledCount = 0;
    if (billReminders) enabledCount++;
    
  // other notification types intentionally excluded from UI/count

    if (enabledCount == 0) {
      return 'No notifications enabled';
    } else if (enabledCount == 4) {
      return 'All notifications enabled';
    } else {
      return '$enabledCount notification${enabledCount == 1 ? '' : 's'} enabled';
    }
  }

  void _showNotificationsDialog() async {
    // First show which notifications are currently enabled in the app
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Notification Preferences'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Current notification preferences:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _buildNotificationPreferenceItem('Bill Reminders', 'notif_billReminders'),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              const Text(
                'To manage system notification permissions, open device settings.',
                style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _openNotificationSettings();
            },
            child: const Text('Device Settings'),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationPreferenceItem(String label, String settingKey) {
    final isEnabled = DatabaseService.getSetting<bool>(settingKey, false) ?? false;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            isEnabled ? Icons.check_circle : Icons.cancel,
            color: isEnabled ? Colors.green : Colors.grey,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: isEnabled ? null : Colors.grey,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              await DatabaseService.setSetting(settingKey, !isEnabled);

              if (settingKey == 'notif_billReminders') {
  if (!isEnabled) {
    await BillReminderService().scheduleAllReminders();
  } else {
    await BillReminderService().cancelAllReminders();
  }
}
              // Refresh the dialog
              Navigator.pop(context);
              _showNotificationsDialog();
              // Also refresh the main screen to update the subtitle
              setState(() {});
            },
            child: Text(isEnabled ? 'Disable' : 'Enable'),
          ),
        ],
      ),
    );
  }

  Future<void> _openNotificationSettings() async {
    // Open device notification settings for this app
    String url;
    
    if (Platform.isIOS) {
      // iOS app-specific notification settings
      url = 'app-settings:';
    } else if (Platform.isAndroid) {
      // Android app-specific notification settings
      // Note: This opens the app's notification settings page
      url = 'app-settings://notification';
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notification settings not available on this platform')),
        );
      }
      return;
    }

    try {
      final Uri settingsUri = Uri.parse(url);
      if (await canLaunchUrl(settingsUri)) {
        await launchUrl(settingsUri);
      } else {
        // Fallback: show a dialog with instructions
        if (context.mounted) {
          _showNotificationInstructions();
        }
      }
    } catch (e) {
      // If there's an error, show instructions dialog
      if (context.mounted) {
        _showNotificationInstructions();
      }
    }
  }

  void _showNotificationInstructions() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Notification Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('To manage notifications for CashSense:'),
            const SizedBox(height: 12),
            if (Platform.isIOS) ...[
              const Text('1. Open Settings on your device'),
              const Text('2. Scroll down and tap CashSense'),
              const Text('3. Tap Notifications'),
              const Text('4. Configure your preferences'),
            ] else if (Platform.isAndroid) ...[
              const Text('1. Open Settings on your device'),
              const Text('2. Tap Apps or Application Manager'),
              const Text('3. Find and tap CashSense'),
              const Text('4. Tap Notifications'),
              const Text('5. Configure your preferences'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showArchivedAccountsDialog() {
    final archived = DatabaseService.getArchivedAccounts();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Center(child: Text('Archived Accounts')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: archived.isEmpty
                ? [const Text('No archived accounts')] 
                : archived.map((account) {
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: account.name,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  TextSpan(
                                    text: ' (${account.typeDisplayName})',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                TextButton(
                                  onPressed: () async {
                                    final restored = account.copyWith(isActive: true);
                                    await DatabaseService.updateAccount(restored);

                                    // Restore all transactions for this account
                                    final allTransactions = DatabaseService.getAllTransactions();
                                    for (var tx in allTransactions) {
                                      if (tx.accountId == account.id && tx.isArchived == true) {
                                        final restoredTx = tx.copyWith(isArchived: false);
                                        await DatabaseService.updateTransaction(restoredTx);
                                      }
                                    }

                                    if (mounted) Navigator.pop(context);
                                  },
                                  child: const Text('Restore'),
                                ),
                                const SizedBox(width: 8),
                                TextButton(
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Delete Account'),
                                        content: const Text('Are you sure you want to permanently delete this archived account? This action cannot be undone.'),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(context, false),
                                            child: const Text('Cancel'),
                                          ),
                                          TextButton(
                                            onPressed: () => Navigator.pop(context, true),
                                            child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      await DatabaseService.deleteAccount(account.id);
                                      if (mounted) Navigator.pop(context);
                                    }
                                  },
                                  child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  void _showRateAppDialog() async {
    await _openRatingPage();
  }

  Future<void> _openRatingPage() async {
    // Define your app's store URLs
    const iosAppStoreUrl = 'https://apps.apple.com/app/id6741378616'; // App Store ID provided by user
    const androidPlayStoreUrl = 'https://play.google.com/store/apps/details?id=com.example.cashsense'; // Replace with your actual package name

    if (Platform.isIOS) {
      // Prefer the itms-apps scheme to open the App Store directly to the review page.
      // Format: itms-apps://apps.apple.com/app/id<APP_ID>?action=write-review
      final Uri itmsReviewUri = Uri.parse('itms-apps://apps.apple.com/app/id6741378616?action=write-review');
      final Uri httpsReviewUri = Uri.parse(iosAppStoreUrl);

      // Try to open App Store via itms-apps first, fall back to https if that fails.
      if (await canLaunchUrl(itmsReviewUri)) {
        await launchUrl(itmsReviewUri, mode: LaunchMode.externalApplication);
        return;
      }

      if (await canLaunchUrl(httpsReviewUri)) {
        await launchUrl(httpsReviewUri, mode: LaunchMode.externalApplication);
        return;
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open App Store')));
      }
      return;
    } else if (Platform.isAndroid) {
      final Uri playUri = Uri.parse(androidPlayStoreUrl);
      if (await canLaunchUrl(playUri)) {
        await launchUrl(playUri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open Play Store')));
        }
      }
      return;
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('App store not available on this platform')),
        );
      }
      return;
    }
  }
}
