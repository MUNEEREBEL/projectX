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
  final String? mobileNumber;
  final String? ifscCode;
  final String? bankName;
  final String? accountNumber;
  final String? branch;
  final String? cifNumber;
  final String? micrCode;
  final bool isPrimaryCardholder;
  final String? relationshipToCardholder;
  final List<Map<String, String>> familyMembers;
  final Map<String, String> extraFields;
  final Map<String, String> subjectMarks;
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
    this.mobileNumber,
    this.ifscCode,
    this.bankName,
    this.accountNumber,
    this.branch,
    this.cifNumber,
    this.micrCode,
    this.isPrimaryCardholder = false,
    this.relationshipToCardholder,
    this.familyMembers = const [],
    this.extraFields = const {},
    this.subjectMarks = const {},
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
      'mobile_number': mobileNumber,
      'ifsc_code': ifscCode,
      'bank_name': bankName,
      'account_number': accountNumber,
      'branch': branch,
      'cif_number': cifNumber,
      'micr_code': micrCode,
      'is_primary_cardholder': isPrimaryCardholder,
      'relationship_to_cardholder': relationshipToCardholder,
      'family_members': familyMembers,
      'extra_fields': extraFields,
      'subject_marks': subjectMarks,
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
      model: 'gemini-1.5-flash',
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
1. ACCURATE PERSON & FAMILY MEMBER DISAMBIGUATION:
   The primary cardholder registered in this vault is "$cardholderAnchor".
   - DO NOT FORCIBLY ASSIGN "$cardholderAnchor" TO DOCUMENTS THAT BELONG TO SOMEONE ELSE!
   - If an Aadhaar card, PAN card, driving license, or certificate belongs to the user's father, mother, spouse, or another family member, "holder_name" MUST be that person's exact name printed on the card!
   - Look at the photo and printed name:
     - If it matches "$cardholderAnchor" (allowing Indian inverted names, e.g. "Shaik Muneer" vs "Muneer Shaik"):
       Set "is_primary_cardholder": true
       Set "relationship_to_cardholder": "Self"
       Set "document_title": e.g. "Aadhaar Card", "PAN Card", "Class 10th Marksheet"
     - If it belongs to Father or another person:
       Set "is_primary_cardholder": false
       Set "relationship_to_cardholder": "Father" (or "Mother", "Spouse", etc.)
       Set "document_title": e.g. "Father's Aadhaar Card", "Father's PAN Card"

2. BANK PASSBOOK / STATEMENT / CHEQUE:
   - doc_type: "BANK_PASSBOOK"
   - category: "Financial"
   - You MUST extract:
     - "bank_name": (e.g. "State Bank of India", "HDFC Bank", "Punjab National Bank", "Canara Bank", "ICICI Bank", "Axis Bank", "Union Bank")
     - "account_number": Full bank account number
     - "ifsc_code": The 11-character alphanumeric IFSC code (e.g. "SBIN0001234", "HDFC0000245"). Extract every single character accurately!
     - "branch": Branch name / location (e.g. "Main Branch Hyderabad")
     - "cif_number": CIF number / Customer ID if present
     - "micr_code": 9-digit MICR code if present
     - "document_title": "[Bank Name] Passbook" (e.g. "SBI Passbook", "HDFC Passbook")

3. RATION CARD & FAMILY MEMBERS:
   - doc_type: "RATION_CARD"
   - category: "Identity"
   - "document_title": "Ration Card"
   - "id_number": Ration Card Number / RC No / Food Security Card No
   - "holder_name": Head of Family (usually Father or Mother)
   - "family_members": Extract all family members listed on the card as a list of objects:
     [{"name": "Full Name", "relationship": "Head / Father / Son / Daughter / Wife / Mother"}]

4. MOBILE NUMBER EXTRACTION:
   - If a 10-digit mobile number or phone number is visible anywhere on any document (Aadhaar, Bank Passbook, Insurance, Certificates, Application forms), extract it into "mobile_number".

5. FATHER / PARENT / RELATION NAME DETECTION:
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

6. EXPIRY DATE & VALIDITY RULES (CRITICAL):
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

7. ACADEMIC MARKSHEETS & CERTIFICATES:
   - PRECISE DOCUMENT TITLE WITH SEMESTER OR CLASS:
     If the document is a marksheet or grade sheet, check for semester or academic class:
     - If it is for Class 10 / SSC: "Class 10th Marksheet (SSC)"
     - If it is for Class 12 / HSC / Intermediate: "Class 12th Marksheet (HSC)"
     - If it mentions a semester (e.g. "III Semester", "Semester 4", "6th Sem"): "B.Tech Semester 4 Grade Sheet" or "[Degree] [Semester] Marksheet"
     Set "document_title" to this exact, descriptive title!
   - ALL INDIVIDUAL SUBJECTS AND MARKS:
     In "subject_marks", you MUST extract EVERY SINGLE SUBJECT listed in the table along with its marks, points, or grade obtained (e.g. {"Mathematics": "96", "Science": "92", "English": "88", "Social Science": "90"}). DO NOT omit any subjects!
   - Extract "semester" into extra_fields (e.g. "4th Semester", "Semester 3").
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
- BANK_PASSBOOK (Bank Passbook / Statement / Cheque)
- RATION_CARD (Ration Card / Food Security Card)
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
  "document_title": "string (Clean, proper short title under 35 chars: e.g. 'Class 10th Marksheet (SSC)', 'Father\\'s Aadhaar Card', 'PAN Card', 'SBI Passbook', 'Income Certificate', 'EWS Certificate')",
  "holder_name": "string (Full Name of the cardholder/applicant/student/account holder)",
  "is_primary_cardholder": true,
  "relationship_to_cardholder": "string ('Self', 'Father', 'Mother', 'Spouse', 'Child', 'Other')",
  "relation_name": "string or null (ONLY actual Father/Husband/Spouse name. NEVER the Tahsildar or officer)",
  "relation_type": "string or null ('Father', 'Husband', 'Spouse', 'Mother')",
  "id_number": "string or null (Certificate number, Aadhaar, PAN, DL, Passport, Account Number, Roll Number, RC number)",
  "mobile_number": "string or null (10-digit mobile number if printed anywhere)",
  "bank_name": "string or null (e.g. 'State Bank of India', 'HDFC Bank')",
  "account_number": "string or null",
  "ifsc_code": "string or null (11-digit IFSC code e.g. 'SBIN0001234')",
  "branch": "string or null",
  "cif_number": "string or null",
  "micr_code": "string or null",
  "family_members": [
    {
      "name": "string",
      "relationship": "string"
    }
  ],
  "dob": "string or null (YYYY-MM-DD format)",
  "gender": "string or null ('Male', 'Female', 'Other')",
  "issue_date": "string or null (YYYY-MM-DD)",
  "expiry_date": "string or null (YYYY-MM-DD)",
  "address": "string or null (complete address)",
  "pin_code": "string or null (6-digit PIN code)",
  "subject_marks": {
    "Subject Name": "Marks or Grade (e.g. 95 or A+)"
  },
  "extra_fields": {
    "semester": "string or null",
    "sgpa": "string or null",
    "cgpa": "string or null",
    "percentage": "string or null",
    "total_marks": "string or null",
    "roll_number": "string or null",
    "institution_name": "string or null",
    "board_or_university": "string or null",
    "passing_year": "string or null",
    "issuing_authority": "string or null",
    "issuing_district_or_state": "string or null",
    "financial_year": "string or null",
    "valid_year": "string or null",
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
      String pdfText = '';
      try {
        final document = PdfDocument(inputBytes: bytes);
        final textExtractor = PdfTextExtractor(document);
        pdfText = textExtractor.extractText().trim();
        document.dispose();
      } catch (_) {}

      contentParts.add(TextPart(systemPrompt));
      if (pdfText.isNotEmpty) {
        contentParts.add(TextPart('Document extracted text:\n$pdfText'));
      }
      contentParts.add(DataPart('application/pdf', bytes));
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

    GenerateContentResponse? response;
    try {
      response = await model.generateContent([
        Content.multi(contentParts),
      ]).timeout(
        const Duration(seconds: 30),
      );
    } catch (_) {
      // Fallback model in case of regional deprecation or quota
      final fallbackModel = GenerativeModel(
        model: 'gemini-2.0-flash',
        apiKey: apiKey,
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json',
          temperature: 0.1,
        ),
      );
      response = await fallbackModel.generateContent([
        Content.multi(contentParts),
      ]).timeout(
        const Duration(seconds: 30),
      );
    }

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
      final mobileNumber = (data['mobile_number'] as String?)?.trim();
      final bankName = (data['bank_name'] as String?)?.trim();
      final accountNumber = (data['account_number'] as String?)?.trim();
      final ifscCode = (data['ifsc_code'] as String?)?.trim().toUpperCase();
      final branch = (data['branch'] as String?)?.trim();
      final cifNumber = (data['cif_number'] as String?)?.trim();
      final micrCode = (data['micr_code'] as String?)?.trim();
      final isPrimaryCardholder = data['is_primary_cardholder'] == true;
      final relationshipToCardholder = data['relationship_to_cardholder'] as String?;

      List<Map<String, String>> familyMembers = [];
      if (data['family_members'] is List) {
        for (final item in data['family_members']) {
          if (item is Map) {
            final name = item['name']?.toString().trim() ?? '';
            final rel = item['relationship']?.toString().trim() ?? 'Member';
            if (name.isNotEmpty) {
              familyMembers.add({'name': name, 'relationship': rel});
            }
          }
        }
      }
      
      Map<String, String> extraFields = {};
      if (data['extra_fields'] is Map) {
        (data['extra_fields'] as Map).forEach((k, v) {
          if (v != null) extraFields[k.toString()] = v.toString();
        });
      }

      Map<String, String> subjectMarks = {};
      if (data['subject_marks'] is Map) {
        (data['subject_marks'] as Map).forEach((k, v) {
          if (v != null && v.toString().trim().isNotEmpty && v.toString().toLowerCase() != 'null') {
            subjectMarks[k.toString().trim()] = v.toString().trim();
          }
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
        mobileNumber: mobileNumber,
        ifscCode: ifscCode,
        bankName: bankName,
        accountNumber: accountNumber,
        branch: branch,
        cifNumber: cifNumber,
        micrCode: micrCode,
        isPrimaryCardholder: isPrimaryCardholder,
        relationshipToCardholder: relationshipToCardholder,
        familyMembers: familyMembers,
        extraFields: extraFields,
        subjectMarks: subjectMarks,
        isChecksumValid: isChecksumValid,
        rawResponse: rawJson,
      );
    } catch (e) {
      throw Exception('Failed to parse AI response: $e\nRaw: $rawJson');
    }
  }
}
