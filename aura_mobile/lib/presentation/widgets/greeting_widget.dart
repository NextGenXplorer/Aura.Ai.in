import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aura_mobile/presentation/providers/user_provider.dart';
import 'package:aura_mobile/presentation/providers/persona_provider.dart';
import 'package:aura_mobile/presentation/widgets/starburst_painter.dart';

class GreetingWidget extends ConsumerWidget {
  const GreetingWidget({super.key});

  String _getDynamicGreeting(String name) {
    final hour = DateTime.now().hour;
    final displayName = name.isNotEmpty ? name : 'there';
    
    if (hour >= 22 || hour < 4) {
      return 'How can I help you\nthis late night, $displayName?';
    } else if (hour >= 4 && hour < 12) {
      return 'How can I help you\nthis morning, $displayName?';
    } else if (hour >= 12 && hour < 17) {
      return 'How can I help you\nthis afternoon, $displayName?';
    } else {
      return 'How can I help you\nthis evening, $displayName?';
    }
  }

  List<Color> _getOrbColors(Color accentColor) {
    final hsl = HSLColor.fromColor(accentColor);
    
    // Create 4 soft pastel colors matching the accentColor's hue family
    final c1 = hsl.withLightness(0.78).withSaturation(0.80).toColor();
    final c2 = hsl.withHue((hsl.hue + 35) % 360).withLightness(0.80).withSaturation(0.75).toColor();
    final c3 = hsl.withHue((hsl.hue - 35) % 360).withLightness(0.76).withSaturation(0.82).toColor();
    final c4 = hsl.withHue((hsl.hue + 180) % 360).withLightness(0.82).withSaturation(0.60).toColor();
    
    return [c1, c2, c3, c4];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userState = ref.watch(userProvider);
    final personaState = ref.watch(personaProvider);
    final activePersona = personaState.activePersona;
    final accentColor = activePersona.accentColor;

    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    
    final double orbSize = isKeyboardOpen ? 180.0 : 280.0;
    final double logoSize = isKeyboardOpen ? 36.0 : 52.0;
    final double spacing = isKeyboardOpen ? 12.0 : 24.0;
    final double fontSize = isKeyboardOpen ? 14.0 : 21.0;
    final double blurSigma = isKeyboardOpen ? 25.0 : 40.0;
    final double scale = orbSize / 280.0;

    final orbColors = _getOrbColors(accentColor);

    return userState.when(
      data: (name) => Center(
        child: SizedBox(
          width: orbSize,
          height: orbSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 1. Organic Gradient Mesh Orb (Blurred color cloud)
              ClipRRect(
                borderRadius: BorderRadius.circular(orbSize / 2),
                child: SizedBox(
                  width: orbSize,
                  height: orbSize,
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma, tileMode: TileMode.decal),
                    child: Stack(
                      children: [
                        // Soft base overlay
                        Container(color: orbColors[0].withOpacity(0.1)),
                        // Color 1 Circle (Top Left)
                        Positioned(
                          top: -10 * scale,
                          left: -10 * scale,
                          child: Container(
                            width: 170 * scale,
                            height: 170 * scale,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: orbColors[0],
                            ),
                          ),
                        ),
                        // Color 2 Circle (Bottom Right)
                        Positioned(
                          bottom: -20 * scale,
                          right: -10 * scale,
                          child: Container(
                            width: 180 * scale,
                            height: 180 * scale,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: orbColors[1],
                            ),
                          ),
                        ),
                        // Color 3 Circle (Top Right)
                        Positioned(
                          top: -10 * scale,
                          right: -20 * scale,
                          child: Container(
                            width: 160 * scale,
                            height: 160 * scale,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: orbColors[2],
                            ),
                          ),
                        ),
                        // Color 4 Circle (Bottom Left)
                        Positioned(
                          bottom: -10 * scale,
                          left: -30 * scale,
                          child: Container(
                            width: 170 * scale,
                            height: 170 * scale,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: orbColors[3],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // 2. Logo and Greeting text positioned on top (crisp and readable)
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  StarburstLogo(size: logoSize, accentColor: accentColor),
                  SizedBox(height: spacing),
                  Text(
                    _getDynamicGreeting(name),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: fontSize,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      height: 1.35,
                      shadows: [
                        Shadow(
                          color: Colors.black.withOpacity(0.15),
                          offset: Offset(0, 1.5 * scale),
                          blurRadius: 3.5 * scale,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      loading: () => const SizedBox.shrink(),
      error: (_, err) => const SizedBox.shrink(),
    );
  }
}
