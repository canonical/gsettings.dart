import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:xdg_directories/xdg_directories.dart';

import 'gvariant_database.dart';

/// A client that connects to DConf.
class DConfClient {
  /// The bus this client is connected to.
  final DBusClient _bus;
  final bool _closeBus;

  /// The D-Bus DConf write object.
  //late final DBusRemoteObject _writer;

  late final GVariantDatabase _database;

  /// Creates a new DConf client.
  DConfClient({DBusClient? bus})
      : _bus = bus ?? DBusClient.session(),
        _closeBus = bus == null {
    //_writer = DBusRemoteObject(
    //    _bus, 'ca.desrt.dconf', DBusObjectPath('/ca/desrt/dconf/Writer/user'));
    //_database = GVariantDatabase(
    //    '/usr/share/glib-2.0/schemas/gschemas.compiled');
    _database = GVariantDatabase(configHome.path + '/dconf/user');
  }

  Future<List<String>> list(String dir) async {
    return _database.list(dir);
  }

  Future<DBusValue?> lookup(String key) async {
    return _database.lookup(key);
  }

  /// Terminates the connection to the DConf daemon. If a client remains unclosed, the Dart process may not terminate.
  Future<void> close() async {
    if (_closeBus) {
      await _bus.close();
    }
  }
}
