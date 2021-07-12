import 'dart:async';

import 'package:dbus/dbus.dart';

import 'dconf_client.dart';
import 'gvariant_database.dart';

/// Get the names of the installed schemas.
Future<List<String>> listGSettingsSchemas() async {
  var database =
      GVariantDatabase('/usr/share/glib-2.0/schemas/gschemas.compiled');
  return database.list(dir: '');
}

class GSettingsSchema {
  final String name;

  GSettingsSchema(this.name);

  Future<GVariantDatabaseTable> _load() async {
    var database =
        GVariantDatabase('/usr/share/glib-2.0/schemas/gschemas.compiled');
    var table = await database.lookupTable(name);
    if (table == null) {
      throw ('GSettings schema $name not installed');
    }
    table.list(dir: '');

    return table;
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

    // Get path key is stored in backed.
    var pathValue = table.lookup('.path');
    if (pathValue == null) {
      throw ('Unable to determine path for schema ${this.name}');
    }
    var path = (pathValue as DBusString).value;

    // Lookup user value in DConf.
    var client = DConfClient();
    var value = await client.lookup(path + name);
    await client.close();
    if (value != null) {
      return value;
    }

    // Return default value.
    return (schemaEntry as DBusStruct).children[0];
  }
}
