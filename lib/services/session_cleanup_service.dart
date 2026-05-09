import 'package:flutter/foundation.dart';

import '../providers/user_session_controller.dart';
import 'cognito_service.dart';
import 'database_service.dart';
import 'user_auth_service.dart';

class SessionCleanupService {
  static Future<void> clearInvalidatedBackendUser({
    UserSessionController? userSession,
  }) async {
    try {
      await CognitoService.signOut();
    } catch (e) {
      debugPrint('Cognito signOut after backend user invalidation failed: $e');
    }

    userSession?.clear();

    try {
      await UserAuthService.logout();
      await UserAuthService.clearDeviceToken();
      await UserAuthService.clearEndpointArn();
    } catch (e) {
      debugPrint(
        'Local user cleanup after backend user invalidation failed: $e',
      );
    }

    try {
      await DatabaseService.setSubscriptionPlan('Free');
    } catch (e) {
      debugPrint(
        'Subscription reset after backend user invalidation failed: $e',
      );
    }
  }
}
