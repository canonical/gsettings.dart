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
Future<List<String>> listGSettingss() async {
  var database =
      GVariantDatabase('/usr/share/glib-2.0/schemas/gschemas.compiled');
  return database.list(dir: '');
}

/// A GSettings schema.
class GSettings {
  /// The name of this schema, e.g. 'org.gnome.desktop.interface'.
  final String name;

  /// Create a new GSettings schema with [name].
  GSettings(this.name);

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

    // Get path key is stored in backed.
    var pathValue = table.lookup('.path');
    if (pathValue == null) {
      throw ('Unable to determine path for schema ${this.name}');
    }
    var path = (pathValue as DBusString).value;

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
    var pathValue = table.lookup('.path');
    if (pathValue == null) {
      throw ('Unable to determine path for schema $name');
    }
    var path = (pathValue as DBusString).value;

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
}
