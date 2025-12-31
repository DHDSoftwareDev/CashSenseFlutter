import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

part 'account.g.dart';

@HiveType(typeId: 3)
enum AccountType {
  @HiveField(0)
  cash,
  @HiveField(1)
  bank,
  @HiveField(2)
  card,
  @HiveField(3)
  investment,
}

@HiveType(typeId: 4)
class Account extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  AccountType type;

  @HiveField(3)
  double balance;

  @HiveField(4)
  String currency;

  @HiveField(5)
  bool isActive;

  @HiveField(6)
  String? description;

  @HiveField(7)
  String? accountNumber;

  @HiveField(8)
  double? availableBalance;

  @HiveField(9)
  String? customType;

  Account({
    String? id,
    required this.name,
    required this.type,
    this.balance = 0.0,
    this.currency = 'USD',
    this.isActive = true,
    this.description,
    this.accountNumber,
    this.availableBalance,
    this.customType,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'balance': balance,
      'currency': currency,
      'isActive': isActive,
      'description': description,
      'accountNumber': accountNumber,
      'availableBalance': availableBalance,
      'customType': customType,
    };
  }

  factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      id: json['id'],
      name: json['name'],
      type: AccountType.values.firstWhere(
        (e) => e.name == json['type'],
      ),
      balance: json['balance'].toDouble(),
      currency: json['currency'],
      isActive: json['isActive'] ?? true,
      description: json['description'],
      accountNumber: json['accountNumber'],
      availableBalance: json['availableBalance'] == null ? null : (json['availableBalance'] as num).toDouble(),
      customType: json['customType'],
    );
  }

  Account copyWith({
    String? id,
    String? name,
    AccountType? type,
    double? balance,
    String? currency,
    bool? isActive,
    String? description,
    String? accountNumber,
    double? availableBalance,
    String? customType,
  }) {
    return Account(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      balance: balance ?? this.balance,
      currency: currency ?? this.currency,
      isActive: isActive ?? this.isActive,
      description: description ?? this.description,
      accountNumber: accountNumber ?? this.accountNumber,
      availableBalance: availableBalance ?? this.availableBalance,
      customType: customType ?? this.customType,
    );
  }

  String get typeDisplayName {
    if (customType != null && customType!.isNotEmpty) {
      return customType![0].toUpperCase() + customType!.substring(1);
    }
    switch (type) {
      case AccountType.cash:
        return 'Cash';
      case AccountType.bank:
        return 'Checking';
      case AccountType.card:
        return 'Card';
      case AccountType.investment:
        return 'Savings';
    }
  }
}