import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.cliquepix.clique_pix"
    // compileSdk 36 is required by androidx.browser:1.9.0 + androidx.activity:1.12.4
    // (transitive deps from app_links / image_cropper).
    //
    // targetSdk 36 (Android 16) since 2026-07: Google Play requires the target API to
    // stay within one year of the latest Android release. Targeting 35 blocked ALL
    // updates from 2026-08-30. Shipped in 1.0.1+14 after the device pass in
    // docs/BETA_TEST_PLAN.md section 13.
    //
    // Both levels are written as literals so the shipped value is visible in the diff
    // and cannot move underneath us on a Flutter SDK upgrade. The floor is enforced by
    // the check() below - raise BOTH when Play raises the requirement.
    // Next deadline: target API 37 by ~2026-08-31. See docs/HANDOFF.md section 6.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    defaultConfig {
        applicationId = "com.cliquepix.clique_pix"
        minSdk = Math.max(flutter.minSdkVersion, 21)
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

// Google Play target-API floor. Play blocks ALL updates (hotfixes included) for apps
// below this, enforced annually around Aug 31, and the flag clears only on a PRODUCTION
// publish. Raise this and defaultConfig.targetSdk together. See docs/HANDOFF.md section 6.
val playTargetSdkFloor = 36
check((android.defaultConfig.targetSdk ?: 0) >= playTargetSdkFloor) {
    "targetSdk=${android.defaultConfig.targetSdk} is below the Google Play floor of " +
        "$playTargetSdkFloor - see docs/HANDOFF.md section 6"
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
