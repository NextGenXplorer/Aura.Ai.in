import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:aura_mobile/data/datasources/llm_service.dart';
import 'package:aura_mobile/core/providers/ai_providers.dart';

final documentGenerationServiceProvider = Provider((ref) {
  return DocumentGenerationService(ref.read(llmServiceProvider));
});

/// Types of documents AURA can generate.
enum GeneratedDocType {
  pdf,
  code,
  csv,
  textFile,
}

/// Result of a document generation operation.
class DocGenResult {
  final bool success;
  final String? filePath;
  final String? error;
  final String content;
  
  const DocGenResult({
    required this.success,
    this.filePath,
    this.error,
    this.content = '',
  });
}

/// Service that generates documents (PDF, code, CSV, text) using the on-device LLM.
/// 
/// Flow: User request → LLM generates content → Convert to file format → Share/Save
/// Everything runs 100% offline.
class DocumentGenerationService {
  final LLMService _llmService;

  DocumentGenerationService(this._llmService);

  /// Generate a PDF document from a user prompt.
  /// The LLM writes the content, then it's rendered as a formatted PDF.
  /// If [preGeneratedContent] is provided, skip LLM generation and use it directly.
  Stream<String> generateAndExportPdf({
    required String topic,
    String? style, // "report", "notes", "resume", "letter", "essay"
    String? preGeneratedContent,
  }) async* {
    if (!_llmService.isModelLoaded && preGeneratedContent == null) {
      yield '❌ Please load an AI model first.';
      return;
    }

    String content;

    if (preGeneratedContent != null && preGeneratedContent.isNotEmpty) {
      // Use pre-generated content directly (from Writing Workspace)
      content = preGeneratedContent;
      yield '📄 **Creating PDF from your draft...**\n';
    } else {
      yield '📝 **Writing about "$topic"...**\n\n';

      // 1. Generate content using LLM — plain, direct prompt (weak models
      // refuse "act as a document writer" style prompts, so keep it natural).
      final prompt = _buildDocPrompt(topic, style ?? 'report');
      final contentBuffer = StringBuffer();

      await for (final token in _llmService.chat(
        prompt,
        systemPrompt: 'You are a helpful assistant. Write clear, detailed, well-organized content. Use headings where helpful.',
        temperature: 0.6,
        maxTokens: 1024,
      )) {
        contentBuffer.write(token);
        yield token; // Stream content to chat as it generates
      }

      content = contentBuffer.toString().trim();

      // Detect a refusal or empty/tiny output and retry once with a simpler ask.
      final looksRefused = content.isEmpty ||
          content.length < 40 ||
          RegExp(r"(i\s+can'?t\s+assist|i\s+cannot\s+assist|i'?m\s+sorry,?\s+but)",
              caseSensitive: false).hasMatch(content);

      if (looksRefused) {
        contentBuffer.clear();
        await for (final token in _llmService.chat(
          'Explain "$topic" in detail. Write several clear paragraphs.',
          temperature: 0.7,
          maxTokens: 1024,
        )) {
          contentBuffer.write(token);
        }
        content = contentBuffer.toString().trim();
      }

      if (content.isEmpty || content.length < 40) {
        yield '\n\n❌ Couldn\'t generate enough content for that topic. Try rephrasing, or ask the question first then say "make it a pdf".';
        return;
      }
      yield '\n\n📄 **Creating PDF...**\n';
    }
    
    try {
      final pdfBytes = await _renderContentToPdf(content, topic);
      final filePath = await _saveTempFile(pdfBytes, 'aura_${_sanitizeFileName(topic)}.pdf');
      
      // 3. Share
      final xFile = XFile(filePath, mimeType: 'application/pdf');
      await SharePlus.instance.share(ShareParams(files: [xFile]));
      
      // Cleanup
      try { await File(filePath).delete(); } catch (_) {}
      
      yield '✅ **PDF exported successfully!**';
    } catch (e) {
      yield '\n\n❌ Failed to create PDF: $e';
    }
  }

  /// Generate a code file from a user prompt.
  Stream<String> generateAndExportCode({
    required String description,
    required String language, // "python", "javascript", "dart", "html", etc.
  }) async* {
    if (!_llmService.isModelLoaded) {
      yield '❌ Please load an AI model first.';
      return;
    }

    yield '💻 **Generating $language code...**\n\n';

    final prompt = 'Write complete, working $language code for: $description\n\n'
        'Output ONLY the code with comments. No explanations before or after.';
    
    final contentBuffer = StringBuffer();
    await for (final token in _llmService.chat(
      prompt,
      systemPrompt: 'You are an expert programmer. Write clean, complete, working code with comments. Output only code.',
      temperature: 0.3,
      maxTokens: 1024,
    )) {
      contentBuffer.write(token);
      yield token;
    }

    final code = _extractCode(contentBuffer.toString());
    if (code.isEmpty) {
      yield '\n\n❌ Failed to generate code.';
      return;
    }

    // Save and share
    yield '\n\n💾 **Saving file...**\n';
    
    try {
      final ext = _getFileExtension(language);
      final fileName = 'aura_code_${DateFormat('HHmmss').format(DateTime.now())}.$ext';
      final bytes = Uint8List.fromList(code.codeUnits);
      final filePath = await _saveTempFile(bytes, fileName);
      
      final xFile = XFile(filePath, mimeType: 'text/plain');
      await SharePlus.instance.share(ShareParams(files: [xFile], text: 'Generated $language code by AURA'));
      
      try { await File(filePath).delete(); } catch (_) {}
      
      yield '✅ **Code file exported: $fileName**';
    } catch (e) {
      yield '\n\n❌ Failed to save code: $e';
    }
  }

  /// Generate a CSV/spreadsheet from a user prompt.
  Stream<String> generateAndExportCsv({
    required String description,
  }) async* {
    if (!_llmService.isModelLoaded) {
      yield '❌ Please load an AI model first.';
      return;
    }

    yield '📊 **Generating spreadsheet data...**\n\n';

    final prompt = 'Create CSV data for: $description\n\n'
        'Output ONLY valid CSV format with headers on the first line. '
        'Use commas as separators. No other text.';
    
    final contentBuffer = StringBuffer();
    await for (final token in _llmService.chat(
      prompt,
      systemPrompt: 'Output only valid CSV data. First line is headers. No extra text.',
      temperature: 0.3,
      maxTokens: 512,
    )) {
      contentBuffer.write(token);
      yield token;
    }

    final csv = contentBuffer.toString().trim();
    
    yield '\n\n💾 **Saving CSV...**\n';
    
    try {
      final fileName = 'aura_data_${DateFormat('HHmmss').format(DateTime.now())}.csv';
      final bytes = Uint8List.fromList(csv.codeUnits);
      final filePath = await _saveTempFile(bytes, fileName);
      
      final xFile = XFile(filePath, mimeType: 'text/csv');
      await SharePlus.instance.share(ShareParams(files: [xFile]));
      
      try { await File(filePath).delete(); } catch (_) {}
      
      yield '✅ **CSV exported: $fileName**';
    } catch (e) {
      yield '\n\n❌ Failed to save CSV: $e';
    }
  }

  /// Summarize a previous conversation and export as PDF.
  Stream<String> summarizeAndExportPdf({
    required List<Map<String, String>> messages,
  }) async* {
    if (!_llmService.isModelLoaded) {
      yield '❌ Please load an AI model first.';
      return;
    }

    if (messages.isEmpty) {
      yield '❌ No conversation to summarize.';
      return;
    }

    yield '📝 **Summarizing conversation...**\n\n';

    // Build conversation text
    final convoText = messages.take(20).map((m) {
      final role = m['role'] == 'user' ? 'User' : 'Assistant';
      return '$role: ${m['content'] ?? ''}';
    }).join('\n');

    final prompt = 'Summarize this conversation into a clear, organized document with key points:\n\n$convoText';
    
    final contentBuffer = StringBuffer();
    await for (final token in _llmService.chat(
      prompt,
      systemPrompt: 'Create a structured summary document with clear headings and bullet points. Be concise but complete.',
      temperature: 0.4,
      maxTokens: 512,
    )) {
      contentBuffer.write(token);
      yield token;
    }

    final content = contentBuffer.toString().trim();
    
    yield '\n\n📄 **Creating PDF...**\n';
    
    try {
      final pdfBytes = await _renderContentToPdf(content, 'Conversation Summary');
      final filePath = await _saveTempFile(pdfBytes, 'aura_summary_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf');
      
      final xFile = XFile(filePath, mimeType: 'application/pdf');
      await SharePlus.instance.share(ShareParams(files: [xFile]));
      
      try { await File(filePath).delete(); } catch (_) {}
      
      yield '✅ **Summary PDF exported!**';
    } catch (e) {
      yield '\n\n❌ Failed to create PDF: $e';
    }
  }

  // ─── Private helpers ─────────────────────────────────────────────────────

  String _buildDocPrompt(String topic, String style) {
    switch (style.toLowerCase()) {
      case 'resume':
        return 'Write a professional resume/CV for: $topic\n\nInclude sections: Summary, Experience, Skills, Education.';
      case 'letter':
        return 'Write a formal letter about: $topic\n\nInclude proper letter formatting with date, greeting, body, and closing.';
      case 'notes':
        return 'Write detailed study notes on: $topic\n\nUse clear headings, bullet points, and key definitions.';
      case 'essay':
        return 'Write an essay on: $topic\n\nInclude introduction, body paragraphs with arguments, and conclusion.';
      default: // report
        return 'Write a detailed report on: $topic\n\nInclude: Title, Introduction, Main Content with sections, and Conclusion.';
    }
  }

  Future<Uint8List> _renderContentToPdf(String content, String title) async {
    final pdf = pw.Document();
    
    // Parse content into sections
    final lines = content.split('\n');
    final widgets = <pw.Widget>[];
    
    // Title
    widgets.add(pw.Header(
      level: 0,
      child: pw.Text(title, style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
    ));
    widgets.add(pw.SizedBox(height: 8));
    widgets.add(pw.Text(
      'Generated by AURA AI • ${DateFormat('MMMM d, yyyy').format(DateTime.now())}',
      style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
    ));
    widgets.add(pw.SizedBox(height: 16));
    widgets.add(pw.Divider());
    widgets.add(pw.SizedBox(height: 16));
    
    // Content — parse markdown-like formatting. Every line is passed through
    // _cleanInline first, which (a) strips markdown emphasis correctly, (b)
    // normalizes Unicode punctuation to ASCII, and (c) drops glyphs the base PDF
    // font cannot render (emoji), which previously showed as ▯ boxes.
    for (final rawLine in lines) {
      final line = rawLine;
      if (line.trim().isEmpty) {
        widgets.add(pw.SizedBox(height: 8));
      } else if (line.startsWith('# ')) {
        widgets.add(pw.SizedBox(height: 12));
        widgets.add(pw.Text(_cleanInline(line.substring(2)), style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)));
        widgets.add(pw.SizedBox(height: 6));
      } else if (line.startsWith('## ')) {
        widgets.add(pw.SizedBox(height: 10));
        widgets.add(pw.Text(_cleanInline(line.substring(3)), style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)));
        widgets.add(pw.SizedBox(height: 4));
      } else if (line.startsWith('### ')) {
        widgets.add(pw.SizedBox(height: 8));
        widgets.add(pw.Text(_cleanInline(line.substring(4)), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)));
        widgets.add(pw.SizedBox(height: 4));
      } else if (line.startsWith('- ') || line.startsWith('• ') || line.startsWith('* ')) {
        widgets.add(pw.Padding(
          padding: const pw.EdgeInsets.only(left: 16),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('• ', style: const pw.TextStyle(fontSize: 11)),
              pw.Expanded(child: pw.Text(_cleanInline(line.substring(2)), style: const pw.TextStyle(fontSize: 11))),
            ],
          ),
        ));
      } else if (RegExp(r'^\d+\.\s').hasMatch(line)) {
        widgets.add(pw.Padding(
          padding: const pw.EdgeInsets.only(left: 16),
          child: pw.Text(_cleanInline(line), style: const pw.TextStyle(fontSize: 11)),
        ));
      } else {
        widgets.add(pw.Text(_cleanInline(line), style: const pw.TextStyle(fontSize: 11)));
      }
    }

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (context) => widgets,
    ));

    return await pdf.save();
  }

  /// Cleans a single line of markdown/rich text for rendering with the base
  /// PDF font (Latin-1 only). This (a) strips markdown emphasis correctly using
  /// backreference expansion (Dart's replaceAll does NOT expand `$1`, so we use
  /// replaceAllMapped), (b) normalizes common Unicode punctuation to ASCII, and
  /// (c) drops any remaining non-Latin-1 glyphs (emoji, CJK) that would render
  /// as ▯ boxes.
  String _cleanInline(String input) {
    var s = input;

    // Strip markdown emphasis, keeping the inner text.
    s = s.replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => m.group(1)!); // bold
    s = s.replaceAllMapped(RegExp(r'__(.+?)__'), (m) => m.group(1)!); // bold alt
    s = s.replaceAllMapped(RegExp(r'\*(.+?)\*'), (m) => m.group(1)!); // italic
    s = s.replaceAllMapped(RegExp(r'_(.+?)_'), (m) => m.group(1)!); // italic alt
    s = s.replaceAllMapped(RegExp(r'`(.+?)`'), (m) => m.group(1)!); // inline code
    // Markdown links [text](url) -> text
    s = s.replaceAllMapped(RegExp(r'\[(.+?)\]\((.+?)\)'), (m) => m.group(1)!);

    // Line breaks embedded as HTML.
    s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ');

    // Normalize common Unicode punctuation to ASCII.
    s = s
        .replaceAll('\u2014', '-') // em dash
        .replaceAll('\u2013', '-') // en dash
        .replaceAll('\u2192', '->') // right arrow
        .replaceAll('\u2022', '- ') // bullet
        .replaceAll('\u2026', '...') // ellipsis
        .replaceAll('\u2018', "'") // left single quote
        .replaceAll('\u2019', "'") // right single quote
        .replaceAll('\u201C', '"') // left double quote
        .replaceAll('\u201D', '"') // right double quote
        .replaceAll('\u00A0', ' '); // non-breaking space

    // Drop anything the base PDF font cannot render (keeps Latin-1 only).
    s = s.replaceAll(RegExp(r'[^\x00-\xFF]'), '');

    return s;
  }

  String _extractCode(String text) {
    // Extract code from markdown code blocks if present
    final codeBlockMatch = RegExp(r'```\w*\n([\s\S]*?)```').firstMatch(text);
    if (codeBlockMatch != null) {
      return codeBlockMatch.group(1)!.trim();
    }
    return text.trim();
  }

  String _getFileExtension(String language) {
    switch (language.toLowerCase()) {
      case 'python': return 'py';
      case 'javascript': case 'js': return 'js';
      case 'typescript': case 'ts': return 'ts';
      case 'dart': return 'dart';
      case 'java': return 'java';
      case 'kotlin': case 'kt': return 'kt';
      case 'swift': return 'swift';
      case 'c': return 'c';
      case 'cpp': case 'c++': return 'cpp';
      case 'html': return 'html';
      case 'css': return 'css';
      case 'sql': return 'sql';
      case 'rust': return 'rs';
      case 'go': return 'go';
      case 'ruby': return 'rb';
      case 'php': return 'php';
      default: return 'txt';
    }
  }

  String _sanitizeFileName(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  Future<String> _saveTempFile(Uint8List bytes, String fileName) async {
    final tempDir = await getTemporaryDirectory();
    final filePath = '${tempDir.path}/$fileName';
    final file = File(filePath);
    await file.writeAsBytes(bytes);
    return filePath;
  }
}
