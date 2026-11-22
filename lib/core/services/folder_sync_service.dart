import 'dart:io';
import 'package:file_picker/file_picker.dart';
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

class FolderSyncService {
  static const String _prefFolderPath = 'vault_folder_path';
  static const _uuid = Uuid();
  static const supportedExtensions = {'.pdf', '.png', '.jpg', '.jpeg', '.docx'};

  static Future<String?> getSelectedFolderPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefFolderPath);
  }

  static Future<void> setSelectedFolderPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefFolderPath, path);
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

  /// Pick one or multiple files directly (.pdf, .png, .jpg, .jpeg, .docx)
  /// Guaranteed to work on all modern Android versions (SAF-compliant)
  static Future<List<File>> pickDocumentFiles() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'docx'],
    );
    if (result.isNotEmpty) {
      return result
          .where((pf) => pf.path != null)
          .map((pf) => File(pf.path!))
          .where((f) => f.existsSync())
          .toList();
    }
    return [];
  }

  /// Lets the user pick a folder via native directory picker and persists it.
  static Future<String?> pickFolder() async {
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: 'Select your Documents Vault Folder',
    );
    if (result != null && result.isNotEmpty) {
      await setSelectedFolderPath(result);
      return result;
    }
    return null;
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

    final dir = Directory(targetPath);
    if (!await dir.exists()) {
      yield SyncProgress(
        status: 'Folder not found',
        error: 'The folder at $targetPath is not directly accessible. Try "Select Files Directly".',
        isCompleted: true,
      );
      return;
    }

    yield SyncProgress(status: 'Scanning folder for documents...');

    List<File> files = [];
    try {
      files = dir
          .listSync(recursive: false)
          .whereType<File>()
          .where((file) {
            final ext = p.extension(file.path).toLowerCase();
            return supportedExtensions.contains(ext);
          })
          .toList();
    } catch (e) {
      yield SyncProgress(
        status: 'Scoped access restricted',
        error: 'System restricted access to folder. Please use "Pick Files Directly".',
        isCompleted: true,
      );
      return;
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
      processedCount++;

      yield SyncProgress(
        totalFiles: newFiles.length,
        processedFiles: processedCount,
        currentFileName: originalName,
        status: 'Analyzing $originalName with Vision AI...',
      );

      try {
        // Copy to permanent app storage to ensure 100% offline persistence
        final safeBaseName = originalName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
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
          fileName: originalName,
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
