import 'account_operations.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'user_api_service.dart';

/// Fresh server membership is required for each cloud action.
/// S3 permissions must independently enforce ownership and entitlement.
class BackupAccessService {
  static Future<String> requireCloudAccess() {
    return AccountOperations.run(() async {
    final before = (await Amplify.Auth.getCurrentUser()).userId;
    final user = await UserApiService.fetchCurrentUser();
    final after = (await Amplify.Auth.getCurrentUser()).userId;
    if (before.isEmpty || before != after || user.userId != before) {
      throw StateError('The signed-in account changed. Please try again.');
    }
    final expiry = user.premiumUntil;
    final source = user.premiumSource;
    final verifiedMembership = user.isPremium &&
        user.premiumStatus == 'active' &&
        (source == 'apple' || source == 'google') &&
        expiry > DateTime.now().millisecondsSinceEpoch ~/ 1000 &&
        expiry < 100000000000;
    if (!user.devOverride && !user.testerOverride && !verifiedMembership) {
      throw StateError('An active server-confirmed Premium membership is required.');
    }
    return before;
      });
  }

  static Future<void> requireSameAccount(String expected) {
    return AccountOperations.run(() async {
    if ((await Amplify.Auth.getCurrentUser()).userId != expected) {
      throw StateError('The signed-in account changed. Please try again.');
    }
      });
  }
}
