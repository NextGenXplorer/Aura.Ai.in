# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Fix for R8 processing of pdfbox
-dontwarn com.gemalto.jp2.**
-dontwarn com.tom_roush.pdfbox.**

# Keep our custom platform channels and assistant background services
-keep class com.aura.mobile.aura_mobile.** { *; }
-keep public class * extends io.flutter.embedding.android.FlutterActivity
-keep public class * extends android.app.Service
-keep public class * extends android.content.BroadcastReceiver

# Keep fllama classes to prevent JNI failures
-keep class com.fllama.** { *; }
-dontwarn com.fllama.**

# Keep flutter_gemma classes to prevent JNI failures
-keep class com.fluttergemma.** { *; }
-dontwarn com.fluttergemma.**

# Keep ML Kit classes for text recognition
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**

# Ignore missing classes from optional/deferred features (e.g. Play Core and MediaPipe Protos)
-dontwarn com.google.android.play.core.**
-dontwarn com.google.mediapipe.proto.**

# Keep org.json classes and methods to prevent R8 from renaming JSONObject methods
-keep class org.json.** { *; }
-dontwarn org.json.**
