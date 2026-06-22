import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load keystore properties
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.aura.mobile.aura_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.0.12433566"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }

    defaultConfig {
        applicationId = "com.aura.mobile.aura_mobile"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android.txt"), "proguard-rules.pro")
            
            // Restrict release build architectures to arm64-v8a to prevent bundling unused ABIs
            // in standard APKs, but skip this when building split APKs to avoid conflicts.
            val isSplitBuild = project.hasProperty("split-per-abi") && project.property("split-per-abi") == "true"
            if (!isSplitBuild) {
                ndk {
                    abiFilters.clear()
                    abiFilters.add("arm64-v8a")
                }
            }
        }
    }

    // Req 9.1 / 9.4: Produce a separate APK per CPU architecture so each installed
    // package contains only the native binaries for that device's architecture and
    // excludes the binaries for every other supported architecture. LiteRT/MediaPipe
    // ships native .so files per ABI, so this split keeps installed size in check.
    //
    // NOTE: splits.abi is disabled when a plugin (e.g. flutter_gemma) sets
    // ndk.abiFilters in its own build.gradle, as the two mechanisms conflict.
    // For release builds, re-enable this block after removing the plugin's
    // abiFilters or use bundletool / AAB which handles per-ABI delivery natively.
    // splits {
    //     abi {
    //         isEnable = true
    //         reset()
    //         include("armeabi-v7a", "arm64-v8a", "x86_64")
    //         isUniversalApk = false
    //     }
    // }

    // Req 9.2 / 9.3: LiteRT model files (.task / .litertlm) are NEVER bundled into the
    // application package. They are distributed as downloadable content retrieved after
    // installation, so the produced APK contains zero LiteRT model files. The bundled
    // assets/models/ directory holds only a .gitkeep placeholder. As a defensive guard,
    // exclude any LiteRT model files from packaging (additive to AGP defaults).
    packaging {
        resources {
            excludes += "**/*.task"
            excludes += "**/*.litertlm"
        }
    }


}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
