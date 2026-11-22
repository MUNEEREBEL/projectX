import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:x/core/database/database_service.dart';
import 'package:x/core/services/person_resolution_engine.dart';
import 'package:x/models/document_field.dart';
import 'package:x/models/document_model.dart';
import 'package:x/models/person.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    if (databaseFactoryOrNull != databaseFactoryFfi) {
      databaseFactory = databaseFactoryFfi;
    }
  });

  group('Database & Person Disambiguation Tests', () {
    final db = DatabaseService.instance;

    test('Person Resolution Engine clusters documents by family member', () async {
      // 1. Resolve first person (Self)
      final p1 = await PersonResolutionEngine.resolvePerson(
        holderName: 'Rahul Sharma',
        dob: '1994-05-15',
        gender: 'Male',
      );
      expect(p1.name, equals('Rahul Sharma'));
      expect(p1.relationship, equals('Self'));

      // 2. Incoming document with slight name variation ("RAHUL SHARMA") -> Should match p1
      final p1Variation = await PersonResolutionEngine.resolvePerson(
        holderName: 'RAHUL SHARMA',
        dob: '1994-05-15',
      );
      expect(p1Variation.id, equals(p1.id)); // Same person ID!

      // 3. Incoming document for spouse "Priya Sharma" -> Should create distinct profile
      final p2 = await PersonResolutionEngine.resolvePerson(
        holderName: 'Priya Sharma',
        dob: '1996-08-22',
        gender: 'Female',
        relationType: 'Spouse',
      );
      expect(p2.id, isNot(equals(p1.id)));
      expect(p2.name, equals('Priya Sharma'));
    });

    test('Database stores documents, fields and queries expiring docs', () async {
      final p = Person(id: 'test_p1', name: 'Rahul Sharma', relationship: 'Self');
      await db.upsertPerson(p);

      // Create a document expiring in 15 days
      final expiry = DateTime.now().add(const Duration(days: 15));
      final doc = DocumentModel(
        id: 'doc_dl_1',
        personId: p.id,
        docType: 'DRIVING_LICENSE',
        category: 'Vehicle',
        title: 'Rahul - Driving License',
        idNumber: 'DL0120190012345',
        expiryDate: expiry,
        filePath: '/test/path/dl.jpg',
        fileName: 'dl.jpg',
        fileType: 'jpg',
      );

      final fields = [
        DocumentField(
          id: 'f1',
          documentId: doc.id,
          fieldName: 'DL Number',
          fieldValue: 'DL0120190012345',
          fieldCategory: 'identity',
        ),
        DocumentField(
          id: 'f2',
          documentId: doc.id,
          fieldName: 'Full Address',
          fieldValue: 'Flat 402, Bengaluru 560103',
          fieldCategory: 'address',
        ),
      ];

      await db.saveDocumentWithFields(document: doc, fields: fields);

      // Verify retrieval
      final docs = await db.getDocumentsForPerson(p.id);
      expect(docs.length, equals(1));
      expect(docs.first.idNumber, equals('DL0120190012345'));

      // Verify expiring documents query
      final expiring = await db.getExpiringDocuments(daysAhead: 30);
      expect(expiring.any((d) => d.id == doc.id), isTrue);

      // Verify search across fields
      final searchResults = await db.searchFields('560103');
      expect(searchResults.length, equals(1));
      expect(searchResults.first['field_value'], contains('560103'));
    });
  });
}
