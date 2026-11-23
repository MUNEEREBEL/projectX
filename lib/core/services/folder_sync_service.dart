import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../models/document_field.dart';
import '../../models/document_model.dart';
import '../config/app_config.dart';
import '../database/database_service.dart';
import 'alert_service.dart';
import 'person_resolution_engine.dart';
import 'vision_extractor_service.dart';

class SyncProgress {
  final int totalFiles;
  final int processedFiles;
  final String currentFileName;
  final String status;
  final bool isCompleted;
  final String? error;

  SyncProgress({
    this.totalFiles = 0,
    this.processedFiles = 0,
    this.currentFileName = '',
    this.status = '',
    this.isCompleted = false,
    this.error,
  });
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
  static Stream<SyncProgress> syncFiles(List<File> files) async* {
    final apiKey = await AppConfig.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      yield SyncProgress(
        status: 'API Key Not Configured',
        error: 'Please add your free Gemini API key in Settings or .env before scanning.',
        isCompleted: true,
      );
      return;
    }

    final db = DatabaseService.instance;
    final existingDocs = await db.getAllDocuments();
    final existingFileNames = existingDocs.map((d) => d.fileName.toLowerCase()).toSet();

    // Filter files that are not already indexed
    final newFiles = files.where((f) {
      final name = p.basename(f.path).toLowerCase();
      return !existingFileNames.contains(name);
    }).toList();

    if (newFiles.isEmpty) {
      yield SyncProgress(
        status: 'All ${files.length} documents are already indexed and stored in vault!',
        totalFiles: files.length,
        processedFiles: files.length,
        isCompleted: true,
      );
      return;
    }

    final vaultDir = await getPermanentVaultDirectory();
    int processedCount = 0;

    for (final file in newFiles) {
      final originalName = p.basename(file.path);
      String cleanName = originalName;
      if (cleanName.startsWith('vault_staging_') || cleanName.startsWith('vault_import_')) {
        final parts = cleanName.split('_');
        if (parts.length >= 3) {
          cleanName = parts.sublist(2).join('_');
        }
      }
      processedCount++;

      yield SyncProgress(
        totalFiles: newFiles.length,
        processedFiles: processedCount,
        currentFileName: cleanName,
        status: 'Analyzing $cleanName ($processedCount of ${newFiles.length})...',
      );

      try {
        // Copy to permanent app storage to ensure 100% offline persistence
        final safeBaseName = cleanName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
        final permanentFilePath = p.join(vaultDir.path, '${DateTime.now().millisecondsSinceEpoch}_$safeBaseName');
        final permanentFile = await file.copy(permanentFilePath);

        // 1. Extract details via Vision AI using permanent file
        final extractResult = await VisionExtractorService.extractDocument(
          filePath: permanentFile.path,
        );

        // 2. Resolve or create Person with Indian Name Disambiguation
        final person = await PersonResolutionEngine.resolvePerson(
          holderName: extractResult.holderName,
          dob: extractResult.dob,
          gender: extractResult.gender,
          relationName: extractResult.relationName,
          relationType: extractResult.relationType,
        );

        // 3. Construct DocumentModel
        final docId = _uuid.v4();
        final ext = p.extension(permanentFile.path).replaceAll('.', '').toLowerCase();

        DateTime? issueDate;
        if (extractResult.issueDate != null) {
          issueDate = DateTime.tryParse(extractResult.issueDate!);
        }

        DateTime? expiryDate;
        if (extractResult.expiryDate != null) {
          expiryDate = DateTime.tryParse(extractResult.expiryDate!);
        }

        final docTitle = '${person.name} - ${_formatDocType(extractResult.docType)}';

        final document = DocumentModel(
          id: docId,
          personId: person.id,
          docType: extractResult.docType,
          category: extractResult.category,
          title: docTitle,
          idNumber: extractResult.idNumber,
          issueDate: issueDate,
          expiryDate: expiryDate,
          filePath: permanentFile.path,
          fileName: cleanName,
          fileType: ext,
          rawText: extractResult.rawResponse,
          isVerified: extractResult.isChecksumValid,
        );

        // 4. Construct Field List
        List<DocumentField> fields = [];

        void addField(String name, String? value, String category) {
          if (value != null && value.trim().isNotEmpty) {
            fields.add(
              DocumentField(
                id: _uuid.v4(),
                documentId: docId,
                fieldName: name,
                fieldValue: value.trim(),
                fieldCategory: category,
              ),
            );
          }
        }

        addField('Full Name', extractResult.holderName, 'identity');
        addField('${_formatDocType(extractResult.docType)} Number', extractResult.idNumber, 'identity');
        if (extractResult.relationName != null) {
          addField(extractResult.relationType ?? "Relative's Name", extractResult.relationName, 'identity');
        }
        addField('Date of Birth', extractResult.dob, 'date');
        addField('Gender', extractResult.gender, 'identity');
        addField('Issue Date', extractResult.issueDate, 'date');
        addField('Expiry Date', extractResult.expiryDate, 'date');
        addField('Full Address', extractResult.address, 'address');
        addField('PIN Code', extractResult.pinCode, 'address');

        // Extra dynamic fields
        extractResult.extraFields.forEach((k, v) {
          addField(_formatFieldName(k), v, 'other');
        });

        // 5. Save to Local SQLite
        await db.saveDocumentWithFields(document: document, fields: fields);

        // 6. Schedule Expiry Alerts if applicable
        if (expiryDate != null) {
          await AlertService.instance.scheduleDocumentExpiryAlerts(document, person.name);
        }
      } catch (e) {
        yield SyncProgress(
          totalFiles: newFiles.length,
          processedFiles: processedCount,
          currentFileName: originalName,
          status: 'Error processing $originalName: $e',
          error: e.toString(),
        );
      }
    }

    yield SyncProgress(
      totalFiles: newFiles.length,
      processedFiles: newFiles.length,
      status: 'Stored & indexed ${newFiles.length} document(s) permanently in vault!',
      isCompleted: true,
    );
  }

  static String _formatDocType(String type) {
    switch (type.toUpperCase()) {
      case 'AADHAAR': return 'Aadhaar Card';
      case 'PAN': return 'PAN Card';
      case 'DRIVING_LICENSE': return 'Driving License';
      case 'PASSPORT': return 'Passport';
      case 'VEHICLE_RC': return 'Vehicle RC';
      case 'VEHICLE_INSURANCE': return 'Vehicle Insurance';
      case 'HEALTH_INSURANCE': return 'Health Insurance';
      case 'VOTER_ID': return 'Voter ID';
      case 'MARKSHEET': return 'Marksheet';
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
