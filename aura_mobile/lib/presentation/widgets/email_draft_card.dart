import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Extracted email draft card widget — keeps heavy UI logic out of the chat list builder.
class EmailDraftCard extends StatefulWidget {
  final String address;
  final String? subject;
  final String? body;

  const EmailDraftCard({
    super.key,
    required this.address,
    this.subject,
    this.body,
  });

  @override
  State<EmailDraftCard> createState() => _EmailDraftCardState();
}

class _EmailDraftCardState extends State<EmailDraftCard> {
  bool _isEditing = false;
  late TextEditingController _editController;

  @override
  void initState() {
    super.initState();
    _editController = TextEditingController(text: widget.body ?? '');
  }

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 4, left: 16, right: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1a1a22), Color(0xFF141418)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFc69c3a).withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFc69c3a).withOpacity(0.12),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                const Icon(Icons.email_outlined, color: Color(0xFFc69c3a), size: 18),
                const SizedBox(width: 8),
                Text(
                  'Email Draft',
                  style: GoogleFonts.outfit(
                    color: const Color(0xFFc69c3a),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          // Fields
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _EmailField(label: 'To', value: widget.address),
                const SizedBox(height: 8),
                _EmailField(label: 'Subject', value: widget.subject ?? ''),
                const SizedBox(height: 8),
                Text(
                  'Body',
                  style: GoogleFonts.outfit(
                    color: Colors.white38,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                _isEditing
                    ? TextField(
                        controller: _editController,
                        maxLines: null,
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 14, height: 1.6),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFF2a2a35),
                          contentPadding: const EdgeInsets.all(12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFFc69c3a), width: 1),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFFc69c3a), width: 1.5),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
                          ),
                        ),
                      )
                    : Text(
                        widget.body ?? '',
                        style: GoogleFonts.outfit(color: Colors.white70, fontSize: 14, height: 1.6),
                      ),
              ],
            ),
          ),
          // Action Buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                // Edit / Done Editing button
                Expanded(
                  child: OutlinedButton.icon(
                    icon: Icon(
                      _isEditing ? Icons.check_circle_outline : Icons.edit_outlined,
                      size: 16,
                      color: Colors.white70,
                    ),
                    label: Text(
                      _isEditing ? 'Done Editing' : 'Edit Email',
                      style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.white.withOpacity(0.2)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: () {
                      setState(() => _isEditing = !_isEditing);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                // Send Email button
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.send, size: 16, color: Colors.black),
                    label: Text(
                      'Send Email',
                      style: GoogleFonts.outfit(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFc69c3a),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: () async {
                      final finalBody = (_isEditing
                              ? _editController.text
                              : widget.body ?? '')
                          .replaceAll('[Your Name]', 'Aura User');
                      try {
                        const channel = MethodChannel('com.aura.ai/app_control');
                        await channel.invokeMethod('launchEmailApp', {
                          'address': widget.address,
                          'subject': widget.subject ?? '',
                          'body': finalBody,
                        });
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Could not launch email client: $e')),
                          );
                        }
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmailField extends StatelessWidget {
  final String label;
  final String value;

  const _EmailField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.outfit(
            color: Colors.white38,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(value, style: GoogleFonts.outfit(color: Colors.white, fontSize: 14)),
      ],
    );
  }
}
