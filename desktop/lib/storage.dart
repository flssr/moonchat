import 'dart:convert';
import 'dart:io';

import 'package:mondchat/avatars.dart';
import 'package:mondchat/message_cache.dart';
import 'package:mondchat/session/session_store.dart';
import 'package:mondchat/settings/settings.dart';

/// Web 用 localStorage，Windows 换成本机文件，语义保持一致（见 `docs/truth/frontend/`）。
///
/// 目录是 `%APPDATA%\MondChat`。文件都只有几百字节，读写同步做：启动读一次、改动写一次。
/// 读写失败只影响下一次启动（设置回默认、要求重新登录），不阻断当前会话，
/// 所以这里吞掉异常 —— 与 Web 的隐私模式 / 配额满同一种处理。
Directory? _appDataDir() {
  final String? appData = Platform.environment['APPDATA'];
  return appData == null || appData.isEmpty ? null : Directory('$appData\\MondChat');
}

class _JsonFile {
  _JsonFile(this._file);

  final File _file;

  Object? read() {
    try {
      if (!_file.existsSync()) {
        return null;
      }
      return jsonDecode(_file.readAsStringSync());
    } catch (_) {
      return null;
    }
  }

  void write(Object? value) {
    try {
      _file.parent.createSync(recursive: true);
      _file.writeAsStringSync(jsonEncode(value));
    } catch (_) {
      // 存不下就在本次进程里生效。
    }
  }

  void delete() {
    try {
      if (_file.existsSync()) {
        _file.deleteSync();
      }
    } catch (_) {
      // 同上。
    }
  }
}

class DesktopSettingsStore implements SettingsStore {
  DesktopSettingsStore({Directory? dir}) {
    final Directory? root = dir ?? _appDataDir();
    if (root != null) {
      _settings = _JsonFile(File('${root.path}\\settings.json'));
      _avatars = _JsonFile(File('${root.path}\\avatars.json'));
    }
  }

  _JsonFile? _settings;
  _JsonFile? _avatars;
  MoonSettings _settingsValue = MoonSettings.defaults;
  bool _settingsLoaded = false;
  final Map<int, String> _avatarValues = <int, String>{};
  bool _avatarsLoaded = false;

  @override
  MoonSettings load() {
    if (_settingsLoaded) {
      return _settingsValue;
    }
    _settingsLoaded = true;
    final Object? raw = _settings?.read();
    if (raw is Map<String, dynamic>) {
      _settingsValue = MoonSettings.fromJson(raw);
    }
    return _settingsValue;
  }

  @override
  void save(MoonSettings settings) {
    _settingsValue = settings;
    _settingsLoaded = true;
    _settings?.write(settings.toJson());
  }

  @override
  Map<int, String> loadAvatars() {
    if (_avatarsLoaded) {
      return _avatarValues;
    }
    _avatarsLoaded = true;
    final Object? raw = _avatars?.read();
    if (raw is Map<String, dynamic>) {
      raw.forEach((String id, Object? key) {
        final int? accountId = int.tryParse(id);
        // 本地数据是信任边界：不认识的 key 当没选过。
        if (accountId != null && key is String && isKnownAvatar(key)) {
          _avatarValues[accountId] = key;
        }
      });
    }
    return _avatarValues;
  }

  @override
  void saveAvatars(Map<int, String> avatars) {
    _avatarValues
      ..clear()
      ..addAll(avatars);
    _avatarsLoaded = true;
    _avatars?.write(
      avatars.map((int id, String key) => MapEntry<String, String>('$id', key)),
    );
  }
}

class DesktopMessageCacheStore implements MessageCacheStore {
  DesktopMessageCacheStore({Directory? dir}) {
    final Directory? root = dir ?? _appDataDir();
    if (root != null) {
      _file = _JsonFile(File('${root.path}\\cache.json'));
    }
  }

  _JsonFile? _file;
  Map<String, dynamic> _all = <String, dynamic>{};
  bool _loaded = false;

  void _ensureLoaded() {
    if (_loaded) {
      return;
    }
    _loaded = true;
    final Object? raw = _file?.read();
    if (raw is Map<String, dynamic>) {
      _all = raw;
    }
  }

  @override
  Map<String, dynamic>? load(int accountId) {
    _ensureLoaded();
    final Object? value = _all['$accountId'];
    return value is Map<String, dynamic> ? value : null;
  }

  @override
  void save(int accountId, Map<String, dynamic> data) {
    _ensureLoaded();
    _all['$accountId'] = data;
    _file?.write(_all);
  }
}

class DesktopSessionStore implements SessionStore {
  DesktopSessionStore({Directory? dir}) {
    final Directory? root = dir ?? _appDataDir();
    if (root != null) {
      // 登录 JWT 明文落在当前用户目录：Windows 用户配置目录默认只有本人可读。
      _file = _JsonFile(File('${root.path}\\session.json'));
    }
  }

  _JsonFile? _file;
  StoredSession? _session;
  bool _loaded = false;

  @override
  StoredSession? load() {
    if (_loaded) {
      return _session;
    }
    _loaded = true;
    final Object? raw = _file?.read();
    if (raw is Map<String, dynamic>) {
      _session = StoredSession.fromJson(raw);
    }
    return _session;
  }

  @override
  void save(StoredSession session) {
    _session = session;
    _loaded = true;
    _file?.write(session.toJson());
  }

  @override
  void clear() {
    _session = null;
    _loaded = true;
    _file?.delete();
  }
}
