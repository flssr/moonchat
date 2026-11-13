import 'package:flutter/material.dart';

import '../i18n/moon_strings.dart';

/// 设置页的三档字号，UI 与持久化校验共用。
const double kTextScaleEpsilon = 0.001;

const List<(double, String)> kTextScaleOptions = <(double, String)>[
  (0.9, '小'),
  (1.0, '中'),
  (1.12, '大'),
];

double? canonicalTextScale(double value) {
  for (final (double option, String _) in kTextScaleOptions) {
    if ((option - value).abs() < kTextScaleEpsilon) {
      return option;
    }
  }
  return null;
}

@immutable
class MoonSettings {
  const MoonSettings({
    this.textScale = 1.0,
    this.languageCode = 'zh',
    this.themeMode = ThemeMode.system,
  });

  static const MoonSettings defaults = MoonSettings();

  final double textScale;
  final String languageCode;
  final ThemeMode themeMode;

  /// 本地偏好是信任边界：只接受三档字号、四门语言和三种主题，其他值回默认。
  factory MoonSettings.fromJson(Map<String, dynamic> json) {
    final Object? rawScaleValue = json['text_scale'];
    final double rawScale = rawScaleValue is num ? rawScaleValue.toDouble() : 1.0;
    final double scale = canonicalTextScale(rawScale) ?? 1.0;

    final Object? rawLanguageValue = json['language'];
    final String rawLanguage = rawLanguageValue is String ? rawLanguageValue : 'zh';
    final String language =
        kMoonLanguages.any(((String, String) item) => item.$1 == rawLanguage)
            ? rawLanguage
            : 'zh';

    final Object? rawTheme = json['theme'];
    final ThemeMode theme = switch (rawTheme) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    return MoonSettings(textScale: scale, languageCode: language, themeMode: theme);
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'text_scale': textScale,
        'language': languageCode,
        'theme': switch (themeMode) {
          ThemeMode.light => 'light',
          ThemeMode.dark => 'dark',
          ThemeMode.system => 'system',
        },
      };
}

abstract interface class SettingsStore {
  MoonSettings load();
  void save(MoonSettings settings);
}
