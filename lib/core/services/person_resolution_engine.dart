import 'package:uuid/uuid.dart';
import '../../models/person.dart';
import '../database/database_service.dart';

class PersonResolutionEngine {
  static const _uuid = Uuid();

  /// Resolves which Person the extracted document belongs to, or creates a new Person.
  static Future<Person> resolvePerson({
    required String holderName,
    String? dob,
    String? gender,
    String? relationName,
    String? relationType,
  }) async {
    final db = DatabaseService.instance;
    final existingPersons = await db.getAllPersons();

    final cleanHolder = _normalizeName(holderName);

    // 1. Try to find match among existing persons
    for (final person in existingPersons) {
      final cleanExisting = _normalizeName(person.name);

      if (_isNameMatch(cleanHolder, cleanExisting)) {
        // Double check DOB if both have it
        if (dob != null && person.dob != null) {
          if (dob == person.dob) {
            return person;
          }
        } else {
          return person;
        }
      }
    }

    // 2. If no match found, create a new Person profile
    final isFirstPerson = existingPersons.isEmpty;
    String relationship = isFirstPerson ? 'Self' : 'Family Member';

    if (relationType != null && relationType.isNotEmpty) {
      // If document indicates this person is someone's spouse or child
      if (relationType.toLowerCase().contains('father')) {
        relationship = 'Family Member';
      }
    }

    final newPerson = Person(
      id: _uuid.v4(),
      name: holderName.trim().isEmpty ? 'Unknown Person' : holderName.trim(),
      relationship: relationship,
      dob: dob,
      gender: gender,
      avatarColorIndex: existingPersons.length % 6,
      createdAt: DateTime.now(),
    );

    await db.upsertPerson(newPerson);
    return newPerson;
  }

  static String _normalizeName(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool _isNameMatch(String nameA, String nameB) {
    if (nameA == nameB) return true;
    if (nameA.isEmpty || nameB.isEmpty) return false;

    final tokensA = nameA.split(' ').where((t) => t.length > 1).toSet();
    final tokensB = nameB.split(' ').where((t) => t.length > 1).toSet();

    if (tokensA.isEmpty || tokensB.isEmpty) return false;

    // Check intersection: e.g. "rahul sharma" vs "sharma rahul"
    final common = tokensA.intersection(tokensB);
    if (common.length >= tokensA.length || common.length >= tokensB.length) {
      return true;
    }

    return false;
  }
}
