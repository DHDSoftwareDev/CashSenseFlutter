// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bill.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class BillAdapter extends TypeAdapter<Bill> {
  @override
  final int typeId = 6;

  @override
  Bill read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Bill(
      id: fields[0] as String?,
      amount: fields[1] as double,
      description: fields[2] as String?,
      dueDate: fields[3] as DateTime,
      recurrence: fields[4] as Recurrence,
      customDays: (fields[9] as List?)?.cast<int>(),
      recurrenceEndDate: fields[10] as DateTime?,
      recurrenceInterval: fields[11] as int,
      recurrenceWeekdays: (fields[12] as List?)?.cast<int>(),
      categoryId: fields[13] as String?,
      type: fields[14] as BillType,
      fromAccountId: fields[15] as String?,
      toAccountId: fields[16] as String?,
      payeeId: fields[5] as String?,
      accountId: fields[6] as String?,
      isPaid: fields[7] as bool,
      paymentStatus: fields[17] as PaymentStatus?,
    );
  }

  @override
  void write(BinaryWriter writer, Bill obj) {
    writer
      ..writeByte(17)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.amount)
      ..writeByte(2)
      ..write(obj.description)
      ..writeByte(3)
      ..write(obj.dueDate)
      ..writeByte(4)
      ..write(obj.recurrence)
      ..writeByte(9)
      ..write(obj.customDays)
      ..writeByte(10)
      ..write(obj.recurrenceEndDate)
      ..writeByte(11)
      ..write(obj.recurrenceInterval)
      ..writeByte(12)
      ..write(obj.recurrenceWeekdays)
      ..writeByte(13)
      ..write(obj.categoryId)
      ..writeByte(14)
      ..write(obj.type)
      ..writeByte(15)
      ..write(obj.fromAccountId)
      ..writeByte(16)
      ..write(obj.toAccountId)
      ..writeByte(5)
      ..write(obj.payeeId)
      ..writeByte(6)
      ..write(obj.accountId)
      ..writeByte(7)
      ..write(obj.isPaid)
      ..writeByte(17)
      ..write(obj.paymentStatus)
      ;
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BillAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class PaymentStatusAdapter extends TypeAdapter<PaymentStatus> {
  @override
  final int typeId = 8;

  @override
  PaymentStatus read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return PaymentStatus.paid;
      case 1:
        return PaymentStatus.unpaid;
      case 2:
        return PaymentStatus.partial;
      default:
        return PaymentStatus.paid;
    }
  }

  @override
  void write(BinaryWriter writer, PaymentStatus obj) {
    switch (obj) {
      case PaymentStatus.paid:
        writer.writeByte(0);
        break;
      case PaymentStatus.unpaid:
        writer.writeByte(1);
        break;
      case PaymentStatus.partial:
        writer.writeByte(2);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PaymentStatusAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class RecurrenceAdapter extends TypeAdapter<Recurrence> {
  @override
  final int typeId = 5;

  @override
  Recurrence read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return Recurrence.none;
      case 1:
        return Recurrence.daily;
      case 2:
        return Recurrence.weekly;
      case 3:
        return Recurrence.monthly;
      case 4:
        return Recurrence.yearly;
      case 5:
        return Recurrence.custom;
      default:
        return Recurrence.none;
    }
  }

  @override
  void write(BinaryWriter writer, Recurrence obj) {
    switch (obj) {
      case Recurrence.none:
        writer.writeByte(0);
        break;
      case Recurrence.daily:
        writer.writeByte(1);
        break;
      case Recurrence.weekly:
        writer.writeByte(2);
        break;
      case Recurrence.monthly:
        writer.writeByte(3);
        break;
      case Recurrence.yearly:
        writer.writeByte(4);
        break;
      case Recurrence.custom:
        writer.writeByte(5);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecurrenceAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class BillTypeAdapter extends TypeAdapter<BillType> {
  @override
  final int typeId = 7;

  @override
  BillType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return BillType.expense;
      case 1:
        return BillType.income;
      case 2:
        return BillType.transfer;
      default:
        return BillType.expense;
    }
  }

  @override
  void write(BinaryWriter writer, BillType obj) {
    switch (obj) {
      case BillType.expense:
        writer.writeByte(0);
        break;
      case BillType.income:
        writer.writeByte(1);
        break;
      case BillType.transfer:
        writer.writeByte(2);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BillTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
