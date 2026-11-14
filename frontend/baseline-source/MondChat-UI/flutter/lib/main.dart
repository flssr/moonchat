import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'chat_screen.dart';
import 'login_screen.dart';
import 'theme.dart';

void main() {
  runApp(const MondChatApp());
}

class MondChatApp extends StatelessWidget {
  const MondChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MondChat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: MoonColors.bg0,
        colorScheme: const ColorScheme.dark(
          primary: MoonColors.blue,
          surface: Color(0xFF0B1730),
        ),
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: MoonColors.blue,
          selectionColor: Color(0x447CC4FF),
          selectionHandleColor: MoonColors.blue,
        ),
      ),
      home: const RootScene(),
    );
  }
}

/// Owns the hand-off between the launch sequence and the chat home.
class RootScene extends StatefulWidget {
  const RootScene({super.key});

  @override
  State<RootScene> createState() => _RootSceneState();
}

class _RootSceneState extends State<RootScene> with SingleTickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  bool _showChat = false;
  bool _revealDone = false;
  Offset _origin = const Offset(0.6, 0.32);

  @override
  void initState() {
    super.initState();
    _reveal.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _revealDone = true);
      }
    });
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  void _enter(Offset origin) {
    if (_showChat) return;
    setState(() {
      _showChat = true;
      _origin = origin;
    });
    _reveal.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          if (!_revealDone)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _reveal,
                builder: (context, child) => Opacity(
                  opacity: (1 - _reveal.value * 1.6).clamp(0.0, 1.0).toDouble(),
                  child: child,
                ),
                child: LoginScreen(onEntered: _enter),
              ),
            ),
          if (_showChat)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _reveal,
                builder: (context, child) {
                  if (_reveal.value >= 0.999) return child!;
                  return ClipPath(
                    clipper: _CircleRevealClipper(progress: _reveal.value, origin: _origin),
                    child: child,
                  );
                },
                child: const ChatScreen(),
              ),
            ),
        ],
      ),
    );
  }
}

/// Expands a circle from the point where the rocket slipped into the moon.
class _CircleRevealClipper extends CustomClipper<Path> {
  _CircleRevealClipper({required this.progress, required this.origin});

  final double progress;
  final Offset origin;

  @override
  Path getClip(Size size) {
    final c = Offset(size.width * origin.dx, size.height * origin.dy);
    final dx = math.max(c.dx, size.width - c.dx);
    final dy = math.max(c.dy, size.height - c.dy);
    final maxR = math.sqrt(dx * dx + dy * dy) * 1.02;
    final p = Curves.easeInOutCubic.transform(progress.clamp(0.0, 1.0).toDouble());
    return Path()..addOval(Rect.fromCircle(center: c, radius: maxR * p));
  }

  @override
  bool shouldReclip(covariant _CircleRevealClipper old) =>
      old.progress != progress || old.origin != origin;
}

