import 'dart:ui';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aura_mobile/presentation/widgets/clay_components.dart';
import 'package:aura_mobile/core/services/app_navigator.dart';
import 'package:aura_mobile/features/interactive_agent/ui/interactive_mode_screen.dart';

class VoiceAssistantOverlay extends StatefulWidget {
  final Widget child;

  const VoiceAssistantOverlay({super.key, required this.child});

  @override
  State<VoiceAssistantOverlay> createState() => _VoiceAssistantOverlayState();
}

class _VoiceAssistantOverlayState extends State<VoiceAssistantOverlay> with TickerProviderStateMixin {
  static const EventChannel _stateChannel = EventChannel('com.aura.ai/assistant_state');
  
  String _assistantState = "IDLE"; // IDLE, LISTENING, PROCESSING
  
  // Independent controllers for staggered Siri-like multi-orb animation
  late AnimationController _controller1;
  late AnimationController _controller2;
  late AnimationController _controller3;

  @override
  void initState() {
    super.initState();
    
    _controller1 = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    _controller2 = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _controller3 = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2700),
    )..repeat(reverse: true);

    _stateChannel.receiveBroadcastStream().listen((event) {
      if (mounted) {
        setState(() {
          _assistantState = event.toString();
        });
      }
    });
  }

  @override
  void dispose() {
    _controller1.dispose();
    _controller2.dispose();
    _controller3.dispose();
    super.dispose();
  }

  /// Opens Interactive Mode from the assistant popup. Uses the global navigator
  /// so it works even though this overlay sits above the app's Navigator in the
  /// MaterialApp builder.
  void _openInteractiveMode() {
    final navigator = auraNavigatorKey.currentState;
    if (navigator == null) return;
    navigator.push(
      MaterialPageRoute(builder: (_) => const InteractiveModeScreen()),
    );
  }

  Widget _buildInteractiveModePill() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openInteractiveMode,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: ClayColors.goldAccent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: ClayColors.goldAccent.withOpacity(0.35),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                size: 16,
                color: ClayColors.goldAccent,
              ),
              const SizedBox(width: 8),
              Text(
                'Interactive Mode',
                style: GoogleFonts.outfit(
                  color: ClayColors.textDark,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSiriOrb() {
    return AnimatedBuilder(
      animation: Listenable.merge([_controller1, _controller2, _controller3]),
      builder: (context, child) {
        // Continuous organic scale breathing
        double scale1 = 0.95 + _controller1.value * 0.22;
        double scale2 = 1.12 - _controller2.value * 0.18;
        double scale3 = 0.88 + _controller3.value * 0.28;

        // Elliptical trigonometric sway offsets to morph the overall shape
        Offset offset1 = Offset(cos(_controller1.value * 2 * pi) * 16, sin(_controller1.value * 2 * pi) * 8);
        Offset offset2 = Offset(sin(_controller2.value * 2 * pi) * 10, cos(_controller2.value * 2 * pi) * 14);
        Offset offset3 = Offset(cos(_controller3.value * 2 * pi + 0.5) * 18, sin(_controller3.value * 2 * pi - 0.5) * 12);

        // Slow rotate when thinking / processing
        double rotation = _assistantState == "PROCESSING" 
            ? _controller2.value * 2 * pi 
            : 0.0;

        return Transform.rotate(
          angle: rotation,
          child: SizedBox(
            width: 140,
            height: 140,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 25, sigmaY: 25, tileMode: TileMode.decal),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 1. Sky Blue / Purple Orb
                  Transform.translate(
                    offset: offset3,
                    child: Transform.scale(
                      scale: scale3,
                      child: Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              const Color(0xFF54C5F8).withOpacity(0.8),
                              const Color(0xFF7E6BCE).withOpacity(0.35),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 2. Terracotta Core Orb
                  Transform.translate(
                    offset: offset1,
                    child: Transform.scale(
                      scale: scale1,
                      child: Container(
                        width: 85,
                        height: 85,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              const Color(0xFFBC4B2E).withOpacity(0.8),
                              const Color(0xFFE25F4E).withOpacity(0.35),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 3. Amber / Gold Highlights Orb
                  Transform.translate(
                    offset: offset2,
                    child: Transform.scale(
                      scale: scale2,
                      child: Container(
                        width: 75,
                        height: 75,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              const Color(0xFFFFB300).withOpacity(0.75),
                              const Color(0xFFFFE082).withOpacity(0.3),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isActive = _assistantState != "IDLE";
    
    return Material(
      type: MaterialType.transparency,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            widget.child,
            
            // Fading blurred background dim
            IgnorePointer(
              ignoring: !isActive,
              child: AnimatedOpacity(
                opacity: isActive ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 400),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(
                    color: Colors.black.withOpacity(0.25),
                  ),
                ),
              ),
            ),

            // Sliding bottom panel (Aura claymorphic style)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
              left: 0,
              right: 0,
              bottom: isActive ? 0 : -450, // Slide out of view when idle
              height: 350,
              child: Container(
                padding: const EdgeInsets.only(top: 16, bottom: 20),
                decoration: BoxDecoration(
                  color: ClayColors.obsidianBg, // Light warm paper background
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
                  boxShadow: [
                    BoxShadow(
                      color: ClayColors.shadow.withOpacity(0.4),
                      blurRadius: 40,
                      spreadRadius: 2,
                      offset: const Offset(0, -8),
                    )
                  ],
                  border: Border(
                    top: BorderSide(
                      color: ClayColors.goldAccent.withOpacity(0.18),
                      width: 1.5,
                    ),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Sleek Drag Handle Indicator
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: ClayColors.shadow.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _assistantState == "LISTENING"
                          ? "Hi there, I'm listening..."
                          : _assistantState == "SPEAKING"
                              ? "Here's what I found..."
                              : "Thinking about that...",
                      style: GoogleFonts.outfit(
                        color: ClayColors.textDark,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Quick hand-off to the full multi-step Interactive Mode.
                    _buildInteractiveModePill(),
                    const Spacer(),
                    // Animated Morphing Orb with Crisp Floating Mic Button
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        _buildSiriOrb(),
                        
                        // Crisp white button containing terracotta mic icon
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Icon(
                              _assistantState == "LISTENING" ? Icons.mic_rounded : Icons.graphic_eq_rounded,
                              color: ClayColors.goldAccent,
                              size: 24,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
