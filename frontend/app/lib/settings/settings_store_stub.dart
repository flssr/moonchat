import 'settings.dart';

class _MemorySettingsStore implements SettingsStore {
  MoonSettings _settings = MoonSettings.defaults;
  Map<int, String> _avatars = <int, String>{};
  String? _lastEmail;

  @override
  MoonSettings load() => _settings;

  @override
  void save(MoonSettings settings) => _settings = settings;

  @override
  Map<int, String> loadAvatars() => _avatars;

  @override
  void saveAvatars(Map<int, String> avatars) => _avatars = avatars;

  @override
  String? loadLastEmail() => _lastEmail;

  @override
  void saveLastEmail(String email) => _lastEmail = email.trim();
}

SettingsStore createSettingsStore() => _MemorySettingsStore();
