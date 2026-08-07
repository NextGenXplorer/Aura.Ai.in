import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aura_mobile/features/screen_reader/screen_context_service.dart';
import 'package:aura_mobile/core/providers/ai_providers.dart';

/// Bottom sheet UI for Screen Reader AI.
/// Captures what's on the user's screen and lets AI analyze it.
class ScreenReaderSheet extends ConsumerStatefulWidget {
  const ScreenReaderSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF7F4EF),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: const ScreenReaderSheet(),
        ),
      ),
    );
  }

  @override
  ConsumerState<ScreenReaderSheet> createState() => _ScreenReaderSheetState();
}

class _ScreenReaderSheetState extends ConsumerState<ScreenReaderSheet> {
  ScreenContext? _screenContext;
  String _aiResult = '';
  bool _isCapturing = false;
  bool _isAnalyzing = false;
  bool _serviceEnabled = false;

  @override
  void initState() {
    super.initState();
    _checkService();
  }

  Future<void> _checkService() async {
    final enabled = await ScreenContextService.checkServiceStatus();
    if (mounted) {
      setState(() => _serviceEnabled = enabled);
      if (enabled) {
        _captureScreen();
      }
    }
  }

  Future<void> _captureScreen() async {
    setState(() => _isCapturing = true);
    try {
      final context = await ScreenContextService.captureCurrentScreen();
      if (mounted) {
        setState(() {
          _screenContext = context;
          _isCapturing = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Title
          Row(
            children: [
              const Icon(Icons.visibility_rounded, color: Color(0xFFB3862B)),
              const SizedBox(width: 8),
              Text(
                'Screen Reader AI',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (!_serviceEnabled) ...[
            // Service not enabled — show setup instructions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '⚠️ Accessibility Service Required',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'To read what\'s on your screen, AURA needs accessibility permission. '
                    'This allows AURA to see text in other apps and help you with it.',
                    style: GoogleFonts.outfit(fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => ScreenContextService.openAccessibilitySettings(),
                      icon: const Icon(Icons.settings, size: 18),
                      label: const Text('Open Accessibility Settings'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFB3862B),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Find "AURA Screen Reader" and enable it.',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: TextButton.icon(
                onPressed: _checkService,
                icon: const Icon(Icons.refresh),
                label: const Text('Check Again'),
              ),
            ),
          ] else ...[
            // Service enabled — show screen content
            if (_isCapturing)
              const Center(child: CircularProgressIndicator(color: Color(0xFFB3862B)))
            else if (_screenContext == null || !_screenContext!.hasContent)
              Center(
                child: Column(
                  children: [
                    const Icon(Icons.screen_search_desktop_rounded,
                        size: 48, color: Colors.grey),
                    const SizedBox(height: 12),
                    Text(
                      'No readable text found on screen',
                      style: GoogleFonts.outfit(color: Colors.grey[500]),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _captureScreen,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Capture Again'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFB3862B),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              // Screen content preview
              Container(
                padding: const EdgeInsets.all(12),
                constraints: const BoxConstraints(maxHeight: 120),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFECE6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '📱 ${_screenContext!.appName}',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: const Color(0xFFB3862B),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _screenContext!.preview,
                        style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF4A4A4A)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Action buttons
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _actionChip('Summarize', Icons.auto_awesome, () => _analyze('Summarize this screen content concisely')),
                    const SizedBox(width: 8),
                    _actionChip('Explain', Icons.lightbulb_outline, () => _analyze('Explain what this screen is showing in simple terms')),
                    const SizedBox(width: 8),
                    _actionChip('Translate', Icons.translate, () => _analyze('Translate this text to English')),
                    const SizedBox(width: 8),
                    _actionChip('Extract Data', Icons.data_object, () => _analyze('Extract key information, numbers, names, and dates from this text')),
                    const SizedBox(width: 8),
                    _actionChip('Reply', Icons.reply, () => _analyze('Write a reply to the message shown on screen')),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // AI result
              Expanded(
                child: _isAnalyzing
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: Color(0xFFB3862B)),
                            SizedBox(height: 12),
                            Text('Analyzing screen...'),
                          ],
                        ),
                      )
                    : _aiResult.isEmpty
                        ? Center(
                            child: Text(
                              'Tap an action to analyze screen content',
                              style: GoogleFonts.outfit(color: Colors.grey[400]),
                            ),
                          )
                        : SingleChildScrollView(
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFB3862B).withOpacity(0.3)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SelectableText(
                                    _aiResult,
                                    style: GoogleFonts.outfit(
                                      fontSize: 14,
                                      height: 1.5,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      TextButton.icon(
                                        onPressed: () {
                                          Clipboard.setData(ClipboardData(text: _aiResult));
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Copied!')),
                                          );
                                        },
                                        icon: const Icon(Icons.copy, size: 16),
                                        label: const Text('Copy', style: TextStyle(fontSize: 12)),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _actionChip(String label, IconData icon, VoidCallback onTap) {
    return ActionChip(
      avatar: Icon(icon, size: 14, color: const Color(0xFFB3862B)),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      onPressed: _isAnalyzing ? null : onTap,
      backgroundColor: const Color(0xFFEFECE6),
    );
  }

  Future<void> _analyze(String instruction) async {
    if (_screenContext == null || !_screenContext!.hasContent) return;

    setState(() {
      _isAnalyzing = true;
      _aiResult = '';
    });

    try {
      final llm = ref.read(llmServiceProvider);
      if (!llm.isModelLoaded) {
        setState(() {
          _aiResult = '⚠️ No AI model loaded. Please load a model first.';
          _isAnalyzing = false;
        });
        return;
      }

      // Truncate screen text to avoid exceeding context window
      final screenText = _screenContext!.screenText.length > 2000
          ? _screenContext!.screenText.substring(0, 2000)
          : _screenContext!.screenText;

      final prompt = '$instruction:\n\nApp: ${_screenContext!.appName}\n\nScreen Content:\n$screenText';

      final buffer = StringBuffer();
      await for (final chunk in llm.chat(prompt, maxTokens: 512, temperature: 0.3)) {
        buffer.write(chunk);
        setState(() => _aiResult = buffer.toString());
      }
    } catch (e) {
      setState(() => _aiResult = '❌ Error: $e');
    } finally {
      setState(() => _isAnalyzing = false);
    }
  }
}
