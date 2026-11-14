import 'settings.dart';

class _MemorySettingsStore implements SettingsStore {
  MoonSettings _settings = MoonSettings.defaults;
  Map<int, String> _avatars = <int, String>{};

  @override
  MoonSettings load() => _settings;

  @override
  void save(MoonSettings settings) => _settings = settings;

  @override
  Map<int, String> loadAvatars() => _avatars;

  @override
  void saveAvatars(Map<int, String> avatars) => _avatars = avatars;
}

SettingsStore createSettingsStore() => _MemorySettingsStore();
