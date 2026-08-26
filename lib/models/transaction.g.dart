// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transaction.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TransactionAdapter extends TypeAdapter<Transaction> {
  @override
  final int typeId = 1;

  @override
  Transaction read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Transaction(
      id: fields[0] as String?,
      amount: fields[1] as double,
      categoryId: fields[2] as String,
      type: fields[3] as TransactionType,
      description: fields[4] as String,
      date: fields[5] as DateTime,
      createdAt: fields[9] as DateTime?,
      updatedAt: fields[21] as DateTime?,
      note: fields[6] as String?,
      accountId: fields[7] as String?,
      cleared: fields[8] as bool?,
      isArchived: fields[10] as bool,
      payeeId: fields[11] as String?,
      payerId: fields[12] as String?,
      billId: fields[13] as String?,
      occurrenceDate: fields[14] as DateTime?,
      splitsJson: fields[15] as String?,
      showInReports: fields[16] as bool,
      hideFromCalendarDashboard: fields[17] as bool,
      categoryName: fields[18] as String?,
      payeeName: fields[19] as String?,
      payerName: fields[20] as String?,
      paymentFor: fields[22] as String?,
      sortOrder: fields[23] as int?,
    );
  }

  @override
  void write(BinaryWriter writer, Transaction obj) {
    writer
      ..writeByte(24)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.amount)
      ..writeByte(2)
      ..write(obj.categoryId)
      ..writeByte(3)
      ..write(obj.type)
      ..writeByte(4)
      ..write(obj.description)
      ..writeByte(5)
      ..write(obj.date)
      ..writeByte(6)
      ..write(obj.note)
      ..writeByte(7)
      ..write(obj.accountId)
      ..writeByte(8)
      ..write(obj.cleared)
      ..writeByte(9)
      ..write(obj.createdAt)
      ..writeByte(10)
      ..write(obj.isArchived)
      ..writeByte(11)
      ..write(obj.payeeId)
      ..writeByte(12)
      ..write(obj.payerId)
      ..writeByte(13)
      ..write(obj.billId)
      ..writeByte(14)
      ..write(obj.occurrenceDate)
      ..writeByte(15)
      ..write(obj.splitsJson)
      ..writeByte(16)
      ..write(obj.showInReports)
      ..writeByte(17)
      ..write(obj.hideFromCalendarDashboard)
      ..writeByte(18)
      ..write(obj.categoryName)
      ..writeByte(19)
      ..write(obj.payeeName)
      ..writeByte(20)
      ..write(obj.payerName)
      ..writeByte(21)
      ..write(obj.updatedAt)
      ..writeByte(22)
      ..write(obj.paymentFor)
      ..writeByte(23)
      ..write(obj.sortOrder);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransactionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class TransactionTypeAdapter extends TypeAdapter<TransactionType> {
  @override
  final int typeId = 0;

  @override
  TransactionType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return TransactionType.income;
      case 1:
        return TransactionType.expense;
      default:
        return TransactionType.income;
    }
  }

  @override
  void write(BinaryWriter writer, TransactionType obj) {
    switch (obj) {
      case TransactionType.income:
        writer.writeByte(0);
        break;
      case TransactionType.expense:
        writer.writeByte(1);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransactionTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
