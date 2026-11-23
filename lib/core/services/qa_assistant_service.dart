import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:intl/intl.dart';
import '../../models/document_model.dart';
import '../database/database_service.dart';
import 'vision_extractor_service.dart';

class QAResponse {
  final String answer;
  final List<String> copyableValues;
  final List<DocumentModel> referenceDocuments;
  final bool isAiGenerated;

  QAResponse({
    required this.answer,
    this.copyableValues = const [],
    this.referenceDocuments = const [],
    this.isAiGenerated = true,
  });
}

class QAAssistantService {
  static Future<QAResponse> askQuestion(String question) async {
    final db = DatabaseService.instance;
    final persons = await db.getAllPersons();
    final documents = await db.getAllDocuments();

    if (documents.isEmpty) {
      return QAResponse(
        answer: 'You have not added any documents to your vault yet. Please select your documents folder to sync your files.',
        isAiGenerated: false,
      );
    }

    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);

    final personMap = {for (var p in persons) p.id: p.name};

    // Calculate age ground truth if DOB exists in persons or document fields
    String? dobStr;
    int? calculatedAge;

    for (final p in persons) {
      if (p.dob != null && p.dob!.trim().isNotEmpty) {
        dobStr = p.dob;
        break;
      }
    }

    if (dobStr == null) {
      for (final doc in documents) {
        final fields = await db.getFieldsForDocument(doc.id);
        for (final f in fields) {
          if (f.fieldName.toLowerCase().contains('date of birth') || f.fieldName.toLowerCase() == 'dob') {
            dobStr = f.fieldValue;
            break;
          }
        }
        if (dobStr != null) break;
      }
    }

    if (dobStr != null) {
      DateTime? parsedDob;
      // Try YYYY-MM-DD
      parsedDob = DateTime.tryParse(dobStr);
      // Try DD/MM/YYYY or DD-MM-YYYY
      if (parsedDob == null && RegExp(r'^\d{2}[-/]\d{2}[-/]\d{4}$').hasMatch(dobStr)) {
        final parts = dobStr.split(RegExp(r'[-/]'));
        if (parts.length == 3) {
          parsedDob = DateTime.tryParse('${parts[2]}-${parts[1]}-${parts[0]}');
        }
      }
      if (parsedDob != null) {
        calculatedAge = now.year - parsedDob.year;
        if (now.month < parsedDob.month || (now.month == parsedDob.month && now.day < parsedDob.day)) {
          calculatedAge--;
        }
      }
    }

    // 1. Check if user configured Gemini API key for fast intelligent answering
    final apiKey = await VisionExtractorService.getApiKey();

    if (apiKey != null && apiKey.isNotEmpty) {
      try {
        // Collect document summaries and fields for context
        StringBuffer contextBuffer = StringBuffer();
        contextBuffer.writeln('CURRENT SYSTEM DATE: $todayStr (Year ${now.year})');
        if (calculatedAge != null && dobStr != null) {
          contextBuffer.writeln('GROUND TRUTH AGE: The vault owner is exactly $calculatedAge years old (DOB: $dobStr as of today $todayStr).');
        }

        contextBuffer.writeln('\nVAULT PERSONS:');
        for (final p in persons) {
          contextBuffer.writeln('- Person: ${p.name} (Relationship: ${p.relationship}, DOB: ${p.dob ?? 'N/A'})');
        }

        contextBuffer.writeln('\nVAULT DOCUMENTS & FIELDS:');
        for (final doc in documents) {
          final fields = await db.getFieldsForDocument(doc.id);
          contextBuffer.writeln('\n[DOCUMENT ID: ${doc.id}]');
          contextBuffer.writeln('Title: ${doc.title}');
          contextBuffer.writeln('Type: ${doc.docType}');
          contextBuffer.writeln('Owner: ${personMap[doc.personId] ?? 'Self'}');
          if (doc.idNumber != null) contextBuffer.writeln('ID/Cert/Roll Number: ${doc.idNumber}');
          if (doc.issueDate != null) contextBuffer.writeln('Issue Date: ${DateFormat('yyyy-MM-dd').format(doc.issueDate!)}');
          if (doc.expiryDate != null) {
            final isExpired = doc.expiryDate!.isBefore(now);
            contextBuffer.writeln('Expiry Date: ${DateFormat('yyyy-MM-dd').format(doc.expiryDate!)} (Status: ${isExpired ? "EXPIRED" : "VALID"})');
          } else {
            contextBuffer.writeln('Expiry Date: Lifetime (Does not expire)');
          }
          for (final f in fields) {
            contextBuffer.writeln('${f.fieldName}: ${f.fieldValue}');
          }
        }

        final model = GenerativeModel(
          model: 'gemini-1.5-flash',
          apiKey: apiKey,
          systemInstruction: Content.system('''
You are PrivDoc Assistant, a warm, thoughtful, and personal document intelligence companion.
You have access to the user's verified local family vault.

CRITICAL HUMAN CONVERSATIONAL & ACCURACY RULES:
1. Warm, Natural & Empathetic Tone:
   - Speak like a helpful, attentive personal companion. Use natural, human language rather than cold robotic formulas.
   - NEVER use robotic robotic boilerplate like "Based on the verified context provided..." or "According to the database records...".
   - Speak directly: "Your PAN number is ABCDE1234F.", "You scored an 8.42 SGPA in your 4th semester marksheet.", "Your EWS certificate expired on March 31, 2024, so you will need to renew it for this academic year."
   - NO MARKDOWN ASTERISKS: NEVER use '***', '**', or markdown headers '#'. Keep your sentences clean and natural.

2. Handling Multiple Family Members:
   - The vault manages documents for multiple people (e.g. Self, Father, Mother, Spouse, Children).
   - Pay close attention to who the question is about:
     - "my": ALWAYS refers to the primary cardholder (Self).
     - "my father's" / "my dad's": refers specifically to the Father's documents.
     - "my mother's" / "my mom's": refers specifically to the Mother's documents.
   - If the user asks for "my aadhar number", give the primary cardholder's Aadhaar number ONLY. DO NOT give their father's Aadhaar number!
   - If the user asks for their father's Aadhaar or document, look under the documents owned by Father and answer with the father's details.

3. Mobile Numbers & Bank Details (IFSC, Account Number):
   - Mobile Number: If asked "What is my mobile number?", search the verified 'Mobile Number' or 'Phone' fields in the context and provide it directly.
   - Bank Passbook & IFSC: If asked for IFSC code, account number, or bank details, check the Financial / Bank Passbook records in the context and provide the exact 11-digit IFSC code (e.g. SBIN0001234) and account number.

4. Accurate Numbers, Dates & Expiries:
   - Age: Use the exact Ground Truth Age provided in the context.
   - Marksheet & Subject Marks: Directly quote exact SGPA, CGPA, percentage, or roll numbers. If asked for individual subject marks (e.g. Mathematics, Science, English, Hindi, etc.) or a summary of grades, list the exact marks or grades found in the "Subject:" records.
   - Expiries: Compare against today's date. Clearly note whether a certificate is valid or expired. If expired, state clearly when it expired rather than showing negative days. Remember EWS certificates are valid for 1 financial year only.

5. If asked whether this AI chat requires internet:
   - Answer warmly: "Yes, chatting with me requires an active internet connection because Gemini processes your questions in the cloud, but all your personal documents and vault files are stored 100% privately on your device."

6. Reference Documents:
   - At the very end of your response, on a new line, list ONLY the 1 or 2 specific document IDs that actually contained the answer:
   [REFS: <doc_id>]
'''),
        );

        final prompt = '''
User Question: "$question"

Verified Vault Context:
$contextBuffer
''';

        final response = await model.generateContent([Content.text(prompt)]);
        String rawAnswer = response.text ?? 'No response received.';

        // Parse references
        List<DocumentModel> referencedDocs = [];
        final refsMatch = RegExp(r'\[REFS:\s*([^\]]+)\]', caseSensitive: false).firstMatch(rawAnswer);
        if (refsMatch != null) {
          final refIds = refsMatch.group(1)!.split(',').map((s) => s.trim()).toSet();
          rawAnswer = rawAnswer.replaceAll(refsMatch.group(0)!, '').trim();
          for (final id in refIds) {
            final matches = documents.where((d) => d.id == id || d.id.startsWith(id));
            if (matches.isNotEmpty) {
              referencedDocs.addAll(matches);
            }
          }
        }

        // Clean up markdown formatting clutter
        rawAnswer = rawAnswer
            .replaceAll('***', '')
            .replaceAll('**', '')
            .replaceAll('###', '')
            .replaceAll('##', '')
            .trim();

        // Fallback reference matching: ONLY if no [REFS] were generated and answer quotes document ID number or exact title
        if (referencedDocs.isEmpty) {
          for (final doc in documents) {
            if (doc.idNumber != null && doc.idNumber!.length >= 6 && rawAnswer.contains(doc.idNumber!)) {
              if (!referencedDocs.any((d) => d.id == doc.id)) {
                referencedDocs.add(doc);
              }
            } else if (doc.title.length >= 6 && rawAnswer.toLowerCase().contains(doc.title.toLowerCase())) {
              if (!referencedDocs.any((d) => d.id == doc.id)) {
                referencedDocs.add(doc);
              }
            }
          }
        }

        // Strictly deduplicate and limit to at most 2 relevant documents
        final uniqueDocIds = <String>{};
        final limitedDocs = <DocumentModel>[];
        for (final d in referencedDocs) {
          if (!uniqueDocIds.contains(d.id)) {
            uniqueDocIds.add(d.id);
            limitedDocs.add(d);
          }
        }
        referencedDocs = limitedDocs.take(2).toList();

        // Extract copyable candidates (numbers, codes)
        final copyableRegex = RegExp(r'\b([A-Z0-9]{5,20}|\d{4}\s?\d{4}\s?\d{4})\b');
        final matches = copyableRegex.allMatches(rawAnswer).map((m) => m.group(0)!).toSet().toList();

        return QAResponse(
          answer: rawAnswer,
          copyableValues: matches,
          referenceDocuments: referencedDocs,
          isAiGenerated: true,
        );
      } catch (e) {
        // Fall back to local search if API call fails
      }
    }

    // Fallback: Local search over SQLite database (100% offline!)
    final searchResults = await db.searchFields(question.trim());
    if (searchResults.isEmpty) {
      return QAResponse(
        answer: 'Could not find any matching details in your local documents for "$question".',
        isAiGenerated: false,
      );
    }

    StringBuffer localBuffer = StringBuffer();
    localBuffer.writeln('Here is what I found in your local vault:');
    List<String> copyables = [];
    List<DocumentModel> localRefs = [];

    for (final row in searchResults.take(5)) {
      final val = row['field_value'] as String;
      final docId = row['document_id'] as String;
      localBuffer.writeln('• ${row['doc_title']}: ${row['field_name']} = $val');
      copyables.add(val);
      final matchedDoc = documents.where((d) => d.id == docId);
      if (matchedDoc.isNotEmpty && !localRefs.any((d) => d.id == docId)) {
        localRefs.add(matchedDoc.first);
      }
    }

    return QAResponse(
      answer: localBuffer.toString(),
      copyableValues: copyables,
      referenceDocuments: localRefs,
      isAiGenerated: false,
    );
  }
}
