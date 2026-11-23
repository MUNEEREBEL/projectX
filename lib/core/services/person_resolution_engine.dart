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
