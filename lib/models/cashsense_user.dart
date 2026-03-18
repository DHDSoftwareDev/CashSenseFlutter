class CashSenseUser {
  final String userId;
  final String email;
  final String name;
  final String tier;
  final bool isPremium;
  final String premiumStatus;
  final String? premiumSource;
  final int premiumUntil;
  final int trialEndsAt;
  final bool devOverride;
  final bool testerOverride;
  final String? createdAt;
  final String? updatedAt;

  const CashSenseUser({
    required this.userId,
    required this.email,
    required this.name,
    required this.tier,
    required this.isPremium,
    required this.premiumStatus,
    required this.premiumSource,
    required this.premiumUntil,
    required this.trialEndsAt,
    required this.devOverride,
    required this.testerOverride,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CashSenseUser.fromJson(Map<String, dynamic> json) {
    return CashSenseUser(
      userId: json['userId']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      tier: json['tier']?.toString() ?? 'free',
      isPremium: json['isPremium'] == true,
      premiumStatus: json['premiumStatus']?.toString() ?? 'inactive',
      premiumSource: json['premiumSource']?.toString(),
      premiumUntil: (json['premiumUntil'] as num?)?.toInt() ?? 0,
      trialEndsAt: (json['trialEndsAt'] as num?)?.toInt() ?? 0,
      devOverride: json['devOverride'] == true,
      testerOverride: json['testerOverride'] == true,
      createdAt: json['createdAt']?.toString(),
      updatedAt: json['updatedAt']?.toString(),
    );
  }
}