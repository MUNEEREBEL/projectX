class Person {
  final String id;
  final String name;
  final String relationship; // 'Self', 'Spouse', 'Father', 'Mother', 'Child', 'Other'
  final String? dob;
  final String? gender;
  final int avatarColorIndex;
  final DateTime createdAt;

  Person({
    required this.id,
    required this.name,
    this.relationship = 'Self',
    this.dob,
    this.gender,
    this.avatarColorIndex = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'relationship': relationship,
      'dob': dob,
      'gender': gender,
      'avatar_color_index': avatarColorIndex,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Person.fromMap(Map<String, dynamic> map) {
    return Person(
      id: map['id'] as String,
      name: map['name'] as String,
      relationship: (map['relationship'] as String?) ?? 'Self',
      dob: map['dob'] as String?,
      gender: map['gender'] as String?,
      avatarColorIndex: (map['avatar_color_index'] as int?) ?? 0,
      createdAt: map['created_at'] != null 
          ? DateTime.tryParse(map['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Person copyWith({
    String? name,
    String? relationship,
    String? dob,
    String? gender,
    int? avatarColorIndex,
  }) {
    return Person(
      id: id,
      name: name ?? this.name,
      relationship: relationship ?? this.relationship,
      dob: dob ?? this.dob,
      gender: gender ?? this.gender,
      avatarColorIndex: avatarColorIndex ?? this.avatarColorIndex,
      createdAt: createdAt,
    );
  }
}
