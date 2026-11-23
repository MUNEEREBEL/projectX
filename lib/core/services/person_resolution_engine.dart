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
    bool isPrimaryCardholder = false,
    String? relationshipToCardholder,
  }) async {
    final db = DatabaseService.instance;
    final existingPersons = await db.getAllPersons();

    if (existingPersons.isEmpty) {
      final newPerson = Person(
        id: _uuid.v4(),
        name: holderName.trim().isEmpty ? 'Primary User' : holderName.trim(),
        relationship: 'Self',
        dob: dob,
        gender: gender,
        avatarColorIndex: 0,
        createdAt: DateTime.now(),
      );
      await db.upsertPerson(newPerson);
      return newPerson;
    }

    // 1. If explicitly verified by AI as the primary cardholder:
    if (isPrimaryCardholder) {
      final self = existingPersons.firstWhere(
        (p) => p.relationship == 'Self',
        orElse: () => existingPersons.first,
      );
      return self;
    }

    // 2. If explicitly designated as a non-Self family member (e.g. Father, Mother):
    if (relationshipToCardholder != null && relationshipToCardholder.toLowerCase() != 'self') {
      for (final person in existingPersons) {
        if (person.relationship.toLowerCase() == relationshipToCardholder.toLowerCase()) {
          if (isNameMatch(holderName, person.name)) {
            return person;
          }
        }
      }

      for (final person in existingPersons) {
        if (person.relationship != 'Self' && isNameMatch(holderName, person.name)) {
          return person;
        }
      }

      final newPerson = Person(
        id: _uuid.v4(),
        name: holderName.trim().isEmpty ? relationshipToCardholder : holderName.trim(),
        relationship: relationshipToCardholder,
        dob: dob,
        gender: gender,
        avatarColorIndex: existingPersons.length % 6,
        createdAt: DateTime.now(),
      );
      await db.upsertPerson(newPerson);
      return newPerson;
    }

    // 3. Try to find match among existing persons
    for (final person in existingPersons) {
      if (isNameMatch(holderName, person.name)) {
        if (dob != null && person.dob != null && dob.isNotEmpty && person.dob!.isNotEmpty) {
          if (dob == person.dob) {
            return person;
          }
          continue;
        } else {
          return person;
        }
      }
    }

    // 4. Create new Person profile for this family member
    String relationship = 'Family Member';
    if (relationType != null && relationType.toLowerCase().contains('father')) {
      relationship = 'Father';
    }

    final newPerson = Person(
      id: _uuid.v4(),
      name: holderName.trim().isEmpty ? 'Family Member' : holderName.trim(),
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

  static int levenshtein(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;

    List<int> v0 = List<int>.generate(t.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(t.length + 1, 0);

    for (int i = 0; i < s.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < t.length; j++) {
        int cost = (s[i] == t[j]) ? 0 : 1;
        v1[j + 1] = [v1[j] + 1, v0[j + 1] + 1, v0[j] + cost].reduce((a, b) => a < b ? a : b);
      }
      for (int j = 0; j <= t.length; j++) {
        v0[j] = v1[j];
      }
    }
    return v0[t.length];
  }

  static bool _isTokenMatch(String a, String b) {
    if (a == b) return true;
    // Allow 1 character typo/OCR hallucination for words of length >= 4 (e.g. Munfeer vs Muneer)
    if (a.length >= 4 && b.length >= 4 && (a.length - b.length).abs() <= 1) {
      if (levenshtein(a, b) <= 1) return true;
    }
    return false;
  }

  static bool _isTokenOrInitialMatch(String a, String b) {
    if (_isTokenMatch(a, b)) return true;
    if ((a.length == 1 || b.length == 1) && a.isNotEmpty && b.isNotEmpty) {
      return a[0] == b[0];
    }
    return false;
  }

  /// Robust Indian name comparator handling inverted orders, initials, OCR typos and honorifics:
  /// e.g. "Muneer Shaik" == "Shaik Muneer"
  /// e.g. "Munfeer Shaik" == "Muneer Shaik" (OCR noise correction)
  /// e.g. "Shaik Muneer Ahmed" matches "Muneer Shaik"
  /// e.g. "Md Muneer Shaik" == "Mohammed Shaik Muneer"
  static bool isNameMatch(String nameA, String nameB) {
    if (nameA.trim().toLowerCase() == nameB.trim().toLowerCase()) return true;

    final tokensA = tokenizeName(nameA);
    final tokensB = tokenizeName(nameB);

    if (tokensA.isEmpty || tokensB.isEmpty) return false;

    // Conflicting distinctive tokens check:
    // If nameA has an unmatched token AND nameB has an unmatched token, they are DIFFERENT family members!
    final unmatchedA = tokensA.where((tA) => !tokensB.any((tB) => _isTokenOrInitialMatch(tA, tB))).toList();
    final unmatchedB = tokensB.where((tB) => !tokensA.any((tA) => _isTokenOrInitialMatch(tA, tB))).toList();

    if (unmatchedA.isNotEmpty && unmatchedB.isNotEmpty) {
      // Both names have different distinct given names (e.g. "Shaik Basha" vs "Shaik Muneer")
      return false;
    }

    // Check direct equality or OCR typo equality for tokens
    int matchingTokens = 0;
    for (final tA in tokensA) {
      for (final tB in tokensB) {
        if (_isTokenMatch(tA, tB)) {
          matchingTokens++;
          break;
        }
      }
    }

    if (matchingTokens >= 2) {
      return true;
    }

    if (tokensA.length == 1 && tokensB.length == 1) {
      return _isTokenMatch(tokensA.first, tokensB.first);
    }

    // Handle Indian single-letter initials (e.g. "S. Muneer" vs "Shaik Muneer")
    if (tokensA.length == 2 && tokensB.length == 2) {
      for (final tA in tokensA) {
        for (final tB in tokensB) {
          if (tA.length > 2 && tB.length > 2 && _isTokenMatch(tA, tB)) {
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
