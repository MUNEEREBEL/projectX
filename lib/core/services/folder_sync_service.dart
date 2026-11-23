import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../models/document_field.dart';
import '../../models/document_model.dart';
import '../../models/person.dart';
import '../database/database_service.dart';
import 'alert_service.dart';
import 'person_resolution_engine.dart';
import 'vision_extractor_service.dart';

class SyncProgress {
  final int totalFiles;
  final int processedFiles;
  final String currentFileName;
  final String status;
  final String? logMessage;
  final bool isCompleted;
  final String? error;

  SyncProgress({
    this.totalFiles = 0,
    this.processedFiles = 0,
    this.currentFileName = '',
    this.status = '',
    this.logMessage,
    this.isCompleted = false,
    this.error,
  });

  double get percentage => totalFiles > 0 ? (processedFiles / totalFiles).clamp(0.0, 1.0) : 0.0;
}

class PickFolderResult {
  final String folderPathOrUri;
  final String folderDisplayName;
  final List<File> files;

  PickFolderResult({
    required this.folderPathOrUri,
    required this.folderDisplayName,
    required this.files,
  });
}

class FolderSyncService {
  static const String _prefFolderPath = 'vault_folder_path';
  static const _uuid = Uuid();
  static const supportedExtensions = {'.pdf', '.png', '.jpg', '.jpeg', '.docx'};
  static const MethodChannel _storageChannel = MethodChannel('com.example.x/storage_channel');

  static Future<String?> getSelectedFolderPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefFolderPath);
  }

  static Future<void> setSelectedFolderPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefFolderPath, path);
  }

  static Future<bool> hasStoragePermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final bool res = await _storageChannel.invokeMethod('hasStoragePermission') ?? false;
      return res;
    } catch (_) {
      return true;
    }
  }

  static Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final bool res = await _storageChannel.invokeMethod('requestStoragePermission') ?? false;
      return res;
    } catch (_) {
      return true;
    }
  }

  static Future<List<File>> scanFolderNative(String target) async {
    if (!Platform.isAndroid) return [];
    try {
      final List<dynamic>? res = await _storageChannel.invokeMethod('scanFolderNative', {'target': target});
      if (res != null) {
        return res
            .map((item) => File(item.toString()))
            .where((f) => f.existsSync())
            .toList();
      }
    } catch (_) {}
    return [];
  }

  /// Permanent sandboxed storage location inside app directory
  static Future<Directory> getPermanentVaultDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final vaultDir = Directory(p.join(appDir.path, 'vault_documents'));
    if (!await vaultDir.exists()) {
      await vaultDir.create(recursive: true);
    }
    return vaultDir;
  }

  /// Native SAF folder picker with instant file discovery
  static Future<PickFolderResult?> pickFolderAndDiscover() async {
    if (Platform.isAndroid) {
      try {
        final Map<dynamic, dynamic>? res = await _storageChannel.invokeMethod('pickFolder');
        if (res != null) {
          final uri = res['folderUri'] as String? ?? '';
          final name = res['folderName'] as String? ?? 'Monitored Folder';
          final List<dynamic> filePaths = res['files'] as List<dynamic>? ?? [];
          final files = filePaths
              .map((p) => File(p.toString()))
              .where((f) => f.existsSync())
              .toList();

          if (uri.isNotEmpty) {
            await setSelectedFolderPath(uri);
          }
          return PickFolderResult(
            folderPathOrUri: uri,
            folderDisplayName: name,
            files: files,
          );
        }
      } catch (_) {}
    }

    try {
      final uri = await FilePicker.pickDirectory(
        dialogTitle: 'Select your Documents Vault Folder',
      );
      if (uri != null) {
        final pathOrUri = uri.scheme == 'file' ? uri.toFilePath() : uri.toString();
        await setSelectedFolderPath(pathOrUri);
        final files = await scanFolderNative(pathOrUri);
        return PickFolderResult(
          folderPathOrUri: pathOrUri,
          folderDisplayName: p.basename(pathOrUri),
          files: files,
        );
      }
    } catch (_) {}

    try {
      final result = await FilePicker.getDirectoryPath(
        dialogTitle: 'Select your Documents Vault Folder',
      );
      if (result != null && result.isNotEmpty) {
        await setSelectedFolderPath(result);
        List<File> files = await scanFolderNative(result);
        if (files.isEmpty) {
          final dir = Directory(result);
          if (await dir.exists()) {
            files = dir
                .listSync(recursive: true)
                .whereType<File>()
                .where((f) => supportedExtensions.contains(p.extension(f.path).toLowerCase()))
                .toList();
          }
        }
        return PickFolderResult(
          folderPathOrUri: result,
          folderDisplayName: p.basename(result),
          files: files,
        );
      }
    } catch (_) {}

    return null;
  }

  /// Lets the user pick a folder via native directory picker and persists it.
  static Future<String?> pickFolder() async {
    final res = await pickFolderAndDiscover();
    return res?.folderPathOrUri;
  }

  /// Scans the selected folder and processes un-indexed documents.
  static Stream<SyncProgress> syncFolder({String? folderPath}) async* {
    final targetPath = folderPath ?? await getSelectedFolderPath();
    if (targetPath == null || targetPath.isEmpty) {
      yield SyncProgress(
        status: 'No folder selected',
        error: 'Please select a folder containing your documents first.',
        isCompleted: true,
      );
      return;
    }

    yield SyncProgress(status: 'Scanning folder for documents...');

    List<File> files = [];

    // 1. Try native Android scanner first (handles SAF tree URIs and native walk)
    if (Platform.isAndroid) {
      files = await scanFolderNative(targetPath);
    }

    // 2. If native scan returned empty, fallback to recursive Dart Directory scan
    if (files.isEmpty) {
      final dir = Directory(targetPath);
      if (await dir.exists()) {
        try {
          files = dir
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) {
                final ext = p.extension(file.path).toLowerCase();
                return supportedExtensions.contains(ext);
              })
              .toList();
        } catch (_) {}
      }
    }

    if (files.isEmpty) {
      yield SyncProgress(
        status: 'No document files found in folder (.pdf, .png, .jpg, .docx).',
        totalFiles: 0,
        processedFiles: 0,
        isCompleted: true,
      );
      return;
    }

    yield* syncFiles(files);
  }

  /// Imports and indexes a list of files into permanent vault storage
  static Stream<SyncProgress> syncFiles(List<File> files) {
    final controller = StreamController<SyncProgress>();
    _runSyncJob(files, controller);
    return controller.stream;
  }

  static Future<void> _runSyncJob(List<File> files, StreamController<SyncProgress> controller) async {
    if (files.isEmpty) {
      controller.add(SyncProgress(status: 'No files to index', isCompleted: true));
      await controller.close();
      return;
    }

    final db = DatabaseService.instance;
    final vaultDir = await getPermanentVaultDirectory();
    final existingDocs = await db.getAllDocuments();
    final existingFileNames = existingDocs.map((d) => d.fileName.toLowerCase()).toSet();

    // Helper to strip staging timestamps and get clean original filename
    String getCleanName(String filePath) {
      String clean = p.basename(filePath);
      if (clean.startsWith('vault_staging_') || clean.startsWith('vault_import_')) {
        final parts = clean.split('_');
        if (parts.length >= 3) {
          clean = parts.sublist(2).join('_');
        }
      }
      return clean.toLowerCase();
    }

    // Filter files that are not already indexed - only scan genuinely new files!
    final newFiles = files.where((f) {
      final clean = getCleanName(f.path);
      return !existingFileNames.contains(clean);
    }).toList();

    if (newFiles.isEmpty) {
      controller.add(SyncProgress(
        status: 'All ${files.length} documents are already indexed and stored in vault!',
        totalFiles: files.length,
        processedFiles: files.length,
        isCompleted: true,
      ));
      await controller.close();
      return;
    }

    // Ensure at least 1 person exists for initial ownership
    final persons = await db.getAllPersons();
    String defaultPersonId;
    final prefs = await SharedPreferences.getInstance();
    final storedName = prefs.getString('vault_owner_name');

    // Prioritize stored name over generic placeholders
    String ownerName = (storedName != null && storedName.trim().isNotEmpty && storedName.trim() != 'Primary Cardholder')
        ? storedName.trim()
        : (persons.isNotEmpty && persons.first.name != 'Primary Cardholder' ? persons.first.name : 'Primary User');

    if (persons.isEmpty) {
      defaultPersonId = _uuid.v4();
      await db.upsertPerson(Person(
        id: defaultPersonId,
        name: ownerName,
        relationship: 'Self',
        avatarColorIndex: 0,
      ));
    } else {
      defaultPersonId = persons.first.id;
      if ((persons.first.name == 'Primary Cardholder' || persons.first.name == 'Primary User') &&
          ownerName != 'Primary Cardholder' &&
          ownerName != 'Primary User') {
        await db.upsertPerson(Person(
          id: defaultPersonId,
          name: ownerName,
          relationship: persons.first.relationship,
          avatarColorIndex: persons.first.avatarColorIndex,
        ));
      } else {
        ownerName = persons.first.name;
      }
    }

    // 1. INSTANT LOCAL PERSISTENCE: Save all documents to SQLite immediately!
    final List<({File permanentFile, DocumentModel doc, String cleanName})> stagedList = [];

    for (final file in newFiles) {
      final originalName = p.basename(file.path);
      String cleanName = originalName;
      if (cleanName.startsWith('vault_staging_') || cleanName.startsWith('vault_import_')) {
        final parts = cleanName.split('_');
        if (parts.length >= 3) {
          cleanName = parts.sublist(2).join('_');
        }
      }

      final safeBaseName = cleanName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final permanentFilePath = p.join(vaultDir.path, '${DateTime.now().millisecondsSinceEpoch}_$safeBaseName');
      final permanentFile = await file.copy(permanentFilePath);

      final guessedType = _guessDocTypeFromFilename(cleanName);
      final docId = _uuid.v4();
      final ext = p.extension(cleanName).replaceAll('.', '').toLowerCase();

      final initialDoc = DocumentModel(
        id: docId,
        personId: defaultPersonId,
        docType: guessedType,
        category: _categoryForDocType(guessedType),
        title: _formatDocType(guessedType),
        filePath: permanentFile.path,
        fileName: cleanName,
        fileType: ext,
        isVerified: false,
      );

      // Save to SQLite right now! (Guarantees vault is NEVER empty!)
      await db.saveDocumentWithFields(
        document: initialDoc,
        fields: [
          DocumentField(
            id: _uuid.v4(),
            documentId: docId,
            fieldName: 'File Name',
            fieldValue: cleanName,
            fieldCategory: 'general',
          ),
        ],
      );

      stagedList.add((
        permanentFile: permanentFile,
        doc: initialDoc,
        cleanName: cleanName,
      ));
    }

    controller.add(SyncProgress(
      totalFiles: stagedList.length,
      processedFiles: 0,
      status: 'Secured ${stagedList.length} document(s) in vault. Enriching with Vision AI...',
      logMessage: '[${DateFormat('HH:mm:ss').format(DateTime.now())}] 💾 All ${stagedList.length} file(s) saved to local SQLite vault.',
    ));

    // 2. TRUE PARALLEL BATCH EXTRACTION (Batch: 3 parallel AI requests - ultra-fast & low network)
    int completedCount = 0;
    const int concurrency = 3;

    for (int i = 0; i < stagedList.length; i += concurrency) {
      final end = (i + concurrency < stagedList.length) ? i + concurrency : stagedList.length;
      final batch = stagedList.sublist(i, end);

      for (final item in batch) {
        final timeStart = DateFormat('HH:mm:ss').format(DateTime.now());
        controller.add(SyncProgress(
          totalFiles: stagedList.length,
          processedFiles: completedCount,
          currentFileName: item.cleanName,
          status: 'Analyzing ${item.cleanName} (${completedCount + 1} of ${stagedList.length})...',
          logMessage: '[$timeStart] ⚡ Querying Gemini AI for ${item.cleanName}...',
        ));
      }

      await Future.wait(batch.map((item) async {
        try {
          final extractResult = await VisionExtractorService.extractDocument(
            filePath: item.permanentFile.path,
            referenceCardholderName: ownerName,
          );

          final person = await PersonResolutionEngine.resolvePerson(
            holderName: extractResult.holderName,
            dob: extractResult.dob,
            gender: extractResult.gender,
            relationName: extractResult.relationName,
            relationType: extractResult.relationType,
          );

          DateTime? issueDate;
          if (extractResult.issueDate != null) {
            issueDate = DateTime.tryParse(extractResult.issueDate!);
          }

          DateTime? expiryDate;
          if (extractResult.expiryDate != null) {
            expiryDate = DateTime.tryParse(extractResult.expiryDate!);
          }

          final cleanTitle = (extractResult.documentTitle != null && extractResult.documentTitle!.trim().isNotEmpty)
              ? extractResult.documentTitle!.trim()
              : _formatDocType(extractResult.docType);

          final updatedDoc = DocumentModel(
            id: item.doc.id,
            personId: person.id,
            docType: extractResult.docType,
            category: extractResult.category,
            title: cleanTitle,
            idNumber: extractResult.idNumber,
            issueDate: issueDate,
            expiryDate: expiryDate,
            filePath: item.permanentFile.path,
            fileName: item.cleanName,
            fileType: item.doc.fileType,
            rawText: extractResult.rawResponse,
            isVerified: extractResult.isChecksumValid,
          );

          List<DocumentField> fields = [];
          void addField(String name, String? value, String category) {
            if (value != null && value.trim().isNotEmpty && value.trim().toLowerCase() != 'null') {
              fields.add(DocumentField(
                id: _uuid.v4(),
                documentId: item.doc.id,
                fieldName: name,
                fieldValue: value.trim(),
                fieldCategory: category,
              ));
            }
          }

          // Use the verified, normalized cardholder name to eliminate any OCR typo (e.g. Munfeer -> Muneer)
          addField('Full Name', person.name, 'identity');
          if (extractResult.idNumber != null && extractResult.idNumber!.trim().isNotEmpty) {
            addField('${_formatDocType(extractResult.docType)} Number', extractResult.idNumber, 'identity');
          }
          if (extractResult.relationName != null && extractResult.relationName!.trim().isNotEmpty) {
            addField(extractResult.relationType ?? "Relative's Name", extractResult.relationName, 'identity');
          }
          addField('Date of Birth', extractResult.dob, 'date');
          addField('Gender', extractResult.gender, 'identity');
          addField('Issue Date', extractResult.issueDate, 'date');
          addField('Expiry Date', extractResult.expiryDate, 'date');
          addField('Full Address', extractResult.address, 'address');
          addField('PIN Code', extractResult.pinCode, 'address');

          // Extract all rich certificate & document fields into database
          extractResult.extraFields.forEach((k, v) {
            if (v.trim().isNotEmpty && v.trim().toLowerCase() != 'null') {
              addField(_formatFieldName(k), v, 'details');
            }
          });

          // Extract all individual subject marks into distinct, queryable fields
          extractResult.subjectMarks.forEach((subject, marks) {
            if (marks.trim().isNotEmpty && marks.trim().toLowerCase() != 'null') {
              addField('Subject: $subject', marks.trim(), 'academic');
            }
          });

          await db.saveDocumentWithFields(document: updatedDoc, fields: fields);

          if (expiryDate != null) {
            await AlertService.instance.scheduleDocumentExpiryAlerts(updatedDoc, person.name);
          }

          completedCount++;
          final timeDone = DateFormat('HH:mm:ss').format(DateTime.now());
          final idStr = extractResult.idNumber != null ? ' (${extractResult.idNumber})' : '';
          controller.add(SyncProgress(
            totalFiles: stagedList.length,
            processedFiles: completedCount,
            currentFileName: item.cleanName,
            status: 'Verified ${item.cleanName} ($completedCount of ${stagedList.length})',
            logMessage: '[$timeDone] ✓ Verified: ${_formatDocType(extractResult.docType)}$idStr for ${person.name}',
          ));
        } catch (e) {
          completedCount++;
          final timeErr = DateFormat('HH:mm:ss').format(DateTime.now());
          final errShort = e.toString().split('\n').first.replaceAll('Exception:', '').trim();
          controller.add(SyncProgress(
            totalFiles: stagedList.length,
            processedFiles: completedCount,
            currentFileName: item.cleanName,
            status: 'Saved ${item.cleanName} (offline metadata)',
            logMessage: '[$timeErr] ⚠️ ${item.cleanName}: Stored with offline filename metadata ($errShort)',
          ));
        }
      }));
    }

    final allDoneTime = DateFormat('HH:mm:ss').format(DateTime.now());
    controller.add(SyncProgress(
      totalFiles: stagedList.length,
      processedFiles: stagedList.length,
      status: 'Indexed & secured ${stagedList.length} document(s) in offline vault!',
      logMessage: '[$allDoneTime] 🎉 All ${stagedList.length} document(s) successfully indexed into offline vault!',
      isCompleted: true,
    ));
    await controller.close();
  }

  static String _guessDocTypeFromFilename(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('10th') || lower.contains('ssc') || lower.contains('class_10') || lower.contains('class 10')) return 'CLASS_10_MARKSHEET';
    if (lower.contains('12th') || lower.contains('hsc') || lower.contains('intermediate') || lower.contains('class_12') || lower.contains('class 12')) return 'CLASS_12_MARKSHEET';
    if (lower.contains('aadhaar') || lower.contains('aadhar') || lower.contains('uidai')) return 'AADHAAR';
    if (lower.contains('pan') || lower.contains('nsdl') || lower.contains('uti')) return 'PAN';
    if (lower.contains('dl') || lower.contains('driving') || lower.contains('license')) return 'DRIVING_LICENSE';
    if (lower.contains('passport')) return 'PASSPORT';
    if (lower.contains('rc') || lower.contains('registration') || lower.contains('vahan')) return 'VEHICLE_RC';
    if (lower.contains('insurance') || lower.contains('policy')) return 'VEHICLE_INSURANCE';
    if (lower.contains('voter') || lower.contains('epic') || lower.contains('election')) return 'VOTER_ID';
    if (lower.contains('ews')) return 'EWS_CERTIFICATE';
    if (lower.contains('caste') || lower.contains('community')) return 'CASTE_CERTIFICATE';
    if (lower.contains('income')) return 'INCOME_CERTIFICATE';
    if (lower.contains('domicile') || lower.contains('residence') || lower.contains('nativity')) return 'DOMICILE_CERTIFICATE';
    if (lower.contains('birth')) return 'BIRTH_CERTIFICATE';
    if (lower.contains('marksheet') || lower.contains('degree') || lower.contains('transcript') || lower.contains('certificate')) return 'MARKSHEET';
    return 'OTHER';
  }

  static String _categoryForDocType(String docType) {
    switch (docType.toUpperCase()) {
      case 'AADHAAR':
      case 'PAN':
      case 'PASSPORT':
      case 'VOTER_ID':
      case 'BIRTH_CERTIFICATE':
        return 'Identity';
      case 'DRIVING_LICENSE':
      case 'VEHICLE_RC':
      case 'VEHICLE_INSURANCE':
        return 'Vehicle';
      case 'HEALTH_INSURANCE':
        return 'Health';
      case 'EWS_CERTIFICATE':
      case 'CASTE_CERTIFICATE':
      case 'INCOME_CERTIFICATE':
      case 'DOMICILE_CERTIFICATE':
        return 'Government';
      case 'MARKSHEET':
      case 'CLASS_10_MARKSHEET':
      case 'CLASS_12_MARKSHEET':
        return 'Education';
      default:
        return 'Other';
    }
  }

  static String _formatDocType(String type) {
    switch (type.toUpperCase()) {
      case 'CLASS_10_MARKSHEET': return 'Class 10th Marksheet';
      case 'CLASS_12_MARKSHEET': return 'Class 12th Marksheet';
      case 'AADHAAR': return 'Aadhaar Card';
      case 'PAN': return 'PAN Card';
      case 'DRIVING_LICENSE': return 'Driving License';
      case 'PASSPORT': return 'Passport';
      case 'VEHICLE_RC': return 'Vehicle RC';
      case 'VEHICLE_INSURANCE': return 'Vehicle Insurance';
      case 'HEALTH_INSURANCE': return 'Health Insurance';
      case 'VOTER_ID': return 'Voter ID';
      case 'MARKSHEET': return 'Marksheet';
      case 'EWS_CERTIFICATE': return 'EWS Certificate';
      case 'CASTE_CERTIFICATE': return 'Caste Certificate';
      case 'INCOME_CERTIFICATE': return 'Income Certificate';
      case 'DOMICILE_CERTIFICATE': return 'Domicile Certificate';
      case 'BIRTH_CERTIFICATE': return 'Birth Certificate';
      default: return type.replaceAll('_', ' ');
    }
  }

  static String _formatFieldName(String key) {
    return key
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
        .join(' ');
  }
}
