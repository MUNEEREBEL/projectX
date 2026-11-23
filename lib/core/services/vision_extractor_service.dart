import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image/image.dart' as img;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../config/app_config.dart';
import '../utils/indian_doc_validator.dart';

class ExtractionResult {
  final String docType;
  final String category;
  final String holderName;
  final String? documentTitle;
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
    this.documentTitle,
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
      'document_title': documentTitle,
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
  static Future<String?> getApiKey() => AppConfig.getApiKey();

  static Future<void> setApiKey(String key) => AppConfig.setApiKey(key);

  /// Main extraction method for files (Images or PDFs)
  static Future<ExtractionResult> extractDocument({
    required String filePath,
    String? referenceCardholderName,
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

    // Support for Grok / xAI vision if key starts with xai-
    if (apiKey.startsWith('xai-')) {
      return await _extractWithGrok(
        filePath: filePath,
        apiKey: apiKey,
        ext: ext,
        referenceCardholderName: referenceCardholderName,
      );
    }

    final model = GenerativeModel(
      model: 'gemini-3.5-flash-lite',
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        temperature: 0.1,
      ),
    );

    final cardholderAnchor = (referenceCardholderName != null && referenceCardholderName.trim().isNotEmpty)
        ? referenceCardholderName.trim()
        : 'Unknown';

    final systemPrompt = '''
You are an expert Indian Government Document, Certificate & Academic Verification Engine.
Analyze this document image/text and extract all structured fields into JSON.

CRITICAL EXTRACTION & ACCURACY RULES:
1. PRIMARY CARDHOLDER NAME ANCHOR:
   The primary user of this vault is "$cardholderAnchor".
   - Official Indian documents frequently use inverted naming (e.g. "Shaik Muneer" vs "Muneer Shaik").
   - DO NOT hallucinate characters or misread scan artifacts. For example, never misread "Muneer" as "Munfeer". If the document belongs to the cardholder, use the verified spelling "$cardholderAnchor".

2. FATHER / PARENT / RELATION NAME DETECTION:
   - On Certificates (EWS, Caste, Income, Domicile):
     The document almost always states:
     "This is to certify that Shri/Kumari [APPLICANT NAME] son/daughter/ward of Shri [FATHER NAME]..."
     Or uses "S/o", "D/o", "W/o", "C/o", "Father's Name".
     The person following "son of", "daughter of", "S/o", "D/o", "Father's Name" is the FATHER'S NAME.
     Set "relation_name" to this name, and "relation_type" to "Father".
   - On Marksheets:
     Extract the name explicitly listed under "Father's Name", "Father Name", "Parent's Name", or "Guardian's Name".
   - ABSOLUTE PROHIBITION:
     The government officer who signed or issued the certificate (e.g. Tahsildar, Revenue Officer, SDM, Revenue Divisional Officer, District Collector, Registrar, Controller of Examinations) is the ISSUING AUTHORITY, NEVER the father!
     NEVER place the signing officer or Tahsildar in "relation_name"! Put them in "issuing_authority".

3. EXPIRY DATE & VALIDITY RULES (CRITICAL):
   - EWS CERTIFICATE: In India, an EWS Certificate is strictly valid for ONE financial year only! Look for "Valid for the year: YYYY-YYYY" or "Financial Year: YYYY-YYYY".
     If it states "Valid for the year 2023-2024", the certificate EXPIRES on "2024-03-31".
     If it states "Valid for the year 2024-2025", the certificate EXPIRES on "2025-03-31".
     IT IS NEVER LIFETIME! Always calculate the expiry_date as the March 31 end of that valid financial year.
   - INCOME CERTIFICATE: Valid for 1 financial year (expires on March 31 of that financial year).
   - DRIVING LICENSE: Extract "NT Valid Till" or "Transport Valid Till".
   - VEHICLE INSURANCE: Extract the policy end / expiry date.
   - VEHICLE RC: Extract "Fitness Valid Upto" or "Regn Valid Upto".
   - PASSPORT: Extract "Date of Expiry".
   - NON-EXPIRING: Aadhaar, PAN, Caste Certificate, Marksheets, Degree Certificates, and Birth Certificates do NOT expire. Set "expiry_date": null.

4. ACADEMIC MARKSHEETS & CERTIFICATES:
   - Extract "document_title" properly (e.g. "Class 10th Marksheet", "Class 12th Marksheet", "B.Tech Grade Sheet", "Degree Certificate").
   - Extract "sgpa" (Semester Grade Point Average, e.g. "8.45").
   - Extract "cgpa" (Cumulative Grade Point Average, e.g. "8.12").
   - Extract "percentage" (e.g. "85.6%").
   - Extract "total_marks" (e.g. "850/1000").
   - Extract "roll_number" / "hall_ticket_no" / "registration_number".
   - Extract "institution_name" (School/College/Institute name).
   - Extract "board_or_university" (e.g. CBSE, ICSE, State Board, JNTU, Anna University).
   - Extract "passing_year" (e.g. "2022").

Supported document types:
- EWS_CERTIFICATE (Economically Weaker Section Certificate)
- CASTE_CERTIFICATE (Community / Caste / Category Certificate)
- INCOME_CERTIFICATE (Income & Asset Certificate)
- DOMICILE_CERTIFICATE (Residence / Domicile Certificate)
- BIRTH_CERTIFICATE (Birth Certificate)
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
  "document_title": "string (Clean, proper title: e.g. 'PAN Card', 'Class 10th Marksheet', 'Class 12th Marksheet', 'B.Tech Grade Sheet', 'Income Certificate', 'EWS Certificate', 'Driving License', 'Vehicle RC')",
  "holder_name": "string (Full Name of the cardholder/applicant/student)",
  "relation_name": "string or null (ONLY actual Father/Husband/Spouse name. NEVER the Tahsildar or officer)",
  "relation_type": "string or null ('Father', 'Husband', 'Spouse', 'Mother')",
  "id_number": "string or null (Certificate number, Aadhaar, PAN, DL, Passport, Roll Number, RC number)",
  "dob": "string or null (YYYY-MM-DD format)",
  "gender": "string or null ('Male', 'Female', 'Other')",
  "issue_date": "string or null (YYYY-MM-DD)",
  "expiry_date": "string or null (YYYY-MM-DD, e.g. valid financial year end 2024-03-31 for EWS 2023-2024, license validity, insurance expiry)",
  "address": "string or null (complete address)",
  "pin_code": "string or null (6-digit PIN code)",
  "extra_fields": {
    "sgpa": "string or null (Semester Grade Point Average)",
    "cgpa": "string or null (Cumulative Grade Point Average)",
    "percentage": "string or null",
    "total_marks": "string or null",
    "roll_number": "string or null",
    "institution_name": "string or null",
    "board_or_university": "string or null",
    "passing_year": "string or null",
    "issuing_authority": "string or null (e.g. Tahsildar, Revenue Officer, SDM)",
    "issuing_district_or_state": "string or null",
    "financial_year": "string or null (e.g. 2023-2024)",
    "valid_year": "string or null (e.g. 2023-2024)",
    "sub_caste_or_category": "string or null",
    "annual_family_income": "string or null"
  }
}
''';

    List<Part> contentParts = [];

    if (ext == 'docx') {
      // DOCX handling: extract word/document.xml from zip archive
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      String docxText = '';
      for (final archiveFile in archive) {
        if (archiveFile.name == 'word/document.xml') {
          final xmlStr = utf8.decode(archiveFile.content, allowMalformed: true);
          docxText = xmlStr.replaceAll(RegExp(r'<w:p[ >]'), '\n')
                           .replaceAll(RegExp(r'<[^>]+>'), ' ')
                           .replaceAll(RegExp(r'\s+'), ' ')
                           .trim();
          break;
        }
      }
      contentParts.add(TextPart('$systemPrompt\n\nWord Document (.docx) text content:\n$docxText'));
    } else if (ext == 'pdf') {
      final bytes = await file.readAsBytes();
      final document = PdfDocument(inputBytes: bytes);
      final textExtractor = PdfTextExtractor(document);
      final extractedText = textExtractor.extractText();
      document.dispose();

      if (extractedText.trim().isNotEmpty) {
        contentParts.add(TextPart('$systemPrompt\n\nDocument text content:\n$extractedText'));
      } else {
        contentParts.add(TextPart(systemPrompt));
        contentParts.add(DataPart('application/pdf', bytes));
      }
    } else {
      final bytes = await file.readAsBytes();
      Uint8List uploadBytes = bytes;
      String mimeType = ext == 'png' ? 'image/png' : 'image/jpeg';

      // Only downsample if file size is very large (> 3.5MB) to avoid CPU waste and keep fine print legible
      if (bytes.length > 3500 * 1024) {
        try {
          final decoded = img.decodeImage(bytes);
          if (decoded != null) {
            img.Image targetImg = decoded;
            if (decoded.width > 1800 || decoded.height > 1800) {
              if (decoded.width > decoded.height) {
                targetImg = img.copyResize(decoded, width: 1800);
              } else {
                targetImg = img.copyResize(decoded, height: 1800);
              }
            }
            uploadBytes = Uint8List.fromList(img.encodeJpg(targetImg, quality: 85));
            mimeType = 'image/jpeg';
          }
        } catch (_) {
          uploadBytes = bytes;
        }
      }

      contentParts.add(TextPart(systemPrompt));
      contentParts.add(DataPart(mimeType, uploadBytes));
    }

    final response = await model.generateContent([
      Content.multi(contentParts),
    ]).timeout(
      const Duration(seconds: 8),
      onTimeout: () => throw TimeoutException('Gemini OCR timed out (8s limit).'),
    );

    final rawJson = response.text;
    if (rawJson == null || rawJson.isEmpty) {
      throw Exception('Empty response from AI vision model.');
    }

    return _parseExtractionJson(rawJson);
  }

  /// Grok (xAI) vision endpoint handler
  static Future<ExtractionResult> _extractWithGrok({
    required String filePath,
    required String apiKey,
    required String ext,
    String? referenceCardholderName,
  }) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final base64Image = base64Encode(bytes);
    final mimeType = ext == 'png' ? 'image/png' : 'image/jpeg';

    final client = HttpClient();
    final request = await client.postUrl(Uri.parse('https://api.x.ai/v1/chat/completions'));
    request.headers.set('Content-Type', 'application/json');
    request.headers.set('Authorization', 'Bearer $apiKey');

    final body = jsonEncode({
      'model': 'grok-2-vision-1212',
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'text',
              'text': 'Extract Indian document identity details into strict JSON: doc_type, category, holder_name, relation_name, id_number, dob, gender, issue_date, expiry_date, address, pin_code.'
            },
            {
              'type': 'image_url',
              'image_url': {'url': 'data:$mimeType;base64,$base64Image'}
            }
          ]
        }
      ],
      'temperature': 0.1,
    });

    request.write(body);
    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    client.close();

    final parsed = jsonDecode(responseBody);
    final content = parsed['choices'][0]['message']['content'] as String;
    final match = RegExp(r'\{[\s\S]*\}').firstMatch(content);
    final rawJson = match != null ? match.group(0)! : content;
    return _parseExtractionJson(rawJson);
  }

  static ExtractionResult _parseExtractionJson(String rawJson) {
    try {
      final Map<String, dynamic> data = jsonDecode(rawJson);
      
      final docType = (data['doc_type'] as String?)?.toUpperCase() ?? 'OTHER';
      final category = (data['category'] as String?) ?? 'Identity';
      final holderName = (data['holder_name'] as String?)?.trim() ?? 'Unknown';
      final documentTitle = (data['document_title'] as String?)?.trim();
      final relationName = data['relation_name'] as String?;
      final relationType = data['relation_type'] as String?;
      final idNumber = (data['id_number'] as String?)?.trim();
      final dob = data['dob'] as String?;
      final gender = data['gender'] as String?;
      final issueDate = data['issue_date'] as String?;
      String? expiryDate = data['expiry_date'] as String?;
      final address = data['address'] as String?;
      final pinCode = data['pin_code'] as String?;
      
      Map<String, String> extraFields = {};
      if (data['extra_fields'] is Map) {
        (data['extra_fields'] as Map).forEach((k, v) {
          if (v != null) extraFields[k.toString()] = v.toString();
        });
      }

      // Discard "lifetime" text for expiry
      if (expiryDate != null && (expiryDate.toLowerCase().contains('lifetime') || expiryDate.trim().isEmpty || expiryDate.toLowerCase() == 'null')) {
        expiryDate = null;
      }

      // Enforce Indian validity rules for EWS and Income certificates (valid until March 31)
      if (docType == 'EWS_CERTIFICATE' || extraFields['valid_year'] != null || extraFields['financial_year'] != null) {
        final yearStr = extraFields['valid_year'] ?? extraFields['financial_year'] ?? '';
        final yearMatch = RegExp(r'(20\d{2})[-/](20\d{2}|\d{2})').firstMatch(yearStr);
        if (yearMatch != null) {
          String endYearStr = yearMatch.group(2)!;
          if (endYearStr.length == 2) endYearStr = '20$endYearStr';
          expiryDate = '$endYearStr-03-31';
        } else {
          final singleYearMatch = RegExp(r'(20\d{2})').firstMatch(yearStr);
          if (singleYearMatch != null) {
            final y = singleYearMatch.group(1)!;
            expiryDate = '$y-03-31';
          }
        }
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
        documentTitle: documentTitle,
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
