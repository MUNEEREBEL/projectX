import 'package:flutter_test/flutter_test.dart';
import 'package:x/core/utils/indian_doc_validator.dart';

void main() {
  group('Indian Document Validator Tests', () {
    test('PAN validation correctly identifies valid and invalid PANs', () {
      expect(IndianDocValidator.validatePAN('ABCPE1234F'), isTrue);
      expect(IndianDocValidator.validatePAN('abcpe1234f'), isTrue); // case-insensitive
      expect(IndianDocValidator.getPANType('ABCPE1234F'), equals('Individual')); // P = Individual
      expect(IndianDocValidator.getPANType('ABCCE1234F'), equals('Company')); // C = Company

      expect(IndianDocValidator.validatePAN('ABCD12345F'), isFalse); // wrong digit count
      expect(IndianDocValidator.validatePAN('12345ABCDE'), isFalse);
    });

    test('Driving License validation handles Indian DL formats', () {
      expect(IndianDocValidator.validateDrivingLicense('DL0120190012345'), isTrue);
      expect(IndianDocValidator.validateDrivingLicense('KA-01-2019-0012345'), isTrue);
      expect(IndianDocValidator.validateDrivingLicense('MH1220180004321'), isTrue);
      expect(IndianDocValidator.validateDrivingLicense('12345'), isFalse);
    });

    test('Passport validation handles Indian passports', () {
      expect(IndianDocValidator.validatePassport('A1234567'), isTrue);
      expect(IndianDocValidator.validatePassport('Z9876543'), isTrue);
      expect(IndianDocValidator.validatePassport('12345678'), isFalse);
    });

    test('Vehicle RC validation handles Indian vehicle registration numbers', () {
      expect(IndianDocValidator.validateVehicleRC('KA01AB1234'), isTrue);
      expect(IndianDocValidator.validateVehicleRC('DL 3C AA 1234'), isTrue);
      expect(IndianDocValidator.validateVehicleRC('MH12DE5678'), isTrue);
      expect(IndianDocValidator.validateVehicleRC('INVALID123'), isFalse);
    });

    test('Voter ID validation handles EPIC numbers', () {
      expect(IndianDocValidator.validateVoterId('ABC1234567'), isTrue);
      expect(IndianDocValidator.validateVoterId('XYZ9876543'), isTrue);
      expect(IndianDocValidator.validateVoterId('1234567890'), isFalse);
    });

    test('Aadhaar masking formats properly', () {
      expect(IndianDocValidator.maskAadhaar('123456789012'), equals('XXXX XXXX 9012'));
      expect(IndianDocValidator.maskAadhaar('1234 5678 9012'), equals('XXXX XXXX 9012'));
    });
  });
}
