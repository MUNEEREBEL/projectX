import 'dart:convert';
import 'dart:io';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../utils/indian_doc_validator.dart';

class ExtractionResult {
  final String docType;
  final String category;
  final String holderName;
  final String? relationName;
  final String? relationType;
  final String? idNumber;
  final String? dob;
  final String? gender;
  final String? issueDate;
  final String? expiryDate;
  final String? address;
  final String? pinCode;
  final Map<String, String> extraFields;
  final bool isChecksumValid;
  final String rawResponse;

  ExtractionResult({
    required this.docType,
    required this.category,
    required this.holderName,
    this.relationName,
    this.relationType,
    this.idNumber,
    this.dob,
    this.gender,
    this.issueDate,
    this.expiryDate,
    this.address,
    this.pinCode,
    this.extraFields = const {},
    this.isChecksumValid = true,
    this.rawResponse = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'doc_type': docType,
      'category': category,
      'holder_name': holderName,
      'relation_name': relationName,
      'relation_type': relationType,
      'id_number': idNumber,
      'dob': dob,
      'gender': gender,
      'issue_date': issueDate,
      'expiry_date': expiryDate,
      'address': address,
      'pin_code': pinCode,
      'extra_fields': extraFields,
      'is_checksum_valid': isChecksumValid,
    };
  }
}

class VisionExtractorService {
  static const String _prefApiKey = 'gemini_api_key';

  static Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefApiKey);
  }

  static Future<void> setApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefApiKey, key.trim());
  }

  /// Main extraction method for files (Images or PDFs)
  static Future<ExtractionResult> extractDocument({
    required String filePath,
    String? customApiKey,
  }) async {
    final apiKey = customApiKey ?? await getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception(
        'Gemini API Key is not configured. Please set your free Gemini API key in Settings.'
      );
    }

    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File does not exist: $filePath');
    }

    final ext = filePath.split('.').last.toLowerCase();
    final model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        temperature: 0.1,
      ),
    );

    const systemPrompt = '''
You are an expert Indian Document Recognition & Verification Engine.
Analyze this document image/text and extract the structured fields into JSON.

Supported document types:
- AADHAAR (Aadhaar Card)
- PAN (Permanent Account Number)
- DRIVING_LICENSE (Indian Driving License)
- PASSPORT (Indian Passport)
- VEHICLE_RC (Registration Certificate)
- VEHICLE_INSURANCE (Motor Insurance Policy)
- HEALTH_INSURANCE (Health Insurance Card/Policy)
- VOTER_ID (Election Commission EPIC)
- MARKSHEET (Academic Marksheet / Certificate)
- RENT_AGREEMENT (Lease Agreement)
- OTHER (Generic Document)

Category must be one of:
- Identity
- Vehicle
- Financial
- Health
- Education
- Other

Output MUST strictly follow this JSON schema:
{
  "doc_type": "string",
  "category": "string",
  "holder_name": "string (Full Name of the cardholder/person)",
  "relation_name": "string or null (Father/Husband/Spouse name)",
  "relation_type": "string or null ('Father', 'Husband', 'Spouse', 'Mother')",
  "id_number": "string or null (Aadhaar/PAN/DL/Passport/RC number)",
  "dob": "string or null (YYYY-MM-DD format)",
  "gender": "string or null ('Male', 'Female', 'Other')",
  "issue_date": "string or null (YYYY-MM-DD)",
  "expiry_date": "string or null (YYYY-MM-DD, e.g. license validity, insurance expiry, passport expiry)",
  "address": "string or null (complete address)",
  "pin_code": "string or null (6-digit PIN code)",
  "extra_fields": {
    "key": "value"
  }
}
Extract accurately. If a field is not found or ambiguous, set it to null.
For dates, always format as YYYY-MM-DD where possible.
''';

    List<Part> contentParts = [];

    if (ext == 'pdf') {
      // PDF handling: read text from PDF
      final bytes = await file.readAsBytes();
      final document = PdfDocument(inputBytes: bytes);
      final textExtractor = PdfTextExtractor(document);
      final extractedText = textExtractor.extractText();
      document.dispose();

      if (extractedText.trim().isNotEmpty) {
        contentParts.add(TextPart('$systemPrompt\n\nDocument text content:\n$extractedText'));
      } else {
        // Fallback for scanned PDF: treat bytes as application/pdf part
        contentParts.add(TextPart(systemPrompt));
        contentParts.add(DataPart('application/pdf', bytes));
      }
    } else {
      // Image handling (JPEG, PNG, WEBP)
      final bytes = await file.readAsBytes();
      final mimeType = ext == 'png' ? 'image/png' : 'image/jpeg';
      contentParts.add(TextPart(systemPrompt));
      contentParts.add(DataPart(mimeType, bytes));
    }

    final response = await model.generateContent([
      Content.multi(contentParts),
    ]);

    final rawJson = response.text;
    if (rawJson == null || rawJson.isEmpty) {
      throw Exception('Empty response from AI vision model.');
    }

    try {
      final Map<String, dynamic> data = jsonDecode(rawJson);
      
      final docType = (data['doc_type'] as String?)?.toUpperCase() ?? 'OTHER';
      final category = (data['category'] as String?) ?? 'Identity';
      final holderName = (data['holder_name'] as String?)?.trim() ?? 'Unknown';
      final relationName = data['relation_name'] as String?;
      final relationType = data['relation_type'] as String?;
      final idNumber = (data['id_number'] as String?)?.trim();
      final dob = data['dob'] as String?;
      final gender = data['gender'] as String?;
      final issueDate = data['issue_date'] as String?;
      final expiryDate = data['expiry_date'] as String?;
      final address = data['address'] as String?;
      final pinCode = data['pin_code'] as String?;
      
      Map<String, String> extraFields = {};
      if (data['extra_fields'] is Map) {
        (data['extra_fields'] as Map).forEach((k, v) {
          if (v != null) extraFields[k.toString()] = v.toString();
        });
      }

      // Checksum & format verification
      bool isChecksumValid = true;
      if (idNumber != null) {
        if (docType == 'AADHAAR') {
          isChecksumValid = IndianDocValidator.validateAadhaar(idNumber);
        } else if (docType == 'PAN') {
          isChecksumValid = IndianDocValidator.validatePAN(idNumber);
        } else if (docType == 'DRIVING_LICENSE') {
          isChecksumValid = IndianDocValidator.validateDrivingLicense(idNumber);
        } else if (docType == 'PASSPORT') {
          isChecksumValid = IndianDocValidator.validatePassport(idNumber);
        } else if (docType == 'VEHICLE_RC') {
          isChecksumValid = IndianDocValidator.validateVehicleRC(idNumber);
        }
      }

      return ExtractionResult(
        docType: docType,
        category: category,
        holderName: holderName,
        relationName: relationName,
        relationType: relationType,
        idNumber: idNumber,
        dob: dob,
        gender: gender,
        issueDate: issueDate,
        expiryDate: expiryDate,
        address: address,
        pinCode: pinCode,
        extraFields: extraFields,
        isChecksumValid: isChecksumValid,
        rawResponse: rawJson,
      );
    } catch (e) {
      throw Exception('Failed to parse AI response: $e\nRaw: $rawJson');
    }
  }
}
