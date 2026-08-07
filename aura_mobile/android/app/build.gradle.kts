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

    buildFeatures {
        aidl = true
    }

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
            // Sign with every scheme so the APK installs on the widest range of
            // devices: v1 (JAR) for very old launchers, v2 for Android 7+, and
            // v3 for newer key-rotation-aware installers. A missing scheme is a
            // common cause of "App not installed" on certain OEM ROMs.
            enableV1Signing = true
            enableV2Signing = true
            enableV3Signing = true
        }
    }

    defaultConfig {
        applicationId = "com.aura.mobile.aura_mobile"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

    }

    // AGP rejects a build that sets both ndk.abiFilters and an enabled splits.abi
    // block, so the two mechanisms are selected by this single flag and are never
    // active at the same time. Flutter sets `split-per-abi` when you pass
    // `--split-per-abi`.
    val isSplitBuild = project.hasProperty("split-per-abi") &&
        project.property("split-per-abi") == "true"

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android.txt"), "proguard-rules.pro")

            // Standard (non-split) release APK is a single "universal" package
            // that must install on ALL real phones, so it carries both 64-bit
            // (arm64-v8a) and 32-bit (armeabi-v7a) ARM binaries. x86_64 is left
            // out because it only targets emulators/Chromebooks and would just
            // inflate the size. For the smallest possible per-device download,
            // build with `--split-per-abi` (handled by splits.abi below).
            if (!isSplitBuild) {
                ndk {
                    abiFilters.clear()
                    abiFilters.add("arm64-v8a")
                    abiFilters.add("armeabi-v7a")
                }
            }
        }
    }

    // Req 9.1 / 9.4: produce a separate APK per CPU architecture so each installed
    // package contains only the native binaries for that device's architecture.
    // LiteRT/MediaPipe ships large per-ABI .so files, so this split is what keeps
    // the installed size in check.
    if (isSplitBuild) {
        splits {
            abi {
                isEnable = true
                reset()
                include("armeabi-v7a", "arm64-v8a", "x86_64")
                isUniversalApk = false
            }
        }
    }

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
        // Compress the native (.so) libraries inside the APK. By default AGP
        // stores them uncompressed (extractNativeLibs=false), which makes the
        // downloadable APK much larger — the AI runtime alone (llm_inference,
        // litertlm, mediapipe vision, ML Kit) is ~150 MB uncompressed. Legacy
        // packaging compresses them (~40-50% smaller download); Android extracts
        // them at install time. This trades a little extra install footprint /
        // first-launch time for a dramatically smaller APK to distribute.
        jniLibs {
            useLegacyPackaging = true
        }
    }


}

flutter {
    source = "../.."
}

// flutter_gemma pulls heavyweight native dependencies whether or not the host
// app uses them. We exclude the RAG stack, which this app never calls:
//
//   localagents-rag -> libgecko_embedding_model_jni.so (16 MB),
//                      libgemma_embedding_model_jni.so (16 MB),
//                      libtext_chunker_jni.so (9 MB),
//                      libsqlite_vector_store_jni.so (7 MB)   (~48 MB total)
//
// EmbeddingService uses the plain LLM inference API and derives its vectors in
// Dart (_textToEmbedding); it never calls the RAG retrieval API.
//
// NOTE: tasks-vision-image-generator is intentionally NOT excluded. Although
// on-device image *generation* is unused, flutter_gemma's genai path references
// the mediapipe image framework (com.google.mediapipe.framework.image.*) for
// image *input* to vision-capable models, which IS a live code path
// (LLMService.chat accepts imageBytes). Excluding it breaks the R8 release build
// and would crash vision inference at runtime.
//
// If RAG is ever adopted, remove the exclude — calling an excluded module fails
// at runtime with NoClassDefFoundError, not at build.
configurations.all {
    exclude(group = "com.google.ai.edge.localagents", module = "localagents-rag")
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
