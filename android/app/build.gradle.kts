import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    namespace = "com.yourname.docscanner"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.yourname.docscanner"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        val targetPlatformProp = project.findProperty("target-platform")?.toString() ?: ""
        val isX86Only = targetPlatformProp == "android-x64" || targetPlatformProp == "android-x86"
        val isSplitPerAbi = project.findProperty("split-per-abi")?.toString() == "true"
        if (!isSplitPerAbi && !isX86Only) {
            ndk {
                abiFilters.clear()
                abiFilters.addAll(listOf("arm64-v8a", "armeabi-v7a"))
            }
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
            pickFirsts += listOf("**/libc++_shared.so")
            val targetPlatformProp = project.findProperty("target-platform")?.toString() ?: ""
            val isX86Only = targetPlatformProp == "android-x64" || targetPlatformProp == "android-x86"
            if (!isX86Only) {
                excludes += listOf(
                    "**/x86/**",
                    "**/x86_64/**",
                    "**/mips/**",
                    "**/mips64/**"
                )
            }
        }
        resources {
            excludes += listOf(
                "META-INF/LICENSE*",
                "META-INF/NOTICE*",
                "META-INF/*.kotlin_module",
                "DebugProbesKt.bin"
            )
        }
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                val storeFilePath = keystoreProperties.getProperty("storeFile")
                if (!storeFilePath.isNullOrBlank()) {
                    storeFile = file(storeFilePath)
                }
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            val targetPlatformProp = project.findProperty("target-platform")?.toString() ?: ""
            val isX86Only = targetPlatformProp == "android-x64" || targetPlatformProp == "android-x86"
            val isSplitPerAbi = project.findProperty("split-per-abi")?.toString() == "true"
            if (!isSplitPerAbi && !isX86Only) {
                ndk {
                    abiFilters.clear()
                    abiFilters.addAll(listOf("arm64-v8a", "armeabi-v7a"))
                }
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

afterEvaluate {
    val targetPlatformProp = project.findProperty("target-platform")?.toString() ?: ""
    val isX86Only = targetPlatformProp == "android-x64" || targetPlatformProp == "android-x86"
    val isSplitPerAbi = project.findProperty("split-per-abi")?.toString() == "true"
    if (!isSplitPerAbi && !isX86Only) {
        android.defaultConfig.ndk.abiFilters.clear()
        android.defaultConfig.ndk.abiFilters.addAll(listOf("arm64-v8a", "armeabi-v7a"))
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.12.0")

    // OpenCV 4.11.0 (16KB ELF page-aligned Android build)
    implementation("org.opencv:opencv:4.11.0")

    // Offline Arabic + English Tesseract 5.5.1 LSTM OCR JNI (Tesseract4Android 4.9.0)
    implementation("cz.adaptech.tesseract4android:tesseract4android:4.9.0")

    // CameraX 1.4.2 (16KB ELF page-aligned)
    val cameraxVersion = "1.4.2"
    implementation("androidx.camera:camera-core:$cameraxVersion")
    implementation("androidx.camera:camera-camera2:$cameraxVersion")
    implementation("androidx.camera:camera-lifecycle:$cameraxVersion")
    implementation("androidx.camera:camera-view:$cameraxVersion")

    // Activity KTX & Coroutines
    implementation("androidx.activity:activity-ktx:1.8.2")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")

    // Guava & Futures for CameraX ListenableFuture
    implementation("com.google.guava:guava:31.1-android")
    implementation("androidx.concurrent:concurrent-futures-ktx:1.1.0")
    implementation("androidx.exifinterface:exifinterface:1.3.7")
}
