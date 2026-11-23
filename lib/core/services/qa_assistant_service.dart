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
          model: 'gemini-3.5-flash-lite',
          apiKey: apiKey,
          systemInstruction: Content.system('''
You are PrivDoc Assistant, a personal document intelligence copilot.
You have access to the user's verified local documents.

STRICT HUMAN RESPONSE GUIDELINES:
1. Short, Clear & Human: Answer ONLY what was asked in 1 to 3 concise, friendly sentences.
2. NO MARKDOWN ASTERISKS: NEVER use '***' or bold asterisks '**' or markdown headers '#'. Speak like a helpful, polite human assistant.
3. Accurate Numbers & Calculations:
   - For age questions: Use the exact ground truth age provided in the context.
   - For academic questions: If asked for SGPA, CGPA, grades, or marks, cite the exact numbers from the marksheet.
   - For expiry questions: Clearly list which documents are expired based on the Expiry Status in the context. Note that EWS certificates are valid only for 1 financial year (e.g. 2023-2024 expired on March 31, 2024).
4. If the user asks whether this AI chat requires internet:
   - State clearly: "Yes, answering conversational questions with Gemini AI requires an active internet connection, but all your personal documents and vault data are stored 100% locally on your device."
5. Reference Documents:
   - At the very end of your response, on a new line, list the document IDs used to answer in this exact syntax:
   [REFS: <doc_id_1>, <doc_id_2>]
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

        // Fallback reference matching by document title if none tagged
        if (referencedDocs.isEmpty) {
          for (final doc in documents) {
            if (rawAnswer.toLowerCase().contains(doc.title.toLowerCase()) ||
                (doc.docType != 'OTHER' && rawAnswer.toLowerCase().contains(doc.docType.toLowerCase().replaceAll('_', ' ')))) {
              if (!referencedDocs.any((d) => d.id == doc.id)) {
                referencedDocs.add(doc);
              }
            }
          }
        }

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
