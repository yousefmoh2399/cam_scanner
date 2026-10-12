# ─── Flutter Wrapper & Engine ────────────────────────────────────────────────
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# ─── Flutter Deferred Components / Play Core (not used offline) ──────────────
-dontwarn com.google.android.play.core.**

# ─── Application Native Scanner & OpenCV 4.9.0 + Tesseract JNI ──────────────
-keep class com.laqta.scanner.** { *; }
-keep class com.yourname.docscanner.** { *; }
-keep class org.opencv.** { *; }
-keepclassmembers class org.opencv.** { *; }
-dontwarn org.opencv.**
-keep class com.googlecode.tesseract.android.** { *; }
-keepclassmembers class com.googlecode.tesseract.android.** { *; }
-dontwarn com.googlecode.tesseract.android.**
-keep class cz.adaptech.tesseract4android.** { *; }
-keepclassmembers class cz.adaptech.tesseract4android.** { *; }
-dontwarn cz.adaptech.tesseract4android.**

# ─── Google ML Kit Text Recognition & Play Services JNI ─────────────────────
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.** { *; }
-keepclassmembers class * extends com.google.android.gms.internal.mlkit_vision_text_common.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**

# ─── CameraX & ExifInterface ─────────────────────────────────────────────────
-keep class androidx.camera.** { *; }
-keep interface androidx.camera.** { *; }
-dontwarn androidx.camera.**

# ─── Keep JNI Native Methods ─────────────────────────────────────────────────
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}

# ─── Biometrics & Security (Vault screen in Release mode) ────────────────────
-keep class androidx.biometric.** { *; }
-dontwarn androidx.biometric.**
-keep class io.flutter.plugins.localauth.** { *; }

# ─── Local Database (sqflite) & Audio & Cryptography ─────────────────────────
-keep class com.tekartik.sqflite.** { *; }
-dontwarn com.tekartik.sqflite.**
-keep class xyz.luan.audioplayers.** { *; }
-dontwarn xyz.luan.audioplayers.**
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-dontwarn com.it_nomads.fluttersecurestorage.**


