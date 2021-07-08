import 'dart:async';

import 'gvariant_database.dart';

/// Get the names of the installed schemas.
Future<List<String>> listGSettingsSchemas() async {
  var database =
      GVariantDatabase('/usr/share/glib-2.0/schemas/gschemas.compiled');
  return database.list('');
}

class GSettingsSchema {
  final String name;
  late final GVariantDatabaseTable _table;
  late final List<String> _keys;

  GSettingsSchema(this.name);

  Future<void> load() async {
    var database =
        GVariantDatabase('/usr/share/glib-2.0/schemas/gschemas.compiled');
    var table = await database.lookupTable(name);
    if (table == null) {
      throw ('Schema $name not installed');
    }
    _table = table;
    _keys = table.list('', 'v');

    print(table.lookup(_keys[0]));
  }
}
