# ─── Flutter Wrapper & Engine ────────────────────────────────────────────────
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# ─── Flutter Deferred Components / Play Core (not used offline) ──────────────
-dontwarn com.google.android.play.core.**

# ─── Application Native Scanner & OpenCV 4.9.0 JNI ──────────────────────────
-keep class com.yourname.docscanner.** { *; }
-keep class org.opencv.** { *; }
-keepclassmembers class org.opencv.** { *; }
-dontwarn org.opencv.**

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
