import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:aura_mobile/presentation/widgets/code_element_builder.dart';
import 'package:aura_mobile/presentation/widgets/clay_components.dart';

/// Extracted user message bubble — const-constructable, avoids full list rebuild.
class UserMessageBubble extends StatelessWidget {
  final String content;

  const UserMessageBubble({super.key, required this.content});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
          child: ClayContainer(
            borderRadius: 22,
            depth: 5.0,
            baseColor: const Color(0xFFEBE8E0), // Soft warm cream/grey
            highlightColor: const Color(0xFFFFFFFF),
            shadowColor: const Color(0xFFD6CDBB),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            border: Border.all(
              color: ClayColors.goldAccent.withOpacity(0.18),
              width: 1.0,
            ),
            child: MarkdownBody(
              data: content,
              styleSheet: MarkdownStyleSheet(
                p: TextStyle(
                  color: ClayColors.textDark,
                  fontSize: 15,
                  height: 1.5,
                  fontFamily: GoogleFonts.outfit().fontFamily,
                ),
                strong: const TextStyle(color: ClayColors.textDark, fontWeight: FontWeight.bold),
                a: const TextStyle(color: ClayColors.goldAccent, decoration: TextDecoration.underline),
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
                  color: ClayColors.textDark,
                  fontSize: 15,
                  height: 1.5,
                  fontFamily: GoogleFonts.outfit().fontFamily,
                ),
                strong: const TextStyle(color: ClayColors.textDark, fontWeight: FontWeight.bold),
                a: const TextStyle(color: ClayColors.goldAccent, decoration: TextDecoration.underline),
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
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8, top: 12),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: options.map((opt) {
                return ClayButton(
                  onTap: () => onOptionSelected(opt['value']!),
                  borderRadius: 14,
                  depth: 4,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  baseColor: ClayColors.warmGrey,
                  highlightColor: ClayColors.highlight,
                  shadowColor: ClayColors.shadow,
                  child: Text(
                    opt['label']!,
                    style: GoogleFonts.outfit(
                      color: ClayColors.textDark, 
                      fontSize: 13, 
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        if (emailDraftCard != null) emailDraftCard!,
      ],
    );
  }
}
