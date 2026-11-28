import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../models/person.dart';
import '../database/database_service.dart';

class PersonResolutionEngine {
  static const _uuid = Uuid();

  static const _commonTitles = {
    'mr', 'mrs', 'ms', 'miss', 'dr', 'shri', 'smt', 'kumari', 'km', 'er', 'prof', 'master',
    'bi', 'bee', 'begum', 'devi', 'bai', 'khan', 'shaik', 'sheikh'
  };

  static const _placeholderRoles = {
    'mother', 'father', 'parent', 'spouse', 'wife', 'husband', 'child',
    'son', 'daughter', 'head', 'ration', 'card', 'holder', 'primary',
    'user', 'cardholder', 'unknown', 'member', 'family', 'applicant', 'self',
    'ration card holder', 'card holder', 'head of family', 'primary user',
    'primary cardholder', 'family member'
  };

  /// Returns true if a string is a role or generic placeholder rather than a real human name
  static bool isGenericPlaceholder(String name) {
    final clean = name.trim().toLowerCase();
    if (clean.isEmpty) return true;
    if (_placeholderRoles.contains(clean)) return true;
    final tokens = clean.split(RegExp(r'\s+'));
    return tokens.every((t) => _placeholderRoles.contains(t));
  }

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
    final prefs = await SharedPreferences.getInstance();
    final storedOwnerName = (prefs.getString('vault_owner_name') ?? '').trim();

    Person? selfPerson;
    try {
      selfPerson = existingPersons.firstWhere((p) => p.relationship == 'Self');
    } catch (_) {
      if (existingPersons.isNotEmpty) selfPerson = existingPersons.first;
    }

    final effectiveOwnerName = (storedOwnerName.isNotEmpty &&
            !isGenericPlaceholder(storedOwnerName))
        ? storedOwnerName
        : (selfPerson != null && !isGenericPlaceholder(selfPerson.name)
            ? selfPerson.name
            : (!isGenericPlaceholder(holderName) ? holderName.trim() : 'Primary Owner'));

    if (existingPersons.isEmpty) {
      final newPerson = Person(
        id: _uuid.v4(),
        name: effectiveOwnerName,
        relationship: 'Self',
        dob: dob,
        gender: gender,
        avatarColorIndex: 0,
        createdAt: DateTime.now(),
      );
      await db.upsertPerson(newPerson);
      return newPerson;
    }

    // Filter out placeholders from holderName
    String candidateName = holderName.trim();
    if (isGenericPlaceholder(candidateName)) {
      candidateName = '';
    }

    // 1. If explicitly verified by AI as the primary cardholder or matches registered owner:
    if (isPrimaryCardholder ||
        (candidateName.isNotEmpty && isNameMatch(candidateName, effectiveOwnerName)) ||
        (selfPerson != null && candidateName.isNotEmpty && isNameMatch(candidateName, selfPerson.name))) {
      return selfPerson ?? existingPersons.first;
    }

    // Target relationship type
    final targetRel = relationshipToCardholder ?? relationType ?? 'Family Member';

    // 2. If designated as non-Self family member, try matching by name or relationship
    if (targetRel.toLowerCase() != 'self') {
      if (candidateName.isNotEmpty) {
        for (final person in existingPersons) {
          if (isNameMatch(candidateName, person.name)) {
            return person;
          }
        }
      } else {
        // Candidate name is empty, but relationship is known (e.g. "Mother")
        for (final person in existingPersons) {
          if (person.relationship.toLowerCase() == targetRel.toLowerCase() && !isGenericPlaceholder(person.name)) {
            return person;
          }
        }
      }
    }

    // 3. Try finding match among existing persons by candidate name
    if (candidateName.isNotEmpty) {
      for (final person in existingPersons) {
        if (isNameMatch(candidateName, person.name)) {
          return person;
        }
      }
    }

    // 4. If candidateName is empty or a placeholder, fallback to selfPerson
    if (candidateName.isEmpty || isGenericPlaceholder(candidateName)) {
      return selfPerson ?? existingPersons.first;
    }

    // 5. Create new Person profile for this family member with valid name
    final newPerson = Person(
      id: _uuid.v4(),
      name: candidateName,
      relationship: targetRel,
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

    final cleanA = nameA.trim().toLowerCase();
    final cleanB = nameB.trim().toLowerCase();

    // Generic placeholders must never match legitimate names
    if (isGenericPlaceholder(cleanA) || isGenericPlaceholder(cleanB)) {
      return false;
    }

    final tokensA = tokenizeName(nameA);
    final tokensB = tokenizeName(nameB);

    if (tokensA.isEmpty || tokensB.isEmpty) return false;

    // Single token vs multi token comparison (e.g. "Hazar" / "Hazara" vs "Hazara Bi" / "Hazara Begum")
    if (tokensA.length == 1 || tokensB.length == 1) {
      final single = tokensA.length == 1 ? tokensA.first : tokensB.first;
      final multi = tokensA.length == 1 ? tokensB : tokensA;
      if (single.length >= 3 && multi.any((t) =>
          _isTokenMatch(single, t) ||
          (t.length >= 4 && (t.startsWith(single) || single.startsWith(t))))) {
        return true;
      }
    }

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
        if (_isTokenMatch(tA, tB) || (tA.length >= 4 && tB.length >= 4 && (tA.startsWith(tB) || tB.startsWith(tA)))) {
          matchingTokens++;
          break;
        }
      }
    }

    if (matchingTokens >= 2) {
      return true;
    }

    if (matchingTokens >= 1 && (tokensA.length == 1 || tokensB.length == 1)) {
      return true;
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
