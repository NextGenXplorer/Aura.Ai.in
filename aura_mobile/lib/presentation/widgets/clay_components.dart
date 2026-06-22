import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A premium color palette with warm-paper cream and ink tones,
/// matching the luxurious Claude-like light mode aesthetic.
class ClayColors {
  static const Color obsidianBg = Color(0xFFF7F4EF); // Light warm paper background
  static const Color warmGrey = Color(0xFFEFECE6); // Light warm clay base fill
  static const Color highlight = Color(0xFFFFFFFF); // Light top-left highlight
  static const Color shadow = Color(0xFFD6CDBB); // Light bottom-right shadow

  // Text Colors (Premium Claude Ink palette)
  static const Color textDark = Color(0xFF191816); // Deep warm ink text
  static const Color textMuted = Color(0xFF5A554E); // Soft charcoal text
  static const Color textHint = Color(0xFF8C8476); // Warm grey text

  // Premium Terracotta/Copper Accents (replaces gold for a luxurious, Claude-like aesthetic)
  static const Color goldAccent = Color(0xFFBC4B2E); // Deep premium terracotta
  static const Color goldHighlight = Color(0xFFFFF0EC); // Soft rose-terracotta tint
  static const Color goldShadow = Color(0xFFEAD5D0); // Warm sepia-clay shadow
  
  // Status Colors (adapted for light mode readability)
  static const Color greenAccent = Color(0xFF2E7D32);
  static const Color greenHighlight = Color(0xFFE8F5E9);
  static const Color greenShadow = Color(0xFFC8E6C9);

  static const Color redAccent = Color(0xFFC62828);
  static const Color redHighlight = Color(0xFFFFEBEE);
  static const Color redShadow = Color(0xFFFFCDD2);

  static const Color blueAccent = Color(0xFF1565C0);
  static const Color blueHighlight = Color(0xFFE3F2FD);
  static const Color blueShadow = Color(0xFFBBDEFB);

  static const Color orangeAccent = Color(0xFFD84315);
  static const Color orangeHighlight = Color(0xFFFBE9E7);
  static const Color orangeShadow = Color(0xFFFFCCBC);
}

/// A custom container that creates a beautiful, tactile 3D claymorphic card
/// using outer shadows, opposite highlights, and a diagonal light-to-dark gradient.
class ClayContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final Color baseColor;
  final Color highlightColor;
  final Color shadowColor;
  final double depth;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Border? border;
  final bool isInset;
  final double? width;
  final double? height;

  const ClayContainer({
    super.key,
    required this.child,
    this.borderRadius = 24.0,
    this.baseColor = ClayColors.warmGrey,
    this.highlightColor = ClayColors.highlight,
    this.shadowColor = ClayColors.shadow,
    this.depth = 8.0,
    this.padding,
    this.margin,
    this.border,
    this.isInset = false,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    // Inset claymorphism reverses the highlights and shadows to look concave (carved in)
    final gradient = isInset
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              shadowColor,
              baseColor,
              highlightColor.withOpacity(0.4),
            ],
            stops: const [0.0, 0.4, 1.0],
          )
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              highlightColor,
              baseColor,
              shadowColor,
            ],
            stops: const [0.0, 0.3, 1.0],
          );

    final List<BoxShadow> shadows = isInset
        ? [
            // Concave/inset shadow effect
            BoxShadow(
              color: shadowColor.withOpacity(0.6),
              offset: Offset(depth / 2, depth / 2),
              blurRadius: depth,
              spreadRadius: -1,
            ),
            BoxShadow(
              color: highlightColor.withOpacity(0.3),
              offset: Offset(-depth / 2, -depth / 2),
              blurRadius: depth,
              spreadRadius: -1,
            ),
          ]
        : [
            // Pillowy outer dark shadow
            BoxShadow(
              color: shadowColor.withOpacity(0.4), // Softer shadow for light mode
              offset: Offset(depth, depth),
              blurRadius: depth * 2.5,
              spreadRadius: 1,
            ),
            // Tactile light glow on the top-left
            BoxShadow(
              color: highlightColor.withOpacity(0.9),
              offset: Offset(-depth * 0.7, -depth * 0.7),
              blurRadius: depth * 2.0,
              spreadRadius: -1,
            ),
          ];

    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: shadows,
        border: border ??
            Border.all(
              color: Colors.black.withOpacity(0.03),
              width: 1.0,
            ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: padding != null
            ? Padding(
                padding: padding!,
                child: child,
              )
            : child,
      ),
    );
  }
}

/// A tactile claymorphic button that shrinks slightly and shifts its shadow
/// on press to give a highly satisfying, responsive feedback loop.
class ClayButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double borderRadius;
  final Color baseColor;
  final Color highlightColor;
  final Color shadowColor;
  final double depth;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;

  const ClayButton({
    super.key,
    required this.child,
    required this.onTap,
    this.borderRadius = 20.0,
    this.baseColor = ClayColors.goldAccent,
    this.highlightColor = ClayColors.goldHighlight,
    this.shadowColor = ClayColors.goldShadow,
    this.depth = 6.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
    this.margin,
    this.width,
    this.height,
  });

  @override
  State<ClayButton> createState() => _ClayButtonState();
}

class _ClayButtonState extends State<ClayButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    if (widget.onTap != null) {
      _controller.forward();
      setState(() => _isPressed = true);
    }
  }

  void _onTapUp(TapUpDetails details) {
    if (widget.onTap != null) {
      _controller.reverse();
      setState(() => _isPressed = false);
      widget.onTap!();
    }
  }

  void _onTapCancel() {
    if (widget.onTap != null) {
      _controller.reverse();
      setState(() => _isPressed = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;

    final base = enabled ? widget.baseColor : const Color(0xFFE8E5DF);
    final highlight = enabled ? widget.highlightColor : const Color(0xFFF7F5F0);
    final shadow = enabled ? widget.shadowColor : const Color(0xFFD6D2C9);

    final Color textColor = widget.baseColor == ClayColors.goldAccent || 
                            widget.baseColor == ClayColors.greenAccent ||
                            widget.baseColor == ClayColors.redAccent ||
                            widget.baseColor == ClayColors.blueAccent ||
                            widget.baseColor == ClayColors.orangeAccent
        ? Colors.white
        : ClayColors.textDark;

    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: ClayContainer(
          width: widget.width,
          height: widget.height,
          margin: widget.margin,
          padding: widget.padding,
          borderRadius: widget.borderRadius,
          baseColor: base,
          highlightColor: highlight,
          shadowColor: shadow,
          depth: _isPressed ? widget.depth * 0.4 : widget.depth,
          child: DefaultTextStyle(
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// An inset-styled claymorphic input text field. It looks carved into the UI.
class ClayTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String hintText;
  final IconData? prefixIcon;
  final bool obscureText;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final TextInputType keyboardType;
  final bool enabled;

  const ClayTextField({
    super.key,
    this.controller,
    required this.hintText,
    this.prefixIcon,
    this.obscureText = false,
    this.maxLines = 1,
    this.onChanged,
    this.keyboardType = TextInputType.text,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return ClayContainer(
      borderRadius: 16.0,
      isInset: true,
      depth: 4.0,
      baseColor: const Color(0xFFE5E2DA),
      highlightColor: const Color(0xFFF7F4EF),
      shadowColor: const Color(0xFFCBC7BE),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          if (prefixIcon != null) ...[
            Icon(prefixIcon, color: ClayColors.goldAccent.withOpacity(0.8), size: 20),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscureText,
              maxLines: maxLines,
              onChanged: onChanged,
              keyboardType: keyboardType,
              enabled: enabled,
              style: GoogleFonts.outfit(color: ClayColors.textDark, fontSize: 15, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: hintText,
                hintStyle: GoogleFonts.outfit(color: ClayColors.textHint.withOpacity(0.7), fontSize: 15),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A pill-like capsule progress bar with an inset background track
/// and a glowing tactile clay fill.
class ClayProgressBar extends StatelessWidget {
  final double value; // 0.0 to 1.0
  final Color progressColor;
  final Color progressHighlight;
  final Color progressShadow;

  const ClayProgressBar({
    super.key,
    required this.value,
    this.progressColor = ClayColors.goldAccent,
    this.progressHighlight = const Color(0xFFD96A4C),
    this.progressShadow = const Color(0xFF96361E),
  });

  @override
  Widget build(BuildContext context) {
    final clampedValue = value.clamp(0.0, 1.0);

    return ClayContainer(
      height: 14,
      borderRadius: 10,
      isInset: true,
      depth: 3.0,
      baseColor: const Color(0xFFE5E2DA),
      highlightColor: const Color(0xFFF7F4EF),
      shadowColor: const Color(0xFFCBC7BE),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          final fillWidth = maxWidth * clampedValue;

          return Align(
            alignment: Alignment.centerLeft,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: fillWidth,
              height: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: LinearGradient(
                  colors: [
                    progressHighlight,
                    progressColor,
                    progressShadow,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                boxShadow: [
                  BoxShadow(
                    color: progressColor.withOpacity(0.3),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A stunning, highly polished claymorphic dialog container.
class ClayDialog extends StatelessWidget {
  final String title;
  final Widget content;
  final List<Widget> actions;

  const ClayDialog({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ClayContainer(
        borderRadius: 28.0,
        baseColor: ClayColors.warmGrey,
        highlightColor: ClayColors.highlight,
        shadowColor: ClayColors.shadow,
        depth: 10.0,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: GoogleFonts.outfit(
                color: ClayColors.textDark,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            content,
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: actions,
            ),
          ],
        ),
      ),
    );
  }
}

/// A custom Route Builder that provides a premium, soft slide-up and fade transition.
Route<T> createClayRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curve,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.0, 0.05),
            end: Offset.zero,
          ).animate(curve),
          child: child,
        ),
      );
    },
    transitionDuration: const Duration(milliseconds: 350),
    reverseTransitionDuration: const Duration(milliseconds: 250),
  );
}
