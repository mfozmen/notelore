plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "io.github.mfozmen.notelore"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.github.mfozmen.notelore"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // The release key comes from the environment (the release workflow decodes it
    // from GitHub secrets) and never from the repo. Without it a release build is
    // signed with the debug key, so `flutter run --release` still works locally.
    val releaseKeystore = System.getenv("NOTELORE_ANDROID_KEYSTORE")
    signingConfigs {
        if (releaseKeystore != null) {
            create("release") {
                storeFile = file(releaseKeystore)
                storePassword = System.getenv("NOTELORE_ANDROID_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("NOTELORE_ANDROID_KEY_ALIAS")
                keyPassword = System.getenv("NOTELORE_ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (releaseKeystore != null) "release" else "debug")
        }
    }

    // The Google Play build (#307): `--dart-define=NOTELORE_STORE=play`, the same
    // switch that turns the Dart updater off (update.dart), merges
    // src/play/AndroidManifest.xml over the main one, which removes the install
    // permission and the updater's FileProvider. Flutter hands the dart-defines to
    // Gradle base64-encoded; every other build is the GitHub one, unchanged.
    val dartDefines = (project.findProperty("dart-defines") as String?)
        ?.split(",")
        ?.map { String(java.util.Base64.getDecoder().decode(it)) }
        .orEmpty()
    if ("NOTELORE_STORE=play" in dartDefines) {
        sourceSets.configureEach {
            if (name in setOf("debug", "profile", "release")) manifest.srcFile("src/play/AndroidManifest.xml")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // FileProvider, for handing a downloaded update to the installer.
    implementation("androidx.core:core-ktx:1.13.1")
}
