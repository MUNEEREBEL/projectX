class DocumentModel {
  final String id;
  final String personId;
  final String docType; // 'AADHAAR', 'PAN', 'DRIVING_LICENSE', 'PASSPORT', 'VEHICLE_RC', 'INSURANCE', 'VOTER_ID', 'OTHER'
  final String category; // 'Identity', 'Vehicle', 'Financial', 'Health', 'Education', 'Other'
  final String title;
  final String? idNumber;
  final DateTime? issueDate;
  final DateTime? expiryDate;
  final String filePath;
  final String fileName;
  final String fileType;
  final String? rawText;
  final bool isVerified;
  final DateTime createdAt;
  final DateTime updatedAt;

  DocumentModel({
    required this.id,
    required this.personId,
    required this.docType,
    this.category = 'Identity',
    required this.title,
    this.idNumber,
    this.issueDate,
    this.expiryDate,
    required this.filePath,
    required this.fileName,
    required this.fileType,
    this.rawText,
    this.isVerified = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'person_id': personId,
      'doc_type': docType,
      'category': category,
      'title': title,
      'id_number': idNumber,
      'issue_date': issueDate?.toIso8601String(),
      'expiry_date': expiryDate?.toIso8601String(),
      'file_path': filePath,
      'file_name': fileName,
      'file_type': fileType,
      'raw_text': rawText,
      'is_verified': isVerified ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory DocumentModel.fromMap(Map<String, dynamic> map) {
    return DocumentModel(
      id: map['id'] as String,
      personId: map['person_id'] as String,
      docType: (map['doc_type'] as String?) ?? 'OTHER',
      category: (map['category'] as String?) ?? 'Identity',
      title: map['title'] as String,
      idNumber: map['id_number'] as String?,
      issueDate: map['issue_date'] != null ? DateTime.tryParse(map['issue_date'] as String) : null,
      expiryDate: map['expiry_date'] != null ? DateTime.tryParse(map['expiry_date'] as String) : null,
      filePath: map['file_path'] as String,
      fileName: map['file_name'] as String,
      fileType: (map['file_type'] as String?) ?? 'image',
      rawText: map['raw_text'] as String?,
      isVerified: (map['is_verified'] as int?) != 0,
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'] as String) ?? DateTime.now() : DateTime.now(),
      updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at'] as String) ?? DateTime.now() : DateTime.now(),
    );
  }

  bool get isExpired {
    if (expiryDate == null) return false;
    return expiryDate!.isBefore(DateTime.now());
  }

  int? get daysUntilExpiry {
    if (expiryDate == null) return null;
    return expiryDate!.difference(DateTime.now()).inDays;
  }
}
