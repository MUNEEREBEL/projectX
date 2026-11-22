# PrivDoc AI (India-First Smart Document Assistant)

PrivDoc AI is a local-first, zero-knowledge document vault, renewal radar, and form-filling copilot.

---

## Key Features

1. **Scoped Folder Sync Only**:
   - Works strictly with your selected documents folder (`.pdf`, `.docx`, `.png`, `.jpg`, `.jpeg`).
   - No broad device storage scanning.

2. **State-of-the-Art Indian Document Recognition**:
   - Powered by Gemini 2.5 Flash Vision (Free tier: fast, sub-second extraction).
   - Extracts structured JSON for **Aadhaar, PAN, Driving License, Passport, Vehicle RC, Vehicle Insurance, Health Insurance, and Voter ID**.
   - Built-in mathematical validation: Verhoeff algorithm for Aadhaar, PAN status check, Driving License format verification, and Passport MRZ check.

3. **Family Profiles & Multi-Person Disambiguation**:
   - Automatically clusters mixed family documents in a single folder into individual profiles (Self, Spouse, Father, Mother, etc.) using normalized name + DOB matching.

4. **100% Offline Local Expiry Radar**:
   - Background alarms via Android AlarmManager at 60, 30, 7, and 1 day prior to expiry.
   - Dashboard renewal carousel with live countdowns.

5. **Screen Copilot & 1-Tap Form Filling**:
   - Floating drawer with fast 2-letter search (`pan`, `dl`, `ifsc`, `address`).
   - 1-tap copy chips to fill government, banking, and application forms quickly without clutter.

6. **Fast Natural Language AI Assistant**:
   - Ask questions over verified local documents: *"When is my car insurance expiring?"*, *"What is my PAN?"*.
