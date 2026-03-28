
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
  static const Object _unset = Object();

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
    Object? description = _unset,
    DateTime? dueDate,
    Recurrence? recurrence,
    Object? customDays = _unset,
    int? recurrenceInterval,
    Object? recurrenceWeekdays = _unset,
    Object? categoryId = _unset,
    BillType? type,
    Object? fromAccountId = _unset,
    Object? toAccountId = _unset,
    Object? payeeId = _unset,
    Object? accountId = _unset,
    bool? isPaid,
    Object? paymentStatus = _unset,
    Object? recurrenceEndDate = _unset,
  }) {
    return Bill(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      description: identical(description, _unset) ? this.description : description as String?,
      dueDate: dueDate ?? this.dueDate,
      recurrence: recurrence ?? this.recurrence,
      customDays: identical(customDays, _unset) ? this.customDays : customDays as List<int>?,
      recurrenceInterval: recurrenceInterval ?? this.recurrenceInterval,
      recurrenceWeekdays: identical(recurrenceWeekdays, _unset) ? this.recurrenceWeekdays : recurrenceWeekdays as List<int>?,
      categoryId: identical(categoryId, _unset) ? this.categoryId : categoryId as String?,
      type: type ?? this.type,
      fromAccountId: identical(fromAccountId, _unset) ? this.fromAccountId : fromAccountId as String?,
      toAccountId: identical(toAccountId, _unset) ? this.toAccountId : toAccountId as String?,
      payeeId: identical(payeeId, _unset) ? this.payeeId : payeeId as String?,
      accountId: identical(accountId, _unset) ? this.accountId : accountId as String?,
      isPaid: isPaid ?? this.isPaid,
      paymentStatus: identical(paymentStatus, _unset) ? this.paymentStatus : paymentStatus as PaymentStatus?,
      recurrenceEndDate: identical(recurrenceEndDate, _unset) ? this.recurrenceEndDate : recurrenceEndDate as DateTime?,
    );
  }
}
