import 'package:flutter_test/flutter_test.dart';
import 'package:x/core/services/person_resolution_engine.dart';

void main() {
  group('Indian Name Ordering and Resolution Tests', () {
    test('Handles inverted first and last names', () {
      expect(PersonResolutionEngine.isNameMatch('Muneer Shaik', 'Shaik Muneer'), isTrue);
      expect(PersonResolutionEngine.isNameMatch('Rahul Sharma', 'Sharma Rahul'), isTrue);
    });

    test('Handles titles and salutations', () {
      expect(PersonResolutionEngine.isNameMatch('Mr. Muneer Shaik', 'Shaik Muneer'), isTrue);
      expect(PersonResolutionEngine.isNameMatch('Dr. Shaik Muneer', 'Muneer Shaik'), isTrue);
      expect(PersonResolutionEngine.isNameMatch('Smt. Ananya Rao', 'Rao Ananya'), isTrue);
    });

    test('Handles common Indian abbreviations (Md, Mohd, Sk)', () {
      expect(PersonResolutionEngine.isNameMatch('Md Muneer Shaik', 'Mohammed Shaik Muneer'), isTrue);
      expect(PersonResolutionEngine.isNameMatch('Mohd Shaik Muneer', 'Mohammed Muneer Shaik'), isTrue);
      expect(PersonResolutionEngine.isNameMatch('Sk Muneer', 'Shaik Muneer'), isTrue);
    });

    test('Handles 3-token superset names', () {
      expect(PersonResolutionEngine.isNameMatch('Shaik Muneer Ahmed', 'Muneer Shaik'), isTrue);
      expect(PersonResolutionEngine.isNameMatch('Shaik Muneer', 'Shaik Muneer Ahmed'), isTrue);
    });

    test('Handles Indian initials matching', () {
      expect(PersonResolutionEngine.isNameMatch('S. Muneer', 'Shaik Muneer'), isTrue);
      expect(PersonResolutionEngine.isNameMatch('Muneer S', 'Shaik Muneer'), isTrue);
    });

    test('Rejects different people with same last name', () {
      expect(PersonResolutionEngine.isNameMatch('Rahul Sharma', 'Amit Sharma'), isFalse);
      expect(PersonResolutionEngine.isNameMatch('Suresh Kumar', 'Ramesh Kumar'), isFalse);
    });
  });
}
