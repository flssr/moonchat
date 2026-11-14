import 'package:flutter/material.dart';

import 'starfield.dart';

/// The sky behind everything: gradient, stars, nebula smudges.
class SkyBackdrop extends StatelessWidget {
  const SkyBackdrop({super.key, this.starSpeed = 0});

  final double starSpeed;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, 1.1),
              radius: 1.15,
              colors: [Color(0xFF15305C), Color(0xFF0A1836), Color(0xFF050B1A), Color(0xFF03060E)],
              stops: [0.0, 0.34, 0.62, 1.0],
            ),
          ),
        ),
        Positioned(left: -180, top: -260, child: _nebula(720, const Color(0x33406AFF))),
        Positioned(right: -220, top: 40, child: _nebula(640, const Color(0x2A7E58FF))),
        Positioned(left: 180, bottom: -320, child: _nebula(820, const Color(0x1F34B2D6))),
        Starfield(speed: starSpeed),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.1),
              radius: 1.25,
              colors: [Color(0x00000000), Color(0x0002040A), Color(0x8C02040A)],
              stops: [0.4, 0.7, 1.0],
            ),
          ),
        ),
      ],
    );
  }

  Widget _nebula(double size, Color color) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withOpacity(0)]),
        ),
      ),
    );
  }
}


