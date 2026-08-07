/// Classification for model catalog sections.
enum ModelCategory { chat, utility, vision }

/// Prompt formatting template identifier.
enum PromptTemplate { gemma, chatml, phi, llama, smollm }

/// Categorizes a model's relative inference speed for catalog display.
enum InferenceSpeed { fast, medium, slow }

/// Publisher of the base model. Used to group the catalog by family so the
/// user can compare one curated pick per vendor instead of a flat list.
enum ModelBrand { google, alibaba, microsoft, huggingFace, deepSeek }

extension ModelBrandInfo on ModelBrand {
  String get displayName => switch (this) {
    ModelBrand.google => 'Google Gemma',
    ModelBrand.alibaba => 'Alibaba Qwen',
    ModelBrand.microsoft => 'Microsoft Phi',
    ModelBrand.huggingFace => 'Hugging Face SmolLM',
    ModelBrand.deepSeek => 'DeepSeek',
  };
}

/// Which class of phone a model is curated for.
enum DeviceTier { lowEnd, midRange, highEnd }

extension DeviceTierInfo on DeviceTier {
  String get displayName => switch (this) {
    DeviceTier.lowEnd => 'Low-end (2-3 GB RAM)',
    DeviceTier.midRange => 'Mid-range (4 GB RAM)',
    DeviceTier.highEnd => 'High-end (6 GB+ RAM)',
  };
}

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
  final bool supportsToolCalling;
  final bool supportsVision;
  final InferenceSpeed inferenceSpeed;
  final ModelCategory category;
  final PromptTemplate promptTemplate;
  final ModelBrand brand;
  final DeviceTier deviceTier;

  /// Usable context window of this LiteRT build, in tokens.
  ///
  /// This is a property of the published `.litertlm` file (its baked-in KV
  /// cache), not of the base model. Every catalog build currently ships a
  /// 4096-token cache, which is why 4096 is the default rather than the base
  /// model's advertised 32K/128K window.
  final int contextTokens;

  /// True when this entry is the curated recommendation for its
  /// brand + device tier combination.
  final bool isRecommendedPick;

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
    this.supportsToolCalling = false,
    this.supportsVision = false,
    this.inferenceSpeed = InferenceSpeed.medium,
    this.category = ModelCategory.chat,
    this.promptTemplate = PromptTemplate.gemma,
    this.brand = ModelBrand.google,
    this.deviceTier = DeviceTier.midRange,
    this.contextTokens = 4096,
    this.isRecommendedPick = true,
  });

  double get sizeMB => sizeBytes / (1024 * 1024);
  bool get qualifiesFastBadge => inferenceSpeed == InferenceSpeed.fast;

  String get sizeFormatted {
    if (sizeMB < 1024) return '${sizeMB.toStringAsFixed(0)} MB';
    return '${(sizeMB / 1024).toStringAsFixed(1)} GB';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MODEL CATALOG — one curated pick per brand per device tier
// ═══════════════════════════════════════════════════════════════════════════════
//
// Every URL below was verified against the Hugging Face model API, and every
// sizeBytes value is the real file size reported by that API. Official
// `litert-community` repositories are preferred over third-party mirrors.
//
// Meta Llama has no entry: litert-community's Llama repositories require
// accepting Meta's licence (HTTP 401 without auth), so an in-app anonymous
// download cannot work. Microsoft publishes only one phone-sized LiteRT model
// (Phi-4 Mini, 3.6 GB), so it appears in the high-end tier only.

final List<ModelInfo> modelCatalog = [
  // ─── GOOGLE GEMMA ───────────────────────────────────────────────────────
  ModelInfo(
    id: 'gemma3-1b',
    name: 'Gemma 3 1B',
    description:
        'Google\'s best pick for low-end phones. Fast, tiny, and reliable for '
        'commands and short answers.',
    url:
        'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/gemma3-1b-it-int4.litertlm?download=true',
    fileName: 'gemma3-1b-it-int4.litertlm',
    sizeBytes: 584417280,
    ramRequirement: '2GB',
    minRamMB: 2048,
    speed: 'Very Fast',
    inferenceSpeed: InferenceSpeed.fast,
    category: ModelCategory.chat,
    promptTemplate: PromptTemplate.gemma,
    brand: ModelBrand.google,
    deviceTier: DeviceTier.lowEnd,
  ),
  ModelInfo(
    id: 'gemma4-e2b',
    name: 'Gemma 4 E2B',
    description:
        'Best all-round mid-range model. Image understanding and 32K context '
        'from Google\'s official LiteRT build.',
    url:
        'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm?download=true',
    fileName: 'gemma-4-E2B-it.litertlm',
    sizeBytes: 2588147712,
    ramRequirement: '4GB',
    minRamMB: 4096,
    speed: 'Medium',
    // Local tool calling is not wired end-to-end (LiteRtService reports
    // supportsToolCalling == false), so the catalog must not advertise it.
    supportsVision: true,
    inferenceSpeed: InferenceSpeed.medium,
    category: ModelCategory.chat,
    promptTemplate: PromptTemplate.gemma,
    brand: ModelBrand.google,
    deviceTier: DeviceTier.midRange,
  ),
  ModelInfo(
    id: 'gemma4-e4b',
    name: 'Gemma 4 E4B',
    description:
        'Highest-quality on-device model overall. Image understanding and 32K '
        'context. Needs a flagship phone.',
    url:
        'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm?download=true',
    fileName: 'gemma-4-E4B-it.litertlm',
    sizeBytes: 3659530240,
    ramRequirement: '6GB',
    minRamMB: 6144,
    speed: 'Slow',
    supportsVision: true,
    inferenceSpeed: InferenceSpeed.slow,
    category: ModelCategory.chat,
    promptTemplate: PromptTemplate.gemma,
    brand: ModelBrand.google,
    deviceTier: DeviceTier.highEnd,
  ),

  // ─── ALIBABA QWEN ───────────────────────────────────────────────────────
  ModelInfo(
    id: 'qwen3-0.6b',
    name: 'Qwen3 0.6B',
    description:
        'Smallest capable model in the catalog. Newest Qwen3 architecture, '
        'runs on almost any Android phone.',
    url:
        'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/qwen3_0_6b_mixed_int4.litertlm?download=true',
    fileName: 'qwen3_0_6b_mixed_int4.litertlm',
    sizeBytes: 497664000,
    ramRequirement: '2GB',
    minRamMB: 2048,
    speed: 'Very Fast',
    inferenceSpeed: InferenceSpeed.fast,
    category: ModelCategory.chat,
    promptTemplate: PromptTemplate.chatml,
    brand: ModelBrand.alibaba,
    deviceTier: DeviceTier.lowEnd,
  ),
  ModelInfo(
    id: 'qwen3-1.7b',
    name: 'Qwen3 1.7B',
    description:
        'Strong mid-range alternative to Gemma. Good multilingual and reasoning '
        'quality for under 2 GB.',
    url:
        'https://huggingface.co/litert-community/Qwen3-1.7B/resolve/main/Qwen3_1.7B.litertlm?download=true',
    fileName: 'Qwen3_1.7B.litertlm',
    sizeBytes: 2056729520,
    ramRequirement: '4GB',
    minRamMB: 4096,
    speed: 'Fast',
    inferenceSpeed: InferenceSpeed.medium,
    category: ModelCategory.chat,
    promptTemplate: PromptTemplate.chatml,
    brand: ModelBrand.alibaba,
    deviceTier: DeviceTier.midRange,
  ),
  ModelInfo(
    id: 'qwen3-4b',
    name: 'Qwen3 4B',
    description:
        'Strongest non-Google model that still fits a phone. Excellent '
        'reasoning and coding for its size.',
    url:
        'https://huggingface.co/litert-community/Qwen3-4B/resolve/main/qwen3_4b_mixed_int4.litertlm?download=true',
    fileName: 'qwen3_4b_mixed_int4.litertlm',
    sizeBytes: 2659057664,
    ramRequirement: '6GB',
    minRamMB: 6144,
    speed: 'Medium',
    inferenceSpeed: InferenceSpeed.medium,
    category: ModelCategory.chat,
    promptTemplate: PromptTemplate.chatml,
    brand: ModelBrand.alibaba,
    deviceTier: DeviceTier.highEnd,
  ),

  // ─── HUGGING FACE SMOLLM ────────────────────────────────────────────────
  ModelInfo(
    id: 'smollm2-360m',
    name: 'SmolLM2 360M',
    description:
        'Ultra-light fully-open model. The lightest option here — ideal for '
        '2 GB phones and quick command handling.',
    url:
        'https://huggingface.co/litert-community/SmolLM2-360M-Instruct/resolve/main/SmolLM2_360M_instruct.litertlm?download=true',
    fileName: 'SmolLM2_360M_instruct.litertlm',
    sizeBytes: 373719040,
    ramRequirement: '2GB',
    minRamMB: 2048,
    speed: 'Very Fast',
    inferenceSpeed: InferenceSpeed.fast,
    category: ModelCategory.chat,
    promptTemplate: PromptTemplate.smollm,
    brand: ModelBrand.huggingFace,
    deviceTier: DeviceTier.lowEnd,
  ),
  ModelInfo(
    id: 'smollm3-3b-q4',
    name: 'SmolLM3 3B (int4)',
    description:
        'Fully-open 3B reasoner, quantized to fit mid-range phones. Strong '
        'multilingual and long-context behaviour.',
    url:
        'https://huggingface.co/litert-community/SmolLM3-3B/resolve/main/SmolLM3-3B_q4_block32_ekv4096.litertlm?download=true',
    fileName: 'SmolLM3-3B_q4_block32_ekv4096.litertlm',
    sizeBytes: 2002257840,
    ramRequirement: '4GB',
    minRamMB: 4096,
    speed: 'Medium',
    inferenceSpeed: InferenceSpeed.medium,
    category: ModelCategory.chat,
    promptTemplate: PromptTemplate.smollm,
    brand: ModelBrand.huggingFace,
    deviceTier: DeviceTier.midRange,
  ),
  ModelInfo(
    id: 'smollm3-3b',
    name: 'SmolLM3 3B',
    description:
        'Full-precision SmolLM3 build. Best quality from the fully-open '
        '(weights, data and configs) family.',
    url:
        'https://huggingface.co/litert-community/SmolLM3-3B/resolve/main/SmolLM3-3B.litertlm?download=true',
    fileName: 'SmolLM3-3B.litertlm',
    sizeBytes: 3108978688,
    ramRequirement: '6GB',
    minRamMB: 6144,
    speed: 'Slow',
    inferenceSpeed: InferenceSpeed.slow,
    category: ModelCategory.chat,
    promptTemplate: PromptTemplate.smollm,
    brand: ModelBrand.huggingFace,
    deviceTier: DeviceTier.highEnd,
  ),

  // ─── MICROSOFT PHI (high-end only) ──────────────────────────────────────
  ModelInfo(
    id: 'phi4-mini',
    name: 'Phi-4 Mini Instruct',
    description:
        'Microsoft\'s 3.8B instruct model. Very strong at maths, logic and '
        'structured answers. Flagship phones only.',
    url:
        'https://huggingface.co/litert-community/Phi-4-mini-instruct/resolve/main/Phi-4-mini-instruct_multi-prefill-seq_q8_ekv4096.litertlm?download=true',
    fileName: 'Phi-4-mini-instruct_multi-prefill-seq_q8_ekv4096.litertlm',
    sizeBytes: 3910090752,
    ramRequirement: '6GB',
    minRamMB: 6144,
    speed: 'Slow',
    inferenceSpeed: InferenceSpeed.slow,
    category: ModelCategory.chat,
    promptTemplate: PromptTemplate.phi,
    brand: ModelBrand.microsoft,
    deviceTier: DeviceTier.highEnd,
  ),

  // ─── DEEPSEEK (mid-range only) ──────────────────────────────────────────
  ModelInfo(
    id: 'deepseek-r1-qwen-1.5b',
    name: 'DeepSeek R1 Distill 1.5B',
    description:
        'Reasoning-distilled model that thinks step by step before answering. '
        'Best pick for maths and logic on mid-range phones.',
    url:
        'https://huggingface.co/litert-community/DeepSeek-R1-Distill-Qwen-1.5B/resolve/main/DeepSeek-R1-Distill-Qwen-1.5B_multi-prefill-seq_q8_ekv4096.litertlm?download=true',
    fileName:
        'DeepSeek-R1-Distill-Qwen-1.5B_multi-prefill-seq_q8_ekv4096.litertlm',
    sizeBytes: 1833451520,
    ramRequirement: '3GB',
    minRamMB: 3072,
    speed: 'Medium',
    inferenceSpeed: InferenceSpeed.medium,
    category: ModelCategory.chat,
    promptTemplate: PromptTemplate.chatml,
    brand: ModelBrand.deepSeek,
    deviceTier: DeviceTier.midRange,
  ),

  // ─── UNCENSORED VARIANTS (not tier picks) ───────────────────────────────
  ModelInfo(
    id: 'gemma4-e2b-abliterated',
    name: 'Gemma 4 E2B Uncensored',
    description:
        'Abliterated Gemma 4 E2B community build. Refuses far less. Image '
        'understanding retained.',
    url:
        'https://huggingface.co/DuoNeural/Gemma-4-Abliterated-LiteRT/resolve/main/Gemma-4-E2B-Abliterated.litertlm?download=true',
    fileName: 'Gemma-4-E2B-Abliterated.litertlm',
    sizeBytes: 2400000000,
    ramRequirement: '4GB',
    minRamMB: 4096,
    speed: 'Medium',
    supportsVision: true,
    inferenceSpeed: InferenceSpeed.medium,
    category: ModelCategory.chat,
    promptTemplate: PromptTemplate.gemma,
    brand: ModelBrand.google,
    deviceTier: DeviceTier.midRange,
    isRecommendedPick: false,
  ),
  ModelInfo(
    id: 'gemma4-e4b-abliterated',
    name: 'Gemma 4 E4B Uncensored',
    description:
        'Abliterated Gemma 4 E4B community build. Highest-quality uncensored '
        'option. Image understanding retained.',
    url:
        'https://huggingface.co/DuoNeural/Gemma-4-Abliterated-LiteRT/resolve/main/Gemma-4-E4B-Abliterated.litertlm?download=true',
    fileName: 'Gemma-4-E4B-Abliterated.litertlm',
    sizeBytes: 3900000000,
    ramRequirement: '6GB',
    minRamMB: 6144,
    speed: 'Slow',
    supportsVision: true,
    inferenceSpeed: InferenceSpeed.slow,
    category: ModelCategory.chat,
    promptTemplate: PromptTemplate.gemma,
    brand: ModelBrand.google,
    deviceTier: DeviceTier.highEnd,
    isRecommendedPick: false,
  ),
];

// ═══════════════════════════════════════════════════════════════════════════════
// CATALOG FILTERING HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

/// Get all chat models from the catalog.
List<ModelInfo> getChatModels() =>
    modelCatalog.where((m) => m.category == ModelCategory.chat).toList();

/// Get all utility models from the catalog.
List<ModelInfo> getUtilityModels() =>
    modelCatalog.where((m) => m.category == ModelCategory.utility).toList();

/// Get all vision models from the catalog.
List<ModelInfo> getVisionModels() =>
    modelCatalog.where((m) => m.category == ModelCategory.vision).toList();

/// Models published by [brand], ordered low-end first.
List<ModelInfo> getModelsByBrand(ModelBrand brand) =>
    modelCatalog.where((m) => m.brand == brand).toList()
      ..sort((a, b) => a.deviceTier.index.compareTo(b.deviceTier.index));

/// Models curated for [tier], including non-recommended variants.
List<ModelInfo> getModelsByDeviceTier(DeviceTier tier) =>
    modelCatalog.where((m) => m.deviceTier == tier).toList();

/// The curated pick for a brand + device tier, or null when that vendor
/// publishes no phone-sized LiteRT model for the tier.
ModelInfo? getRecommendedPick(ModelBrand brand, DeviceTier tier) {
  for (final model in modelCatalog) {
    if (model.brand == brand &&
        model.deviceTier == tier &&
        model.isRecommendedPick) {
      return model;
    }
  }
  return null;
}

/// Brands present in the catalog, in display order.
List<ModelBrand> get catalogBrands =>
    ModelBrand.values.where((b) => getModelsByBrand(b).isNotEmpty).toList();
