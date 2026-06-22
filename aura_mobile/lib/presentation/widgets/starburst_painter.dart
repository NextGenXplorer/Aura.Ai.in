import 'dart:math';
import 'package:flutter/material.dart';

class StarburstPainter extends CustomPainter {
  final List<Color>? customColors;

  const StarburstPainter({this.customColors});

  static const List<Color> _petalColors = [
    Color(0xFFE25F4E), // Red/Orange
    Color(0xFFEAA04B), // Orange
    Color(0xFFEBCE4B), // Yellow
    Color(0xFF86C166), // Green
    Color(0xFF38B0A6), // Teal
    Color(0xFF4390DE), // Blue
    Color(0xFF7E6BCE), // Purple
    Color(0xFFD05C9F), // Pink
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.width * (5.0 / 28.0)
      ..style = PaintingStyle.stroke;

    final double innerRadius = size.width * (4.0 / 28.0);
    final double outerRadius = size.width * (13.0 / 28.0);

    final colors = customColors ?? _petalColors;

    for (int i = 0; i < 8; i++) {
      final double angle = i * 45 * pi / 180;
      paint.color = colors[i % colors.length];

      final startPoint = center + Offset(cos(angle) * innerRadius, sin(angle) * innerRadius);
      final endPoint = center + Offset(cos(angle) * outerRadius, sin(angle) * outerRadius);

      canvas.drawLine(startPoint, endPoint, paint);
    }
  }

  @override
  bool shouldRepaint(covariant StarburstPainter oldDelegate) =>
      oldDelegate.customColors != customColors;
}

class StarburstLogo extends StatelessWidget {
  final double size;
  final Color? accentColor;

  const StarburstLogo({
    super.key,
    this.size = 56.0,
    this.accentColor,
  });

  List<Color> _generatePetalColors(Color baseColor) {
    final hsl = HSLColor.fromColor(baseColor);
    return List.generate(8, (index) {
      // Rotate hue around the base accent color to create a beautiful, cohesive spectrum
      final double hueOffset = (index - 4) * 15.0; // shifts from -60 to +45
      return hsl
          .withHue((hsl.hue + hueOffset) % 360)
          .withLightness((hsl.lightness + (index % 2 == 0 ? 0.05 : -0.05)).clamp(0.2, 0.8))
          .toColor();
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Color>? customColors = accentColor != null ? _generatePetalColors(accentColor!) : null;
    final scale = size / 56.0;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10 * scale,
            offset: Offset(0, 4 * scale),
          ),
        ],
      ),
      child: Center(
        child: SizedBox(
          width: size * 0.5,
          height: size * 0.5,
          child: CustomPaint(
            painter: StarburstPainter(customColors: customColors),
          ),
        ),
      ),
    );
  }
}
