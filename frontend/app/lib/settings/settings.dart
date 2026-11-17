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
    this.notifyOnMessage = true,
  });

  static const MoonSettings defaults = MoonSettings();

  final double textScale;
  final String languageCode;
  final ThemeMode themeMode;

  /// 收到消息时是否弹桌面通知；列表里的未读/预览不受这个开关影响。
  final bool notifyOnMessage;

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
    return MoonSettings(
      textScale: scale,
      languageCode: language,
      themeMode: theme,
      notifyOnMessage: json['notify'] != false,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'text_scale': textScale,
        'language': languageCode,
        'theme': switch (themeMode) {
          ThemeMode.light => 'light',
          ThemeMode.dark => 'dark',
          ThemeMode.system => 'system',
        },
        'notify': notifyOnMessage,
      };
}

abstract interface class SettingsStore {
  MoonSettings load();
  void save(MoonSettings settings);

  /// 头像偏好：账号 id → 默认头像 key（`avatars.dart`）。服务端还没有这一列（issue #10），
  /// 所以跟着设备走，不跟账号走。
  Map<int, String> loadAvatars();
  void saveAvatars(Map<int, String> avatars);
}
