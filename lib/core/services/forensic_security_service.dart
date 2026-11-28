import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../utils/indian_doc_validator.dart';
import 'vision_extractor_service.dart';

enum ForensicStatus {
  genuine,
  suspicious,
  tamperedOrInvalid,
}

class ForensicAuditResult {
  final ForensicStatus status;
  final int integrityScore; // 0 to 100
  final List<String> passedChecks;
  final List<String> anomalies;
  final String sha256Checksum;
  final String softwareSignatures;
  final DateTime auditedAt;

  const ForensicAuditResult({
    required this.status,
    required this.integrityScore,
    required this.passedChecks,
    required this.anomalies,
    required this.sha256Checksum,
    required this.softwareSignatures,
    required this.auditedAt,
  });

  bool get isAuthentic => status == ForensicStatus.genuine;

  String get statusLabel {
    switch (status) {
      case ForensicStatus.genuine:
        return 'GENUINE & VERIFIED';
      case ForensicStatus.suspicious:
        return 'SUSPICIOUS / EDITED';
      case ForensicStatus.tamperedOrInvalid:
        return 'ANOMALY / FORGERY DETECTED';
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'status': status.name,
      'integrity_score': integrityScore,
      'passed_checks': passedChecks,
      'anomalies': anomalies,
      'sha256': sha256Checksum,
      'software_signatures': softwareSignatures,
      'audited_at': auditedAt.toIso8601String(),
    };
  }

  factory ForensicAuditResult.fromMap(Map<String, dynamic> map) {
    return ForensicAuditResult(
      status: ForensicStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => ForensicStatus.genuine,
      ),
      integrityScore: (map['integrity_score'] as num?)?.toInt() ?? 100,
      passedChecks: (map['passed_checks'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      anomalies: (map['anomalies'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      sha256Checksum: (map['sha256'] as String?) ?? '',
      softwareSignatures: (map['software_signatures'] as String?) ?? 'None',
      auditedAt: map['audited_at'] != null ? DateTime.tryParse(map['audited_at'] as String) ?? DateTime.now() : DateTime.now(),
    );
  }
}

/// Advanced Forensic Security Engine for detecting forged, edited, photoshopped, or invalid documents.
class ForensicSecurityService {
  // Known digital image editing & synthesis software signatures in EXIF / byte headers
  static final List<String> _knownEditingSoftware = [
    'Adobe Photoshop',
    'Photoshop',
    'Canva',
    'PicsArt',
    'GIMP',
    'InPage',
    'Photopea',
    'Snapseed',
    'Pixelmator',
    'CorelDRAW',
    'Affinity Photo',
  ];

  /// Performs comprehensive multi-vector forensic security analysis
  static Future<ForensicAuditResult> analyzeDocument({
    required File file,
    required ExtractionResult extraction,
    String? cardholderSurname,
  }) async {
    final passedChecks = <String>[];
    final anomalies = <String>[];
    int score = 100;

    // 1. Compute Cryptographic File Checksum
    String fileChecksum = '';
    String softwareSignatures = 'None (Clean Camera/Scanner Source)';
    try {
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        fileChecksum = sha256.convert(bytes).toString();

        // 2. Scan Binary Headers & EXIF for Editing Software Signatures
        final detectedEditingTools = _detectEditingSignatures(bytes);
        if (detectedEditingTools.isNotEmpty) {
          softwareSignatures = detectedEditingTools.join(', ');
          anomalies.add('Digital manipulation signature detected: Altered with $softwareSignatures');
          score -= 30;
        } else {
          passedChecks.add('Binary EXIF integrity clean (no editing tool signatures)');
        }
      }
    } catch (_) {}

    final docType = extraction.docType.toUpperCase();
    final idNumber = extraction.idNumber?.trim();

    // 3. Mathematical & Algorithmic Checksum Verification
    if (docType.contains('AADHAAR') || (idNumber != null && RegExp(r'^\d{4}\s?\d{4}\s?\d{4}$').hasMatch(idNumber))) {
      if (idNumber != null) {
        final isValidAadhaar = IndianDocValidator.validateAadhaar(idNumber);
        if (isValidAadhaar) {
          passedChecks.add('Aadhaar Verhoeff dihedral algorithm checksum mathematically verified');
        } else {
          anomalies.add('Aadhaar number fails Verhoeff algorithm check (mathematically invalid/forged number)');
          score -= 45;
        }
      }
    }

    // 4. PAN Section 139A & Surname Initial Checksum
    if (docType == 'PAN' && idNumber != null) {
      final isValidPan = IndianDocValidator.validatePAN(idNumber);
      if (isValidPan) {
        passedChecks.add('PAN structure follows Section 139A standard format');
        // Check 5th character vs surname
        final cleanPan = idNumber.toUpperCase().replaceAll(' ', '');
        final fifthChar = cleanPan.length >= 5 ? cleanPan[4] : '';
        if (cardholderSurname != null && cardholderSurname.trim().isNotEmpty) {
          final firstLetter = cardholderSurname.trim()[0].toUpperCase();
          if (fifthChar == firstLetter) {
            passedChecks.add('PAN 5th character \'$fifthChar\' accurately matches cardholder surname');
          } else {
            anomalies.add('PAN 5th character \'$fifthChar\' conflicts with holder surname \'$cardholderSurname\' (potential edited holder name)');
            score -= 20;
          }
        }
      } else {
        anomalies.add('PAN number violates statutory alphanumeric formatting');
        score -= 35;
      }
    }

    // 5. IFSC Code 5th Character Check
    if (extraction.ifscCode != null && extraction.ifscCode!.trim().isNotEmpty) {
      final ifsc = extraction.ifscCode!.trim().toUpperCase();
      if (ifsc.length == 11 && ifsc[4] == '0') {
        passedChecks.add('Bank IFSC code follows RBI 11-digit syntax with 5th zero anchor');
      } else {
        anomalies.add('Invalid IFSC syntax: 5th character must be digit \'0\' (found \'${ifsc.length >= 5 ? ifsc[4] : ""}\')');
        score -= 15;
      }
    }

    // 6. Chronological & Temporal Integrity Checks
    final now = DateTime.now();
    DateTime? issueDt;
    DateTime? expiryDt;
    DateTime? dobDt;

    if (extraction.issueDate != null) issueDt = DateTime.tryParse(extraction.issueDate!);
    if (extraction.expiryDate != null) expiryDt = DateTime.tryParse(extraction.expiryDate!);
    if (extraction.dob != null) dobDt = DateTime.tryParse(extraction.dob!);

    if (issueDt != null) {
      if (issueDt.isAfter(now.add(const Duration(days: 1)))) {
        anomalies.add('Chronological violation: Issue date (${extraction.issueDate}) is in the future');
        score -= 40;
      } else {
        passedChecks.add('Issue date chronologically consistent with present timeline');
      }
    }

    if (issueDt != null && expiryDt != null) {
      if (expiryDt.isBefore(issueDt)) {
        anomalies.add('Chronological impossibility: Expiry date precedes document issue date');
        score -= 45;
      } else {
        passedChecks.add('Validity interval (Issue -> Expiry) logically sound');
      }
    }

    if (issueDt != null && dobDt != null) {
      if (issueDt.isBefore(dobDt)) {
        anomalies.add('Chronological impossibility: Document issued before cardholder\'s date of birth');
        score -= 50;
      }
    }

    // 7. Academic Completion Age Check
    if (docType.contains('MARKSHEET') || docType.contains('CLASS_10') || extraction.category == 'Education') {
      if (dobDt != null && issueDt != null) {
        final ageAtIssue = issueDt.difference(dobDt).inDays ~/ 365;
        if (ageAtIssue < 12) {
          anomalies.add('Academic age anomaly: Candidate age at completion is $ageAtIssue years (< 12 years)');
          score -= 30;
        } else {
          passedChecks.add('Candidate completion age ($ageAtIssue yrs) satisfies academic board prerequisites');
        }
      }
    }

    // 8. Regulatory Validity Cap (EWS & Income Certificates)
    if (docType == 'EWS_CERTIFICATE' || docType == 'INCOME_CERTIFICATE') {
      if (issueDt != null && expiryDt != null) {
        final validityDays = expiryDt.difference(issueDt).inDays;
        if (validityDays > 380) {
          anomalies.add('Regulatory violation: EWS/Income certificate validity exceeds statutory 1 financial year');
          score -= 25;
        } else {
          passedChecks.add('Statutory 1-year financial validity verified under administrative gazette rules');
        }
      }
    }

    // Determine Forensic Status
    score = score.clamp(0, 100);
    ForensicStatus status;
    if (score >= 85 && anomalies.isEmpty) {
      status = ForensicStatus.genuine;
    } else if (score >= 50) {
      status = ForensicStatus.suspicious;
    } else {
      status = ForensicStatus.tamperedOrInvalid;
    }

    return ForensicAuditResult(
      status: status,
      integrityScore: score,
      passedChecks: passedChecks,
      anomalies: anomalies,
      sha256Checksum: fileChecksum,
      softwareSignatures: softwareSignatures,
      auditedAt: DateTime.now(),
    );
  }

  /// Scans file byte sequence for editing software fingerprints
  static List<String> _detectEditingSignatures(Uint8List bytes) {
    final detected = <String>[];
    // Search first 64KB and last 64KB of file where EXIF & creator headers are stored
    final headLimit = bytes.length > 65536 ? 65536 : bytes.length;
    final headString = latin1.decode(bytes.sublist(0, headLimit), allowInvalid: true);

    String tailString = '';
    if (bytes.length > 65536) {
      tailString = latin1.decode(bytes.sublist(bytes.length - 65536), allowInvalid: true);
    }

    final combined = headString + tailString;
    for (final software in _knownEditingSoftware) {
      if (combined.contains(software)) {
        detected.add(software);
      }
    }
    return detected;
  }
}
