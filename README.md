# Project X

Project X is an offline document vault for Android. It indexes files selected from device storage, extracts text and structured fields locally, stores the result in SQLite, and answers questions only from stored records.

## Runtime behavior

- No bundled personal document catalog or seeded database.
- PDF/text extraction and Android OCR run locally.
- Unknown values are rejected instead of invented.
- SQLite is the source of truth; the in-memory list is only a UI projection.
- The selected synthesis model is Qwen2.5 1.5B Instruct Q4_K_M. Its GGUF stays outside the APK under the app model directory. If it is absent, grounded field retrieval remains active.

## Build

```powershell
flutter pub get
flutter build apk --release --split-per-abi
```

The Android build targets `arm64-v8a` and uses the native llama.cpp shim when the optional GGUF model is present.
