import 'settings.dart';
import 'settings_store_stub.dart'
    if (dart.library.js_interop) 'settings_store_web.dart' as impl;

SettingsStore createSettingsStore() => impl.createSettingsStore();
