import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../models/person.dart';
import '../../models/document_model.dart';
import '../../models/document_field.dart';
import '../../models/expiry_alert.dart';

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
      databaseFactory = databaseFactoryFfi;
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
  }

  Future<void> deleteDocument(String id) async {
    final db = await database;
    await db.delete('documents', where: 'id = ?', whereArgs: [id]);
    await db.delete('document_fields', where: 'document_id = ?', whereArgs: [id]);
    await db.delete('alerts', where: 'document_id = ?', whereArgs: [id]);
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

  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('document_fields');
    await db.delete('alerts');
    await db.delete('documents');
    await db.delete('persons');
  }
}
