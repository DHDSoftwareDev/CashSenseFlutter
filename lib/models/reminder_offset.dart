class ReminderOffset {
  final int daysBefore;
  final int hour;
  final int minute;

  const ReminderOffset({
    required this.daysBefore,
    required this.hour,
    required this.minute,
  });

  Map<String, dynamic> toJson() => {
        'daysBefore': daysBefore,
        'hour': hour,
        'minute': minute,
      };

  factory ReminderOffset.fromJson(Map<String, dynamic> json) {
    return ReminderOffset(
      daysBefore: (json['daysBefore'] as num?)?.toInt() ?? 0,
      hour: (json['hour'] as num?)?.toInt() ?? 9,
      minute: (json['minute'] as num?)?.toInt() ?? 0,
    );
  }

  ReminderOffset copyWith({
    int? daysBefore,
    int? hour,
    int? minute,
  }) {
    return ReminderOffset(
      daysBefore: daysBefore ?? this.daysBefore,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
    );
  }

  String get timeLabel {
    final hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final amPm = hour >= 12 ? 'PM' : 'AM';
    final mm = minute.toString().padLeft(2, '0');
    return '$hour12:$mm $amPm';
  }

  String get daysLabel {
    if (daysBefore == 0) return 'Due date';
    if (daysBefore == 1) return '1 day before';
    return '$daysBefore days before';
  }

  String get displayLabel => '$daysLabel at $timeLabel';

  String get dedupeKey => '$daysBefore-$hour-$minute';
}
