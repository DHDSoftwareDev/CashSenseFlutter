import 'package:flutter/foundation.dart';

import '../models/cashsense_user.dart';
import '../services/user_api_service.dart';

class UserSessionController extends ChangeNotifier {
  final CashSenseUserApi api;

  UserSessionController({required this.api});

  CashSenseUser? currentUser;
  bool isLoadingUser = false;

  bool get isPremium => currentUser?.isPremium ?? false;
  String get tier => currentUser?.tier ?? 'free';

  Future<void> refreshUser({
    required String idToken,
  }) async {
    isLoadingUser = true;
    notifyListeners();

    try {
      currentUser = await api.getCurrentUser(idToken: idToken);
    } finally {
      isLoadingUser = false;
      notifyListeners();
    }
  }

  void clear() {
    currentUser = null;
    notifyListeners();
  }
}