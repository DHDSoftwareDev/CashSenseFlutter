class LookupItem {
  final String id;
  final String type; // category, payee, payer
  final String name;
  final String? color;
  final String? icon;
  final int sortOrder;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;

  const LookupItem({
    required this.id,
    required this.type,
    required this.name,
    this.color,
    this.icon,
    required this.sortOrder,
    required this.isDeleted,
    required this.createdAt,
    required this.updatedAt,
  });

  factory LookupItem.fromJson(Map<String, dynamic> json) {
    return LookupItem(
      id: json['id'] as String,
      type: json['type'] as String,
      name: json['name'] as String,
      color: json['color'] as String?,
      icon: json['icon'] as String?,
      sortOrder: (json['sortOrder'] ?? 0) as int,
      isDeleted: (json['isDeleted'] ?? false) as bool,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'name': name,
      'color': color,
      'icon': icon,
      'sortOrder': sortOrder,
      'isDeleted': isDeleted,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  LookupItem copyWith({
    String? id,
    String? type,
    String? name,
    String? color,
    String? icon,
    int? sortOrder,
    bool? isDeleted,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return LookupItem(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      color: color ?? this.color,
      icon: icon ?? this.icon,
      sortOrder: sortOrder ?? this.sortOrder,
      isDeleted: isDeleted ?? this.isDeleted,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
