import 'package:flutter/material.dart';

import '../i18n/moon_strings.dart';
import '../settings/settings.dart';
import '../theme.dart';
import 'widgets.dart';

/// 设置：字体、界面语言、隐私入口。字体与语言立即生效。
Future<void> showSettingsDialog(
  BuildContext context, {
  required double textScale,
  required ThemeMode themeMode,
  required ValueChanged<ThemeMode> onThemeModeChanged,
  required ValueChanged<double> onTextScaleChanged,
  required ValueChanged<String> onLanguageChanged,
  bool notifyOnMessage = true,
  ValueChanged<bool>? onNotifyChanged,
  Future<void> Function()? onOpenBlocklist,
  Future<void> Function()? onDeleteAccount,
}) async {
  await showDialog<void>(
    context: context,
    builder: (BuildContext context) => _SettingsDialog(
      textScale: textScale,
      themeMode: themeMode,
      onThemeModeChanged: onThemeModeChanged,
      onTextScaleChanged: onTextScaleChanged,
      onLanguageChanged: onLanguageChanged,
      notifyOnMessage: notifyOnMessage,
      onNotifyChanged: onNotifyChanged,
      onOpenBlocklist: onOpenBlocklist,
      onDeleteAccount: onDeleteAccount,
    ),
  );
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({
    required this.textScale,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.onTextScaleChanged,
    required this.onLanguageChanged,
    required this.notifyOnMessage,
    required this.onNotifyChanged,
    this.onOpenBlocklist,
    this.onDeleteAccount,
  });

  final double textScale;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<double> onTextScaleChanged;
  final ValueChanged<String> onLanguageChanged;
  final bool notifyOnMessage;
  final ValueChanged<bool>? onNotifyChanged;
  final Future<void> Function()? onOpenBlocklist;
  final Future<void> Function()? onDeleteAccount;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late double _textScale = widget.textScale;
  late bool _notify = widget.notifyOnMessage;
  late ThemeMode _themeMode = widget.themeMode;
  String? _language;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 只在第一次拿当前语言；之后的重建不覆盖用户刚点的选项。
    _language ??= Localizations.localeOf(context).languageCode;
  }

  static const List<(double, String)> _sizes = kTextScaleOptions;

  static const List<(String, String)> _languages = kMoonLanguages;

  String _t(String zh) => moonText(_language!, zh);

  void _setTextScale(double value) {
    setState(() => _textScale = value);
    widget.onTextScaleChanged(value);
  }

  void _setLanguage(String value) {
    setState(() => _language = value);
    widget.onLanguageChanged(value);
  }

  void _setThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
    widget.onThemeModeChanged(mode);
  }

  void _setNotify(bool value) {
    setState(() => _notify = value);
    widget.onNotifyChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final MoonPalette p = context.moon;
    final double maxHeight = MediaQuery.sizeOf(context).height * 0.86;
    return Dialog(
      backgroundColor: p.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: p.line),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 440, maxHeight: maxHeight),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    _t('设置'),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: p.ink,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: _t('关闭'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, size: 16, color: p.ink3),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(_t('字体'), style: _labelStyle(p)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final (double value, String label) in _sizes)
                    MoonChoicePill(
                      label: _t(label),
                      selected: (_textScale - value).abs() < kTextScaleEpsilon,
                      onTap: () => _setTextScale(value),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              Text(_t('语言'), style: _labelStyle(p)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final (String code, String label) in _languages)
                    MoonChoicePill(
                      label: label,
                      selected: _language == code,
                      onTap: () => _setLanguage(code),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              Text(_t('主题'), style: _labelStyle(p)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final (ThemeMode mode, String label) in <(ThemeMode, String)>[
                    (ThemeMode.light, '浅色'),
                    (ThemeMode.dark, '深色'),
                    (ThemeMode.system, '跟随系统'),
                  ])
                    MoonChoicePill(
                      label: _t(label),
                      selected: _themeMode == mode,
                      onTap: () => _setThemeMode(mode),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              Text(_t('消息通知'), style: _labelStyle(p)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  MoonChoicePill(
                    label: _t('收到消息并且提示'),
                    selected: _notify,
                    onTap: () => _setNotify(true),
                  ),
                  MoonChoicePill(
                    label: _t('收到消息不提示'),
                    selected: !_notify,
                    onTap: () => _setNotify(false),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Text(_t('隐私'), style: _labelStyle(p)),
              const SizedBox(height: 4),
              _PrivacyRow(
                label: _t('黑名单管理'),
                onTap: widget.onOpenBlocklist,
                trailing: Icon(Icons.chevron_right, size: 16, color: p.ink3),
              ),
              Divider(color: p.line, height: 1),
              _PrivacyRow(
                label: _t('我的友情关系'),
                trailing: MoonTag(text: _t('敬请期待')),
              ),
              if (widget.onDeleteAccount != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(_t('账号'), style: _labelStyle(p)),
                const SizedBox(height: 4),
                _PrivacyRow(
                  label: _t('注销账号'),
                  danger: true,
                  onTap: widget.onDeleteAccount,
                  trailing: Icon(Icons.chevron_right, size: 16, color: p.ink3),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  TextStyle _labelStyle(MoonPalette p) => TextStyle(
    fontSize: 10,
    letterSpacing: 1.1,
    color: p.ink3,
    fontFamilyFallback: kMonoFallback,
  );
}

class _PrivacyRow extends StatelessWidget {
  const _PrivacyRow({
    required this.label,
    required this.trailing,
    this.onTap,
    this.danger = false,
  });

  final String label;
  final Widget trailing;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final MoonPalette p = context.moon;
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 13, color: danger ? p.accent : p.ink),
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}
