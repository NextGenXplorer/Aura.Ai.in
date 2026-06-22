import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aura_mobile/presentation/providers/clipboard_bubble_provider.dart';
import 'package:aura_mobile/core/services/clipboard_ai_service.dart';

// ---------------------------------------------------------------------------
// Theme constants
// ---------------------------------------------------------------------------

const _kPrimaryGold = Color(0xFFB3862B);
const _kSurface = Color(0xFFEFECE6);
const _kBackground = Color(0xFFF7F4EF);
const _kTextInk = Color(0xFF191816);

// ---------------------------------------------------------------------------
// ClipboardBubbleOverlay
// ---------------------------------------------------------------------------

class ClipboardBubbleOverlay extends ConsumerStatefulWidget {
  final Widget child;

  const ClipboardBubbleOverlay({super.key, required this.child});

  @override
  ConsumerState<ClipboardBubbleOverlay> createState() =>
      _ClipboardBubbleOverlayState();
}

class _ClipboardBubbleOverlayState
    extends ConsumerState<ClipboardBubbleOverlay> {
  double _opacity = 0.0;
  Timer? _errorDismissTimer;

  @override
  void dispose() {
    _errorDismissTimer?.cancel();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  IconData _iconForType(ClipboardContentType type) {
    switch (type) {
      case ClipboardContentType.url:
        return Icons.link_rounded;
      case ClipboardContentType.phone:
        return Icons.phone_rounded;
      case ClipboardContentType.email:
        return Icons.email_rounded;
      case ClipboardContentType.code:
        return Icons.code_rounded;
      case ClipboardContentType.address:
        return Icons.location_on_rounded;
      case ClipboardContentType.text:
        return Icons.text_fields_rounded;
    }
  }

  String _labelForType(ClipboardContentType type) {
    switch (type) {
      case ClipboardContentType.url:
        return 'URL';
      case ClipboardContentType.phone:
        return 'Phone';
      case ClipboardContentType.email:
        return 'Email';
      case ClipboardContentType.code:
        return 'Code';
      case ClipboardContentType.address:
        return 'Address';
      case ClipboardContentType.text:
        return 'Text';
    }
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(clipboardBubbleProvider);
    final isVisible = state.status != ClipboardBubbleStatus.hidden;

    // Drive opacity based on visibility
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = isVisible ? 1.0 : 0.0;
      if (_opacity != target) {
        setState(() => _opacity = target);
      }
    });

    // Auto-dismiss on error after 2 seconds
    if (state.status == ClipboardBubbleStatus.error) {
      _errorDismissTimer?.cancel();
      _errorDismissTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) {
          ref.read(clipboardBubbleProvider.notifier).dismiss();
        }
      });
    }

    return Stack(
      children: [
        widget.child,

        // Tap-outside-to-dismiss layer
        if (isVisible)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () =>
                  ref.read(clipboardBubbleProvider.notifier).dismiss(),
              child: const SizedBox.expand(),
            ),
          ),

        // The floating bubble
        Positioned(
          bottom: 80,
          left: 20,
          right: 20,
          child: IgnorePointer(
            ignoring: !isVisible,
            child: AnimatedOpacity(
              opacity: _opacity,
              duration: Duration(milliseconds: _opacity == 1.0 ? 200 : 400),
              child: AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                alignment: Alignment.bottomCenter,
                child: isVisible
                    ? _buildBubble(state)
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBubble(ClipboardBubbleData state) {
    return GestureDetector(
      // Swipe down to dismiss
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) > 100) {
          ref.read(clipboardBubbleProvider.notifier).dismiss();
        }
      },
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: _kBackground,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: _kPrimaryGold.withOpacity(0.08),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Content type badge + preview
              if (state.event != null) ...[
                _buildTypeBadge(state.event!.type),
                const SizedBox(height: 8),
                _buildPreview(state.event!.text),
              ],

              // Error state
              if (state.status == ClipboardBubbleStatus.error) ...[
                const SizedBox(height: 12),
                _buildError(state.errorMessage ?? 'Something went wrong'),
              ],

              // Action buttons (showing state)
              if (state.status == ClipboardBubbleStatus.showing &&
                  state.actions.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildActions(state.actions),
              ],

              // Streaming / completed response area
              if (state.status == ClipboardBubbleStatus.streaming ||
                  state.status == ClipboardBubbleStatus.completed) ...[
                const SizedBox(height: 12),
                _buildResponseArea(state),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Sub-widgets
  // -------------------------------------------------------------------------

  Widget _buildTypeBadge(ClipboardContentType type) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _kPrimaryGold.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _iconForType(type),
            size: 14,
            color: _kPrimaryGold,
          ),
          const SizedBox(width: 5),
          Text(
            _labelForType(type),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _kPrimaryGold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(String text) {
    return Text(
      ClipboardBubbleNotifier.truncatePreview(text),
      style: TextStyle(
        fontSize: 13,
        color: _kTextInk.withOpacity(0.6),
        height: 1.4,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildActions(List<ClipboardAction> actions) {
    final notifier = ref.read(clipboardBubbleProvider.notifier);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: actions.take(4).map((action) {
        return GestureDetector(
          onTap: () => notifier.executeAction(action.actionId),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _kSurface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _kPrimaryGold.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Text(
              action.label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: _kTextInk,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildResponseArea(ClipboardBubbleData state) {
    final isStreaming = state.status == ClipboardBubbleStatus.streaming;
    final notifier = ref.read(clipboardBubbleProvider.notifier);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Loading indicator while streaming
        if (isStreaming)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _kPrimaryGold,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Generating...',
                  style: TextStyle(
                    fontSize: 12,
                    color: _kTextInk.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),

        // Scrollable response text
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 160),
          child: SingleChildScrollView(
            reverse: true,
            child: Text(
              state.responseText,
              style: const TextStyle(
                fontSize: 14,
                color: _kTextInk,
                height: 1.5,
              ),
            ),
          ),
        ),

        // Copy result button (completed state)
        if (!isStreaming && state.responseText.isNotEmpty) ...[
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => notifier.copyResult(),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _kPrimaryGold,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.copy_rounded, size: 14, color: Colors.white),
                  SizedBox(width: 6),
                  Text(
                    'Copy Result',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildError(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, size: 16, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 13, color: Colors.red),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
