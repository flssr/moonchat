import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// 主按钮只有一种形状：40 高、8 圆角、0 18 内边距（DESIGN-SPEC §6）。
enum MoonButtonKind { primary, secondary, text, danger }

class MoonButton extends StatelessWidget {
  const MoonButton({
    super.key,
    required this.label,
    this.onPressed,
    this.kind = MoonButtonKind.primary,
    this.small = false,
    this.icon,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final MoonButtonKind kind;
  final bool small;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final MoonPalette p = context.moon;
    final bool enabled = onPressed != null && !busy;
    final Color fg = switch (kind) {
      MoonButtonKind.primary => p.bg,
      MoonButtonKind.secondary => p.ink,
      MoonButtonKind.text => p.ink2,
      MoonButtonKind.danger => p.accent,
    };
    final Color bg = switch (kind) {
      MoonButtonKind.primary => p.ink,
      _ => Colors.transparent,
    };
    final Color border = switch (kind) {
      MoonButtonKind.primary => p.ink,
      MoonButtonKind.secondary => p.lineStrong,
      MoonButtonKind.text => Colors.transparent,
      MoonButtonKind.danger => p.accent,
    };

    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: SizedBox(
        height: small ? 30 : 40,
        child: Material(
          color: bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: border),
          ),
          child: InkWell(
            onTap: enabled ? onPressed : null,
            borderRadius: BorderRadius.circular(8),
            hoverColor: p.ink.withValues(alpha: 0.04),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: small ? 12 : 18),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  if (busy)
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: fg),
                    )
                  else if (icon != null)
                    Icon(icon, size: small ? 14 : 16, color: fg),
                  if (busy || icon != null) const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: fg,
                      fontSize: small ? 12 : 13.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 输入：1px 描边、8 圆角、10px 等宽大写标签，焦点加 3px 外环。
class MoonField extends StatefulWidget {
  const MoonField({
    super.key,
    required this.label,
    required this.controller,
    this.obscure = false,
    this.errorText,
    this.hint,
    this.keyboardType,
    this.onSubmitted,
    this.enabled = true,
    this.autofocus = false,
  });

  final String label;
  final TextEditingController controller;
  final bool obscure;
  final String? errorText;
  final String? hint;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final bool autofocus;

  @override
  State<MoonField> createState() => _MoonFieldState();
}

class _MoonFieldState extends State<MoonField> {
  late final FocusNode _focus = FocusNode();
  bool _hidden = true;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
  }

  void _onFocusChanged() => setState(() {});

  @override
  void dispose() {
    _focus
      ..removeListener(_onFocusChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final MoonPalette p = context.moon;
    final bool hasError = widget.errorText != null;
    final Color border = hasError
        ? p.accent
        : _focus.hasFocus
            ? p.ink2
            : p.line;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          widget.label.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 1.1,
            color: p.ink3,
            fontFamilyFallback: kMonoFallback,
          ),
        ),
        const SizedBox(height: 4),
        AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: border),
            boxShadow: _focus.hasFocus
                ? <BoxShadow>[BoxShadow(color: p.accentSoft, spreadRadius: 3)]
                : null,
          ),
          padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focus,
                  enabled: widget.enabled,
                  autofocus: widget.autofocus,
                  obscureText: widget.obscure && _hidden,
                  keyboardType: widget.keyboardType,
                  onSubmitted: widget.onSubmitted,
                  style: TextStyle(fontSize: 14, color: p.ink),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: widget.hint,
                    hintStyle: TextStyle(fontSize: 14, color: p.ink3),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              if (widget.obscure)
                IconButton(
                  onPressed: () => setState(() => _hidden = !_hidden),
                  icon: Icon(
                    _hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    size: 16,
                    color: p.ink3,
                  ),
                  tooltip: _hidden ? '显示密码' : '隐藏密码',
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),
        if (hasError) ...<Widget>[
          const SizedBox(height: 4),
          Text(widget.errorText!, style: TextStyle(fontSize: 11, color: p.accent)),
        ],
      ],
    );
  }
}

/// 头像平台生成：按账号 id 取色，首字占位，不做上传（PRD §5.3）。
class MoonAvatar extends StatelessWidget {
  const MoonAvatar({super.key, required this.name, required this.seed, this.size = 34});

  final String name;
  final int seed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final MoonPalette p = context.moon;
    final int tone = (seed % 5);
    final List<Color> tones = <Color>[p.surface2, p.line, p.bubbleThem, p.bg, p.stage];
    final String initial = name.isEmpty ? '?' : name.characters.first;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tones[tone],
        shape: BoxShape.circle,
        border: Border.all(color: p.lineStrong),
      ),
      child: Text(
        initial,
        style: TextStyle(fontSize: size * 0.4, color: p.ink, fontWeight: FontWeight.w500),
      ),
    );
  }
}

/// 可选胶囊：资料编辑的性别、设置页的字体/语言共用。
class MoonChoicePill extends StatelessWidget {
  const MoonChoicePill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final MoonPalette p = context.moon;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: IntrinsicWidth(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? p.surface2 : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: selected ? p.ink2 : p.line),
              ),
              child: Text(
                label,
                style: TextStyle(fontSize: 12.5, color: selected ? p.ink : p.ink3),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 关系标记：20 高、全圆、1px 描边。
class MoonTag extends StatelessWidget {
  const MoonTag({super.key, required this.text, this.strong = false});

  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final MoonPalette p = context.moon;
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: strong ? p.ink2 : p.ink3),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10.5, color: strong ? p.ink2 : p.ink3),
      ),
    );
  }
}

/// 空状态：左对齐、最大 38ch、不画插画（DESIGN-SPEC §6）。
class MoonEmpty extends StatelessWidget {
  const MoonEmpty({super.key, required this.title, this.hint, this.action});

  final String title;
  final String? hint;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final MoonPalette p = context.moon;
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: TextStyle(fontSize: 15, color: p.ink, fontWeight: FontWeight.w500)),
              if (hint != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(hint!, style: TextStyle(fontSize: 13, height: 1.6, color: p.ink3)),
              ],
              if (action != null) ...<Widget>[
                const SizedBox(height: 16),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 等宽小字：时间、账号 id、密钥。
class MonoText extends StatelessWidget {
  const MonoText(this.text, {super.key, this.size = 10.5, this.color, this.selectable = false});

  final String text;
  final double size;
  final Color? color;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final MoonPalette p = context.moon;
    final TextStyle style = TextStyle(
      fontSize: size,
      color: color ?? p.ink3,
      fontFamilyFallback: kMonoFallback,
      height: 1.3,
    );
    if (selectable) {
      return SelectableText(text, style: style);
    }
    return Text(text, style: style);
  }
}

Future<void> copyText(BuildContext context, String value, String tip) async {
  await Clipboard.setData(ClipboardData(text: value));
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(tip, style: TextStyle(fontSize: 13, color: context.moon.ink)),
      backgroundColor: context.moon.surface,
      duration: const Duration(seconds: 2),
    ),
  );
}

String formatClock(DateTime? utc) {
  if (utc == null) {
    return '';
  }
  final DateTime local = utc.toLocal();
  final String hh = local.hour.toString().padLeft(2, '0');
  final String mm = local.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

/// 列表 + 详情：宽屏并排，容器 ≤620 时上下两段（`DESIGN-SPEC.md` §5）。
/// 断点由外壳统一给出，联系人页与账号页不再各自按父容器宽度算一次。
class MoonSplitLayout extends StatelessWidget {
  const MoonSplitLayout({
    super.key,
    required this.narrow,
    required this.list,
    required this.detail,
  });

  final bool narrow;
  final Widget list;
  final Widget detail;

  @override
  Widget build(BuildContext context) {
    if (narrow) {
      return Column(
        children: <Widget>[
          Expanded(flex: 6, child: list),
          Expanded(flex: 5, child: detail),
        ],
      );
    }
    return Row(
      children: <Widget>[
        SizedBox(width: 320, child: list),
        Expanded(child: detail),
      ],
    );
  }
}
