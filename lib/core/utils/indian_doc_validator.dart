class IndianDocValidator {
  // Verhoeff algorithm lookup tables for Aadhaar checksum validation
  static const List<List<int>> _d = [
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
    [1, 2, 3, 4, 0, 6, 7, 8, 9, 5],
    [2, 3, 4, 0, 1, 7, 8, 9, 5, 6],
    [3, 4, 0, 1, 2, 8, 9, 5, 6, 7],
    [4, 0, 1, 2, 3, 9, 5, 6, 7, 8],
    [5, 9, 8, 7, 6, 0, 4, 3, 2, 1],
    [6, 5, 9, 8, 7, 1, 0, 4, 3, 2],
    [7, 6, 5, 9, 8, 2, 1, 0, 4, 3],
    [8, 7, 6, 5, 9, 3, 2, 1, 0, 4],
    [9, 8, 7, 6, 5, 4, 3, 2, 1, 0]
  ];

  static const List<List<int>> _p = [
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
    [1, 5, 7, 6, 2, 8, 3, 0, 9, 4],
    [5, 8, 0, 3, 7, 9, 6, 1, 4, 2],
    [8, 9, 1, 6, 0, 4, 3, 5, 2, 7],
    [9, 4, 5, 3, 1, 2, 6, 8, 7, 0],
    [4, 2, 8, 6, 5, 7, 3, 9, 0, 1],
    [2, 7, 9, 3, 8, 0, 6, 4, 1, 5],
    [7, 0, 4, 6, 9, 1, 3, 2, 5, 8]
  ];

  /// Validates a 12-digit Aadhaar number using the Verhoeff algorithm.
  static bool validateAadhaar(String aadhaar) {
    final clean = aadhaar.replaceAll(RegExp(r'\s+|-'), '');
    if (!RegExp(r'^\d{12}$').hasMatch(clean)) return false;

    int c = 0;
    final digits = clean.split('').map(int.parse).toList().reversed.toList();
    for (int i = 0; i < digits.length; i++) {
      c = _d[c][_p[i % 8][digits[i]]];
    }
    return c == 0;
  }

  /// Formats Aadhaar as masked: XXXX XXXX 1234
  static String maskAadhaar(String aadhaar) {
    final clean = aadhaar.replaceAll(RegExp(r'\s+|-'), '');
    if (clean.length == 12) {
      return 'XXXX XXXX ${clean.substring(8)}';
    }
    return aadhaar;
  }

  /// Validates a PAN (Permanent Account Number): 5 letters + 4 digits + 1 letter
  static bool validatePAN(String pan) {
    final clean = pan.toUpperCase().trim();
    return RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$').hasMatch(clean);
  }

  /// Returns PAN status description from 4th letter
  static String getPANType(String pan) {
    final clean = pan.toUpperCase().trim();
    if (clean.length < 4) return 'Unknown';
    switch (clean[3]) {
      case 'P': return 'Individual';
      case 'C': return 'Company';
      case 'H': return 'HUF (Hindu Undivided Family)';
      case 'F': return 'Firm / Partnership';
      case 'A': return 'Association of Persons';
      case 'T': return 'Trust';
      default: return 'Entity';
    }
  }

  /// Validates Indian Driving License (e.g. DL-0120190012345 or KA01 20190012345)
  static bool validateDrivingLicense(String dl) {
    final clean = dl.toUpperCase().replaceAll(RegExp(r'\s+|-'), '');
    // Standard formats: 2 letter state code + 2 digit RTO + 4 digit year + 7 digits
    // Or legacy formats: 15-16 alphanumeric chars
    return RegExp(r'^[A-Z]{2}[0-9]{13,14}$').hasMatch(clean) ||
           RegExp(r'^[A-Z]{2}[0-9]{2}[A-Z0-9]{7,12}$').hasMatch(clean);
  }

  /// Validates Indian Passport number: 1 letter + 7 digits
  static bool validatePassport(String passport) {
    final clean = passport.toUpperCase().trim();
    return RegExp(r'^[A-PR-WYZ][0-9]{7}$').hasMatch(clean);
  }

  /// Validates Indian Vehicle Registration Number (e.g. KA01AB1234 or DL3CAA1234)
  static bool validateVehicleRC(String rc) {
    final clean = rc.toUpperCase().replaceAll(RegExp(r'\s+|-'), '');
    return RegExp(r'^[A-Z]{2}[0-9]{1,2}[A-Z]{0,3}[0-9]{4}$').hasMatch(clean);
  }

  /// Validates Indian Voter ID (EPIC): 3 letters + 7 digits
  static bool validateVoterId(String epic) {
    final clean = epic.toUpperCase().replaceAll(RegExp(r'\s+|-'), '');
    return RegExp(r'^[A-Z]{3}[0-9]{7}$').hasMatch(clean);
  }
}
