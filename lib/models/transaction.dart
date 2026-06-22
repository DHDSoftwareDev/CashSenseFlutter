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
  static const Object _unset = Object();

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

  @HiveField(17)
  bool hideFromCalendarDashboard;

  @HiveField(18)
  String? categoryName;

  @HiveField(19)
  String? payeeName;

  @HiveField(20)
  String? payerName;

  @HiveField(21)
  DateTime updatedAt;

  @HiveField(22)
  String? paymentFor;

  Transaction({
    String? id,
    required this.amount,
    required this.categoryId,
    required this.type,
    required this.description,
    required this.date,
    DateTime? createdAt,
    DateTime? updatedAt,
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
    this.hideFromCalendarDashboard = false,
    this.categoryName,
    this.payeeName,
    this.payerName,
    this.paymentFor,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'amount': amount,
      'categoryId': categoryId,
      'categoryName': categoryName,
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
      'payeeName': payeeName,
      'payerId': payerId,
      'payerName': payerName,
      'billId': billId,
      'occurrenceDate': occurrenceDate?.toIso8601String(),
      'showInReports': showInReports,
      'hideFromCalendarDashboard': hideFromCalendarDashboard,
      'updatedAt': updatedAt.toIso8601String(),
      'paymentFor': paymentFor,
    };
  }

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: json['id'],
      amount: json['amount'].toDouble(),
      categoryId: json['categoryId'],
      categoryName: json['categoryName'] as String?,
      type: TransactionType.values.firstWhere((e) => e.name == json['type']),
      description: json['description'],
      date: DateTime.parse(json['date']),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      note: json['note'],
      accountId: json['accountId'],
      cleared: json['cleared'],
      isArchived: json['isArchived'] ?? false,
      payeeId: json['payeeId'],
      payeeName: json['payeeName'] as String?,
      payerId: json['payerId'],
      payerName: json['payerName'] as String?,
      billId: json['billId'],
      occurrenceDate: json['occurrenceDate'] != null
          ? DateTime.parse(json['occurrenceDate'])
          : null,
      splitsJson: json['splitsJson'] as String?,
      showInReports: json['showInReports'] as bool? ?? true,
      hideFromCalendarDashboard:
          json['hideFromCalendarDashboard'] as bool? ?? false,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : DateTime.now(),
      paymentFor: json['paymentFor'] as String?,
    );
  }

  Transaction copyWith({
    String? id,
    double? amount,
    String? categoryId,
    Object? categoryName = _unset,
    TransactionType? type,
    String? description,
    DateTime? date,
    DateTime? updatedAt,
    Object? note = _unset,
    Object? accountId = _unset,
    bool? cleared,
    bool? isArchived,
    Object? payeeId = _unset,
    Object? payeeName = _unset,
    Object? payerId = _unset,
    Object? payerName = _unset,
    Object? paymentFor = _unset,
    Object? billId = _unset,
    Object? occurrenceDate = _unset,
    Object? splitsJson = _unset,
    bool? showInReports,
    bool? hideFromCalendarDashboard,
  }) {
    return Transaction(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      categoryId: categoryId ?? this.categoryId,
      categoryName: identical(categoryName, _unset)
          ? this.categoryName
          : categoryName as String?,
      type: type ?? this.type,
      description: description ?? this.description,
      date: date ?? this.date,
      updatedAt: updatedAt ?? this.updatedAt,
      note: identical(note, _unset) ? this.note : note as String?,
      accountId: identical(accountId, _unset)
          ? this.accountId
          : accountId as String?,
      cleared: cleared ?? this.cleared,
      isArchived: isArchived ?? this.isArchived,
      payeeId: identical(payeeId, _unset) ? this.payeeId : payeeId as String?,
      payeeName: identical(payeeName, _unset)
          ? this.payeeName
          : payeeName as String?,
      payerId: identical(payerId, _unset) ? this.payerId : payerId as String?,
      payerName: identical(payerName, _unset)
          ? this.payerName
          : payerName as String?,
      paymentFor: identical(paymentFor, _unset)
          ? this.paymentFor
          : paymentFor as String?,
      billId: identical(billId, _unset) ? this.billId : billId as String?,
      occurrenceDate: identical(occurrenceDate, _unset)
          ? this.occurrenceDate
          : occurrenceDate as DateTime?,
      splitsJson: identical(splitsJson, _unset)
          ? this.splitsJson
          : splitsJson as String?,
      showInReports: showInReports ?? this.showInReports,
      hideFromCalendarDashboard:
          hideFromCalendarDashboard ?? this.hideFromCalendarDashboard,
    );
  }
}
