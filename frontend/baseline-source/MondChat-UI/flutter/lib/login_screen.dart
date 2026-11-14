import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'sky.dart';
import 'starfield.dart';
import 'theme.dart';

enum _Phase { login, boarding, closing, ready, launching, done }

/// One sampled frame of the launch arc.
class _Pose {
  const _Pose(this.t, this.fx, this.fy, this.rot, this.scale, this.opacity);

  final double t;
  final double fx;
  final double fy;
  final double rot;
  final double scale;
  final double opacity;
}

const _kFlight = <_Pose>[
  _Pose(0.00, 0.00, 0.00, 0, 1.000, 1.00),
  _Pose(0.08, 0.00, 0.02, -3.0, 1.015, 1.00),
  _Pose(0.22, 0.02, 0.07, -1.6, 1.010, 1.00),
  _Pose(0.36, 0.07, 0.17, 7.0, 0.950, 1.00),
  _Pose(0.52, 0.16, 0.33, 16.0, 0.840, 1.00),
  _Pose(0.67, 0.30, 0.52, 25.0, 0.680, 1.00),
  _Pose(0.80, 0.50, 0.71, 34.0, 0.500, 1.00),
  _Pose(0.91, 0.74, 0.87, 44.0, 0.300, 0.92),
  _Pose(0.97, 0.94, 0.97, 54.0, 0.100, 0.55),
  _Pose(1.00, 1.00, 1.00, 62.0, 0.015, 0.00),
];

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onEntered});

  /// Called once the ship has disappeared into the moon.
  final void Function(Offset fractionalOrigin) onEntered;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  final _stackKey = GlobalKey();
  final _rocketKey = GlobalKey();
  final _emailKey = GlobalKey();
  final _passKey = GlobalKey();

  final _email = TextEditingController();
  final _pass = TextEditingController();

  late final AnimationController _intro =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  late final AnimationController _fly =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
  late final AnimationController _door =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
  late final AnimationController _button =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 640));
  late final AnimationController _launch =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2700));
  late final AnimationController _shake =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 460));
  late final AnimationController _impact =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 820));
  late final AnimationController _flash =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 560));

  _Phase _phase = _Phase.login;
  String _error = '';
  bool _obscure = true;
  bool _formGone = false;

  Offset _fieldDeltaEmail = Offset.zero;
  Offset _fieldDeltaPass = Offset.zero;
  Offset _flightDelta = Offset.zero;

  bool get _launching => _phase.index >= _Phase.launching.index;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    _intro.dispose();
    _fly.dispose();
    _door.dispose();
    _button.dispose();
    _launch.dispose();
    _shake.dispose();
    _impact.dispose();
    _flash.dispose();
    super.dispose();
  }

  /* ------------------------------------------------------------------ */
  /*  geometry helpers                                                   */
  /* ------------------------------------------------------------------ */

  Rect _rectOf(GlobalKey key, RenderBox ancestor) {
    final box = key.currentContext!.findRenderObject() as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: ancestor);
    return topLeft & box.size;
  }

  /* ------------------------------------------------------------------ */
  /*  sequence                                                           */
  /* ------------------------------------------------------------------ */

  Future<void> _submit() async {
    if (_phase != _Phase.login) return;
    final email = _email.text.trim();
    final pass = _pass.text;

    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(email)) {
      setState(() => _error = '邮箱格式好像不太对');
      return;
    }
    if (pass.length < 4) {
      setState(() => _error = '密码至少需要 4 位');
      return;
    }

    final stackBox = _stackKey.currentContext!.findRenderObject() as RenderBox;
    final rocketRect = _rectOf(_rocketKey, stackBox);
    final doorCenter = Offset(
      rocketRect.left + rocketRect.width * 0.6505,
      rocketRect.top + rocketRect.height * 0.4185,
    );
    final emailRect = _rectOf(_emailKey, stackBox);
    final passRect = _rectOf(_passKey, stackBox);

    setState(() {
      _error = '';
      _phase = _Phase.boarding;
      _fieldDeltaEmail = doorCenter - emailRect.center;
      _fieldDeltaPass = doorCenter - passRect.center;
    });

    FocusScope.of(context).unfocus();
    _intro.forward();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;

    await _fly.forward();
    if (!mounted) return;
    setState(() {
      _formGone = true;
      _phase = _Phase.closing;
    });

    await _door.forward();
    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (!mounted) return;

    setState(() => _phase = _Phase.ready);
    _button.forward();
  }

  Future<void> _launchRocket() async {
    if (_phase != _Phase.ready) return;
    final size = MediaQuery.sizeOf(context);
    setState(() => _phase = _Phase.launching);
    _shake.forward(from: 0);

    final stackBox = _stackKey.currentContext!.findRenderObject() as RenderBox;
    final rocketRect = _rectOf(_rocketKey, stackBox);
    final moonTarget = Offset(size.width * 0.6, size.height * 0.32);
    setState(() {
      _flightDelta = Offset(
        moonTarget.dx - rocketRect.center.dx,
        moonTarget.dy - rocketRect.center.dy - rocketRect.height * 0.08,
      );
    });

    await Future<void>.delayed(const Duration(milliseconds: 240));
    if (!mounted) return;
    _launch.forward(from: 0);

    await Future<void>.delayed(const Duration(milliseconds: 2450));
    if (!mounted) return;
    _impact.forward(from: 0);

    await Future<void>.delayed(const Duration(milliseconds: 320));
    if (!mounted) return;
    _flash.forward(from: 0);

    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    setState(() => _phase = _Phase.done);
    widget.onEntered(const Offset(0.6, 0.32));
  }

  _Pose _poseAt(double t) {
    if (t <= 0) return _kFlight.first;
    if (t >= 1) return _kFlight.last;
    for (var i = 1; i < _kFlight.length; i++) {
      final a = _kFlight[i - 1];
      final b = _kFlight[i];
      if (t <= b.t) {
        final span = b.t - a.t;
        final local = span <= 0 ? 1.0 : ((t - a.t) / span).clamp(0.0, 1.0).toDouble();
        final k = Curves.easeInOutSine.transform(local);
        double mix(double x, double y) => x + (y - x) * k;
        return _Pose(
          t,
          mix(a.fx, b.fx),
          mix(a.fy, b.fy),
          mix(a.rot, b.rot),
          mix(a.scale, b.scale),
          mix(a.opacity, b.opacity),
        );
      }
    }
    return _kFlight.last;
  }

  /* ------------------------------------------------------------------ */
  /*  build                                                              */
  /* ------------------------------------------------------------------ */

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final wide = size.width > 940;
        final rh = wide
            ? math.min(size.height * 0.78, math.min(size.height - 210, 860.0))
            : math.min(size.height * 0.34, 330.0);
        final rw = rh * MoonColors.rocketRatio;
        final colW = wide ? math.min(460.0, size.width * 0.36) : math.min(420.0, size.width - 36);
        final gap = wide ? (size.width * 0.05).clamp(32.0, 110.0).toDouble() : 0.0;
        final totalW = colW + gap + rw;
        final left = wide ? (size.width - totalW) / 2 : 18.0;
        final rocketLeft = wide ? left + colW + gap : (size.width - rw) / 2;
        final rocketTop = wide ? (size.height - rh) / 2 : size.height * 0.045;
        final centered = (size.width - rw) / 2;
        final shifted = wide && _phase.index >= _Phase.closing.index;
        final introTop = rocketTop + rh + 34;

        Widget introLayer;
        if (wide) {
          introLayer = Positioned(
            left: left,
            top: 0,
            width: colW,
            height: size.height,
            child: Center(child: _introColumn(colW, false)),
          );
        } else {
          introLayer = Positioned(
            left: 18,
            right: 18,
            top: introTop,
            bottom: 0,
            child: SingleChildScrollView(child: _introColumn(colW, true)),
          );
        }

        return Stack(
          key: _stackKey,
          children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _launch,
                builder: (context, _) => SkyBackdrop(
                  starSpeed: _launching ? _launch.value : 0.0,
                ),
              ),
            ),
            _moonLayer(size, wide),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 1100),
              curve: Curves.easeInOutCubic,
              left: shifted ? centered : rocketLeft,
              top: rocketTop,
              width: rw,
              height: rh,
              child: _rocket(rh),
            ),
            if (!_formGone) introLayer,
            _brand(),
            _flashLayer(size),
            _impactLayer(size),
          ],
        );
      },
    );
  }

  /* ------------------------------------------------------------------ */
  /*  layers                                                             */
  /* ------------------------------------------------------------------ */

  Widget _brand() {
    return Positioned(
      left: 40,
      top: 34,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset('assets/logo.png', width: 44, height: 44, filterQuality: FilterQuality.high),
          ),
          const SizedBox(width: 12),
          const Text(
            'MondChat',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: MoonColors.ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _moonLayer(Size size, bool wide) {
    final moonSize = wide ? math.min(math.max(size.width * 0.08, 84.0), 132.0) : 58.0;
    final right = wide ? size.width * 0.08 : 14.0;
    final top = wide ? size.height * 0.06 : 72.0;
    final startCenter = Offset(size.width - right - moonSize / 2, top + moonSize / 2);

    return Positioned(
      right: right,
      top: top,
      child: AnimatedBuilder(
        animation: _launch,
        builder: (context, child) {
          final t = Curves.easeInOutSine.transform(_launch.value.clamp(0.0, 1.0).toDouble());
          return Transform.translate(
            offset: Offset(
              (size.width * 0.6 - startCenter.dx) * t,
              (size.height * 0.32 - startCenter.dy) * t,
            ),
            child: Transform.scale(scale: 1 + 1.9 * t, child: child),
          );
        },
        child: Opacity(
          opacity: _phase == _Phase.done ? 0.0 : 1.0,
          child: MoonGlobe(size: moonSize),
        ),
      ),
    );
  }

  Widget _flashLayer(Size size) {
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _flash,
          builder: (context, _) {
            if (!_flash.isAnimating && _flash.value == 0) return const SizedBox.shrink();
            final v = math.sin(math.pi * _flash.value).clamp(0.0, 1.0).toDouble();
            return Opacity(
              opacity: (v * (1 - v * 0.2)).clamp(0.0, 1.0).toDouble(),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0.2, -0.36),
                    radius: 0.95,
                    colors: [Color(0xFFFFFFFF), Color(0xCCE4F1FF), Color(0x005A8CFF)],
                    stops: [0.0, 0.32, 1.0],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _impactLayer(Size size) {
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _impact,
          builder: (context, _) {
            if (_impact.value <= 0 || _impact.value >= 1) return const SizedBox.shrink();
            return CustomPaint(
              painter: _RipplePainter(
                progress: _impact.value,
                center: Offset(size.width * 0.6, size.height * 0.32),
              ),
              child: const SizedBox.expand(),
            );
          },
        ),
      ),
    );
  }

  /* ------------------------------------------------------------------ */
  /*  rocket                                                             */
  /* ------------------------------------------------------------------ */

  Widget _rocket(double rh) {
    return AnimatedBuilder(
      animation: Listenable.merge([_door, _launch, _shake, _button, _impact]),
      builder: (context, _) {
        final launching = _launching;
        final pose = _poseAt(_launch.value);
        final m = Matrix4.identity();
        if (launching) {
          final s = _shake.value;
          if (s < 1) {
            final amp = (1 - s) * 3.0;
            m.translate(math.sin(s * 46) * amp, math.cos(s * 38) * amp * 0.6);
          }
          m.translate(_flightDelta.dx * pose.fx, _flightDelta.dy * pose.fy);
          m.rotateZ(pose.rot * math.pi / 180);
          m.scale(pose.scale);
        }
        return Opacity(
          opacity: launching ? pose.opacity : 1,
          child: Transform(
            alignment: const Alignment(0, 0.16),
            transform: m,
            child: _rocketStack(rh),
          ),
        );
      },
    );
  }

  Widget _rocketStack(double rh) {
    final w = rh * MoonColors.rocketRatio;
    final burn = (_launch.value * 7).clamp(0.0, 1.0).toDouble();

    return SizedBox(
      key: _rocketKey,
      width: w,
      height: rh,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // the standing ship: hull, swinging leaf, closing door
          Opacity(
            opacity: 1 - burn,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset('assets/rocket_body.png', fit: BoxFit.contain, filterQuality: FilterQuality.high),

                // the door leaf, hinged on its left edge
                AnimatedBuilder(
                  animation: _door,
                  builder: (context, child) {
                    final t = (_door.value / 0.42).clamp(0.0, 1.0).toDouble();
                    if (t >= 1) return const SizedBox.shrink();
                    return Opacity(
                      opacity: 1 - t,
                      child: Transform(
                        alignment: Alignment.centerLeft,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.0016)
                          ..rotateY(-1.62 * t),
                        child: child,
                      ),
                    );
                  },
                  child: Image.asset('assets/rocket_leaf.png', fit: BoxFit.contain, filterQuality: FilterQuality.high),
                ),

                // the shut door slides across the doorway
                AnimatedBuilder(
                  animation: _door,
                  builder: (context, child) {
                    final t = ((_door.value - 0.30) / 0.70).clamp(0.0, 1.0).toDouble();
                    if (t <= 0) return const SizedBox.shrink();
                    return ClipRect(clipper: _DoorClipper(t), child: child);
                  },
                  child: Image.asset('assets/rocket_closed.png', fit: BoxFit.contain, filterQuality: FilterQuality.high),
                ),

                // repaint the hull edge the open leaf was hiding
                AnimatedBuilder(
                  animation: _door,
                  builder: (context, child) {
                    final t = ((_door.value - 0.70) / 0.30).clamp(0.0, 1.0).toDouble();
                    if (t <= 0) return const SizedBox.shrink();
                    return Opacity(
                      opacity: t,
                      child: ClipRect(clipper: const _PatchClipper(), child: child),
                    );
                  },
                  child: Image.asset('assets/rocket_closed.png', fit: BoxFit.contain, filterQuality: FilterQuality.high),
                ),
              ],
            ),
          ),

          // the launch art with its own flame
          Opacity(
            opacity: burn,
            child: Image.asset('assets/rocket_launch.png', fit: BoxFit.contain, filterQuality: FilterQuality.high),
          ),

          // doorway light
          Positioned(
            left: w * 0.40,
            top: rh * 0.13,
            width: w * 0.50,
            height: rh * 0.44,
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _door,
                builder: (context, _) {
                  final glow = _phase == _Phase.boarding
                      ? 1.0
                      : (_phase == _Phase.closing ? (1 - _door.value) * 0.5 : 0.0);
                  return Opacity(
                    opacity: glow,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [Color(0xF2A0EBFF), Color(0x8C5AB4FF), Color(0x00468CFF)],
                          stops: [0.0, 0.38, 0.72],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // exhaust glow
          Positioned(
            left: w * 0.14,
            bottom: -rh * 0.02,
            width: w * 0.72,
            height: rh * 0.42,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _launching ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 260),
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0, 0.42),
                      radius: 0.55,
                      colors: [Color(0xF2FFF4D6), Color(0x8CFFBE6E), Color(0x38FF7846), Color(0x00FF5A32)],
                      stops: [0.0, 0.32, 0.52, 0.72],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // the red button pinned on the hull
          Align(
            alignment: const Alignment(0, 0.268),
            child: AnimatedBuilder(
              animation: _button,
              builder: (context, child) {
                final t = Curves.elasticOut.transform(_button.value.clamp(0.0, 1.0).toDouble());
                final visible = _phase.index >= _Phase.ready.index;
                return IgnorePointer(
                  ignoring: !(visible && _phase == _Phase.ready),
                  child: Opacity(
                    opacity: visible ? 1.0 : 0.0,
                    child: Transform.scale(scale: 0.42 + 0.58 * t, child: child),
                  ),
                );
              },
              child: _enterButton(rh),
            ),
          ),
        ],
      ),
    );
  }

  Widget _enterButton(double rh) {
    return GestureDetector(
      onTap: _launchRocket,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: rh * 0.215,
          height: rh * 0.081,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(rh * 0.042),
            border: Border.all(color: const Color(0xFF2F353A), width: rh * 0.0055),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFF6C78), Color(0xFFFF4157), Color(0xFFDC1836)],
            ),
            boxShadow: [
              BoxShadow(color: const Color(0x59FF3C5A), blurRadius: rh * 0.05, offset: Offset(0, rh * 0.012)),
              BoxShadow(color: const Color(0x3D000000), blurRadius: rh * 0.02, offset: Offset(0, rh * 0.008)),
            ],
          ),
          child: Text(
            '登 录',
            style: TextStyle(
              color: Colors.white,
              fontSize: rh * 0.026,
              fontWeight: FontWeight.w700,
              letterSpacing: 3,
            ),
          ),
        ),
      ),
    );
  }

  /* ------------------------------------------------------------------ */
  /*  intro copy + form                                                  */
  /* ------------------------------------------------------------------ */

  Widget _introColumn(double colW, bool center) {
    return AnimatedBuilder(
      animation: _intro,
      builder: (context, _) {
        final fade = (1 - _intro.value).clamp(0.0, 1.0).toDouble();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            Opacity(opacity: fade, child: _eyebrow()),
            const SizedBox(height: 20),
            Opacity(opacity: fade, child: _headline(colW, center)),
            const SizedBox(height: 30),
            _panel(fade, center),
          ],
        );
      },
    );
  }

  Widget _eyebrow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: MoonColors.cyan,
            boxShadow: [BoxShadow(color: MoonColors.cyan.withOpacity(0.8), blurRadius: 10)],
          ),
        ),
        const SizedBox(width: 10),
        const Text(
          'WELCOME TO MONDCHAT',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 3.2,
            fontWeight: FontWeight.w500,
            color: Color(0xCC8CBEFF),
          ),
        ),
      ],
    );
  }

  Widget _headline(double colW, bool center) {
    final size = math.min(62.0, math.max(34.0, colW * 0.118));
    final shader = const LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [Color(0xFFFFFFFF), Color(0xFFC6DEFE), Color(0xFF93B8FF)],
    ).createShader(Rect.fromLTWH(0, 0, math.max(colW, 320.0), 92.0));

    return Text.rich(
      TextSpan(
        children: [
          const TextSpan(text: '欢迎来到'),
          TextSpan(
            text: '月读世界',
            style: TextStyle(foreground: Paint()..shader = shader),
          ),
        ],
      ),
      textAlign: center ? TextAlign.center : TextAlign.left,
      style: TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w700,
        height: 1.12,
        letterSpacing: -1.2,
        color: MoonColors.ink,
      ),
    );
  }

  Future<void> _toast(String message) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
        behavior: SnackBarBehavior.floating,
        width: 320,
        duration: const Duration(milliseconds: 2600),
        backgroundColor: const Color(0xF20C1830),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: const BorderSide(color: MoonColors.line),
        ),
      ),
    );
  }

  Widget _panel(double fade, bool center) {
    return SizedBox(
      width: double.infinity,
      child: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: fade,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xC4172849), Color(0xC6091024)],
                  ),
                  border: Border.all(color: MoonColors.line),
                  boxShadow: const [
                    BoxShadow(color: Color(0x8C000000), blurRadius: 60, offset: Offset(0, 26)),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _flyingField(
                  _fieldDeltaEmail,
                  0.0,
                  _Field(
                    key: _emailKey,
                    icon: Icons.alternate_email_rounded,
                    label: '邮箱',
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                const SizedBox(height: 10),
                _flyingField(
                  _fieldDeltaPass,
                  0.12,
                  _Field(
                    key: _passKey,
                    icon: Icons.lock_outline_rounded,
                    label: '密码',
                    controller: _pass,
                    obscure: _obscure,
                    onSubmitted: (_) => _submit(),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _iconTap(
                          icon: _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          onTap: () => setState(() => _obscure = !_obscure),
                        ),
                        const SizedBox(width: 6),
                        _goButton(),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  height: 30,
                  child: Align(
                    alignment: center ? Alignment.center : Alignment.centerLeft,
                    child: AnimatedOpacity(
                      opacity: _error.isEmpty ? 0.0 : 1.0,
                      duration: const Duration(milliseconds: 180),
                      child: Text(
                        _error,
                        style: const TextStyle(fontSize: 12, color: Color(0xFFFF9AA8)),
                      ),
                    ),
                  ),
                ),
                Opacity(
                  opacity: fade,
                  child: GestureDetector(
                    onTap: () => _toast('注册通道正在铺设中，先用任意邮箱登舱吧 ✦'),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          '注册账号  →',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.6,
                            color: MoonColors.blue,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _flyingField(Offset delta, double delay, Widget child) {
    return AnimatedBuilder(
      animation: _fly,
      builder: (context, _) {
        final v = ((_fly.value - delay) / (1 - delay)).clamp(0.0, 1.0).toDouble();
        final m = Matrix4.identity()
          ..translate(delta.dx * v, delta.dy * v)
          ..rotateZ(0.22 * v)
          ..scale(1 - 0.84 * v);
        return Transform(alignment: Alignment.center, transform: m, child: child);
      },
      child: child,
    );
  }

  Widget _iconTap({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: SizedBox(
          width: 30,
          height: 30,
          child: Icon(icon, size: 18, color: MoonColors.ink3),
        ),
      ),
    );
  }

  Widget _goButton() {
    return GestureDetector(
      onTap: _submit,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF9DD4FF), Color(0xFF6FB6FF), Color(0xFF5B8BFF)],
            ),
            boxShadow: const [
              BoxShadow(color: Color(0x59468CFF), blurRadius: 18, offset: Offset(0, 6)),
            ],
          ),
          child: const Icon(Icons.arrow_forward_rounded, size: 18, color: Color(0xFF06101F)),
        ),
      ),
    );
  }
}

/* ------------------------------------------------------------------ */
/*  field                                                              */
/* ------------------------------------------------------------------ */

class _Field extends StatefulWidget {
  const _Field({
    super.key,
    required this.icon,
    required this.label,
    required this.controller,
    this.obscure = false,
    this.keyboardType,
    this.onSubmitted,
    this.onChanged,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final TextEditingController controller;
  final bool obscure;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onChanged;
  final Widget? trailing;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  final _focus = FocusNode();
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_refresh);
    widget.controller.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focus.removeListener(_refresh);
    widget.controller.removeListener(_refresh);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = _focus.hasFocus || widget.controller.text.isNotEmpty;
    final focused = _focus.hasFocus;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: _focus.requestFocus,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 62,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: focused ? const Color(0x0F7CC4FF) : const Color(0x09FFFFFF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: focused
                  ? const Color(0x9F7CC4FF)
                  : (_hover ? const Color(0x428FBEEF) : const Color(0x248FBEEF)),
            ),
            boxShadow: focused
                ? const [BoxShadow(color: Color(0x224080FF), blurRadius: 26)]
                : null,
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 19, color: focused ? MoonColors.blue : MoonColors.ink3),
              const SizedBox(width: 12),
              Expanded(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 15),
                        child: TextField(
                          controller: widget.controller,
                          focusNode: _focus,
                          obscureText: widget.obscure,
                          keyboardType: widget.keyboardType,
                          onSubmitted: widget.onSubmitted,
                          onChanged: (_) => widget.onChanged?.call(),
                          cursorColor: MoonColors.blue,
                          style: const TextStyle(fontSize: 15, color: MoonColors.ink),
                          decoration: const InputDecoration(
                            isCollapsed: true,
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ),
                    IgnorePointer(
                      child: AnimatedAlign(
                        duration: const Duration(milliseconds: 190),
                        curve: Curves.easeOutCubic,
                        alignment: active ? const Alignment(-1, -0.78) : const Alignment(-1, 0),
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 190),
                          style: TextStyle(
                            fontSize: active ? 10.5 : 15,
                            letterSpacing: active ? 1.2 : 0,
                            color: active ? const Color(0xCC8FC8FF) : MoonColors.ink3,
                          ),
                          child: Text(widget.label),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.trailing != null) ...[
                const SizedBox(width: 6),
                widget.trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/* ------------------------------------------------------------------ */
/*  clippers                                                           */
/* ------------------------------------------------------------------ */

class _DoorClipper extends CustomClipper<Rect> {
  const _DoorClipper(this.progress);

  final double progress;

  @override
  Rect getClip(Size size) {
    final left = size.width * 0.533;
    final right = size.width * 0.768;
    final top = size.height * 0.265;
    final bottom = size.height * 0.586;
    final w = (right - left) * progress;
    return Rect.fromLTRB(right - w, top, right, bottom);
  }

  @override
  bool shouldReclip(covariant _DoorClipper old) => old.progress != progress;
}

class _PatchClipper extends CustomClipper<Rect> {
  const _PatchClipper();

  @override
  Rect getClip(Size size) => Rect.fromLTRB(
        size.width * 0.77,
        size.height * 0.24,
        size.width * 0.86,
        size.height * 0.60,
      );

  @override
  bool shouldReclip(covariant _PatchClipper old) => false;
}

/* ------------------------------------------------------------------ */
/*  ripple                                                             */
/* ------------------------------------------------------------------ */

class _RipplePainter extends CustomPainter {
  _RipplePainter({required this.progress, required this.center});

  final double progress;
  final Offset center;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Curves.easeOutCubic.transform(progress.clamp(0.0, 1.0).toDouble());
    final r = 26 + 210 * p;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withOpacity((1 - p) * 0.9);
    canvas.drawCircle(center, r, stroke);

    final glowRect = Rect.fromCircle(center: center, radius: r);
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [Colors.white.withOpacity((1 - p) * 0.35), Colors.white.withOpacity(0)],
      ).createShader(glowRect);
    canvas.drawCircle(center, r, glow);
  }

  @override
  bool shouldRepaint(covariant _RipplePainter old) => old.progress != progress;
}




