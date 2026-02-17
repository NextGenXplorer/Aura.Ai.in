import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:google_fonts/google_fonts.dart';

// Helper class for code blocks
class CodeElementBuilder extends MarkdownElementBuilder {
  final BuildContext context;

  CodeElementBuilder(this.context);

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    if (element.tag != 'code') return null;

    // 1. Extract Code Content
    String textContent = element.textContent;
    if (textContent.endsWith('\n')) {
      textContent = textContent.substring(0, textContent.length - 1);
    }
    
    // 2. Determine Language (if provided in fence)
    String language = 'plaintext';
    final String? className = element.attributes['class'];
    if (className != null && className.startsWith('language-')) {
       language = className.substring(9); // Remove 'language-' prefix
    }

    // 3. Render Custom UI
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1e1e1e), // Dark Editor Background
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A. Header (Language + Copy)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF2d2d2d), // Slightly lighter header
              borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                 // Language Label
                 Text(
                   language.toUpperCase(),
                   style: GoogleFonts.outfit(
                     color: Colors.white70,
                     fontSize: 12,
                     fontWeight: FontWeight.bold,
                   ),
                 ),
                 // Copy Button
                 GestureDetector(
                   onTap: () async {
                      await Clipboard.setData(ClipboardData(text: textContent));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text("Code copied!", style: GoogleFonts.outfit()),
                            duration: const Duration(seconds: 1),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: const Color(0xFFc69c3a),
                          ),
                        );
                      }
                   },
                   child: Row(
                     children: [
                       const Icon(Icons.copy, size: 14, color: Colors.white70),
                       const SizedBox(width: 4),
                       Text(
                         "Copy code",
                         style: GoogleFonts.outfit(
                           color: Colors.white70,
                           fontSize: 12,
                         ),
                       ),
                     ],
                   ),
                 ),
              ],
            ),
          ),
          
          // B. Code Body (Plain Text for now)
          Container(
             width: double.infinity, 
             padding: const EdgeInsets.all(12),
             child: SingleChildScrollView(
               scrollDirection: Axis.horizontal,
               child: Text(
                 textContent,
                 style: GoogleFonts.firaCode(
                    fontSize: 14,
                    color: Colors.white, // Ensure visibility
                 ), 
               ),
             ),
          ),
        ],
      ),
    );
  }
}
