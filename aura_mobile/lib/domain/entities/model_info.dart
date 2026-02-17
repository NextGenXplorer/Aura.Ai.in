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
  });

  String get sizeFormatted {
    final sizeMB = sizeBytes / (1024 * 1024);
    if (sizeMB < 1024) {
      return '${sizeMB.toStringAsFixed(0)} MB';
    }
    final sizeGB = sizeMB / 1024;
    return '${sizeGB.toStringAsFixed(1)} GB';
  }
}

// Model Catalog
final List<ModelInfo> modelCatalog = [
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
  ),
  ModelInfo(
    id: 'qwen2.5-3b',
    name: 'Qwen 2.5 3B',
    description: 'Strong reasoning. The sweet spot for modern phones.',
    url: 'https://hf-mirror.com/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf?download=true',
    fileName: 'qwen2.5-3b-instruct-q4_k_m.gguf',
    sizeBytes: 1930000000, // ~1.8GB
    ramRequirement: '4GB',
    minRamMB: 3500, // Fits tightly in 4GB, comfortable in 6GB
    speed: 'Medium',
  ),
  ModelInfo(
    id: 'qwen2.5-7b',
    name: 'Qwen 2.5 7B',
    description: 'Desktop-class intelligence. Requires high-end device.',
    url: 'https://hf-mirror.com/Qwen/Qwen2.5-7B-Instruct-GGUF/resolve/main/qwen2.5-7b-instruct-q4_k_m.gguf?download=true',
    fileName: 'qwen2.5-7b-instruct-q4_k_m.gguf',
    sizeBytes: 4660000000, // ~4.3GB
    ramRequirement: '8GB',
    minRamMB: 7500, // Needs 8GB+ device
    speed: 'Slow',
  ),
];
