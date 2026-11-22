import 'package:uuid/uuid.dart';
import '../../models/person.dart';
import '../database/database_service.dart';

class PersonResolutionEngine {
  static const _uuid = Uuid();

  static const _commonTitles = {
    'mr', 'mrs', 'ms', 'miss', 'dr', 'shri', 'smt', 'kumari', 'km', 'er', 'prof', 'master'
  };

  static const _nameAliases = {
    'md': 'mohammed',
    'mohd': 'mohammed',
    'muhammad': 'mohammed',
    'sk': 'shaik',
    'sheikh': 'shaik',
    'syed': 'sayyad',
  };

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

    // 1. Try to find match among existing persons
    for (final person in existingPersons) {
      if (isNameMatch(holderName, person.name)) {
        // Double check DOB if both have it
        if (dob != null && person.dob != null && dob.isNotEmpty && person.dob!.isNotEmpty) {
          if (dob == person.dob) {
            return person;
          }
          // If DOB explicitly mismatches, might be senior/junior (father/son with same name)
          continue;
        } else {
          return person;
        }
      }
    }

    // 2. If no match found, create a new Person profile
    final isFirstPerson = existingPersons.isEmpty;
    String relationship = isFirstPerson ? 'Self' : 'Family Member';

    if (relationType != null && relationType.isNotEmpty) {
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

  static List<String> tokenizeName(String name) {
    if (name.trim().isEmpty) return [];

    final clean = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final rawTokens = clean.split(' ');
    final result = <String>[];

    for (final raw in rawTokens) {
      if (raw.isEmpty) continue;
      // Filter out titles
      if (_commonTitles.contains(raw)) continue;
      // Normalize aliases (e.g. sk -> shaik, md -> mohammed)
      final normalized = _nameAliases[raw] ?? raw;
      result.add(normalized);
    }

    return result;
  }

  /// Robust Indian name comparator handling inverted orders, initials, and honorifics:
  /// e.g. "Muneer Shaik" == "Shaik Muneer"
  /// e.g. "Shaik Muneer Ahmed" matches "Muneer Shaik"
  /// e.g. "Md Muneer Shaik" == "Mohammed Shaik Muneer"
  static bool isNameMatch(String nameA, String nameB) {
    if (nameA.trim().toLowerCase() == nameB.trim().toLowerCase()) return true;

    final tokensA = tokenizeName(nameA);
    final tokensB = tokenizeName(nameB);

    if (tokensA.isEmpty || tokensB.isEmpty) return false;

    final setA = tokensA.toSet();
    final setB = tokensB.toSet();

    // 1. Direct Set Equality (e.g. {"muneer", "shaik"} == {"shaik", "muneer"})
    if (setA.length == setB.length && setA.containsAll(setB)) {
      return true;
    }

    // 2. Multi-token intersection (e.g., {"shaik", "muneer"} subset of {"shaik", "muneer", "ahmed"})
    final common = setA.intersection(setB);
    final nonSingleLetterCommon = common.where((t) => t.length > 1).toSet();

    // If they share 2 or more meaningful tokens (e.g., "Shaik" and "Muneer")
    if (nonSingleLetterCommon.length >= 2) {
      return true;
    }

    // If one person has a single meaningful word name and matches the only word of the other
    if (setA.length == 1 && setB.length == 1 && setA.first == setB.first) {
      return true;
    }

    // 3. Handle Indian single-letter initials (e.g. "S. Muneer" vs "Shaik Muneer")
    if (tokensA.length == 2 && tokensB.length == 2) {
      // Find the longer token match and initial match
      for (final tA in tokensA) {
        for (final tB in tokensB) {
          if (tA.length > 2 && tB.length > 2 && tA == tB) {
            // Found matching main name, check other tokens
            final remainingA = tokensA.firstWhere((t) => t != tA);
            final remainingB = tokensB.firstWhere((t) => t != tB);
            if (remainingA.isNotEmpty && remainingB.isNotEmpty) {
              if (remainingA[0] == remainingB[0]) {
                return true;
              }
            }
          }
        }
      }
    }

    return false;
  }
}
