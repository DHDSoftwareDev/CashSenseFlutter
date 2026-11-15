import 'package:amplify_flutter/amplify_flutter.dart';
import 'cognito_service.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_api/amplify_api.dart';
import '../amplifyconfiguration.dart';

// Configure Amplify (call from main.dart once at startup)
Future<void> configureAmplifyIfNeeded() async {
  try {
    if (!Amplify.isConfigured) {
      await Amplify.addPlugins([
        AmplifyAuthCognito(),
        AmplifyAPI(),
      ]);
      await Amplify.configure(amplifyconfig);
      safePrint('Amplify configured');
    }
  } catch (e) {
    safePrint('Error configuring Amplify: $e');
  }
}

// Sign up a new user
Future<void> signUp(String email, String password) async {
  try {
    final result = await Amplify.Auth.signUp(
      username: email,
      password: password,
      options: SignUpOptions(userAttributes: {
        CognitoUserAttributeKey.email: email,
      }),
    );

    if (result.isSignUpComplete) {
      safePrint('Sign up successful!');
    } else {
      safePrint('Confirm sign up with code sent to email');
    }
  } catch (e) {
    safePrint('Sign up error: $e');
  }
}

// Confirm sign up with verification code
Future<void> confirmSignUp(String email, String code) async {
  try {
    final res = await Amplify.Auth.confirmSignUp(
      username: email,
      confirmationCode: code,
    );
    if (res.isSignUpComplete) {
      safePrint('Sign up confirmed!');
    } else {
      safePrint('Sign up confirmation requires additional steps');
    }
  } catch (e) {
    safePrint('Confirmation error: $e');
  }
}

// Sign in
Future<void> signIn(String email, String password) async {
  try {
    final result = await CognitoService.signIn(
      email: email,
      password: password,
    );

    if (result.isSignedIn) {
      safePrint('Sign in successful!');
    } else {
      safePrint('Sign in not complete: ${result.nextStep}');
    }
  } catch (e) {
    safePrint('Sign in error: $e');
  }
}

// Sign out
Future<void> signOut() async {
  try {
    await CognitoService.signOut();
    safePrint('Signed out!');
  } catch (e) {
    safePrint('Sign out error: $e');
  }
}

// Call your API (after signing in)
Future<void> getAccounts() async {
  try {
    final response = await Amplify.API.get('/accounts').response;
    final data = response.decodeBody();
    safePrint('Accounts: $data');
  } catch (e) {
    safePrint('API error: $e');
  }
}
