import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

part 'transaction.g.dart';

@HiveType(typeId: 0)
enum TransactionType {
  @HiveField(0)
  income,
  @HiveField(1)
  expense,
}

@HiveType(typeId: 1)

class Transaction extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  double amount;

  @HiveField(2)
  String categoryId;

  @HiveField(3)
  TransactionType type;

  @HiveField(4)
  String description;

  @HiveField(5)
  DateTime date;

  @HiveField(6)
  String? note;

  @HiveField(7)
  String? accountId;

  @HiveField(8)
  bool? cleared;

  @HiveField(9)
  DateTime createdAt;

  @HiveField(10)
  bool isArchived;

  // New fields for payee and payer
  @HiveField(11)
  String? payeeId;

  @HiveField(12)
  String? payerId;
  
    // Bill ID for bill-related transactions
    @HiveField(13)
    String? billId;
  
    // Optional occurrence date linking this transaction to a specific bill occurrence
    @HiveField(14)
    DateTime? occurrenceDate;
  
    // Optional JSON-encoded splits for this transaction. Format:
    // '[{"categoryId":"id1","amount":10.0},{"categoryId":"id2","amount":5.0}]'
    // When present, the transaction represents a single logical transaction
    // whose amount is allocated across multiple categories.
    @HiveField(15)
    String? splitsJson;

    @HiveField(16)
    bool showInReports;

  Transaction({
    String? id,
    required this.amount,
    required this.categoryId,
    required this.type,
    required this.description,
    required this.date,
    DateTime? createdAt,
    this.note,
    this.accountId,
    this.cleared,
    this.isArchived = false,
    this.payeeId,
    this.payerId,
      this.billId,
      this.occurrenceDate,
      this.splitsJson,
      this.showInReports = true,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'amount': amount,
      'categoryId': categoryId,
      'splitsJson': splitsJson,
      'type': type.name,
      'description': description,
      'date': date.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'note': note,
      'accountId': accountId,
      'cleared': cleared,
      'isArchived': isArchived,
      'payeeId': payeeId,
      'payerId': payerId,
        'billId': billId,
        'occurrenceDate': occurrenceDate?.toIso8601String(),
      'showInReports': showInReports,
    };
  }

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: json['id'],
      amount: json['amount'].toDouble(),
      categoryId: json['categoryId'],
      type: TransactionType.values.firstWhere(
        (e) => e.name == json['type'],
      ),
      description: json['description'],
      date: DateTime.parse(json['date']),
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : DateTime.now(),
      note: json['note'],
      accountId: json['accountId'],
      cleared: json['cleared'],
      isArchived: json['isArchived'] ?? false,
      payeeId: json['payeeId'],
      payerId: json['payerId'],
        billId: json['billId'],
        occurrenceDate: json['occurrenceDate'] != null ? DateTime.parse(json['occurrenceDate']) : null,
        splitsJson: json['splitsJson'] as String?,
      showInReports: json['showInReports'] as bool? ?? true,
    );
  }

  Transaction copyWith({
    String? id,
    double? amount,
    String? categoryId,
    TransactionType? type,
    String? description,
    DateTime? date,
    String? note,
    String? accountId,
    bool? cleared,
    bool? isArchived,
    String? payeeId,
    String? payerId,
      String? billId,
      DateTime? occurrenceDate,
      String? splitsJson,
      bool? showInReports,
  }) {
    return Transaction(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      categoryId: categoryId ?? this.categoryId,
      type: type ?? this.type,
      description: description ?? this.description,
      date: date ?? this.date,
      note: note ?? this.note,
      accountId: accountId ?? this.accountId,
      cleared: cleared ?? this.cleared,
      isArchived: isArchived ?? this.isArchived,
      payeeId: payeeId ?? this.payeeId,
      payerId: payerId ?? this.payerId,
        billId: billId ?? this.billId,
        occurrenceDate: occurrenceDate ?? this.occurrenceDate,
        splitsJson: splitsJson ?? this.splitsJson,
      showInReports: showInReports ?? this.showInReports,
    );
  }
}