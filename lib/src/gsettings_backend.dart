import 'package:dbus/dbus.dart';

/// Abstract class that all GSettings backends conform to.
abstract class GSettingsBackend {
  /// Stream containing paths as their values change.
  Stream<List<String>> get valuesChanged;

  /// Get the value at [path] if it exists.
  Future<DBusValue?> get(String path);

  /// Sets multiple values.
  Future<void> set(Map<String, DBusValue?> values);

  /// Close the backend.
  Future<void> close();
}
