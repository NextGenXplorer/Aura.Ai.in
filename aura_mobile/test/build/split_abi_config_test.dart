// Build/smoke assertions for the split-ABI Android configuration and the
// guarantee that no LiteRT model files are bundled into the application package.
//
// Spec: multi-engine-ai-models, Task 12.2
// Validates: Requirements 9.1, 9.2, 9.3, 9.4
//
// These are static assertions over the build configuration and bundled assets
// rather than a full Gradle build, so they run fast in CI and fail loudly if a
// future change removes the split or accidentally bundles a model file.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // Flutter tests execute with the package root (aura_mobile) as the working
  // directory, so these paths are resolved relative to that root.
  final buildGradle = File('android/app/build.gradle.kts');
  final modelsAssetDir = Directory('assets/models');

  group('Split-ABI build configuration (Req 9.1, 9.4)', () {
    late String contents;

    setUpAll(() {
      expect(
        buildGradle.existsSync(),
        isTrue,
        reason: 'android/app/build.gradle.kts must exist',
      );
      contents = buildGradle.readAsStringSync();
    });

    test('declares a splits { abi { ... } } block', () {
      // Tolerate arbitrary whitespace/newlines between the tokens.
      final splitsAbi = RegExp(r'splits\s*\{\s*abi\s*\{', multiLine: true);
      expect(
        splitsAbi.hasMatch(contents),
        isTrue,
        reason: 'A splits { abi { ... } } block must be present (Req 9.1).',
      );
    });

    test('enables the ABI split', () {
      final enabled = RegExp(r'isEnable\s*=\s*true');
      expect(
        enabled.hasMatch(contents),
        isTrue,
        reason: 'The ABI split must be enabled via isEnable = true (Req 9.1).',
      );
    });

    test('includes the supported CPU architectures', () {
      // Each installed package contains only its architecture's binaries, so we
      // must explicitly enumerate the supported ABIs (Req 9.4).
      for (final abi in const ['armeabi-v7a', 'arm64-v8a', 'x86_64']) {
        expect(
          contents.contains('"$abi"'),
          isTrue,
          reason: 'The ABI split must include "$abi" (Req 9.4).',
        );
      }
    });

    test('disables the universal (all-ABI) APK', () {
      final noUniversal = RegExp(r'isUniversalApk\s*=\s*false');
      expect(
        noUniversal.hasMatch(contents),
        isTrue,
        reason:
            'isUniversalApk must be false so no all-architecture APK bundles '
            'every architecture\'s binaries (Req 9.4).',
      );
    });

    test('excludes LiteRT model files from packaging as a defensive guard', () {
      // Req 9.3: the produced package contains zero LiteRT model files.
      expect(
        contents.contains('*.task'),
        isTrue,
        reason: 'Packaging must exclude *.task model files (Req 9.3).',
      );
      expect(
        contents.contains('*.litertlm'),
        isTrue,
        reason: 'Packaging must exclude *.litertlm model files (Req 9.3).',
      );
    });
  });

  group('No bundled model files in assets (Req 9.2, 9.3)', () {
    test('assets/models contains no LiteRT or GGUF model files', () {
      expect(
        modelsAssetDir.existsSync(),
        isTrue,
        reason: 'assets/models directory must exist (it holds only .gitkeep).',
      );

      const modelExtensions = ['.task', '.litertlm', '.gguf'];

      final bundledModelFiles = modelsAssetDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) {
            final lower = f.path.toLowerCase();
            return modelExtensions.any(lower.endsWith);
          })
          .map((f) => f.path)
          .toList();

      expect(
        bundledModelFiles,
        isEmpty,
        reason:
            'LiteRT/GGUF model files must NOT be bundled; they are downloaded '
            'post-install (Req 9.2, 9.3). Found: $bundledModelFiles',
      );
    });

    test('assets/models holds only the .gitkeep placeholder', () {
      final entries = modelsAssetDir
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .toList();

      expect(
        entries,
        equals(['.gitkeep']),
        reason:
            'assets/models should contain only a .gitkeep placeholder so the '
            'application package bundles zero model files. Found: $entries',
      );
    });
  });
}
