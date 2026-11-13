import 'package:flutter/material.dart';

/// 设计 token 的唯一出处：数值全部取自 `docs/frontend/DESIGN-SPEC.md` §2–§6。
/// 组件只引用这里的语义名，不写死十六进制。
@immutable
class MoonPalette extends ThemeExtension<MoonPalette> {
  const MoonPalette({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.stage,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.line,
    required this.lineStrong,
    required this.accent,
    required this.accentInk,
    required this.accentSoft,
    required this.bubbleThem,
    required this.bubbleMe,
    required this.flash,
  });

  final Color bg;
  final Color surface;
  final Color surface2;
  final Color stage;
  final Color ink;
  final Color ink2;
  final Color ink3;
  final Color line;
  final Color lineStrong;
  final Color accent;
  final Color accentInk;
  final Color accentSoft;
  final Color bubbleThem;
  final Color bubbleMe;
  final Color flash;

  static const MoonPalette light = MoonPalette(
    bg: Color(0xFFF3F1EC),
    surface: Color(0xFFFAF9F6),
    surface2: Color(0xFFEAE7DF),
    stage: Color(0xFFE6E2D9),
    ink: Color(0xFF1A1917),
    ink2: Color(0xFF56534C),
    ink3: Color(0xFF69645A),
    line: Color(0xFFDCD7CC),
    lineStrong: Color(0xFFC8C2B3),
    accent: Color(0xFFA9432C),
    accentInk: Color(0xFFFAF7F1),
    accentSoft: Color(0x17A9432C),
    bubbleThem: Color(0xFFEFEBE3),
    bubbleMe: Color(0xFFEAE7DF),
    flash: Color(0xFFFFFEFB),
  );

  static const MoonPalette dark = MoonPalette(
    bg: Color(0xFF12110F),
    surface: Color(0xFF191816),
    surface2: Color(0xFF232120),
    stage: Color(0xFF181715),
    ink: Color(0xFFEDE9E1),
    ink2: Color(0xFFA9A49A),
    ink3: Color(0xFF8F8A80),
    line: Color(0xFF2B2926),
    lineStrong: Color(0xFF3D3A34),
    accent: Color(0xFFD2684C),
    accentInk: Color(0xFF1B110D),
    accentSoft: Color(0x21D2684C),
    bubbleThem: Color(0xFF211F1D),
    bubbleMe: Color(0xFF232120),
    flash: Color(0xFFECE7DC),
  );

  @override
  MoonPalette copyWith({
    Color? bg,
    Color? surface,
    Color? surface2,
    Color? stage,
    Color? ink,
    Color? ink2,
    Color? ink3,
    Color? line,
    Color? lineStrong,
    Color? accent,
    Color? accentInk,
    Color? accentSoft,
    Color? bubbleThem,
    Color? bubbleMe,
    Color? flash,
  }) {
    return MoonPalette(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      stage: stage ?? this.stage,
      ink: ink ?? this.ink,
      ink2: ink2 ?? this.ink2,
      ink3: ink3 ?? this.ink3,
      line: line ?? this.line,
      lineStrong: lineStrong ?? this.lineStrong,
      accent: accent ?? this.accent,
      accentInk: accentInk ?? this.accentInk,
      accentSoft: accentSoft ?? this.accentSoft,
      bubbleThem: bubbleThem ?? this.bubbleThem,
      bubbleMe: bubbleMe ?? this.bubbleMe,
      flash: flash ?? this.flash,
    );
  }

  @override
  MoonPalette lerp(ThemeExtension<MoonPalette>? other, double t) {
    if (other is! MoonPalette) {
      return this;
    }
    return MoonPalette(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      stage: Color.lerp(stage, other.stage, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      ink2: Color.lerp(ink2, other.ink2, t)!,
      ink3: Color.lerp(ink3, other.ink3, t)!,
      line: Color.lerp(line, other.line, t)!,
      lineStrong: Color.lerp(lineStrong, other.lineStrong, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentInk: Color.lerp(accentInk, other.accentInk, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      bubbleThem: Color.lerp(bubbleThem, other.bubbleThem, t)!,
      bubbleMe: Color.lerp(bubbleMe, other.bubbleMe, t)!,
      flash: Color.lerp(flash, other.flash, t)!,
    );
  }
}

extension MoonColorsX on BuildContext {
  /// 取不到扩展时按亮度回退，而不是让整个子树在 build 里崩。
  MoonPalette get moon =>
      Theme.of(this).extension<MoonPalette>() ??
      (Theme.of(this).brightness == Brightness.dark ? MoonPalette.dark : MoonPalette.light);
}

/// 字体：系统字体栈，不加载网络字体（DESIGN-SPEC §3）。
const List<String> kSansFallback = <String>[
  'Segoe UI Variable Text',
  'Segoe UI',
  'PingFang SC',
  'Hiragino Sans GB',
  'Microsoft YaHei',
  'system-ui',
];

const List<String> kMonoFallback = <String>[
  'Cascadia Mono',
  'Consolas',
  'SF Mono',
  'Liberation Mono',
  'monospace',
];

/// 容器断点：单点定义，代码与 `DESIGN-SPEC.md` §5 对齐。
class MoonBreakpoints {
  const MoonBreakpoints._();

  static const double hideInfo = 860;
  static const double hideList = 620;
}

ThemeData buildMoonTheme(Brightness brightness) {
  final MoonPalette p = brightness == Brightness.light ? MoonPalette.light : MoonPalette.dark;
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: p.accent,
    brightness: brightness,
  ).copyWith(
    surface: p.surface,
    onSurface: p.ink,
    primary: p.ink,
    onPrimary: p.bg,
    error: p.accent,
    onError: p.accentInk,
    outline: p.lineStrong,
    outlineVariant: p.line,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.surface,
    fontFamilyFallback: kSansFallback,
    visualDensity: VisualDensity.standard,
    splashFactory: NoSplash.splashFactory,
    extensions: <ThemeExtension<dynamic>>[p],
    textTheme: TextTheme(
      bodyMedium: TextStyle(fontSize: 15, height: 1.68, color: p.ink, fontFamilyFallback: kSansFallback),
      bodySmall: TextStyle(fontSize: 12, height: 1.65, color: p.ink3, fontFamilyFallback: kSansFallback),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.ink, fontFamilyFallback: kSansFallback),
      titleSmall: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: p.ink, fontFamilyFallback: kSansFallback),
      labelSmall: TextStyle(fontSize: 10, color: p.ink3, letterSpacing: 1.0, fontFamilyFallback: kMonoFallback),
    ),
    dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
  );
}
