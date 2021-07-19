import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:xdg_directories/xdg_directories.dart';

import 'dconf_client.dart';
import 'gvariant_database.dart';

// Get the directories that contain schemas.
List<Directory> _getSchemaDirs() {
  var schemaDirs = <Directory>[];

  var schemaDir = Platform.environment['GSETTINGS_SCHEMA_DIR'];
  if (schemaDir != null) {
    schemaDirs.add(Directory(schemaDir));
  }

  for (var dataDir in dataDirs) {
    var path = dataDir.path;
    if (!path.endsWith('/')) {
      path += '/';
    }
    path += 'glib-2.0/schemas';
    schemaDirs.add(Directory(path));
  }
  return schemaDirs;
}

/// Get the names of the installed schemas.
Future<List<String>> listGSettingsSchemas() async {
  var database =
      GVariantDatabase('/usr/share/glib-2.0/schemas/gschemas.compiled');
  return database.list(dir: '');
}

/// A GSettings schema.
class GSettings {
  /// The name of this schema, e.g. 'org.gnome.desktop.interface'.
  final String name;

  /// Stream of keys that have changed.
  Stream<List<String>> get keysChanged => _keysChangedController.stream;
  final _keysChangedController = StreamController<List<String>>();

  /// Create a new GSettings schema with [name].
  GSettings(this.name) {
    _keysChangedController.onListen = () {
      _load().then((table) {
        var client = DConfClient();
        var path = _getPath(table);
        _keysChangedController.addStream(client.notify
            .map((event) => event.paths.isEmpty
                ? [event.prefix]
                : event.paths.map((path) => event.prefix + path))
            .where((keys) => keys.any((key) => key.startsWith(path)))
            .map((keys) =>
                keys.map((key) => key.substring(path.length)).toList()));
      });
    };
  }

  /// Gets the keys in this schema.
  Future<List<String>> list() async {
    var table = await _load();
    return table.list(dir: '', type: 'v');
  }

  /// Gets the value of a key in this schema.
  Future<DBusValue> get(String name) async {
    var table = await _load();
    var schemaEntry = table.lookup(name);
    if (schemaEntry == null) {
      throw ('Key $name not in GSettings schema ${this.name}');
    }
    var path = _getPath(table);

    // Lookup user value in DConf.
    var client = DConfClient();
    var value = await client.read(path + name);
    await client.close();
    if (value != null) {
      return value;
    }

    // Return default value.
    return (schemaEntry as DBusStruct).children[0];
  }

  /// Sets keys in the schema.
  Future<void> set(Map<String, DBusValue> values) async {
    var table = await _load();
    var path = _getPath(table);

    var client = DConfClient();
    await client
        .write(values.map((name, value) => MapEntry(path + name, value)));
    await client.close();
  }

  // Get the database entry for this schema.
  Future<GVariantDatabaseTable> _load() async {
    for (var dir in _getSchemaDirs()) {
      var database = GVariantDatabase(dir.path + '/gschemas.compiled');
      try {
        var table = await database.lookupTable(name);
        if (table != null) {
          return table;
        }
      } on FileSystemException {
        continue;
      }
    }

    throw ('GSettings schema $name not installed');
  }

  // Get the key path from the database table.
  String _getPath(GVariantDatabaseTable table) {
    var pathValue = table.lookup('.path');
    if (pathValue == null) {
      throw ('Unable to determine path for schema $name');
    }
    return (pathValue as DBusString).value;
  }
}
