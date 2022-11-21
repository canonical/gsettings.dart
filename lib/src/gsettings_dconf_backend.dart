import 'package:dbus/dbus.dart';

import 'dconf_client.dart';
import 'gsettings_backend.dart';

/// GSettings backend that reads/writes values in DConf
class GSettingsDConfBackend implements GSettingsBackend {
  // Client for communicating with DConf.
  final DConfClient _dconfClient;

  @override
  Stream<List<String>> get valuesChanged =>
      _dconfClient.notify.map((event) => event.paths.isEmpty
          ? [event.prefix]
          : event.paths.map((path) => event.prefix + path).toList());

  GSettingsDConfBackend({DBusClient? systemBus, DBusClient? sessionBus})
      : _dconfClient =
            DConfClient(systemBus: systemBus, sessionBus: sessionBus);

  @override
  Future<DBusValue?> get(String path) async {
    return await _dconfClient.read(path);
  }

  @override
  Future<void> set(Map<String, DBusValue?> values) async {
    await _dconfClient
        .write(values.map((path, value) => MapEntry(path, value)));
  }

  @override
  Future<void> close() async {
    await _dconfClient.close();
  }
}
