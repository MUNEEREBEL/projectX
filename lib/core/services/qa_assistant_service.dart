import 'package:google_generative_ai/google_generative_ai.dart';
import '../database/database_service.dart';
import 'vision_extractor_service.dart';

class QAResponse {
  final String answer;
  final List<String> copyableValues;
  final bool isAiGenerated;

  QAResponse({
    required this.answer,
    this.copyableValues = const [],
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

    // 1. Check if user configured Gemini API key for fast intelligent answering
    final apiKey = await VisionExtractorService.getApiKey();

    if (apiKey != null && apiKey.isNotEmpty) {
      try {
        // Collect document summaries and fields for context
        StringBuffer contextBuffer = StringBuffer();
        contextBuffer.writeln('VAULT PERSONS:');
        for (final p in persons) {
          contextBuffer.writeln('- Person: ${p.name} (Relationship: ${p.relationship}, DOB: ${p.dob ?? 'N/A'})');
        }

        contextBuffer.writeln('\nVAULT DOCUMENTS & FIELDS:');
        for (final doc in documents) {
          final fields = await db.getFieldsForDocument(doc.id);
          contextBuffer.writeln('\n[Document: ${doc.title} (${doc.docType})]');
          contextBuffer.writeln('ID Number: ${doc.idNumber ?? 'N/A'}');
          contextBuffer.writeln('Issue Date: ${doc.issueDate?.toIso8601String() ?? 'N/A'}');
          contextBuffer.writeln('Expiry Date: ${doc.expiryDate?.toIso8601String() ?? 'N/A'}');
          for (final f in fields) {
            contextBuffer.writeln('${f.fieldName}: ${f.fieldValue}');
          }
        }

        final model = GenerativeModel(
          model: 'gemini-2.5-flash',
          apiKey: apiKey,
          systemInstruction: Content.system('''
You are PrivDoc Assistant, a personal document intelligence copilot.
You have access to the user's verified local documents.
Answer questions accurately, concisely, and directly.
If specific ID numbers, dates, or values are mentioned, highlight them clearly so the user can easily copy them.
Never invent document details not present in the context.
'''),
        );

        final prompt = '''
User Question: "$question"

Verified Vault Context:
$contextBuffer
''';

        final response = await model.generateContent([Content.text(prompt)]);
        final answerText = response.text ?? 'No response received.';

        // Extract copyable candidates (numbers, codes)
        final copyableRegex = RegExp(r'\b([A-Z0-9]{5,20}|\d{4}\s?\d{4}\s?\d{4})\b');
        final matches = copyableRegex.allMatches(answerText).map((m) => m.group(0)!).toSet().toList();

        return QAResponse(
          answer: answerText,
          copyableValues: matches,
          isAiGenerated: true,
        );
      } catch (e) {
        // Fall back to local search if API call fails
      }
    }

    // Fallback: Local search over SQLite database
    final searchResults = await db.searchFields(question.trim());
    if (searchResults.isEmpty) {
      return QAResponse(
        answer: 'Could not find any matching details in your local documents for "$question".',
        isAiGenerated: false,
      );
    }

    StringBuffer localBuffer = StringBuffer();
    localBuffer.writeln('Found matching records from your local vault:');
    List<String> copyables = [];

    for (final row in searchResults.take(5)) {
      final val = row['field_value'] as String;
      localBuffer.writeln('• ${row['person_name']} - ${row['doc_title']}: ${row['field_name']} = $val');
      copyables.add(val);
    }

    return QAResponse(
      answer: localBuffer.toString(),
      copyableValues: copyables,
      isAiGenerated: false,
    );
  }
}
