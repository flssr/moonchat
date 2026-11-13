import 'settings.dart';

class _MemorySettingsStore implements SettingsStore {
  MoonSettings _settings = MoonSettings.defaults;

  @override
  MoonSettings load() => _settings;

  @override
  void save(MoonSettings settings) => _settings = settings;
}

SettingsStore createSettingsStore() => _MemorySettingsStore();
