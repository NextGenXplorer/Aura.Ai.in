import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Tracks availability of utility models (FunctionGemma, EmbeddingGemma) on disk.
class UtilityModelState {
  final bool isFunctionGemmaAvailable;
  final bool isEmbeddingGemmaAvailable;

  const UtilityModelState({
    this.isFunctionGemmaAvailable = false,
    this.isEmbeddingGemmaAvailable = false,
  });

  UtilityModelState copyWith({
    bool? isFunctionGemmaAvailable,
    bool? isEmbeddingGemmaAvailable,
  }) => UtilityModelState(
    isFunctionGemmaAvailable: isFunctionGemmaAvailable ?? this.isFunctionGemmaAvailable,
    isEmbeddingGemmaAvailable: isEmbeddingGemmaAvailable ?? this.isEmbeddingGemmaAvailable,
  );
}

class UtilityModelManager extends StateNotifier<UtilityModelState> {
  static const String functionGemmaFileName = 'functiongemma-270m.task';
  static const String embeddingGemmaFileName = 'embeddinggemma-300m.task';

  String? _docsPath;

  UtilityModelManager() : super(const UtilityModelState());

  /// Check file existence on app start.
  Future<void> checkAvailability() async {
    final dir = await getApplicationDocumentsDirectory();
    _docsPath = dir.path;

    final fgExists = await File('${dir.path}/$functionGemmaFileName').exists();
    final egExists = await File('${dir.path}/$embeddingGemmaFileName').exists();

    state = UtilityModelState(
      isFunctionGemmaAvailable: fgExists,
      isEmbeddingGemmaAvailable: egExists,
    );
  }

  /// Called when a utility model download completes.
  void onDownloadComplete(String fileName) {
    if (fileName == functionGemmaFileName) {
      state = state.copyWith(isFunctionGemmaAvailable: true);
    } else if (fileName == embeddingGemmaFileName) {
      state = state.copyWith(isEmbeddingGemmaAvailable: true);
    }
  }

  /// Called when a utility model file is deleted.
  void onModelDeleted(String fileName) {
    if (fileName == functionGemmaFileName) {
      state = state.copyWith(isFunctionGemmaAvailable: false);
    } else if (fileName == embeddingGemmaFileName) {
      state = state.copyWith(isEmbeddingGemmaAvailable: false);
    }
  }

  /// Full path to FunctionGemma model file, or null if not available.
  String? get functionGemmaPath =>
      state.isFunctionGemmaAvailable && _docsPath != null
          ? '$_docsPath/$functionGemmaFileName'
          : null;

  /// Full path to EmbeddingGemma model file, or null if not available.
  String? get embeddingGemmaPath =>
      state.isEmbeddingGemmaAvailable && _docsPath != null
          ? '$_docsPath/$embeddingGemmaFileName'
          : null;
}

/// Riverpod provider for UtilityModelManager.
final utilityModelManagerProvider =
    StateNotifierProvider<UtilityModelManager, UtilityModelState>(
  (ref) => UtilityModelManager(),
);
