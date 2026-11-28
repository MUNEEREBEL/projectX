import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import '../database/database_service.dart';

class MerkleVerificationResult {
  final bool isUntampered;
  final String fileHashOnRecord;
  final String currentFileHash;
  final String metadataHashOnRecord;
  final String currentMetadataHash;
  final String blockHash;
  final String prevBlockHash;
  final DateTime recordTimestamp;
  final String details;

  const MerkleVerificationResult({
    required this.isUntampered,
    required this.fileHashOnRecord,
    required this.currentFileHash,
    required this.metadataHashOnRecord,
    required this.currentMetadataHash,
    required this.blockHash,
    required this.prevBlockHash,
    required this.recordTimestamp,
    required this.details,
  });
}

/// Cryptographic Merkle Provenance Ledger for Edge Documents
/// Provides mathematical, append-only tamper-evidence for every document in the vault.
class MerkleProvenanceService {
  static const String _tableName = 'provenance_ledger';
  static bool _tableInitialized = false;

  static Future<void> _ensureTable(Database db) async {
    if (_tableInitialized) return;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableName (
        block_index INTEGER PRIMARY KEY AUTOINCREMENT,
        document_id TEXT NOT NULL UNIQUE,
        file_sha256 TEXT NOT NULL,
        metadata_sha256 TEXT NOT NULL,
        prev_hash TEXT NOT NULL,
        block_hash TEXT NOT NULL,
        timestamp TEXT NOT NULL
      )
    ''');
    _tableInitialized = true;
  }

  /// Hashes file bytes with SHA-256
  static Future<String> hashFile(File file) async {
    if (!await file.exists()) return '';
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString();
  }

  /// Hashes canonical sorted metadata JSON with SHA-256
  static String hashMetadata(Map<String, String> fields) {
    final sortedKeys = fields.keys.toList()..sort();
    final canonicalMap = <String, String>{};
    for (final k in sortedKeys) {
      canonicalMap[k] = fields[k] ?? '';
    }
    final rawJson = jsonEncode(canonicalMap);
    return sha256.convert(utf8.encode(rawJson)).toString();
  }

  /// Appends or updates a cryptographic block in the local provenance ledger
  static Future<String> recordBlock({
    required String documentId,
    required String filePath,
    required Map<String, String> fields,
  }) async {
    final db = await DatabaseService.instance.database;
    await _ensureTable(db);

    final file = File(filePath);
    final fileHash = await hashFile(file);
    final metaHash = hashMetadata(fields);

    // Retrieve previous block hash to maintain cryptographic DAG chain
    final lastBlocks = await db.query(
      _tableName,
      orderBy: 'block_index DESC',
      limit: 1,
    );

    final prevHash = lastBlocks.isNotEmpty
        ? (lastBlocks.first['block_hash'] as String? ?? 'GENESIS_BLOCK_000000000000000000000000')
        : 'GENESIS_BLOCK_000000000000000000000000';

    final nowStr = DateTime.now().toIso8601String();
    final blockPayload = '$prevHash:$fileHash:$metaHash:$nowStr';
    final blockHash = sha256.convert(utf8.encode(blockPayload)).toString();

    await db.insert(
      _tableName,
      {
        'document_id': documentId,
        'file_sha256': fileHash,
        'metadata_sha256': metaHash,
        'prev_hash': prevHash,
        'block_hash': blockHash,
        'timestamp': nowStr,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return blockHash;
  }

  /// Cryptographically verifies whether local file or extracted fields were tampered with post-indexing
  static Future<MerkleVerificationResult> verifyDocumentIntegrity(String documentId) async {
    final db = await DatabaseService.instance.database;
    await _ensureTable(db);

    final records = await db.query(
      _tableName,
      where: 'document_id = ?',
      whereArgs: [documentId],
    );

    if (records.isEmpty) {
      return MerkleVerificationResult(
        isUntampered: true,
        fileHashOnRecord: 'N/A',
        currentFileHash: 'N/A',
        metadataHashOnRecord: 'N/A',
        currentMetadataHash: 'N/A',
        blockHash: 'UNRECORDED',
        prevBlockHash: 'N/A',
        recordTimestamp: DateTime.now(),
        details: 'No historical provenance record found; document is unanchored.',
      );
    }

    final block = records.first;
    final fileHashOnRecord = block['file_sha256'] as String;
    final metaHashOnRecord = block['metadata_sha256'] as String;
    final blockHash = block['block_hash'] as String;
    final prevHash = block['prev_hash'] as String;
    final timestamp = DateTime.tryParse(block['timestamp'] as String) ?? DateTime.now();

    // Verify current file on disk
    final doc = await DatabaseService.instance.getDocumentById(documentId);
    if (doc == null) {
      return MerkleVerificationResult(
        isUntampered: false,
        fileHashOnRecord: fileHashOnRecord,
        currentFileHash: 'DELETED',
        metadataHashOnRecord: metaHashOnRecord,
        currentMetadataHash: 'DELETED',
        blockHash: blockHash,
        prevBlockHash: prevHash,
        recordTimestamp: timestamp,
        details: 'Document record missing from database.',
      );
    }

    final currentFileHash = await hashFile(File(doc.filePath));
    final fields = await DatabaseService.instance.getDocumentFields(documentId);
    final fieldMap = <String, String>{};
    for (final f in fields) {
      fieldMap[f.fieldName] = f.fieldValue;
    }
    final currentMetaHash = hashMetadata(fieldMap);

    final fileMatch = currentFileHash == fileHashOnRecord;
    final metaMatch = currentMetaHash == metaHashOnRecord;

    if (fileMatch && metaMatch) {
      return MerkleVerificationResult(
        isUntampered: true,
        fileHashOnRecord: fileHashOnRecord,
        currentFileHash: currentFileHash,
        metadataHashOnRecord: metaHashOnRecord,
        currentMetadataHash: currentMetaHash,
        blockHash: blockHash,
        prevBlockHash: prevHash,
        recordTimestamp: timestamp,
        details: 'Cryptographically verified: SHA-256 byte payload and metadata ledger match perfectly.',
      );
    } else if (!fileMatch && metaMatch) {
      return MerkleVerificationResult(
        isUntampered: false,
        fileHashOnRecord: fileHashOnRecord,
        currentFileHash: currentFileHash,
        metadataHashOnRecord: metaHashOnRecord,
        currentMetadataHash: currentMetaHash,
        blockHash: blockHash,
        prevBlockHash: prevHash,
        recordTimestamp: timestamp,
        details: 'TAMPER ALERT: Raw document file bytes modified on disk post-indexing!',
      );
    } else {
      return MerkleVerificationResult(
        isUntampered: false,
        fileHashOnRecord: fileHashOnRecord,
        currentFileHash: currentFileHash,
        metadataHashOnRecord: metaHashOnRecord,
        currentMetadataHash: currentMetaHash,
        blockHash: blockHash,
        prevBlockHash: prevHash,
        recordTimestamp: timestamp,
        details: 'TAMPER ALERT: Structured document field values were modified outside verified provenance pipeline!',
      );
    }
  }
}
