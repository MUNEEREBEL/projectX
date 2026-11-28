import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../models/person.dart';
import '../../models/document_model.dart';
import '../../models/document_field.dart';
import '../../models/expiry_alert.dart';
import '../services/person_resolution_engine.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._internal();
  DatabaseService._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      if (databaseFactoryOrNull != databaseFactoryFfi) {
        databaseFactory = databaseFactoryFfi;
      }
    }

    String path;
    if (Platform.isAndroid || Platform.isIOS) {
      final docsDir = await getApplicationDocumentsDirectory();
      path = join(docsDir.path, 'privdoc_vault.db');
    } else {
      path = join(Directory.current.path, 'privdoc_vault.db');
    }

    return await openDatabase(
      path,
      version: 1,
      onOpen: (db) async {
        try {
          await db.execute('''
            UPDATE documents 
            SET title = SUBSTR(title, INSTR(title, ' - ') + 3)
            WHERE title LIKE '% - %' AND (title LIKE 'Primary Cardholder - %' OR title LIKE 'Primary User - %');
          ''');
        } catch (_) {}
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE persons (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            relationship TEXT NOT NULL,
            dob TEXT,
            gender TEXT,
            avatar_color_index INTEGER DEFAULT 0,
            created_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE documents (
            id TEXT PRIMARY KEY,
            person_id TEXT NOT NULL,
            doc_type TEXT NOT NULL,
            category TEXT NOT NULL,
            title TEXT NOT NULL,
            id_number TEXT,
            issue_date TEXT,
            expiry_date TEXT,
            file_path TEXT NOT NULL,
            file_name TEXT NOT NULL,
            file_type TEXT NOT NULL,
            raw_text TEXT,
            is_verified INTEGER DEFAULT 1,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY (person_id) REFERENCES persons(id) ON DELETE CASCADE
          )
        ''');

        await db.execute('''
          CREATE TABLE document_fields (
            id TEXT PRIMARY KEY,
            document_id TEXT NOT NULL,
            field_name TEXT NOT NULL,
            field_value TEXT NOT NULL,
            field_category TEXT NOT NULL,
            is_copyable INTEGER DEFAULT 1,
            FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE CASCADE
          )
        ''');

        await db.execute('''
          CREATE TABLE alerts (
            id TEXT PRIMARY KEY,
            document_id TEXT NOT NULL,
            person_name TEXT NOT NULL,
            document_title TEXT NOT NULL,
            expiry_date TEXT NOT NULL,
            days_before INTEGER NOT NULL,
            is_notified INTEGER DEFAULT 0,
            scheduled_at TEXT NOT NULL,
            FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE CASCADE
          )
        ''');
      },
    );
  }

  // --- Persons ---
  Future<List<Person>> getAllPersons() async {
    final db = await database;
    final res = await db.query('persons', orderBy: 'created_at ASC');
    return res.map((m) => Person.fromMap(m)).toList();
  }

  Future<Person?> getPersonById(String id) async {
    final db = await database;
    final res = await db.query('persons', where: 'id = ?', whereArgs: [id]);
    if (res.isEmpty) return null;
    return Person.fromMap(res.first);
  }

  Future<void> upsertPerson(Person person) async {
    final db = await database;
    await db.insert(
      'persons',
      person.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // --- Documents ---
  Future<List<DocumentModel>> getAllDocuments() async {
    final db = await database;
    final res = await db.query('documents', orderBy: 'created_at DESC');
    return res.map((m) => DocumentModel.fromMap(m)).toList();
  }

  Future<DocumentModel?> getDocumentById(String id) async {
    final db = await database;
    final res = await db.query('documents', where: 'id = ?', whereArgs: [id]);
    if (res.isEmpty) return null;
    return DocumentModel.fromMap(res.first);
  }

  Future<List<DocumentModel>> getDocumentsForPerson(String personId) async {
    final db = await database;
    final res = await db.query(
      'documents',
      where: 'person_id = ?',
      whereArgs: [personId],
      orderBy: 'created_at DESC',
    );
    return res.map((m) => DocumentModel.fromMap(m)).toList();
  }

  Future<List<DocumentModel>> getExpiringDocuments({int daysAhead = 60}) async {
    final db = await database;
    final now = DateTime.now();
    final threshold = now.add(Duration(days: daysAhead));

    final res = await db.rawQuery('''
      SELECT * FROM documents 
      WHERE expiry_date IS NOT NULL 
      AND expiry_date <= ? 
      ORDER BY expiry_date ASC
    ''', [threshold.toIso8601String()]);

    return res.map((m) => DocumentModel.fromMap(m)).toList();
  }

  Future<void> saveDocumentWithFields({
    required DocumentModel document,
    required List<DocumentField> fields,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert(
        'documents',
        document.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await txn.delete(
        'document_fields',
        where: 'document_id = ?',
        whereArgs: [document.id],
      );

      for (final field in fields) {
        await txn.insert('document_fields', field.toMap());
      }
    });
    await writeVaultCache();
  }

  Future<void> deleteDocument(String id) async {
    final db = await database;
    await db.delete('documents', where: 'id = ?', whereArgs: [id]);
    await db.delete('document_fields', where: 'document_id = ?', whereArgs: [id]);
    await db.delete('alerts', where: 'document_id = ?', whereArgs: [id]);
    await writeVaultCache();
  }

  Future<void> updateDocumentField(DocumentField field) async {
    final db = await database;
    await db.update(
      'document_fields',
      field.toMap(),
      where: 'id = ?',
      whereArgs: [field.id],
    );
  }

  Future<void> updateDocument(DocumentModel document) async {
    final db = await database;
    await db.update(
      'documents',
      document.toMap(),
      where: 'id = ?',
      whereArgs: [document.id],
    );
  }

  // --- Fields ---
  Future<List<DocumentField>> getFieldsForDocument(String documentId) async {
    final db = await database;
    final res = await db.query(
      'document_fields',
      where: 'document_id = ?',
      whereArgs: [documentId],
    );
    return res.map((m) => DocumentField.fromMap(m)).toList();
  }

  /// Alias for getFieldsForDocument
  Future<List<DocumentField>> getDocumentFields(String documentId) => getFieldsForDocument(documentId);

  Future<List<Map<String, dynamic>>> searchFields(String query, {String? personId}) async {
    final db = await database;
    String sql = '''
      SELECT f.*, d.title as doc_title, d.doc_type, p.name as person_name
      FROM document_fields f
      JOIN documents d ON f.document_id = d.id
      JOIN persons p ON d.person_id = p.id
      WHERE (f.field_name LIKE ? OR f.field_value LIKE ? OR d.title LIKE ?)
    ''';
    List<dynamic> args = ['%$query%', '%$query%', '%$query%'];

    if (personId != null && personId.isNotEmpty) {
      sql += ' AND d.person_id = ?';
      args.add(personId);
    }

    sql += ' LIMIT 30';
    return await db.rawQuery(sql, args);
  }

  // --- Alerts ---
  Future<List<ExpiryAlert>> getAllAlerts() async {
    final db = await database;
    final res = await db.query('alerts', orderBy: 'scheduled_at ASC');
    return res.map((m) => ExpiryAlert.fromMap(m)).toList();
  }

  Future<void> saveAlerts(List<ExpiryAlert> alerts) async {
    final db = await database;
    final batch = db.batch();
    for (final alert in alerts) {
      batch.insert('alerts', alert.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> cleanLegacyTitlesAndOwner(String realOwnerName) async {
    final db = await database;
    try {
      await db.execute('''
        UPDATE persons SET name = ? WHERE name = 'Primary Cardholder' OR name = 'Primary User';
      ''', [realOwnerName]);
      await db.execute('''
        UPDATE document_fields SET field_value = ? WHERE field_name = 'Full Name' AND (field_value = 'Primary Cardholder' OR field_value = 'Primary User');
      ''', [realOwnerName]);
      await db.execute('''
        UPDATE documents 
        SET title = SUBSTR(title, INSTR(title, ' - ') + 3)
        WHERE title LIKE '% - %' AND (title LIKE 'Primary Cardholder - %' OR title LIKE 'Primary User - %' OR title LIKE '$realOwnerName - %');
      ''');
    } catch (_) {}
  }

  Future<int> cleanupDuplicates() async {
    final allDocs = await getAllDocuments();
    final seenByPath = <String, DocumentModel>{};
    final toDelete = <String>{};

    for (final doc in allDocs) {
      final pathKey = doc.filePath.trim().toLowerCase();
      if (pathKey.isEmpty) continue;

      if (seenByPath.containsKey(pathKey)) {
        final existing = seenByPath[pathKey]!;
        // If one is verified and other is not, keep the verified one
        if (!existing.isVerified && doc.isVerified) {
          toDelete.add(existing.id);
          seenByPath[pathKey] = doc;
        } else {
          toDelete.add(doc.id);
        }
      } else {
        seenByPath[pathKey] = doc;
      }
    }

    for (final id in toDelete) {
      await deleteDocument(id);
    }

    // Merge duplicate person variations (e.g. "MUNeer shaik" and "shaik muneer")
    await cleanupDuplicatePersons();
    await writeVaultCache();

    return toDelete.length;
  }

  /// Canonical deduplication of persons (handles inverted names, case differences, and aliases)
  Future<void> cleanupDuplicatePersons() async {
    final db = await database;
    final persons = await getAllPersons();
    if (persons.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final ownerName = (prefs.getString('vault_owner_name') ?? '').trim();

    // Step 1: Identify or promote the primary self person
    Person? selfPerson;
    try {
      selfPerson = persons.firstWhere((p) => p.relationship == 'Self');
    } catch (_) {
      selfPerson = persons.first;
    }

    final canonicalOwner = (ownerName.isNotEmpty && ownerName != 'Primary User' && ownerName != 'Primary Cardholder')
        ? ownerName
        : (selfPerson.name != 'Primary User' && selfPerson.name != 'Primary Cardholder' ? selfPerson.name : '');

    if (canonicalOwner.isNotEmpty && selfPerson.name != canonicalOwner) {
      await db.execute('UPDATE persons SET name = ?, relationship = ? WHERE id = ?', [canonicalOwner, 'Self', selfPerson.id]);
      selfPerson = Person(
        id: selfPerson.id,
        name: canonicalOwner,
        relationship: 'Self',
        dob: selfPerson.dob,
        gender: selfPerson.gender,
        avatarColorIndex: selfPerson.avatarColorIndex,
      );
    }

    // Step 2: Merge duplicate persons
    final masterPersons = <Person>[selfPerson];
    final personRemap = <String, String>{}; // duplicateId -> masterId

    // Step 1b: Purge placeholder persons (e.g. "mother", "ration card holder", "card holder", "unknown")
    for (final p in persons) {
      if (p.id == selfPerson.id) continue;
      if (PersonResolutionEngine.isGenericPlaceholder(p.name)) {
        Person? legitimateMatch;
        for (final valid in persons) {
          if (!PersonResolutionEngine.isGenericPlaceholder(valid.name) &&
              valid.relationship.toLowerCase() == p.relationship.toLowerCase()) {
            legitimateMatch = valid;
            break;
          }
        }
        personRemap[p.id] = legitimateMatch?.id ?? selfPerson.id;
      }
    }

    for (final p in persons) {
      if (p.id == selfPerson.id || personRemap.containsKey(p.id)) continue;

      // Check if p is a variation of the owner (e.g. "shaik muneer" vs "MUNeer shaik")
      if ((canonicalOwner.isNotEmpty && PersonResolutionEngine.isNameMatch(p.name, canonicalOwner)) ||
          PersonResolutionEngine.isNameMatch(p.name, selfPerson.name) ||
          p.relationship == 'Self') {
        personRemap[p.id] = selfPerson.id;
        continue;
      }

      // Check if p is a duplicate of an existing family member
      Person? match;
      for (final master in masterPersons) {
        if (PersonResolutionEngine.isNameMatch(p.name, master.name)) {
          match = master;
          break;
        }
      }

      if (match != null) {
        personRemap[p.id] = match.id;
      } else {
        masterPersons.add(p);
      }
    }

    // Step 3: Remap documents and delete duplicate persons
    for (final entry in personRemap.entries) {
      final duplicateId = entry.key;
      final masterId = entry.value;
      await db.execute(
        'UPDATE documents SET person_id = ? WHERE person_id = ?',
        [masterId, duplicateId],
      );
      await db.delete('persons', where: 'id = ?', whereArgs: [duplicateId]);
    }

    // Step 4: Fix any "Primary User" or "Primary Cardholder" for self documents only
    if (canonicalOwner.isNotEmpty) {
      await db.execute('''
        UPDATE document_fields 
        SET field_value = ? 
        WHERE field_name = 'Full Name' 
        AND (field_value = 'Primary User' OR field_value = 'Primary Cardholder')
        AND document_id IN (SELECT id FROM documents WHERE person_id = ?);
      ''', [canonicalOwner, selfPerson.id]);
    }

    // Step 5: Automatically link documents to their true family member based on extracted 'Full Name'
    final freshPersons = await getAllPersons();
    final allDocs = await getAllDocuments();
    for (final doc in allDocs) {
      final fields = await getFieldsForDocument(doc.id);
      String? extractedName;
      for (final f in fields) {
        if (f.fieldName == 'Full Name' && !PersonResolutionEngine.isGenericPlaceholder(f.fieldValue)) {
          extractedName = f.fieldValue.trim();
          break;
        }
      }
      if (extractedName != null && extractedName.isNotEmpty) {
        for (final p in freshPersons) {
          if (PersonResolutionEngine.isNameMatch(extractedName, p.name)) {
            if (doc.personId != p.id) {
              await db.execute('UPDATE documents SET person_id = ? WHERE id = ?', [p.id, doc.id]);
            }
            break;
          }
        }
      }
    }

    // Step 5b: Reconcile shared ID numbers (e.g. Aadhaar Back mistakenly linked to Father)
    final aadhaarOwners = <String, String>{};
    for (final doc in allDocs) {
      if (doc.docType.toUpperCase() == 'AADHAAR' && doc.idNumber != null && doc.idNumber!.replaceAll(' ', '').length == 12) {
        final cleanId = doc.idNumber!.replaceAll(' ', '');
        final titleLow = doc.title.toLowerCase();
        if (!titleLow.contains('back') && !aadhaarOwners.containsKey(cleanId)) {
          aadhaarOwners[cleanId] = doc.personId;
        }
      }
    }
    for (final doc in allDocs) {
      if (doc.docType.toUpperCase() == 'AADHAAR' && doc.idNumber != null) {
        final cleanId = doc.idNumber!.replaceAll(' ', '');
        final canonicalOwner = aadhaarOwners[cleanId];
        if (canonicalOwner != null && doc.personId != canonicalOwner) {
          await db.execute('UPDATE documents SET person_id = ? WHERE id = ?', [canonicalOwner, doc.id]);
        }
      }
    }
  }

  /// Exports an instant local JSON cache for fast background/overlay access
  Future<void> writeVaultCache() async {
    try {
      final docs = await getAllDocuments();
      final persons = await getAllPersons();
      final personMap = {for (var p in persons) p.id: p.name};

      final cacheList = <Map<String, dynamic>>[];
      for (final doc in docs) {
        final fields = await getFieldsForDocument(doc.id);

        // Prioritize actual extracted holder name from document fields
        String effectiveOwner = personMap[doc.personId] ?? 'Self';
        for (final f in fields) {
          final low = f.fieldName.toLowerCase().trim();
          if ((low == 'full name' ||
                  low == 'name' ||
                  low == 'holder name' ||
                  low == 'cardholder name' ||
                  low == 'student name' ||
                  low == 'candidate name' ||
                  low == 'policy holder' ||
                  low == 'insured name' ||
                  low == 'patient name' ||
                  low.contains('applicant')) &&
              f.fieldValue.trim().isNotEmpty &&
              f.fieldValue.toLowerCase() != 'unknown' &&
              f.fieldValue.toLowerCase() != 'primary user' &&
              f.fieldValue.toLowerCase() != 'primary cardholder') {
            effectiveOwner = f.fieldValue.trim();
            break;
          }
        }

        cacheList.add({
          'id': doc.id,
          'title': doc.title,
          'category': doc.category,
          'doc_type': doc.docType,
          'owner': effectiveOwner,
          'id_number': doc.idNumber,
          'expiry_date': doc.expiryDate?.toIso8601String(),
          'file_path': doc.filePath,
          'fields': fields.map((f) => {
            'name': f.fieldName,
            'value': f.fieldValue,
            'category': f.fieldCategory,
          }).toList(),
        });
      }

      Directory? appDir;
      if (Platform.isAndroid || Platform.isIOS) {
        appDir = await getApplicationDocumentsDirectory();
      } else {
        appDir = Directory.current;
      }
      final cacheFile = File(join(appDir.path, 'vault_cache.json'));
      await cacheFile.writeAsString(jsonEncode(cacheList), flush: true);
    } catch (_) {}
  }

  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('document_fields');
    await db.delete('alerts');
    await db.delete('documents');
    await db.delete('persons');
  }
}
