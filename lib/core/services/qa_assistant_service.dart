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

        final config = GenerationConfig(
          temperature: 0.1,
          maxOutputTokens: 200,
        );

        final systemInstructionContent = Content.system('''
You are PrivDoc Assistant, a personal document intelligence assistant.
You have access to the user's verified local family vault.

CRITICAL RULES:
1. SHORT & CONCISE ANSWERS ONLY:
   - Give short, direct, 1-2 sentence answers answering ONLY what the user asked.
   - Do NOT write long paragraphs, pleasantries, conversational fluff, or unsolicited advice.
   - Never use markdown asterisks ('***' or '**') or markdown headings ('#'). Speak cleanly and plainly.
   - Examples of desired tone and length:
     - User: "What is my PAN number?" -> "Your PAN number is ABCDE1234F."
     - User: "What is my 4th sem SGPA?" -> "Your 4th semester SGPA is 8.42."
     - User: "Is my EWS certificate expired?" -> "Yes, your EWS certificate expired on March 31, 2024."
     - User: "What is my age?" -> "You are 20 years old (born September 14, 2004)."

2. Family Member Disambiguation:
   - "my" = Primary Cardholder / Self.
   - "father's" / "dad's" = Father only.
   - "mother's" / "mom's" = Mother only.
   - Never return the father's Aadhaar or details when asked for "my" Aadhaar or details.

3. Mobile Numbers & Bank Details (IFSC, Account Number):
   - Provide the exact mobile number, 11-digit IFSC code (e.g. SBIN0001234), or account number found in the vault.

4. Accurate Numbers & Expiry Dates:
   - Use the exact Ground Truth Age and subject marks/grades in the context.
   - For expired documents, state the expiration date simply without showing negative days.

5. Reference Documents:
   - At the very end of your response, on a new line, list ONLY the 1 or 2 document IDs that contained the answer:
   [REFS: <doc_id>]
''');

        final model = GenerativeModel(
          model: 'gemini-1.5-flash',
          apiKey: apiKey,
          generationConfig: config,
          systemInstruction: systemInstructionContent,
        );

        final prompt = '''
User Question: "$question"

Verified Vault Context:
$contextBuffer
''';

        GenerateContentResponse? response;
        try {
          response = await model.generateContent([Content.text(prompt)]).timeout(
            const Duration(seconds: 15),
          );
        } catch (_) {
          final fallbackModel = GenerativeModel(
            model: 'gemini-2.0-flash',
            apiKey: apiKey,
            generationConfig: config,
            systemInstruction: systemInstructionContent,
          );
          response = await fallbackModel.generateContent([Content.text(prompt)]).timeout(
            const Duration(seconds: 15),
          );
        }
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
