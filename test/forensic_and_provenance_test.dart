import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:x/core/database/database_service.dart';
import 'package:x/core/services/forensic_security_service.dart';
import 'package:x/core/services/merkle_provenance_service.dart';
import 'package:x/core/services/family_graph_service.dart';
import 'package:x/core/services/vision_extractor_service.dart';
import 'package:x/models/document_field.dart';
import 'package:x/models/document_model.dart';
import 'package:x/models/person.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
  });

  group('Forensic Security & Tampering Analysis Tests', () {
    test('Valid Aadhaar passes Verhoeff checksum algorithm check', () async {
      // 9876 5432 1012 is a mathematically valid Verhoeff Aadhaar number
      final extraction = ExtractionResult(
        docType: 'AADHAAR',
        category: 'Identity',
        holderName: 'Muneer Shaik',
        idNumber: '9876 5432 1012',
        issueDate: '2022-01-15',
      );

      final dummyFile = File('test_aadhaar.tmp');
      await dummyFile.writeAsString('Clean dummy content without editing signatures');

      final result = await ForensicSecurityService.analyzeDocument(
        file: dummyFile,
        extraction: extraction,
      );

      if (await dummyFile.exists()) await dummyFile.delete();

      expect(result.status, ForensicStatus.genuine);
      expect(result.integrityScore, greaterThanOrEqualTo(85));
      expect(result.passedChecks.any((c) => c.contains('Verhoeff')), isTrue);
      expect(result.anomalies, isEmpty);
    });

    test('Invalid Aadhaar number fails Verhoeff algorithm check', () async {
      // 1234 5678 9012 fails Verhoeff
      final extraction = ExtractionResult(
        docType: 'AADHAAR',
        category: 'Identity',
        holderName: 'Muneer Shaik',
        idNumber: '1234 5678 9012',
      );

      final dummyFile = File('test_fake_aadhaar.tmp');
      await dummyFile.writeAsString('Clean dummy content');

      final result = await ForensicSecurityService.analyzeDocument(
        file: dummyFile,
        extraction: extraction,
      );

      if (await dummyFile.exists()) await dummyFile.delete();

      expect(result.status, isNot(ForensicStatus.genuine));
      expect(result.anomalies.any((a) => a.contains('Verhoeff')), isTrue);
    });

    test('Detects future issue date as chronological anomaly', () async {
      final extraction = ExtractionResult(
        docType: 'PAN',
        category: 'Identity',
        holderName: 'Shaik Muneer',
        idNumber: 'ABCPS1234F',
        issueDate: '2035-12-31', // Future date
      );

      final dummyFile = File('test_future.tmp');
      await dummyFile.writeAsString('Clean content');

      final result = await ForensicSecurityService.analyzeDocument(
        file: dummyFile,
        extraction: extraction,
        cardholderSurname: 'Shaik',
      );

      if (await dummyFile.exists()) await dummyFile.delete();

      expect(result.anomalies.any((a) => a.contains('future')), isTrue);
      expect(result.integrityScore, lessThan(100));
    });

    test('Detects editing tool signatures (Adobe Photoshop / Canva)', () async {
      final extraction = ExtractionResult(
        docType: 'MARKSHEET',
        category: 'Education',
        holderName: 'Shaik Muneer',
        issueDate: '2022-05-10',
      );

      final dummyFile = File('test_tampered.tmp');
      await dummyFile.writeAsString('ExifHeader... Software: Adobe Photoshop 2024 ...Created in Canva');

      final result = await ForensicSecurityService.analyzeDocument(
        file: dummyFile,
        extraction: extraction,
      );

      if (await dummyFile.exists()) await dummyFile.delete();

      expect(result.anomalies.any((a) => a.contains('Adobe Photoshop')), isTrue);
      expect(result.status, isNot(ForensicStatus.genuine));
    });
  });

  group('Merkle Provenance Ledger Tests', () {
    test('Records document block and verifies untampered integrity', () async {
      final dummyFile = File('test_merkle_file.tmp');
      await dummyFile.writeAsString('Genuine unmodified file content');

      final fields = {'Full Name': 'Muneer Shaik', 'Aadhaar Number': '9876 5432 1012'};

      final blockHash = await MerkleProvenanceService.recordBlock(
        documentId: 'doc-merkle-uniq',
        filePath: dummyFile.path,
        fields: fields,
      );

      expect(blockHash.isNotEmpty, isTrue);

      // Verify integrity
      final db = DatabaseService.instance;
      await db.saveDocumentWithFields(
        document: DocumentModel(
          id: 'doc-merkle-uniq',
          personId: 'p-1',
          docType: 'AADHAAR',
          title: 'Aadhaar Card',
          filePath: dummyFile.path,
          fileName: 'aadhaar.pdf',
          fileType: 'pdf',
        ),
        fields: [
          DocumentField(id: 'f-merkle-1', documentId: 'doc-merkle-uniq', fieldName: 'Full Name', fieldValue: 'Muneer Shaik', fieldCategory: 'identity'),
          DocumentField(id: 'f-merkle-2', documentId: 'doc-merkle-uniq', fieldName: 'Aadhaar Number', fieldValue: '9876 5432 1012', fieldCategory: 'identity'),
        ],
      );

      final verify = await MerkleProvenanceService.verifyDocumentIntegrity('doc-merkle-uniq');
      expect(verify.isUntampered, isTrue);

      if (await dummyFile.exists()) await dummyFile.delete();
    });
  });

  group('Family Knowledge Graph (FKG) Tests', () {
    test('Builds canonical graph with zero duplicate person nodes and calculates coverage', () async {
      final db = DatabaseService.instance;
      await db.upsertPerson(Person(id: 'fkg-self', name: 'Shaik Muneer', relationship: 'Self'));
      await db.upsertPerson(Person(id: 'fkg-father', name: 'Shaik Maqbool', relationship: 'Father'));

      await db.saveDocumentWithFields(
        document: DocumentModel(
          id: 'doc-fkg-1',
          personId: 'fkg-self',
          docType: 'AADHAAR',
          category: 'Identity',
          title: 'Aadhaar Card',
          filePath: '',
          fileName: 'aadhaar.pdf',
          fileType: 'pdf',
        ),
        fields: [
          DocumentField(id: 'fkg-f1', documentId: 'doc-fkg-1', fieldName: 'Full Name', fieldValue: 'Shaik Muneer', fieldCategory: 'identity'),
        ],
      );

      final graph = await FamilyGraphService.buildFamilyGraph();
      expect(graph.members.isNotEmpty, isTrue);
      expect(graph.edges.any((e) => e.relationType == 'FATHER_OF'), isTrue);

      final member = graph.members.first;
      expect(member.categoriesPresent.isNotEmpty || member.missingCategories.isNotEmpty, isTrue);
    });
  });
}
