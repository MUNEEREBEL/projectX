class ExpiryAlert {
  final String id;
  final String documentId;
  final String personName;
  final String documentTitle;
  final DateTime expiryDate;
  final int daysBefore; // 60, 30, 7, 1
  final bool isNotified;
  final DateTime scheduledAt;

  ExpiryAlert({
    required this.id,
    required this.documentId,
    required this.personName,
    required this.documentTitle,
    required this.expiryDate,
    required this.daysBefore,
    this.isNotified = false,
    required this.scheduledAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'document_id': documentId,
      'person_name': personName,
      'document_title': documentTitle,
      'expiry_date': expiryDate.toIso8601String(),
      'days_before': daysBefore,
      'is_notified': isNotified ? 1 : 0,
      'scheduled_at': scheduledAt.toIso8601String(),
    };
  }

  factory ExpiryAlert.fromMap(Map<String, dynamic> map) {
    return ExpiryAlert(
      id: map['id'] as String,
      documentId: map['document_id'] as String,
      personName: map['person_name'] as String,
      documentTitle: map['document_title'] as String,
      expiryDate: DateTime.parse(map['expiry_date'] as String),
      daysBefore: map['days_before'] as int,
      isNotified: (map['is_notified'] as int?) != 0,
      scheduledAt: DateTime.parse(map['scheduled_at'] as String),
    );
  }
}
