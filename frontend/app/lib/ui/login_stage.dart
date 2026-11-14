import 'dart:math';

import 'package:flutter/material.dart';

import '../theme.dart';

/// 登录舞台：发射平台的夜空（`docs/frontend/DESIGN-SPEC.md` §6.1）。
///
/// 画的是「观测窗」：夜空渐变、银河带、星点、月相与发射台都在这里用
/// CustomPaint 画出来，只引用 `MoonPalette` 的三枚插画色；不加载任何图片
/// 背景。星点位置用固定种子生成，动画逐帧重绘也不会闪。
class LoginStage extends StatelessWidget {
  const LoginStage({super.key, required this.arrival, required this.label});

  /// 登舱过渡：0–22% 关门，22–34% 点火，22–100% 离地。
  final Animation<double> arrival;

  /// 左下角的站点标注（由调用方做本地化）。
  final String label;

  @override
  Widget build(BuildContext context) {
    final MoonPalette p = context.moon;
    return ColoredBox(
      color: p.skyTop,
      child: ClipRect(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            final double w = c.maxWidth;
            final double h = c.maxHeight;
            // 火箭按舞台高度收放；窄屏（300 高）也不出画。
            final double rocketWidth = min(240.0, h * 0.44);
            final double rocketHeight = rocketWidth * 649 / 420;
            // 月亮与火箭的几何在动画外算一次：离场时朝月亮中心收缩。
            final double moonR = (min(w, h) * 0.175).clamp(46.0, 92.0).toDouble();
            final Offset moonCenter = Offset(w - moonR - 34, 26 + moonR * 0.72);
            final Offset rocketCenter = Offset(w / 2, h - 96 - rocketHeight / 2);
            // 飞行方向、法线与倾角：机身朝月球转过去，路径带一点外弧，不做直线平移。
            final Offset delta = moonCenter - rocketCenter;
            final double distance = delta.distance;
            final Offset direction = distance == 0 ? const Offset(0, -1) : delta / distance;
            final Offset normal = Offset(-direction.dy, direction.dx);
            // 图标鼻尖朝上：把 (0,-1) 转到 direction 的角度就是机身倾角。
            final double tilt = atan2(direction.dx, -direction.dy);
            return AnimatedBuilder(
              animation: arrival,
              builder: (BuildContext context, Widget? _) {
                final double t = arrival.value;
                final double door = (t / 0.22).clamp(0.0, 1.0);
                final double ignite = ((t - 0.22) / 0.12).clamp(0.0, 1.0);
                // 关闭 → 点火之后朝月亮飞走：位移到月心、缩到约 0.08、淡出。
                // easeIn 让前半段仍看得清，后半段才明显加速，读起来是“越来越远”。
                final double flight =
                    Curves.easeIn.transform(((t - 0.22) / 0.78).clamp(0.0, 1.0));
                // sin(πt) 的弧：两端为零、中段外鼓，避免走成死板的直线。
                final double arc = sin(pi * flight) * distance * 0.06;
                final Offset flightOffset = delta * flight + normal * arc;
                // 倾角提前到位（easeOut），飞的时候机身已经对着月亮。
                final double rotation = tilt * Curves.easeOut.transform(flight);
                return Stack(
                  children: <Widget>[
                    Positioned.fill(child: CustomPaint(painter: _SkyPainter(p))),
                    Positioned(left: 24, top: 20, child: _MonoMark('MN-01', p)),
                    Positioned(right: 24, bottom: 20, child: _MonoMark('T-00:00', p)),
                    Positioned(left: 24, bottom: 20, child: _MonoMark(label, p)),
                    Positioned.fill(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 96),
                          child: Transform.translate(
                            offset: flightOffset,
                            child: Transform.rotate(
                              angle: rotation,
                              child: Transform.scale(
                                scale: 1 - 0.92 * flight,
                                child: Opacity(
                                  opacity: 1 - 0.95 * flight * flight,
                                  child: SizedBox(
                                    width: rocketWidth,
                                    child: AspectRatio(
                                      aspectRatio: 420 / 649,
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: <Widget>[
                                          Opacity(
                                            opacity: 1 - door,
                                            child: Image.asset('assets/rocket-open.png',
                                                fit: BoxFit.contain),
                                          ),
                                          Opacity(
                                            opacity: door * (1 - ignite),
                                            child: Image.asset('assets/rocket-closed.png',
                                                fit: BoxFit.contain),
                                          ),
                                          Opacity(
                                            opacity: ignite,
                                            child: Image.asset('assets/rocket-launch.png',
                                                fit: BoxFit.contain),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// 舞台四角的等宽标注：10px、字距 1.6、亮度压到能读但不抢主体。
class _MonoMark extends StatelessWidget {
  const _MonoMark(this.text, this.p);

  final String text;
  final MoonPalette p;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 10,
        letterSpacing: 1.6,
        color: p.moon.withValues(alpha: 0.66),
        fontFamilyFallback: kMonoFallback,
      ),
    );
  }
}

class _Star {
  const _Star(this.x, this.y, this.r, this.a);

  /// 归一化坐标（0–1）与不透明度：尺寸变化时星点跟着缩放，密度不会变稀。
  final double x;
  final double y;
  final double r;
  final double a;
}

class _Dust {
  const _Dust(this.u, this.v, this.r, this.a);

  /// 银河带局部坐标：`u` 沿带方向（-1..1），`v` 垂直方向（-1..1，中心更密）。
  final double u;
  final double v;
  final double r;
  final double a;
}

class _SkyPainter extends CustomPainter {
  _SkyPainter(this.p);

  final MoonPalette p;

  static final List<_Star> _stars = _buildStars();
  static final List<_Dust> _dust = _buildDust();

  static List<_Star> _buildStars() {
    final Random rng = Random(20261113);
    return List<_Star>.generate(190, (_) {
      final double bright = rng.nextDouble();
      // 大多数是 1px 弱星，少数亮星给画面一点锚点。
      return _Star(
        rng.nextDouble(),
        rng.nextDouble(),
        bright > 0.93 ? 1.5 : 0.5 + rng.nextDouble() * 0.9,
        0.12 + rng.nextDouble() * (bright > 0.93 ? 0.7 : 0.45),
      );
    });
  }

  static List<_Dust> _buildDust() {
    final Random rng = Random(1729);
    return List<_Dust>.generate(220, (_) {
      final double v = (rng.nextDouble() + rng.nextDouble() + rng.nextDouble()) / 1.5 - 1;
      return _Dust(
        rng.nextDouble() * 2 - 1,
        v,
        0.4 + rng.nextDouble() * 0.9,
        0.07 + rng.nextDouble() * 0.26,
      );
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    // ① 夜空底色：登录舞台唯一的渐变，属于插画，不是 UI 表面。
    final Paint sky = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[p.skyTop, p.skyBottom],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), sky);

    // ② 银河：两条倾斜的柔光椭圆 + 沿带的尘埃点。
    _drawBand(canvas, Offset(w * 0.52, h * 0.42), -0.42, w * 0.82, h * 0.22, 0.36);
    _drawBand(canvas, Offset(w * 0.44, h * 0.28), -0.30, w * 0.64, h * 0.14, 0.16);
    _drawBand(canvas, Offset(w * 0.34, h * 0.5), -0.42, w * 0.4, h * 0.1, 0.14);
    final Paint dust = Paint();
    for (final _Dust d in _dust) {
      final double angle = -0.42;
      final double dx = cos(angle) * d.u * w * 0.82 - sin(angle) * d.v * h * 0.22;
      final double dy = sin(angle) * d.u * w * 0.82 + cos(angle) * d.v * h * 0.22;
      dust.color = p.moon.withValues(alpha: d.a);
      canvas.drawCircle(Offset(w * 0.52 + dx, h * 0.42 + dy), d.r, dust);
    }

    // ③ 星点：按舞台面积取前 N 个，窄屏自动稀疏。
    final int count = (w * h / 2800).clamp(40, _stars.length).toInt();
    final Paint star = Paint();
    for (int i = 0; i < count; i++) {
      final _Star s = _stars[i];
      star.color = p.moon.withValues(alpha: s.a);
      canvas.drawCircle(Offset(s.x * w, s.y * h), s.r, star);
    }

    // ④ 月亮：整轮亮面 + 两枚陨石坑 + 一圈光晕。不做偏心暗盘，
    // 那样在深色渐变上会露出暗面的边，读起来像日食而不是月相。
    final double r = (min(w, h) * 0.175).clamp(46.0, 92.0).toDouble();
    final Offset moon = Offset(w - r - 34, 26 + r * 0.72);
    final Paint halo = Paint()
      ..shader = RadialGradient(
        colors: <Color>[p.moon.withValues(alpha: 0.18), p.moon.withValues(alpha: 0)],
      ).createShader(Rect.fromCircle(center: moon, radius: r * 2.8));
    canvas.drawCircle(moon, r * 2.8, halo);
    canvas.drawCircle(moon, r, Paint()..color = p.moon);
    final Paint crater = Paint()..color = p.skyBottom.withValues(alpha: 0.14);
    canvas.drawCircle(moon + Offset(-r * 0.34, r * 0.18), r * 0.15, crater);
    canvas.drawCircle(moon + Offset(-r * 0.12, -r * 0.34), r * 0.085, crater);
    canvas.drawCircle(moon + Offset(-r * 0.5, -r * 0.2), r * 0.055, crater);

    // ⑤ 地平线与发射台：1px 线 + 透视刻度，不画实心地面。
    final double horizon = h - 96;
    final Paint line = Paint()..color = p.moon.withValues(alpha: 0.42);
    canvas.drawRect(Rect.fromLTWH(0, horizon, w, 1), line);
    final double cx = w / 2;
    final Paint guide = Paint()..color = p.moon.withValues(alpha: 0.06);
    for (int i = -8; i <= 8; i++) {
      canvas.drawLine(
        Offset(cx + i * w * 0.035, horizon),
        Offset(cx + i * w * 0.062, h),
        guide,
      );
    }
    final Paint floorLine = Paint()..color = p.moon.withValues(alpha: 0.05);
    for (int step = 1; step <= 3; step++) {
      final double y = horizon + step * 24;
      canvas.drawLine(Offset(0, y), Offset(w, y), floorLine);
    }
    // 发射台台面：一条短横线 + 两根支脚。
    final Paint pad = Paint()..color = p.moon.withValues(alpha: 0.5);
    canvas.drawLine(Offset(cx - 118, horizon), Offset(cx + 118, horizon), pad);
    canvas.drawLine(Offset(cx - 78, horizon), Offset(cx - 78, horizon - 5), pad);
    canvas.drawLine(Offset(cx + 78, horizon), Offset(cx + 78, horizon - 5), pad);
  }

  /// 银河带：横向长椭圆 + 纵向「透明 → 亮 → 透明」的线性渐变。
  /// 用径向渐变会退化成中心一个小圆，压不出横贯画面的带子。
  void _drawBand(Canvas canvas, Offset center, double angle, double halfW, double halfH,
      double alpha) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    final Rect rect = Rect.fromCenter(center: Offset.zero, width: halfW * 2, height: halfH * 2);
    final Paint band = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          p.moon.withValues(alpha: 0),
          p.moon.withValues(alpha: alpha),
          p.moon.withValues(alpha: 0),
        ],
        stops: const <double>[0, 0.5, 1],
      ).createShader(rect);
    canvas.drawOval(rect, band);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SkyPainter oldDelegate) => oldDelegate.p != p;
}
