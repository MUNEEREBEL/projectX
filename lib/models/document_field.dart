class DocumentField {
  final String id;
  final String documentId;
  final String fieldName; // e.g. "Full Name", "Aadhaar Number", "Expiry Date", "Address", "IFSC Code"
  final String fieldValue;
  final String fieldCategory; // 'identity', 'date', 'address', 'vehicle', 'financial', 'other'
  final bool isCopyable;

  DocumentField({
    required this.id,
    required this.documentId,
    required this.fieldName,
    required this.fieldValue,
    this.fieldCategory = 'other',
    this.isCopyable = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'document_id': documentId,
      'field_name': fieldName,
      'field_value': fieldValue,
      'field_category': fieldCategory,
      'is_copyable': isCopyable ? 1 : 0,
    };
  }

  factory DocumentField.fromMap(Map<String, dynamic> map) {
    return DocumentField(
      id: map['id'] as String,
      documentId: map['document_id'] as String,
      fieldName: map['field_name'] as String,
      fieldValue: map['field_value'] as String,
      fieldCategory: (map['field_category'] as String?) ?? 'other',
      isCopyable: (map['is_copyable'] as int?) != 0,
    );
  }
}
