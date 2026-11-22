# Proguard / R8 rules for Project X

# ML Kit Text Recognition optional language modules (Chinese, Japanese, Korean)
# Project X uses Latin + Devanagari models, so suppress warnings for unused modules:
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
-dontwarn com.google.mlkit.vision.text.**

# Keep ML Kit components
-keep class com.google.mlkit.** { *; }
-keep interface com.google.mlkit.** { *; }

# Keep ONNX Runtime JNI bindings
-keep class ai.onnxruntime.** { *; }

# Keep Flutter JNI & plugins
-keep class io.flutter.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class com.example.x.** { *; }

# Keep Drift / SQLite native
-keep class org.sqlite.** { *; }
-dontwarn org.sqlite.**

# Flutter Play Store Split / Deferred Components (not used in standard APK)
-dontwarn com.google.android.play.core.**
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**
