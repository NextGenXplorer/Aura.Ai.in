import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:aura_mobile/presentation/widgets/clay_components.dart';
import 'package:aura_mobile/presentation/widgets/markdown_message.dart';

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
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.8,
          ),
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
            child: MarkdownMessage(
              data: content,
              // The user's own message never needs runnable code cards.
              useCodeBuilder: false,
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

  /// Turned off while the reply is still streaming — selectable text rebuilds
  /// its gesture recognisers and selection overlay with every text change.
  final bool selectable;

  const AssistantMessageBubble({
    super.key,
    required this.content,
    this.options = const [],
    required this.onOptionSelected,
    this.emailDraftCard,
    this.selectable = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (content.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: MarkdownMessage(
              data: content,
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
              selectable: selectable,
            ),
          ),
        if (options.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: 8,
              top: 12,
            ),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: options.map((opt) {
                return ClayButton(
                  onTap: () => onOptionSelected(opt['value']!),
                  borderRadius: 14,
                  depth: 4,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
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
