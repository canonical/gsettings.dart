import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:xdg_directories/xdg_directories.dart';

import 'dconf_client.dart';
import 'gvariant_database.dart';

/// Get the names of the installed GSettings schemas.
/// These schemas can be accessed using a [GSettings] object.
Future<List<String>> listGSettingsSchemas() async {
  var schemaNames = <String>{};
  for (var dir in _getSchemaDirs()) {
    try {
      var database = GVariantDatabase(dir.path + '/gschemas.compiled');
      schemaNames.addAll(await database.list(dir: ''));
    } on FileSystemException {
      continue;
    }
  }
  return schemaNames.toList();
}

/// An object to access settings stored in a GSettings database.
class GSettings {
  /// The name of the schema for these settings, e.g. 'org.gnome.desktop.interface'.
  final String schemaName;

  /// A stream of settings key names as they change.
  Stream<List<String>> get keysChanged => _keysChangedController.stream;
  final _keysChangedController = StreamController<List<String>>();

  // Client for communicating with DConf.
  final DConfClient _dconfClient;

  /// Creates an object to access settings from the shema with name [schemaName].
  GSettings(this.schemaName, {DBusClient? systemBus, DBusClient? sessionBus})
      : _dconfClient =
            DConfClient(systemBus: systemBus, sessionBus: sessionBus) {
    _keysChangedController.onListen = () {
      _load().then((table) {
        var path = _getPath(table);
        _keysChangedController.addStream(_dconfClient.notify
            .map((event) => event.paths.isEmpty
                ? [event.prefix]
                : event.paths.map((path) => event.prefix + path))
            .where((keys) => keys.any((key) => key.startsWith(path)))
            .map((keys) =>
                keys.map((key) => key.substring(path.length)).toList()));
      });
    };
  }

  /// Gets the names of the settings keys available.
  /// If the schema is not installed will throw a [GSettingsSchemaNotInstalledException].
  Future<List<String>> list() async {
    var table = await _load();
    return table.list(dir: '', type: 'v');
  }

  /// Reads the value of the settings key with [name].
  /// Attempting to read an unknown key will throw a [GSettingsUnknownKeyException].
  /// If the schema is not installed will throw a [GSettingsSchemaNotInstalledException].
  Future<DBusValue> get(String name) async {
    var table = await _load();
    var schemaEntry = table.lookup(name);
    if (schemaEntry == null) {
      throw GSettingsUnknownKeyException(schemaName, name);
    }
    var path = _getPath(table);

    // Lookup user value in DConf.
    var value = await _dconfClient.read(path + name);
    if (value != null) {
      return value;
    }

    // Return default value.
    return (schemaEntry as DBusStruct).children[0];
  }

  /// Writes new values to settings keys.
  /// Writing a null value will reset it to its default value.
  Future<void> set(Map<String, DBusValue?> values) async {
    var table = await _load();
    var path = _getPath(table);

    await _dconfClient
        .write(values.map((name, value) => MapEntry(path + name, value)));
  }

  /// Terminates any open connections. If a settings object remains unclosed, the Dart process may not terminate.
  Future<void> close() async {
    await _dconfClient.close();
  }

  // Get the database entry for this schema.
  Future<GVariantDatabaseTable> _load() async {
    for (var dir in _getSchemaDirs()) {
      var database = GVariantDatabase(dir.path + '/gschemas.compiled');
      try {
        var table = await database.lookupTable(schemaName);
        if (table != null) {
          return table;
        }
      } on FileSystemException {
        continue;
      }
    }

    throw GSettingsSchemaNotInstalledException(schemaName);
  }

  // Get the key path from the database table.
  String _getPath(GVariantDatabaseTable table) {
    var pathValue = table.lookup('.path');
    if (pathValue == null) {
      throw ('Unable to determine path for schema $schemaName');
    }
    return (pathValue as DBusString).value;
  }
}

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

/// Exception thrown when trying to access a GSettings schema that is not installed.
class GSettingsSchemaNotInstalledException implements Exception {
  /// The name of the GSettings schema that was being accessed.
  final String schemaName;

  const GSettingsSchemaNotInstalledException(this.schemaName);

  @override
  String toString() => 'GSettings schema $schemaName not installed';
}

/// Exception thrown when trying to access a key not in a GSettings schema.
class GSettingsUnknownKeyException implements Exception {
  /// The name of the GSettings schema that was being accessed.
  final String schemaName;

  /// The name of the key being accessed.
  final String keyName;

  const GSettingsUnknownKeyException(this.schemaName, this.keyName);

  @override
  String toString() => 'Key $keyName not in GSettings schema $schemaName';
}
