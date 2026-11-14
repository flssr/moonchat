import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A slow, twinkling star field. [speed] turns the dots into warp streaks.
class Starfield extends StatefulWidget {
  const Starfield({super.key, this.speed = 0});

  final double speed;

  @override
  State<Starfield> createState() => _StarfieldState();
}

class _StarfieldState extends State<Starfield> with SingleTickerProviderStateMixin {
  late final AnimationController _twinkle =
      AnimationController(vsync: this, duration: const Duration(seconds: 12))..repeat();
  late final List<_Star> _stars = _makeStars();

  static List<_Star> _makeStars() {
    final rnd = math.Random(7);
    return List<_Star>.generate(230, (i) {
      final d = rnd.nextDouble();
      return _Star(
        x: rnd.nextDouble(),
        y: rnd.nextDouble(),
        radius: d > 0.94 ? 1.4 + rnd.nextDouble() * 0.9 : 0.35 + rnd.nextDouble() * 0.9,
        alpha: 0.25 + rnd.nextDouble() * 0.7,
        phase: rnd.nextDouble() * math.pi * 2,
        twinkle: 0.3 + rnd.nextDouble() * 1.5,
        depth: 0.3 + rnd.nextDouble() * 0.7,
        warm: rnd.nextDouble() > 0.86,
      );
    });
  }

  @override
  void dispose() {
    _twinkle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _StarPainter(stars: _stars, twinkle: _twinkle, speed: widget.speed),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _Star {
  const _Star({
    required this.x,
    required this.y,
    required this.radius,
    required this.alpha,
    required this.phase,
    required this.twinkle,
    required this.depth,
    required this.warm,
  });

  final double x;
  final double y;
  final double radius;
  final double alpha;
  final double phase;
  final double twinkle;
  final double depth;
  final bool warm;
}

class _StarPainter extends CustomPainter {
  _StarPainter({required this.stars, required this.twinkle, required this.speed})
      : super(repaint: twinkle);

  final List<_Star> stars;
  final Animation<double> twinkle;
  final double speed;

  @override
  void paint(Canvas canvas, Size size) {
    final t = twinkle.value * 12.0;
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint();

    for (final s in stars) {
      final x = s.x * size.width;
      final y = s.y * size.height;
      final a = (s.alpha * (0.62 + 0.38 * math.sin(t * s.twinkle + s.phase))).clamp(0.0, 1.0).toDouble();
      if (a <= 0.01) continue;

      if (speed > 0.02) {
        final dx = x - center.dx;
        final dy = y - center.dy;
        final len = math.sqrt(dx * dx + dy * dy);
        if (len < 1) continue;
        final streak = speed * (40 + 220 * s.depth);
        paint
          ..color = (s.warm ? const Color(0xFFFFECCD) : const Color(0xFFE0EEFF)).withOpacity(a * 0.8)
          ..strokeWidth = s.radius
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          Offset(x, y),
          Offset(x + dx / len * streak, y + dy / len * streak),
          paint,
        );
      } else {
        paint.color = (s.warm ? const Color(0xFFFFECCD) : const Color(0xFFE0EEFF)).withOpacity(a);
        canvas.drawCircle(Offset(x, y), s.radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _StarPainter old) => old.speed != speed || old.stars != stars;
}

/// The distant moon, with craters and a soft halo.
class MoonGlobe extends StatelessWidget {
  const MoonGlobe({super.key, required this.size, this.opacity = 1});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: const Color(0x55D6E9FF), blurRadius: size * 0.45, spreadRadius: size * 0.06),
                  BoxShadow(color: const Color(0x2278AAFF), blurRadius: size * 0.9, spreadRadius: size * 0.15),
                ],
              ),
            ),
            ClipOval(
              child: Container(
                width: size,
                height: size,
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(-0.32, -0.4),
                    radius: 0.95,
                    colors: [Color(0xFFFFFDF6), Color(0xFFF7F1DF), Color(0xFFE8DFC8), Color(0xFFCFC5AD)],
                    stops: [0.0, 0.42, 0.68, 1.0],
                  ),
                ),
              ),
            ),
            _crater(size, 0.26, 0.55, 0.17),
            _crater(size, 0.58, 0.32, 0.10),
            _crater(size, 0.68, 0.63, 0.07),
            _crater(size, 0.38, 0.22, 0.05),
            _crater(size, 0.15, 0.30, 0.12),
          ],
        ),
      ),
    );
  }

  Widget _crater(double size, double left, double top, double d) {
    return Positioned(
      left: size * left,
      top: size * top,
      child: Container(
        width: size * d,
        height: size * d,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0x248A8880),
        ),
      ),
    );
  }
}



