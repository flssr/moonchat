import 'package:flutter/material.dart';

import '../i18n/moon_strings.dart';
import '../theme.dart';
import 'widgets.dart';

/// 设置：字体、界面语言、隐私入口。字体与语言立即生效，隐私项等后端接口。
Future<void> showSettingsDialog(
  BuildContext context, {
  required double textScale,
  required String languageCode,
  required ValueChanged<double> onTextScaleChanged,
  required ValueChanged<String> onLanguageChanged,
}) async {
  await showDialog<void>(
    context: context,
    builder: (BuildContext context) => _SettingsDialog(
      textScale: textScale,
      languageCode: languageCode,
      onTextScaleChanged: onTextScaleChanged,
      onLanguageChanged: onLanguageChanged,
    ),
  );
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({
    required this.textScale,
    required this.languageCode,
    required this.onTextScaleChanged,
    required this.onLanguageChanged,
  });

  final double textScale;
  final String languageCode;
  final ValueChanged<double> onTextScaleChanged;
  final ValueChanged<String> onLanguageChanged;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late double _textScale = widget.textScale;
  late String _language = widget.languageCode;

  static const List<(double, String)> _sizes = <(double, String)>[
    (0.9, '小'),
    (1.0, '中'),
    (1.12, '大'),
  ];

  static const List<(String, String)> _languages = kMoonLanguages;

  String _t(String zh) => moonText(_language, zh);

  void _setTextScale(double value) {
    setState(() => _textScale = value);
    widget.onTextScaleChanged(value);
  }

  void _setLanguage(String value) {
    setState(() => _language = value);
    widget.onLanguageChanged(value);
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
                      selected: (_textScale - value).abs() < 0.001,
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
              Text(_t('隐私'), style: _labelStyle(p)),
              const SizedBox(height: 4),
              _PrivacyRow(
                label: _t('黑名单管理'),
                trailing: MoonTag(text: _t('待接入')),
              ),
              Divider(color: p.line, height: 1),
              _PrivacyRow(
                label: _t('我的友情关系'),
                trailing: MoonTag(text: _t('敬请期待')),
              ),
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
  const _PrivacyRow({required this.label, required this.trailing});

  final String label;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final MoonPalette p = context.moon;
    return SizedBox(
      height: 48,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 13, color: p.ink)),
          ),
          trailing,
        ],
      ),
    );
  }
}
