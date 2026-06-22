import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aura_mobile/features/export/application/chat_export_service.dart';
import 'package:aura_mobile/presentation/providers/chat_provider.dart';
import 'package:aura_mobile/presentation/widgets/clay_components.dart';

class ExportBottomSheet extends ConsumerStatefulWidget {
  const ExportBottomSheet({super.key});

  @override
  ConsumerState<ExportBottomSheet> createState() => _ExportBottomSheetState();
}

class _ExportBottomSheetState extends ConsumerState<ExportBottomSheet> {
  bool _isExporting = false;

  Future<void> _exportMarkdown() async {
    setState(() => _isExporting = true);

    final messages = ref.read(chatProvider).messages;
    final exportService = ref.read(chatExportServiceProvider);
    final result = await exportService.exportAsMarkdown(messages, context);

    setState(() => _isExporting = false);

    if (mounted) {
      Navigator.pop(context);
      _showResultSnackbar(result);
    }
  }

  Future<void> _exportPdf() async {
    setState(() => _isExporting = true);

    final messages = ref.read(chatProvider).messages;
    final exportService = ref.read(chatExportServiceProvider);
    final result = await exportService.exportAsPdf(messages, context);

    setState(() => _isExporting = false);

    if (mounted) {
      Navigator.pop(context);
      _showResultSnackbar(result);
    }
  }

  void _showResultSnackbar(ExportResult result) {
    final String message;
    switch (result) {
      case ExportResult.empty:
        message = 'Nothing to export — start a conversation first';
        break;
      case ExportResult.error:
        message = 'Export failed. Please try again.';
        break;
      case ExportResult.timeout:
        message = 'PDF generation timed out. Try exporting a shorter conversation.';
        break;
      case ExportResult.insufficientStorage:
        message = 'Not enough storage space for export.';
        break;
      case ExportResult.success:
        message = 'Exported successfully!';
        break;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Text(
              'Export Conversation',
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: ClayColors.textDark,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Loading indicator
          if (_isExporting)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24.0),
              child: Center(
                child: CircularProgressIndicator(color: ClayColors.goldAccent),
              ),
            )
          else ...[
            // Export as Markdown
            ListTile(
              leading: const Icon(Icons.description_outlined, color: ClayColors.goldAccent),
              title: Text(
                'Export as Markdown',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w600,
                  color: ClayColors.textDark,
                ),
              ),
              subtitle: Text(
                'Plain text format, easy to share and edit',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: ClayColors.textMuted,
                ),
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onTap: _exportMarkdown,
            ),
            const Divider(height: 1),

            // Export as PDF
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined, color: ClayColors.goldAccent),
              title: Text(
                'Export as PDF',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w600,
                  color: ClayColors.textDark,
                ),
              ),
              subtitle: Text(
                'Formatted document, great for printing or archiving',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: ClayColors.textMuted,
                ),
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onTap: _exportPdf,
            ),
          ],
        ],
      ),
    );
  }
}

/// Helper function to show the export bottom sheet from anywhere.
void showExportBottomSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    builder: (_) => const ExportBottomSheet(),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    backgroundColor: const Color(0xFFF7F4EF),
  );
}
