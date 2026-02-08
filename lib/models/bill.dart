
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
part 'bill.g.dart';

@HiveType(typeId: 8)
enum PaymentStatus {
  @HiveField(0)
  paid,
  @HiveField(1)
  unpaid,
  @HiveField(2)
  partial,
}

@HiveType(typeId: 5)
enum Recurrence {
  @HiveField(0)
  none,
  @HiveField(1)
  daily,
  @HiveField(2)
  weekly,
  @HiveField(3)
  monthly,
  @HiveField(4)
  yearly,
  @HiveField(5)
  custom,
}

@HiveType(typeId: 7)
enum BillType {
  @HiveField(0)
  expense,
  @HiveField(1)
  income,
  @HiveField(2)
  transfer,
}

@HiveType(typeId: 6)
class Bill extends HiveObject {
  static DateTime _parseDateOnly(dynamic raw) {
    final value = raw?.toString();
    if (value == null || value.isEmpty) return DateTime.now();

    final dateOnly = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(value);
    if (dateOnly != null) {
      final yyyy = int.parse(dateOnly.group(1)!);
      final mm = int.parse(dateOnly.group(2)!);
      final dd = int.parse(dateOnly.group(3)!);
      return DateTime(yyyy, mm, dd);
    }

    final parsed = DateTime.parse(value);
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  @HiveField(0)
  String id;

  @HiveField(1)
  double amount;

  @HiveField(2)
  String? description;

  @HiveField(3)
  DateTime dueDate;

  @HiveField(4)
  Recurrence recurrence;

  @HiveField(9)
  List<int>? customDays;

  @HiveField(10)
  DateTime? recurrenceEndDate;

  @HiveField(11)
  int recurrenceInterval;

  @HiveField(12)
  List<int>? recurrenceWeekdays;

  @HiveField(13)
  String? categoryId;

  @HiveField(14)
  BillType type;

  @HiveField(15)
  String? fromAccountId;

  @HiveField(16)
  String? toAccountId;

  @HiveField(5)
  String? payeeId;

  @HiveField(6)
  String? accountId;

  @HiveField(7)
  bool isPaid;

  @HiveField(17)
  PaymentStatus? paymentStatus;

  Bill({
    String? id,
    required this.amount,
    this.description,
    required this.dueDate,
    this.recurrence = Recurrence.none,
    this.customDays,
    this.recurrenceEndDate,
    this.recurrenceInterval = 1,
    this.recurrenceWeekdays,
    this.categoryId,
    this.type = BillType.expense,
    this.fromAccountId,
    this.toAccountId,
    this.payeeId,
    this.accountId,
    this.isPaid = false,
    this.paymentStatus = PaymentStatus.unpaid,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'amount': amount,
      'description': description,
      'dueDate': dueDate.toIso8601String(),
      'recurrence': recurrence.name,
      'customDays': customDays,
      'recurrenceEndDate': recurrenceEndDate?.toIso8601String(),
      'recurrenceInterval': recurrenceInterval,
      'recurrenceWeekdays': recurrenceWeekdays,
      'categoryId': categoryId,
      'type': type.name,
      'isPaid': isPaid,
      'paymentStatus': paymentStatus?.name,
      'payeeId': payeeId,
      'accountId': accountId,
      'fromAccountId': fromAccountId,
      'toAccountId': toAccountId,
    };
  }

  factory Bill.fromJson(Map<String, dynamic> json) {
    final recurrenceName = json['recurrence']?.toString() ?? Recurrence.none.name;
    final typeName = json['type']?.toString() ?? BillType.expense.name;
    final paymentName = json['paymentStatus']?.toString();
    return Bill(
      id: json['id'] ?? json['billId'],
      amount: (json['amount'] as num).toDouble(),
      description: json['description'],
      dueDate: _parseDateOnly(json['dueDate']),
      recurrence: Recurrence.values.firstWhere(
        (e) => e.name == recurrenceName,
        orElse: () => Recurrence.none,
      ),
      customDays: (json['customDays'] as List?)?.map((e) => (e as num).toInt()).toList(),
      recurrenceEndDate: json['recurrenceEndDate'] != null
          ? _parseDateOnly(json['recurrenceEndDate'])
          : null,
      recurrenceInterval: json['recurrenceInterval'] ?? 1,
      recurrenceWeekdays: (json['recurrenceWeekdays'] as List?)?.map((e) => (e as num).toInt()).toList(),
      categoryId: json['categoryId'],
      type: BillType.values.firstWhere(
        (e) => e.name == typeName,
        orElse: () => BillType.expense,
      ),
      fromAccountId: json['fromAccountId'],
      toAccountId: json['toAccountId'],
      payeeId: json['payeeId'],
      accountId: json['accountId'],
      isPaid: json['isPaid'] ?? false,
      paymentStatus: paymentName == null
          ? PaymentStatus.unpaid
          : PaymentStatus.values.firstWhere(
              (e) => e.name == paymentName,
              orElse: () => PaymentStatus.unpaid,
            ),
    );
  }

  Bill copyWith({
    String? id,
    double? amount,
    String? description,
    DateTime? dueDate,
    Recurrence? recurrence,
    List<int>? customDays,
    int? recurrenceInterval,
    List<int>? recurrenceWeekdays,
    String? categoryId,
    BillType? type,
    String? fromAccountId,
    String? toAccountId,
    String? payeeId,
    String? accountId,
    bool? isPaid,
    PaymentStatus? paymentStatus,
    DateTime? recurrenceEndDate,
  }) {
    return Bill(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      description: description ?? this.description,
      dueDate: dueDate ?? this.dueDate,
      recurrence: recurrence ?? this.recurrence,
      customDays: customDays ?? this.customDays,
      recurrenceInterval: recurrenceInterval ?? this.recurrenceInterval,
      recurrenceWeekdays: recurrenceWeekdays ?? this.recurrenceWeekdays,
      categoryId: categoryId ?? this.categoryId,
      type: type ?? this.type,
      fromAccountId: fromAccountId ?? this.fromAccountId,
      toAccountId: toAccountId ?? this.toAccountId,
      payeeId: payeeId ?? this.payeeId,
      accountId: accountId ?? this.accountId,
      isPaid: isPaid ?? this.isPaid,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      recurrenceEndDate: recurrenceEndDate ?? this.recurrenceEndDate,
    );
  }
}
