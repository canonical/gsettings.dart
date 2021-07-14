import 'dart:async';
import 'dart:typed_data';

import 'package:dbus/dbus.dart';
import 'package:xdg_directories/xdg_directories.dart';

import 'gvariant_binary_codec.dart';
import 'gvariant_database.dart';

/// Message received when DConf notifies changes.
class DConfNotifyEvent {
  final String prefix;

  final List<String> paths;

  /// Unique tag for this change, used to detect if this client generated the change.
  final String tag;

  const DConfNotifyEvent(this.prefix, this.paths, this.tag);

  @override
  String toString() => "DConfNotifyEvent('$prefix', $paths, '$tag')";
}

/// A client that connects to DConf.
class DConfClient {
  /// Stream of key names that indicate when a value has changed.
  late final Stream<DConfNotifyEvent> notify;

  /// The bus this client is connected to.
  final DBusClient _bus;
  final bool _closeBus;

  /// The D-Bus DConf write object.
  late final DBusRemoteObject _writer;

  /// The database to read from.
  late final GVariantDatabase _database;

  /// Creates a new DConf client.
  DConfClient({DBusClient? bus})
      : _bus = bus ?? DBusClient.session(),
        _closeBus = bus == null {
    _writer = DBusRemoteObject(
        _bus, 'ca.desrt.dconf', DBusObjectPath('/ca/desrt/dconf/Writer/user'));
    notify = DBusRemoteObjectSignalStream(
            _writer, 'ca.desrt.dconf.Writer', 'Notify',
            signature: DBusSignature('sass'))
        .map((signal) => DConfNotifyEvent(
            (signal.values[0] as DBusString).value,
            (signal.values[1] as DBusArray)
                .children
                .map((child) => (child as DBusString).value)
                .toList(),
            (signal.values[2] as DBusString).value));
    _database = GVariantDatabase(configHome.path + '/dconf/user');
  }

  /// Gets all the keys available underneath the given directory.
  Future<List<String>> list(String dir) async {
    return _database.list(dir: dir);
  }

  /// Gets the value of a given [key].
  Future<DBusValue?> read(String key) async {
    return _database.lookup(key);
  }

  /// Sets key values in the dconf database.
  Future<String> write(Map<String, DBusValue?> values) async {
    var changeset = DBusDict(
        DBusSignature('s'),
        DBusSignature('mv'),
        values.map((key, value) => MapEntry(
            DBusString(key),
            DBusMaybe(DBusSignature('v'),
                value != null ? DBusVariant(value) : null))));
    var codec = GVariantBinaryCodec();
    var result = await _writer.callMethod('ca.desrt.dconf.Writer', 'Change',
        [DBusArray.byte(codec.encode(changeset, endian: Endian.host))],
        replySignature: DBusSignature('s'));
    return (result.values[0] as DBusString).value;
  }

  /// Terminates the connection to the DConf daemon. If a client remains unclosed, the Dart process may not terminate.
  Future<void> close() async {
    if (_closeBus) {
      await _bus.close();
    }
  }
}
