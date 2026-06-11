import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:aura_mobile/presentation/widgets/code_element_builder.dart';

/// Extracted user message bubble — const-constructable, avoids full list rebuild.
class UserMessageBubble extends StatelessWidget {
  final String content;

  const UserMessageBubble({super.key, required this.content});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        decoration: BoxDecoration(
          color: const Color(0xFF2a2a30),
          borderRadius: BorderRadius.circular(20).copyWith(bottomRight: Radius.zero),
          border: Border.all(color: const Color(0xFFc69c3a).withOpacity(0.3)),
        ),
        child: MarkdownBody(
          data: content,
          styleSheet: MarkdownStyleSheet(
            p: TextStyle(
              color: Colors.white,
              fontSize: 16,
              height: 1.5,
              fontFamily: GoogleFonts.outfit().fontFamily,
            ),
            strong: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            a: const TextStyle(color: Color(0xFFc69c3a), decoration: TextDecoration.underline),
            code: const TextStyle(
              color: Color(0xFFe6cf8e),
              backgroundColor: Color(0xFF1a1a20),
              fontFamily: 'monospace',
              fontSize: 14,
            ),
          ),
          selectable: true,
        ),
      ),
    );
  }
}

/// Extracted AI message bubble — handles markdown, links, options, email drafts.
class AssistantMessageBubble extends StatelessWidget {
  final String content;
  final List<Map<String, String>> options;
  final ValueChanged<String> onOptionSelected;
  final Widget? emailDraftCard;

  const AssistantMessageBubble({
    super.key,
    required this.content,
    this.options = const [],
    required this.onOptionSelected,
    this.emailDraftCard,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (content.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: MarkdownBody(
              data: content,
              builders: {'code': CodeElementBuilder(context)},
              styleSheet: MarkdownStyleSheet(
                p: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 16,
                  height: 1.5,
                  fontFamily: GoogleFonts.outfit().fontFamily,
                ),
                strong: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                a: const TextStyle(color: Color(0xFFc69c3a), decoration: TextDecoration.underline),
                code: const TextStyle(
                  color: Color(0xFFe6cf8e),
                  backgroundColor: Color(0xFF1a1a20),
                  fontFamily: 'monospace',
                  fontSize: 14,
                ),
              ),
              onTapLink: (text, href, title) async {
                if (href != null) {
                  final Uri url = Uri.parse(href);
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  } else {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Could not launch $href')),
                      );
                    }
                  }
                }
              },
              selectable: true,
            ),
          ),
        if (options.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: options.map((opt) {
                return ActionChip(
                  label: Text(opt['label']!, style: GoogleFonts.outfit(color: Colors.white)),
                  backgroundColor: const Color(0xFF2a2a30),
                  side: const BorderSide(color: Color(0xFFc69c3a)),
                  onPressed: () => onOptionSelected(opt['value']!),
                );
              }).toList(),
            ),
          ),
        if (emailDraftCard != null) emailDraftCard!,
      ],
    );
  }
}
