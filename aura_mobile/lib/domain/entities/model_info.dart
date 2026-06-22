import 'ai_engine.dart';

class ModelInfo {
  final String id;
  final String name;
  final String description;
  final String url;
  final int sizeBytes;
  final String ramRequirement;
  final String speed;
  final String fileName;
  final int minRamMB;

  /// The inference engine that owns this model. Defaults to [AIEngine.gguf]
  /// so existing Qwen catalog entries remain `gguf` without modification.
  final AIEngine engine;

  /// Whether the model supports native function/tool calling.
  final bool supportsToolCalling;

  /// Whether the model supports vision (image) inputs.
  final bool supportsVision;

  /// The model's relative inference speed category, used for catalog display
  /// and the fast Capability_Badge.
  final InferenceSpeed inferenceSpeed;

  ModelInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.url,
    required this.sizeBytes,
    required this.ramRequirement,
    required this.speed,
    required this.fileName,
    required this.minRamMB,
    this.engine = AIEngine.gguf,
    this.supportsToolCalling = false,
    this.supportsVision = false,
    this.inferenceSpeed = InferenceSpeed.medium,
  });

  /// The download size expressed in megabytes.
  double get sizeMB => sizeBytes / (1024 * 1024);

  /// Whether this model qualifies for the fast Capability_Badge, i.e. its
  /// inference speed is the highest-speed value.
  bool get qualifiesFastBadge => inferenceSpeed == InferenceSpeed.fast;

  String get sizeFormatted {
    if (sizeMB < 1024) {
      return '${sizeMB.toStringAsFixed(0)} MB';
    }
    final sizeGB = sizeMB / 1024;
    return '${sizeGB.toStringAsFixed(1)} GB';
  }
}

// Model Catalog
final List<ModelInfo> modelCatalog = [
  // --- GGUF / Qwen family (RunAnywhere engine) ---
  ModelInfo(
    id: 'qwen2.5-0.5b',
    name: 'Qwen 2.5 0.5B',
    description: 'Ultra-fast, lightweight. Ideal for older devices.',
    url: 'https://hf-mirror.com/bartowski/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf?download=true',
    fileName: 'qwen2.5-0.5b-instruct-q4_k_m.gguf',
    sizeBytes: 397000000, // ~380MB
    ramRequirement: '1.5GB',
    minRamMB: 1536,
    speed: 'Very Fast',
    engine: AIEngine.gguf,
    inferenceSpeed: InferenceSpeed.fast,
  ),
  ModelInfo(
    id: 'qwen2.5-1.5b',
    name: 'Qwen 2.5 1.5B',
    description: 'Balanced performance. Great for general tasks.',
    url: 'https://hf-mirror.com/bartowski/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/Qwen2.5-1.5B-Instruct-Q4_K_M.gguf?download=true',
    fileName: 'qwen2.5-1.5b-instruct-q4_k_m.gguf',
    sizeBytes: 986000000, // ~940MB
    ramRequirement: '2.5GB',
    minRamMB: 2560,
    speed: 'Fast',
    engine: AIEngine.gguf,
    supportsToolCalling: true,
    inferenceSpeed: InferenceSpeed.fast,
  ),
  ModelInfo(
    id: 'qwen2.5-3b',
    name: 'Qwen 2.5 3B',
    description: 'Strong reasoning. The sweet spot for modern phones.',
    url: 'https://hf-mirror.com/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf?download=true',
    fileName: 'qwen2.5-3b-instruct-q4_k_m.gguf',
    sizeBytes: 1930000000, // ~1.8GB
    ramRequirement: '4GB',
    minRamMB: 3500,
    speed: 'Medium',
    engine: AIEngine.gguf,
    supportsToolCalling: true,
    inferenceSpeed: InferenceSpeed.medium,
  ),

  // --- LiteRT / Gemma family (flutter_gemma engine) ---
  ModelInfo(
    id: 'gemma3-1b',
    name: 'Gemma 3 1B',
    description: 'Compact Google Gemma model. Fast, runs on most phones.',
    url: 'https://huggingface.co/MiCkSoftware/Gemma3-1B-IT-LiteRT/resolve/main/gemma3-1b-it-int4.task?download=true',
    fileName: 'gemma3-1b-it-int4.task',
    sizeBytes: 555000000, // ~530MB
    ramRequirement: '2GB',
    minRamMB: 2048,
    speed: 'Very Fast',
    engine: AIEngine.litert,
    inferenceSpeed: InferenceSpeed.fast,
  ),
  ModelInfo(
    id: 'gemma3n-e2b',
    name: 'Gemma 3n E2B',
    description: 'Efficient Gemma 3n model with strong general performance.',
    url: 'https://huggingface.co/MiCkSoftware/gemma-3n-E2B-it-litert-preview/resolve/main/gemma-3n-E2B-it-int4.task?download=true',
    fileName: 'gemma-3n-e2b-it-int4.task',
    sizeBytes: 3140000000, // ~3.0GB
    ramRequirement: '4GB',
    minRamMB: 4096,
    speed: 'Medium',
    engine: AIEngine.litert,
    inferenceSpeed: InferenceSpeed.medium,
  ),
  ModelInfo(
    id: 'gemma4-e2b',
    name: 'Gemma 4 E2B',
    description: 'Best overall. Multimodal Gemma 4 with tool calling and 32K context.',
    url: 'https://huggingface.co/huggingworld/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm?download=true',
    fileName: 'gemma-4-E2B-it.litertlm',
    sizeBytes: 2580000000, // ~2.5GB (matches Google AI Edge Gallery)
    ramRequirement: '4GB',
    minRamMB: 4096,
    speed: 'Medium',
    engine: AIEngine.litert,
    supportsToolCalling: true,
    supportsVision: true,
    inferenceSpeed: InferenceSpeed.medium,
  ),
  ModelInfo(
    id: 'gemma4-e4b',
    name: 'Gemma 4 E4B',
    description: 'Largest Gemma 4. Highest quality, multimodal, tool calling, 32K context.',
    url: 'https://huggingface.co/huggingworld/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm?download=true',
    fileName: 'gemma-4-E4B-it.litertlm',
    sizeBytes: 3650000000, // ~3.6GB (matches Google AI Edge Gallery)
    ramRequirement: '6GB',
    minRamMB: 6144,
    speed: 'Slow',
    engine: AIEngine.litert,
    supportsToolCalling: true,
    supportsVision: true,
    inferenceSpeed: InferenceSpeed.slow,
  ),
];
