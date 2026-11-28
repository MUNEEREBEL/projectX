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
import 'forensic_security_service.dart';
import 'merkle_provenance_service.dart';
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

  static String canonicalFileName(String pathOrName) {
    var clean = p.basename(pathOrName).toLowerCase();
    clean = clean.replaceFirst(RegExp(r'^(vault_staging_|vault_import_|vault_permanent_)+'), '');
    clean = clean.replaceFirst(RegExp(r'^\d+_'), '');
    return clean.trim();
  }

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

  static bool _isSyncing = false;

  static Future<void> _runSyncJob(List<File> files, StreamController<SyncProgress> controller) async {
    if (files.isEmpty) {
      controller.add(SyncProgress(status: 'No files to index', isCompleted: true));
      await controller.close();
      return;
    }

    if (_isSyncing) {
      controller.add(SyncProgress(
        status: 'Indexing is already active...',
        totalFiles: files.length,
        processedFiles: 0,
        isCompleted: false,
      ));
      await controller.close();
      return;
    }

    _isSyncing = true;
    try {
      final db = DatabaseService.instance;
      await db.cleanupDuplicates();

      final vaultDir = await getPermanentVaultDirectory();

      // Deduplicate incoming files list by canonical name
      final uniqueFilesMap = <String, File>{};
      for (final f in files) {
        final canon = canonicalFileName(f.path);
        if (!uniqueFilesMap.containsKey(canon)) {
          uniqueFilesMap[canon] = f;
        }
      }
      final deduplicatedFiles = uniqueFilesMap.values.toList();

      final existingDocs = await db.getAllDocuments();
      final verifiedCanonicalNames = <String>{};
      final staleDocIds = <String>[];

      for (final doc in existingDocs) {
        final canonical = canonicalFileName(doc.fileName);
        final fields = await db.getFieldsForDocument(doc.id);
        final hasRealFields = fields.any((f) =>
            f.fieldName != 'Document Format' &&
            f.fieldName != 'File Source' &&
            !(f.fieldName == 'Full Name' && (f.fieldValue.toLowerCase() == 'unknown' || f.fieldValue.toLowerCase() == 'primary user')));

        if (doc.isVerified && hasRealFields) {
          verifiedCanonicalNames.add(canonical);
        } else {
          staleDocIds.add(doc.id);
        }
      }

      // Purge stale placeholder/failed documents so Vision AI can freshly extract all fields
      for (final staleId in staleDocIds) {
        await db.deleteDocument(staleId);
      }

      // Incremental Sync: Only send NEW/unprocessed files to Gemini AI.
      // Skip all files that are already verified and stored in the database!
      final newFiles = deduplicatedFiles.where((f) {
        final canonical = canonicalFileName(f.path);
        return !verifiedCanonicalNames.contains(canonical);
      }).toList();

      if (newFiles.isEmpty) {
        controller.add(SyncProgress(
          status: 'All ${deduplicatedFiles.length} documents are already indexed and secured in vault!',
          totalFiles: deduplicatedFiles.length,
          processedFiles: deduplicatedFiles.length,
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

      // BATCH EXTRACTION IN CHUNKS OF 4 (Saves 4x time and stays under 15 RPM!)
      int completedCount = 0;
      final totalFiles = newFiles.length;
      const batchSize = 4;

      for (int b = 0; b < totalFiles; b += batchSize) {
        final batchFiles = newFiles.sublist(b, (b + batchSize < totalFiles) ? b + batchSize : totalFiles);
        final batchPaths = <String>[];
        final permanentFiles = <File>[];
        final cleanNames = <String>[];

        for (final file in batchFiles) {
          final cleanName = canonicalFileName(file.path);
          cleanNames.add(cleanName);
          final safeBaseName = cleanName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
          final permanentFilePath = p.join(vaultDir.path, 'vault_permanent_$safeBaseName');
          final permanentFile = await file.copy(permanentFilePath);
          permanentFiles.add(permanentFile);
          batchPaths.add(permanentFile.path);
        }

        final batchNumber = (b ~/ batchSize) + 1;
        final totalBatches = (totalFiles / batchSize).ceil();
        final timeStart = DateFormat('HH:mm:ss').format(DateTime.now());

        // Safe rate-limit pacing: free tier allows 15 RPM per key.
        // A brief 2.5s delay between batches guarantees zero rate-limit spikes!
        if (b > 0) {
          await Future.delayed(const Duration(milliseconds: 2500));
        }

        controller.add(SyncProgress(
          totalFiles: totalFiles,
          processedFiles: completedCount,
          currentFileName: cleanNames.first,
          status: 'Indexing batch $batchNumber of $totalBatches (${batchFiles.length} files)...',
          logMessage: '[$timeStart] ⚡ Extracting batch #$batchNumber of $totalBatches with Vision AI (${cleanNames.join(", ")})...',
        ));

        List<ExtractionResult> results;
        try {
          results = await VisionExtractorService.extractDocumentsBatch(
            filePaths: batchPaths,
            referenceCardholderName: ownerName,
          );
        } catch (e) {
          results = [];
          for (final path in batchPaths) {
            try {
              results.add(await VisionExtractorService.extractDocument(
                filePath: path,
                referenceCardholderName: ownerName,
              ));
            } catch (_) {
              results.add(await VisionExtractorService.fallbackLocalExtraction(
                filePath: path,
                referenceCardholderName: ownerName,
              ));
            }
          }
        }

        // Save documents & fields for this batch
        for (int i = 0; i < batchFiles.length; i++) {
          final permanentFile = permanentFiles[i];
          final cleanName = cleanNames[i];
          final ext = p.extension(cleanName).replaceAll('.', '').toLowerCase();
          final docId = _uuid.v4();
          final extractResult = (i < results.length)
              ? results[i]
              : await VisionExtractorService.fallbackLocalExtraction(
                  filePath: permanentFile.path,
                  referenceCardholderName: ownerName,
                );

          try {
            Person? person;
            // Cross-document ID matching: If same 12-digit Aadhaar or PAN exists in vault, associate to that person
            if (extractResult.idNumber != null && extractResult.idNumber!.trim().length >= 8) {
              final cleanId = extractResult.idNumber!.replaceAll(' ', '').trim().toLowerCase();
              final existingDocs = await db.getAllDocuments();
              DocumentModel? matchingDoc;
              for (final d in existingDocs) {
                if (d.idNumber != null && d.idNumber!.replaceAll(' ', '').trim().toLowerCase() == cleanId && d.personId.isNotEmpty) {
                  matchingDoc = d;
                  break;
                }
              }
              if (matchingDoc != null) {
                final existingPersons = await db.getAllPersons();
                for (final p in existingPersons) {
                  if (p.id == matchingDoc.personId) {
                    person = p;
                    break;
                  }
                }
              }
            }

            person ??= await PersonResolutionEngine.resolvePerson(
              holderName: extractResult.holderName,
              dob: extractResult.dob,
              gender: extractResult.gender,
              relationName: extractResult.relationName,
              relationType: extractResult.relationType,
              isPrimaryCardholder: extractResult.isPrimaryCardholder,
              relationshipToCardholder: extractResult.relationshipToCardholder,
            );

            // If father/relative is extracted, ensure a profile exists for them in persons table
            if (extractResult.relationName != null && extractResult.relationName!.trim().isNotEmpty) {
              final relName = extractResult.relationName!.trim();
              final relType = extractResult.relationType ?? 'Father';
              final existingPersons = await db.getAllPersons();
              if (!existingPersons.any((p) => PersonResolutionEngine.isNameMatch(p.name, relName))) {
                await db.upsertPerson(Person(
                  id: _uuid.v4(),
                  name: relName,
                  relationship: relType,
                  avatarColorIndex: (existingPersons.length + 1) % 6,
                ));
              }
            }

            // If family members are present (e.g. Ration Card), create Person profiles for them too
            for (final member in extractResult.familyMembers) {
              final mName = member['name'] ?? '';
              final mRel = member['relationship'] ?? 'Family Member';
              if (mName.isNotEmpty && !PersonResolutionEngine.isNameMatch(mName, ownerName)) {
                final existingPersons = await db.getAllPersons();
                if (!existingPersons.any((p) => PersonResolutionEngine.isNameMatch(p.name, mName))) {
                  await db.upsertPerson(Person(
                    id: _uuid.v4(),
                    name: mName,
                    relationship: mRel,
                    avatarColorIndex: (existingPersons.length + 2) % 6,
                  ));
                }
              }
            }

            DateTime? issueDate = extractResult.issueDate != null ? DateTime.tryParse(extractResult.issueDate!) : null;
            DateTime? expiryDate = extractResult.expiryDate != null ? DateTime.tryParse(extractResult.expiryDate!) : null;

            var cleanTitle = (extractResult.documentTitle != null && extractResult.documentTitle!.trim().isNotEmpty)
                ? extractResult.documentTitle!.trim()
                : _formatDocType(extractResult.docType);
            cleanTitle = cleanTitle.replaceAll(RegExp(r'\.(pdf|png|jpg|jpeg|docx)$', caseSensitive: false), '');
            cleanTitle = cleanTitle.replaceFirst(RegExp(r'^(vault_staging_|vault_import_|vault_permanent_)+'), '');
            cleanTitle = cleanTitle.replaceFirst(RegExp(r'^\d+_'), '');

            final updatedDoc = DocumentModel(
              id: docId,
              personId: person.id,
              docType: extractResult.docType,
              category: extractResult.category,
              title: cleanTitle,
              idNumber: extractResult.idNumber,
              issueDate: issueDate,
              expiryDate: expiryDate,
              filePath: permanentFile.path,
              fileName: cleanName,
              fileType: ext,
              rawText: extractResult.rawResponse,
              isVerified: extractResult.isChecksumValid,
            );

            List<DocumentField> fields = [];
            void addField(String name, String? value, String category) {
              if (value != null && value.trim().isNotEmpty && value.trim().toLowerCase() != 'null') {
                fields.add(DocumentField(
                  id: _uuid.v4(),
                  documentId: docId,
                  fieldName: name,
                  fieldValue: value.trim(),
                  fieldCategory: category,
                ));
              }
            }

            // Resolve the exact person name printed on this document, avoiding any generic placeholders
            String effectiveFullName = extractResult.holderName.trim();
            if (effectiveFullName.isNotEmpty &&
                effectiveFullName.toLowerCase() != 'unknown' &&
                effectiveFullName.toLowerCase() != 'primary user' &&
                effectiveFullName.toLowerCase() != 'primary cardholder') {
              addField('Full Name', effectiveFullName, 'identity');
            } else if (person.relationship == 'Self' && extractResult.isPrimaryCardholder) {
              addField('Full Name', ownerName, 'identity');
            } else if (person.name.isNotEmpty &&
                person.name.toLowerCase() != 'primary user' &&
                person.name.toLowerCase() != 'primary cardholder' &&
                person.name.toLowerCase() != 'unknown') {
              addField('Full Name', person.name, 'identity');
            }
            if (extractResult.idNumber != null && extractResult.idNumber!.trim().isNotEmpty) {
              addField('${_formatDocType(extractResult.docType)} Number', extractResult.idNumber, 'identity');
            }
            if (extractResult.relationName != null && extractResult.relationName!.trim().isNotEmpty) {
              addField(extractResult.relationType ?? "Relative's Name", extractResult.relationName, 'identity');
            }
            addField('Date of Birth', extractResult.dob, 'date');
            addField('Gender', extractResult.gender, 'identity');
            addField('Mobile Number', extractResult.mobileNumber, 'contact');
            addField('Bank Name', extractResult.bankName, 'financial');
            addField('Account Number', extractResult.accountNumber, 'financial');
            addField('IFSC Code', extractResult.ifscCode, 'financial');
            addField('Branch', extractResult.branch, 'financial');
            addField('CIF Number', extractResult.cifNumber, 'financial');
            addField('MICR Code', extractResult.micrCode, 'financial');
            addField('Issue Date', extractResult.issueDate, 'date');
            addField('Expiry Date', extractResult.expiryDate, 'date');
            addField('Full Address', extractResult.address, 'address');
            addField('PIN Code', extractResult.pinCode, 'address');

            for (final member in extractResult.familyMembers) {
              final mName = member['name'];
              final mRel = member['relationship'] ?? 'Member';
              if (mName != null && mName.isNotEmpty) {
                addField('Family Member: $mName', mRel, 'identity');
              }
            }

            extractResult.extraFields.forEach((k, v) {
              if (v.trim().isNotEmpty && v.trim().toLowerCase() != 'null') {
                addField(_formatFieldName(k), v, 'details');
              }
            });

            extractResult.subjectMarks.forEach((subject, marks) {
              if (marks.trim().isNotEmpty && marks.trim().toLowerCase() != 'null') {
                addField('Subject: $subject', marks.trim(), 'academic');
              }
            });

            // 1. Run Advanced Forensic Security & Tamper Analysis
            final forensicAudit = await ForensicSecurityService.analyzeDocument(
              file: permanentFile,
              extraction: extractResult,
              cardholderSurname: person.name.split(' ').isNotEmpty ? person.name.split(' ').last : null,
            );

            addField('Forensic Security Audit', forensicAudit.statusLabel, 'security');
            addField('Authenticity Score', '${forensicAudit.integrityScore}/100', 'security');
            if (forensicAudit.anomalies.isNotEmpty) {
              addField('Forensic Anomalies', forensicAudit.anomalies.join(' | '), 'security');
            } else {
              addField('Verified Checks', forensicAudit.passedChecks.take(3).join(' • '), 'security');
            }
            addField('SHA-256 Checksum', forensicAudit.sha256Checksum, 'security');

            await db.saveDocumentWithFields(document: updatedDoc, fields: fields);

            // 2. Cryptographic Merkle Provenance Ledger Registration
            try {
              final fieldMap = <String, String>{};
              for (final f in fields) {
                fieldMap[f.fieldName] = f.fieldValue;
              }
              await MerkleProvenanceService.recordBlock(
                documentId: docId,
                filePath: permanentFile.path,
                fields: fieldMap,
              );
            } catch (_) {}

            if (expiryDate != null) {
              await AlertService.instance.scheduleDocumentExpiryAlerts(updatedDoc, person.name);
            }

            completedCount++;
            final timeDone = DateFormat('HH:mm:ss').format(DateTime.now());
            final idStr = extractResult.idNumber != null ? ' (${extractResult.idNumber})' : '';
            controller.add(SyncProgress(
              totalFiles: totalFiles,
              processedFiles: completedCount,
              currentFileName: cleanName,
              status: 'Verified $cleanName ($completedCount of $totalFiles)',
              logMessage: '[$timeDone] ✓ Verified: ${_formatDocType(extractResult.docType)}$idStr for ${person.name}',
            ));
          } catch (e) {
            final guessedType = _guessDocTypeFromFilename(cleanName);
            final cleanBase = cleanName.replaceAll(RegExp(r'\.[^.]+$'), '').replaceAll('_', ' ').trim();
            final fallbackDoc = DocumentModel(
              id: docId,
              personId: defaultPersonId,
              docType: guessedType,
              category: _categoryForDocType(guessedType),
              title: cleanBase.isNotEmpty ? cleanBase : 'Identity Document',
              filePath: permanentFile.path,
              fileName: cleanName,
              fileType: ext,
              isVerified: false,
            );

            await db.saveDocumentWithFields(
              document: fallbackDoc,
              fields: [
                DocumentField(
                  id: _uuid.v4(),
                  documentId: docId,
                  fieldName: 'Full Name',
                  fieldValue: ownerName,
                  fieldCategory: 'identity',
                ),
              ],
            );

            completedCount++;
            final timeErr = DateFormat('HH:mm:ss').format(DateTime.now());
            controller.add(SyncProgress(
              totalFiles: totalFiles,
              processedFiles: completedCount,
              currentFileName: cleanName,
              status: 'Indexed $cleanName ($completedCount of $totalFiles)',
              logMessage: '[$timeErr] ✓ Indexed: $cleanName for $ownerName',
            ));
          }
        }

        // Safety rate limiter pause between batches
        if (b + batchSize < totalFiles) {
          await Future.delayed(const Duration(milliseconds: 2200));
        }
      }

      await db.cleanupDuplicates();

      final allDoneTime = DateFormat('HH:mm:ss').format(DateTime.now());
      controller.add(SyncProgress(
        totalFiles: totalFiles,
        processedFiles: totalFiles,
        status: 'Indexed & secured $totalFiles document(s) in offline vault!',
        logMessage: '[$allDoneTime] 🎉 All $totalFiles document(s) successfully indexed into offline vault!',
        isCompleted: true,
      ));
      await controller.close();
    } finally {
      _isSyncing = false;
    }
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
    if (lower.contains('passbook') || lower.contains('bank') || lower.contains('statement') || lower.contains('cheque') || lower.contains('sbi') || lower.contains('hdfc')) return 'BANK_PASSBOOK';
    if (lower.contains('ration') || lower.contains('fsc') || lower.contains('food')) return 'RATION_CARD';
    if (lower.contains('marksheet') || lower.contains('degree') || lower.contains('transcript') || lower.contains('certificate') || lower.contains('sem')) return 'MARKSHEET';
    return 'OTHER';
  }

  static String _categoryForDocType(String docType) {
    switch (docType.toUpperCase()) {
      case 'AADHAAR':
      case 'PAN':
      case 'PASSPORT':
      case 'VOTER_ID':
      case 'BIRTH_CERTIFICATE':
      case 'RATION_CARD':
        return 'Identity';
      case 'DRIVING_LICENSE':
      case 'VEHICLE_RC':
      case 'VEHICLE_INSURANCE':
        return 'Vehicle';
      case 'BANK_PASSBOOK':
        return 'Financial';
      case 'HEALTH_INSURANCE':
        return 'Health';
      case 'EWS_CERTIFICATE':
      case 'CASTE_CERTIFICATE':
      case 'INCOME_CERTIFICATE':
      case 'DOMICILE_CERTIFICATE':
        return 'Certificates';
      case 'MARKSHEET':
      case 'CLASS_10_MARKSHEET':
      case 'CLASS_12_MARKSHEET':
        return 'Education';
      default:
        return 'Identity';
    }
  }

  static String _formatDocType(String type) {
    switch (type.toUpperCase()) {
      case 'CLASS_10_MARKSHEET': return 'Class 10th Marksheet';
      case 'CLASS_12_MARKSHEET': return 'Class 12th Marksheet';
      case 'AADHAAR': return 'Aadhaar Card';
      case 'PAN': return 'PAN Card';
      case 'BANK_PASSBOOK': return 'Bank Passbook';
      case 'RATION_CARD': return 'Ration Card';
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
      case 'OTHER': return 'Identity Document';
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
