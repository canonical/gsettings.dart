import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dbus/dbus.dart';

import 'gsettings_backend.dart';
import 'gvariant_text_codec.dart';

/// GSettings backend that reads/writes values into a shared keyfile
class GSettingsKeyfileBackend implements GSettingsBackend {
  // The cached settings.
  Map<String, String>? _values;

  // The directory and file containing the settings.
  late final Directory _settingsDirectory;
  late final File _keyfile;

  // Subscription watching for file changes.
  StreamSubscription<FileSystemEvent>? _watchSubscription;

  final _valuesChanged = StreamController<List<String>>();
  @override
  Stream<List<String>> get valuesChanged => _valuesChanged.stream;

  /// Create a new GSettings backend that reads/writes from [file].
  /// If [file] is not provided, `$XDG_CONFIG_HOME/glib-2.0-settings/keyfile` is used.
  GSettingsKeyfileBackend({File? file}) {
    if (file == null) {
      var configHome = Platform.environment['XDG_CONFIG_HOME'];
      if (configHome == null) {
        var home = Platform.environment['HOME'];
        configHome = home != null ? '$home/.config' : null;
      }
      configHome ??= '~/.config';
      file = File('$configHome/glib-2.0/settings/keyfile');
    }

    _keyfile = file;
    _settingsDirectory = _keyfile.parent;
    _init();
  }

  @override
  Future<DBusValue?> get(String path, DBusSignature signature) async {
    await _init();
    var value = _values![path];
    return value != null
        ? GVariantTextCodec().decode(signature.value, value)
        : null;
  }

  @override
  Future<void> set(Map<String, DBusValue?> changedValues) async {
    await _init();
    var codec = GVariantTextCodec();
    for (var entry in changedValues.entries) {
      if (entry.value != null) {
        _values![entry.key] = codec.encode(entry.value!);
      } else {
        _values!.remove(entry.key);
      }
    }
    await _writeKeyfile(_values!);
  }

  @override
  Future<void> close() async {
    await _watchSubscription?.cancel();
  }

  Future<void> _init() async {
    if (_values != null) {
      return;
    }

    // Create the settings directory if it doesn't exist.
    // NOTE: This sets the directory to rwxrwxrwx permissions, it should be rw-------
    await _settingsDirectory.create(recursive: true);

    // Watch for file changes by other clients.
    _watchSubscription ??= _settingsDirectory.watch().listen((e) async {
      if (e.path == _keyfile.path ||
          (e is FileSystemMoveEvent && e.destination == _keyfile.path)) {
        await _reload();
      }
    });

    try {
      _values = await _readKeyfile();
    } on FormatException {
      _values = {};
    }
  }

  Future<void> _reload() async {
    if (_values == null) {
      return;
    }

    Map<String, String> newValues;
    try {
      newValues = await _readKeyfile();
    } on FormatException {
      return;
    }

    // Find out which values have changed.
    var keysChanged = <String>[];
    for (var key in _values!.keys) {
      var value = newValues[key];
      if (value == null || _values![key] != value) {
        keysChanged.add(key);
      }
    }
    for (var key in newValues.keys) {
      if (_values![key] == null) {
        keysChanged.add(key);
      }
    }
    _values = newValues;

    if (keysChanged.isNotEmpty) {
      _valuesChanged.add(keysChanged);
    }
  }

  Future<Map<String, String>> _readKeyfile() async {
    List<String> lines;
    try {
      lines = await _keyfile.readAsLines();
    } on FileSystemException {
      return {};
    }

    String? section;
    var values = <String, String>{};
    for (var line in lines) {
      line = line.trim();
      if (line.startsWith('#') || line.startsWith(';')) {
        // Ignore comments
      } else if (line.isEmpty) {
        // Skip empty lines
      } else if (line.startsWith('[')) {
        section = line.substring(1, line.indexOf(']'));
      } else {
        if (section == null) {
          throw FormatException('Invalid keyfile');
        }
        var index = line.indexOf('=');
        if (index <= 0) {
          throw FormatException('Invalid keyfile');
        }
        var key = line.substring(0, index).trim();
        var value = line.substring(index + 1).trim();
        values['/$section/$key'] = value;
      }
    }

    return values;
  }

  Future<void> _writeKeyfile(Map<String, String> values) async {
    // Break settings into sections.
    var sections = <String, List<_KeyValue>>{};
    for (var entry in values.entries) {
      var path = entry.key;
      var value = entry.value;

      var index = path.lastIndexOf('/');
      if (!path.startsWith('/') || index <= 0) {
        // This should never occur, so just silently ignore
        continue;
      }
      var dir = path.substring(1, index);
      var name = path.substring(index + 1);

      var section = sections[dir];
      section ??= sections[dir] = <_KeyValue>[];
      section.add(_KeyValue(name, value));
    }

    // Convert to keyfile format.
    var sectionNames = sections.keys.toList();
    sectionNames.sort((a, b) => a.compareTo(b));
    var text = '';
    for (var i = 0; i < sectionNames.length; i++) {
      if (i != 0) {
        text += '\n';
      }
      var sectionName = sectionNames[i];
      text += '[$sectionName]\n';
      var keyValues = sections[sectionName]!.toList();
      keyValues.sort((a, b) => a.key.compareTo(b.key));
      for (var v in keyValues) {
        text += '${v.key}=${v.value}\n';
      }
    }

    var path = '${_settingsDirectory.path}/.keyfile-';
    var r = Random();
    for (var i = 0; i < 6; i++) {
      final d = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
      path += d[r.nextInt(d.length)];
    }

    // Atomically write the updated settings.
    var tempFile = File(path);
    await tempFile.writeAsString(text);
    await tempFile.rename(_keyfile.path);
  }
}

class _KeyValue {
  final String key;
  final String value;
  const _KeyValue(this.key, this.value);
}
