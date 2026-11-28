import 'dart:convert';
import 'dart:io';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/document_model.dart';
import '../../models/person.dart';
import '../config/app_config.dart';
import '../database/database_service.dart';
import 'person_resolution_engine.dart';
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
  static Future<QAResponse> askQuestion(String question, {bool forceOffline = false}) async {
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

    final prefs = await SharedPreferences.getInstance();
    final registeredOwner = (prefs.getString('vault_owner_name') ?? '').trim();
    final primaryUser = registeredOwner.isNotEmpty && registeredOwner != 'Primary User' && registeredOwner != 'Primary Cardholder'
        ? registeredOwner
        : (persons.isNotEmpty && persons.first.name != 'Primary User' ? persons.first.name : 'Primary Owner');

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
      parsedDob = DateTime.tryParse(dobStr);
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

    // 1. If not forcing offline, try fast Gemini AI with tight 3.5s timeout
    final apiKey = await VisionExtractorService.getApiKey();

    if (!forceOffline && apiKey != null && apiKey.isNotEmpty) {
      try {
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
          final ownerName = personMap[doc.personId] ?? 'Self';
          contextBuffer.writeln('\n[DOCUMENT ID: ${doc.id}]');
          contextBuffer.writeln('Title: ${doc.title}');
          contextBuffer.writeln('Type: ${doc.docType}');
          contextBuffer.writeln('Owner Name: $ownerName');
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

        // 1. Try Groq (qwen/qwen3.8-27b) ultra-fast LPU inference if configured
        final groqKey = await AppConfig.getGroqApiKey();
        if (groqKey != null && groqKey.startsWith('gsk_')) {
          try {
            final client = HttpClient();
            final req = await client.postUrl(Uri.parse('https://api.groq.com/openai/v1/chat/completions'));
            req.headers.set('Content-Type', 'application/json');
            req.headers.set('Authorization', 'Bearer $groqKey');

            final payload = jsonEncode({
              'model': 'qwen/qwen3.8-27b',
              'messages': [
                {
                  'role': 'system',
                  'content': '''
You are Project X Assistant, a personal document intelligence assistant.
You have access to the user's verified local family vault.
The registered vault owner is "$primaryUser".

CRITICAL PERSON SCOPING RULE:
- When the user asks "What is my Aadhaar?", "What is my PAN?", "Show my driving license", "Give my phone number", or asks generally without mentioning a family member, they are asking strictly about $primaryUser! Return $primaryUser's document details only.
- If and only if the user explicitly specifies another person or relationship (e.g. "father's Aadhaar", "Absar's marksheet", "mother's PAN"), return that specific person's document details.
- Always state the person's exact name. Keep answers under 2 sentences.
- At the end on a new line: [REFS: <doc_id>]
''',
                },
                {
                  'role': 'user',
                  'content': 'Question: "$question"\n\nContext:\n$contextBuffer',
                }
              ],
              'temperature': 0.1,
            });

            req.write(payload);
            final res = await req.close();
            final resBody = await res.transform(utf8.decoder).join();
            client.close();

            if (res.statusCode == 200) {
              final parsed = jsonDecode(resBody);
              final answer = parsed['choices']?[0]?['message']?['content'] as String?;
              if (answer != null && answer.trim().isNotEmpty) {
                return _buildQAResponse(answer, documents);
              }
            }
          } catch (_) {}
        }

        // 2. Try Gemini 3.5 Flash Lite
        final config = GenerationConfig(
          temperature: 0.1,
          maxOutputTokens: 200,
        );

        final systemInstructionContent = Content.system('''
You are Project X Assistant, a personal document intelligence assistant.
You have access to the user's verified local family vault.
The registered vault owner is "$primaryUser".

CRITICAL RULES:
1. PRIMARY PERSON DEFAULT:
   - When the user asks "What is my Aadhaar?", "What is my PAN?", "What is my phone number?", "Show my driving license", or asks generally without specifying someone else, they are asking strictly about $primaryUser!
   - You MUST return $primaryUser's document details only. Do NOT output other family members' documents unless asked!
   - If the user explicitly asks for someone else (e.g., "father's Aadhaar", "Absar Ahmed's Aadhaar", "mother's PAN"), return that specific person's document and clearly name them.
   - Always state the cardholder's exact name.
   - Do NOT write long conversational filler. Keep answers under 2 sentences.
   - Never use asterisks ('**' or '***') or markdown headings ('#').

2. Reference Documents:
   - At the end on a new line: [REFS: <doc_id>]
''');

        final prompt = '''
User Question: "$question"

Verified Vault Context:
$contextBuffer
''';

        GenerateContentResponse? response;
        for (final modelName in ['gemini-3.5-flash-lite', 'gemini-flash-lite-latest', 'gemini-flash-latest']) {
          try {
            final m = GenerativeModel(
              model: modelName,
              apiKey: apiKey,
              generationConfig: config,
              systemInstruction: systemInstructionContent,
            );
            response = await m.generateContent([Content.text(prompt)]).timeout(
              const Duration(milliseconds: 3500),
            );
            if (response.text != null && response.text!.trim().isNotEmpty) {
              break;
            }
          } catch (_) {}
        }

        String rawAnswer = response?.text ?? '';
        if (rawAnswer.isNotEmpty) {
          return _buildQAResponse(rawAnswer, documents);
        }
      } catch (_) {}
    }

    // --- INSTANT SUB-100MS LOCAL VAULT INTELLIGENCE (100% Offline) ---
    final qLower = question.toLowerCase().trim();

    // Check for Age question
    if (qLower.contains('age') || qLower.contains('how old')) {
      if (calculatedAge != null) {
        final pName = persons.isNotEmpty ? persons.first.name : 'You';
        return QAResponse(
          answer: '$pName is $calculatedAge years old (born $dobStr).',
          copyableValues: ['$calculatedAge'],
          isAiGenerated: false,
        );
      }
    }

    // Check for Expiry / Renewal questions
    if (qLower.contains('expire') || qLower.contains('expiry') || qLower.contains('validity') || qLower.contains('due')) {
      for (final doc in documents) {
        final tLower = doc.title.toLowerCase();
        final typeLower = doc.docType.toLowerCase();
        final pName = personMap[doc.personId] ?? 'Self';

        bool isMatch = false;
        if (qLower.contains('insurance') && (tLower.contains('insurance') || typeLower.contains('insurance'))) isMatch = true;
        if (qLower.contains('car') && (tLower.contains('car') || tLower.contains('vehicle'))) isMatch = true;
        if (qLower.contains('license') && (tLower.contains('license') || typeLower.contains('driving'))) isMatch = true;
        if (qLower.contains('passport') && (tLower.contains('passport') || typeLower.contains('passport'))) isMatch = true;
        if (qLower.contains('caste') && (tLower.contains('caste') || typeLower.contains('caste'))) isMatch = true;
        if (qLower.contains('ews') && (tLower.contains('ews') || typeLower.contains('ews'))) isMatch = true;
        if (qLower.contains('income') && (tLower.contains('income') || typeLower.contains('income'))) isMatch = true;

        if (isMatch) {
          if (doc.expiryDate != null) {
            final days = doc.expiryDate!.difference(now).inDays;
            final dateStr = DateFormat('dd MMMM yyyy').format(doc.expiryDate!);
            final statusText = days < 0
                ? 'expired on $dateStr.'
                : 'expires on $dateStr (in $days days).';
            return QAResponse(
              answer: '$pName\'s ${doc.title} $statusText',
              referenceDocuments: [doc],
              isAiGenerated: false,
            );
          } else {
            return QAResponse(
              answer: '$pName\'s ${doc.title} has lifetime validity and does not expire.',
              referenceDocuments: [doc],
              isAiGenerated: false,
            );
          }
        }
      }
    }

    // Direct document ID check (Aadhaar, PAN, DL, RC, Passport, etc.)
    final bool asksAadhaar = qLower.contains('aadhaar') || qLower.contains('aadhar');
    final bool asksPan = qLower.contains('pan') || qLower.contains('pancard');

    if (asksAadhaar || asksPan) {
      final targetType = asksAadhaar ? 'AADHAAR' : 'PAN';
      final matchingDocs = documents.where((d) => d.docType == targetType && d.idNumber != null && d.idNumber!.isNotEmpty).toList();

      if (matchingDocs.isNotEmpty) {
        // Check if query targets a specific person
        DocumentModel? targetDoc;
        for (final doc in matchingDocs) {
          final pName = (personMap[doc.personId] ?? '').toLowerCase();
          final title = doc.title.toLowerCase();
          if (qLower.contains('father') && (title.contains('father') || pName.contains('father'))) {
            targetDoc = doc;
            break;
          } else if (qLower.contains('mother') && (title.contains('mother') || pName.contains('mother'))) {
            targetDoc = doc;
            break;
          } else if (pName.isNotEmpty && qLower.contains(pName.split(' ').first)) {
            targetDoc = doc;
            break;
          }
        }

        // If no specific family member was requested in prompt, default to the primary owner's document!
        targetDoc ??= matchingDocs.firstWhere(
          (d) {
            final pName = personMap[d.personId] ?? '';
            return pName.toLowerCase() == primaryUser.toLowerCase() ||
                   PersonResolutionEngine.isNameMatch(pName, primaryUser);
          },
          orElse: () => matchingDocs.first,
        );

        final pName = personMap[targetDoc.personId] ?? primaryUser;
        return QAResponse(
          answer: '$pName\'s ${targetDoc.title} number is ${targetDoc.idNumber}.',
          copyableValues: [targetDoc.idNumber!],
          referenceDocuments: [targetDoc],
          isAiGenerated: false,
        );
      }
    }

    // Direct Mobile Number check
    if (qLower.contains('mobile') || qLower.contains('phone') || qLower.contains('contact')) {
      for (final doc in documents) {
        final pName = personMap[doc.personId] ?? primaryUser;
        bool isTarget = false;
        if (qLower.contains('father') && (pName.toLowerCase().contains('father') || doc.title.toLowerCase().contains('father'))) {
          isTarget = true;
        } else if (qLower.contains('mother') && (pName.toLowerCase().contains('mother') || doc.title.toLowerCase().contains('mother'))) {
          isTarget = true;
        } else if (!qLower.contains('father') && !qLower.contains('mother')) {
          if (pName.toLowerCase() == primaryUser.toLowerCase() || PersonResolutionEngine.isNameMatch(pName, primaryUser)) {
            isTarget = true;
          }
        }
        if (!isTarget && !qLower.contains(pName.toLowerCase().split(' ').first)) continue;

        final fields = await db.getFieldsForDocument(doc.id);
        for (final f in fields) {
          if (f.fieldName.toLowerCase().contains('mobile') || f.fieldName.toLowerCase().contains('phone')) {
            return QAResponse(
              answer: '$pName\'s mobile number is ${f.fieldValue} (from ${doc.title}).',
              copyableValues: [f.fieldValue],
              referenceDocuments: [doc],
              isAiGenerated: false,
            );
          }
        }
      }
    }

    // Extract search keywords from question
    final stopWords = {
      'what', 'is', 'my', 'the', 'for', 'of', 'in', 'at', 'to', 'a', 'an',
      'when', 'does', 'how', 'many', 'tell', 'me', 'show', 'give', 'number',
      'card', 'details', 'please', 'and', 'or', 'do', 'can', 'you', 'find'
    };

    final words = qLower.split(RegExp(r'[^a-zA-Z0-9]+')).where((w) => w.length > 2 && !stopWords.contains(w)).toList();

    List<Map<String, dynamic>> candidateRows = [];
    for (final word in words) {
      final rows = await db.searchFields(word);
      candidateRows.addAll(rows);
    }

    if (candidateRows.isNotEmpty) {
      final best = candidateRows.first;
      final val = best['field_value'] as String;
      final fieldName = best['field_name'] as String;
      final docTitle = best['doc_title'] as String;
      final docId = best['document_id'] as String;

      final matchedDocs = documents.where((d) => d.id == docId).toList();
      final personId = matchedDocs.isNotEmpty ? matchedDocs.first.personId : null;
      final personName = personId != null ? (personMap[personId] ?? 'Self') : 'Your';

      return QAResponse(
        answer: '$personName\'s $fieldName ($docTitle) is $val.',
        copyableValues: [val],
        referenceDocuments: matchedDocs,
        isAiGenerated: false,
      );
    }

    return QAResponse(
      answer: 'I could not find matching records in your vault for "$question". Please verify that the document is synced.',
      isAiGenerated: false,
    );
  }

  static QAResponse _buildQAResponse(String rawAnswer, List<DocumentModel> documents) {
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

    rawAnswer = rawAnswer
        .replaceAll('***', '')
        .replaceAll('**', '')
        .replaceAll('###', '')
        .replaceAll('##', '')
        .trim();

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

    final uniqueDocIds = <String>{};
    final limitedDocs = <DocumentModel>[];
    for (final d in referencedDocs) {
      if (!uniqueDocIds.contains(d.id)) {
        uniqueDocIds.add(d.id);
        limitedDocs.add(d);
      }
    }
    referencedDocs = limitedDocs.take(2).toList();

    final copyableRegex = RegExp(r'\b([A-Z0-9]{5,20}|\d{4}\s?\d{4}\s?\d{4})\b');
    final matches = copyableRegex.allMatches(rawAnswer).map((m) => m.group(0)!).toSet().toList();

    return QAResponse(
      answer: rawAnswer,
      copyableValues: matches,
      referenceDocuments: referencedDocs,
      isAiGenerated: true,
    );
  }
}
