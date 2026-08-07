import 'package:aura_mobile/domain/entities/model_info.dart';

/// Factory for formatting prompts according to each model's expected template.
///
/// Different LLM families require different chat turn markers. This factory
/// encapsulates the formatting logic so the LiteRtService can apply the
/// correct template for any model in the catalog.
class PromptTemplateFactory {
  /// Format a prompt using the specified template.
  ///
  /// Returns the full formatted prompt string with appropriate turn markers.
  static String format(
    PromptTemplate template,
    String prompt, {
    String? systemPrompt,
  }) {
    switch (template) {
      case PromptTemplate.gemma:
        return _formatGemma(prompt, systemPrompt);
      case PromptTemplate.chatml:
        return _formatChatML(prompt, systemPrompt);
      case PromptTemplate.phi:
        return _formatChatML(prompt, systemPrompt); // Phi uses ChatML
      case PromptTemplate.llama:
        return _formatLlama(prompt, systemPrompt);
      case PromptTemplate.smollm:
        return _formatChatML(prompt, systemPrompt); // SmolLM uses ChatML
    }
  }

  /// Gemma turn-marker format.
  static String _formatGemma(String prompt, String? systemPrompt) {
    final buffer = StringBuffer();
    buffer.write('<start_of_turn>user\n');
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      buffer.write(systemPrompt);
      buffer.write('\n\n');
    }
    buffer.write(prompt);
    buffer.write('<end_of_turn>\n');
    buffer.write('<start_of_turn>model\n');
    return buffer.toString();
  }

  /// ChatML format (Phi-4, SmolLM, Qwen).
  static String _formatChatML(String prompt, String? systemPrompt) {
    final buffer = StringBuffer();
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      buffer.write('<|im_start|>system\n');
      buffer.write(systemPrompt);
      buffer.write('<|im_end|>\n');
    }
    buffer.write('<|im_start|>user\n');
    buffer.write(prompt);
    buffer.write('<|im_end|>\n');
    buffer.write('<|im_start|>assistant\n');
    return buffer.toString();
  }

  /// Llama 3.2 format.
  static String _formatLlama(String prompt, String? systemPrompt) {
    final buffer = StringBuffer();
    buffer.write('<|begin_of_text|>');
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      buffer.write('<|start_header_id|>system<|end_header_id|>\n\n');
      buffer.write(systemPrompt);
      buffer.write('<|eot_id|>');
    }
    buffer.write('<|start_header_id|>user<|end_header_id|>\n\n');
    buffer.write(prompt);
    buffer.write('<|eot_id|>');
    buffer.write('<|start_header_id|>assistant<|end_header_id|>\n\n');
    return buffer.toString();
  }

  /// Format a Gemma 4 prompt with thinking mode enabled.
  ///
  /// Thinking mode instructs the model to reason step-by-step internally
  /// before producing the final answer. This significantly improves quality
  /// for complex tasks (math, code, multi-step reasoning) at the cost of
  /// slightly longer response times.
  ///
  /// The model outputs thinking in `<think>...</think>` tags, followed by
  /// the actual answer. The caller should strip `<think>...</think>` content
  /// before displaying to the user.
  static String formatWithThinking(
    PromptTemplate template,
    String prompt, {
    String? systemPrompt,
  }) {
    final thinkingInstruction =
        'Think step by step before answering. '
        'Put your reasoning inside <think></think> tags, then give your final answer.';

    final effectiveSystem = systemPrompt != null && systemPrompt.isNotEmpty
        ? '$systemPrompt\n\n$thinkingInstruction'
        : thinkingInstruction;

    return format(template, prompt, systemPrompt: effectiveSystem);
  }

  /// Strip thinking tags from model output — returns only the final answer.
  ///
  /// Gemma 4 in thinking mode outputs:
  /// `<think>reasoning here</think>The actual answer`
  ///
  /// This method removes the think block and returns the clean answer.
  static String stripThinking(String output) {
    // Remove <think>...</think> blocks (may appear at start of output)
    final stripped = output.replaceAll(
      RegExp(r'<think>[\s\S]*?</think>\s*', caseSensitive: false),
      '',
    );
    return stripped.trimLeft();
  }
}
