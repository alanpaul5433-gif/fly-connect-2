import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load signing keys from key.properties (gitignored). If the file doesn't exist,
// release builds fall through to the debug keystore so `flutter run` still works.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// Detect whether a release artifact is actually being assembled so we can refuse
// to debug-sign it (Play rejects debug-signed uploads). `flutter run` / debug builds
// are unaffected. Pass -PallowInsecureRelease=true to debug-sign a release on purpose
// for local testing only.
val isAssemblingRelease = gradle.startParameter.taskNames.any { it.contains("Release") }
val allowInsecureRelease = (project.findProperty("allowInsecureRelease") as String?) == "true"

android {
    namespace = "com.urbansyncinnovations.flyconnect"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.urbansyncinnovations.flyconnect"
        minSdk = flutter.minSdkVersion            // = 24 in this Flutter SDK (> Firebase Auth's 23). Flutter's gradle migration rewrites a hard literal back to this, so we track its floor.
        targetSdk = 35         // Google Play requires API 35 for new uploads (since Aug 2025)
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Use release signing if key.properties is present. If it's missing AND a
            // release artifact is being assembled, FAIL rather than silently debug-sign
            // (Play rejects debug-signed bundles). Debug builds / `flutter run` still work.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                if (isAssemblingRelease && !allowInsecureRelease) {
                    throw GradleException(
                        "Release build requested but android/key.properties is missing.\n" +
                        "Production AABs must be signed with the upload keystore — a debug-signed " +
                        "bundle will be rejected by Google Play.\n" +
                        "Fix: add key.properties (see docs/keystore-setup.md) or build via CI " +
                        "(which injects the keystore secret).\n" +
                        "To debug-sign a release for LOCAL testing only, pass -PallowInsecureRelease=true."
                    )
                }
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

// google-services.json is gitignored; apply the plugin only when the file is present
// (Firebase Console → Project settings → Your Android app → Download). Without it,
// Gradle still builds; Firebase is initialized from Dart in lib/main.dart.
val googleServicesJson = file("google-services.json")
if (googleServicesJson.exists()) {
    apply(plugin = "com.google.gms.google-services")
} else {
    logger.lifecycle(
        "[flyconnect] No google-services.json — skipping com.google.gms.google-services. " +
            "Add android/app/google-services.json for native FCM / Google Sign-In resource merging."
    )
}
