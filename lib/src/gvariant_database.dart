import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dbus/dbus.dart';

class GVariantDatabase {
  final String path;

  GVariantDatabase(this.path);

  Future<List<String>> list(String dir) async {
    var root = await _loadRootTable();
    return root.list(dir);
  }

  Future<DBusValue?> lookup(String key) async {
    var root = await _loadRootTable();
    var value = root.lookup(key);
    return value != null
        ? (_parseGVariantSingleValue(value.type, value.value,
                endian: root.endian) as DBusVariant)
            .value
        : null;
  }

  Future<_GVariantTable> _loadRootTable() async {
    var rawData = await File(path).readAsBytes();
    var data = ByteData.view(rawData.buffer);

    // Check for correct signature and detect endianess.
    var signature0 = data.getUint32(0, Endian.little);
    var signature1 = data.getUint32(4, Endian.little);
    var version = data.getUint32(8, Endian.little);
    Endian endian;
    if (signature0 == 1918981703 && signature1 == 1953390953 && version == 0) {
      endian = Endian.little;
      /*} else if (signature0 == && signature1 == && version == 0) {
         endian = Endian.big;*/
    } else {
      throw ('Invalid signature');
    }

    var rootStart = data.getUint32(16, endian);
    var rootEnd = data.getUint32(20, endian);
    return _GVariantTable(
        ByteData.sublistView(data, rootStart, rootEnd), data, endian);
  }

  /// Parse a single GVariant value. [type] is expected to be a valid single type.
  DBusValue _parseGVariantSingleValue(String type, ByteData data,
      {required Endian endian}) {
    // struct
    if (type.startsWith('(')) {
      return _parseGVariantStruct(type, data, endian: endian);
    }

    // array / dict
    if (type.startsWith('a')) {
      if (type.startsWith('a{')) {
        return _parseGVariantDict(type, data, endian: endian);
      } else {
        var childType = type.substring(1);
        return _parseGVariantArray(childType, data, endian: endian);
      }
    }

    // maybe
    if (type.startsWith('m')) {
      var childType = type.substring(1);
      return _parseGVariantMaybe(childType, data, endian: endian);
    }

    switch (type) {
      case 'b': // boolean
        if (data.lengthInBytes != 1) {
          throw ('Invalid length of ${data.lengthInBytes} for boolean GVariant');
        }
        return DBusBoolean(data.getUint8(0) != 0);
      case 'y': // byte
        if (data.lengthInBytes != 1) {
          throw ('Invalid length of ${data.lengthInBytes} for byte GVariant');
        }
        return DBusByte(data.getUint8(0));
      case 'n': // int16
        if (data.lengthInBytes != 2) {
          throw ('Invalid length of ${data.lengthInBytes} for int16 GVariant');
        }
        return DBusInt16(data.getInt16(0, endian));
      case 'q': // uint16
        if (data.lengthInBytes != 2) {
          throw ('Invalid length of ${data.lengthInBytes} for uint16 GVariant');
        }
        return DBusUint16(data.getUint16(0, endian));
      case 'i': // int32
        if (data.lengthInBytes != 4) {
          throw ('Invalid length of ${data.lengthInBytes} for int32 GVariant');
        }
        return DBusInt32(data.getInt32(0, endian));
      case 'u': // uint32
        if (data.lengthInBytes != 4) {
          throw ('Invalid length of ${data.lengthInBytes} for uint32 GVariant');
        }
        return DBusUint32(data.getUint32(0, endian));
      case 'x': // int64
        if (data.lengthInBytes != 8) {
          throw ('Invalid length of ${data.lengthInBytes} for int64 GVariant');
        }
        return DBusInt64(data.getInt64(0, endian));
      case 't': // uint64
        if (data.lengthInBytes != 8) {
          throw ('Invalid length of ${data.lengthInBytes} for uint64 GVariant');
        }
        return DBusUint64(data.getUint64(0, endian));
      case 'd': // double
        return DBusDouble(data.getFloat64(0, endian));
      case 's': // string
        return DBusString(utf8.decode(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes)));
      case 'o': // object path
        return DBusObjectPath(utf8.decode(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes)));
      case 'g': // signature
        return DBusSignature(utf8.decode(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes)));
      case 'v': // variant
        // Type is a suffix on the data
        var childType = '';
        var offset = data.lengthInBytes - 1;
        while (offset >= 0 && data.getUint8(offset) != 0) {
          childType = ascii.decode([data.getUint8(offset)]) + childType;
          offset--;
        }
        if (offset < 0) {
          throw ('GVariant variant missing child type');
        }
        var childData = ByteData.sublistView(data, 0, offset);
        return DBusVariant(
            _parseGVariantSingleValue(childType, childData, endian: endian));
      default:
        throw ("Unsupported GVariant type: '$type'");
    }
  }

  DBusStruct _parseGVariantStruct(String type, ByteData data,
      {required Endian endian}) {
    if (!type.startsWith('(') || !type.endsWith(')')) {
      throw ('Invalid struct type: $type');
    }
    var offset = 1;
    var elementSize = 0;
    var childTypes = <String>[];
    while (offset < type.length - 1) {
      var start = offset;
      var end = _validateType(type, start);
      var childType = type.substring(start, end + 1);
      childTypes.add(childType);
      var size = _getElementSize(childType);
      if (elementSize != -1) {
        // A variable length element forces the whole struct to be variable, or use largest size required.
        if (size < 0 || size > elementSize) {
          elementSize = size;
        }
      }
      offset = end + 1;
    }

    if (elementSize > 0) {
      return _parseGVariantFixedStruct(childTypes, elementSize, data,
          endian: endian);
    } else {
      return _parseGVariantVariableStruct(childTypes, data, endian: endian);
    }
  }

  DBusStruct _parseGVariantFixedStruct(
      List<String> childTypes, int elementSize, ByteData data,
      {required Endian endian}) {
    if (data.lengthInBytes != childTypes.length * elementSize) {
      throw ('Fixed struct size mismatch');
    }

    var children = <DBusValue>[];
    for (var i = 0; i < childTypes.length; i++) {
      var size = _getElementSize(childTypes[i]);
      if (size < 0) {
        throw ('Variable element in fixed struct');
      }
      var start = i * elementSize;
      children.add(_parseGVariantSingleValue(
          childTypes[i], ByteData.sublistView(data, start, start + size),
          endian: endian));
    }

    return DBusStruct(children);
  }

  DBusStruct _parseGVariantVariableStruct(
      List<String> childTypes, ByteData data,
      {required Endian endian}) {
    var offsetSize = _getOffsetSize(data.lengthInBytes);
    var children = <DBusValue>[];
    var start = 0;
    for (var i = 0; i < childTypes.length; i++) {
      int end;
      if (i < childTypes.length - 1) {
        end = _getOffset(
            data,
            data.lengthInBytes - offsetSize * (childTypes.length - i),
            offsetSize,
            endian: endian);
      } else {
        end = data.lengthInBytes - childTypes.length * offsetSize;
      }
      children.add(_parseGVariantSingleValue(
          childTypes[i], ByteData.sublistView(data, start, end),
          endian: endian));
      start = end + 1;
    }

    return DBusStruct(children);
  }

  DBusArray _parseGVariantDict(String type, ByteData data,
      {required Endian endian}) {
    if (!type.startsWith('a{') || !type.endsWith('}')) {
      throw ('Invalid dict type: $type');
    }
    throw ('FIXME: dict $type');
  }

  DBusArray _parseGVariantArray(String childType, ByteData data,
      {required Endian endian}) {
    var elementSize = _getElementSize(childType);
    if (elementSize > 0) {
      return _parseGVariantFixedArray(childType, elementSize, data,
          endian: endian);
    } else {
      return _parseGVariantVariableArray(childType, data, endian: endian);
    }
  }

  DBusArray _parseGVariantFixedArray(
      String childType, int elementSize, ByteData data,
      {required Endian endian}) {
    var arrayLength = data.lengthInBytes ~/ elementSize;

    var children = <DBusValue>[];
    for (var i = 0; i < arrayLength; i++) {
      var start = i * elementSize;
      var childData = ByteData.sublistView(data, start, start + elementSize);
      children
          .add(_parseGVariantSingleValue(childType, childData, endian: endian));
    }

    return DBusArray(DBusSignature(childType), []);
  }

  DBusArray _parseGVariantVariableArray(String childType, ByteData data,
      {required Endian endian}) {
    // Get end of last element.
    var offsetSize = _getOffsetSize(data.lengthInBytes);
    int arrayLength;
    if (data.lengthInBytes > 0) {
      var lastOffset = _getOffset(
          data, data.lengthInBytes - offsetSize, offsetSize,
          endian: endian);

      // Array size is the number of offsets after the last element.
      arrayLength = (data.lengthInBytes - lastOffset) ~/ offsetSize;
    } else {
      arrayLength = 0;
    }

    var children = <DBusValue>[];
    var start = 0;
    for (var i = 0; i < arrayLength; i++) {
      var end = _getOffset(
          data, data.lengthInBytes - offsetSize * (arrayLength - i), offsetSize,
          endian: endian);
      var childData = ByteData.sublistView(data, start, end);
      children
          .add(_parseGVariantSingleValue(childType, childData, endian: endian));
      start = end;
    }

    return DBusArray(DBusSignature(childType), children);
  }

  DBusArray _parseGVariantMaybe(String childType, ByteData data,
      {required Endian endian}) {
    throw ('FIXME: maybe $childType');
  }

  int _getElementSize(String type) {
    /// Containers are variable length.
    if (type.startsWith('(') || type.startsWith('a')) {
      return -1;
    }

    int elementSize;
    switch (type) {
      case 'y': // byte
      case 'b': // boolean
        return 1;
      case 'n': // int16
      case 'q': // uint16
        return 2;
      case 'i': // int32
      case 'u': // uint32
        return 4;
      case 'x': // int64
      case 't': // uint64
      case 'd': // double
        return 8;
      case 's': // string
      case 'o': // object path
      case 'g': // signature
        return -1; // variable size
      default:
        throw ArgumentError.value(type, 'type', 'Unknown type');
    }
  }

  /// Check [value] contains a valid type and return the index of the end of the current child type.
  int _validateType(String value, int index) {
    // FIXME: Maybe ('m') type

    if (value.startsWith('(', index)) {
      // Struct.
      var end = _findClosing(value, index, '(', ')');
      if (end < 0) {
        throw ArgumentError.value(
            value, 'value', 'Struct missing closing parenthesis');
      }
      var childIndex = index + 1;
      while (childIndex < end) {
        childIndex = _validateType(value, childIndex) + 1;
      }
      return end;
    } else if (value.startsWith('a{', index)) {
      // Dict.
      var end = _findClosing(value, index, '{', '}');
      if (end < 0) {
        throw ArgumentError.value(value, 'value', 'Dict missing closing brace');
      }
      var childIndex = index + 2;
      var childCount = 0;
      while (childIndex < end) {
        childIndex = _validateType(value, childIndex) + 1;
        childCount++;
      }
      if (childCount != 2) {
        throw ArgumentError.value(
            value, 'value', "Dict doesn't have correct number of child types");
      }
      return end;
    } else if (value.startsWith('a', index)) {
      // Array.
      if (index >= value.length - 1) {
        throw ArgumentError.value(value, 'value', 'Array missing child type');
      }
      return _validateType(value, index + 1);
    } else if ('ybnqiuxtdsogv'.contains(value[index])) {
      return index;
    } else {
      throw ArgumentError.value(
          value, 'value', 'Type contains unknown characters');
    }
  }

  /// Find the index int [value] where there is a [closeChar] that matches [openChar].
  /// These characters nest.
  int _findClosing(String value, int index, String openChar, String closeChar) {
    var depth = 0;
    for (var i = index; i < value.length; i++) {
      if (value[i] == openChar) {
        depth++;
      } else if (value[i] == closeChar) {
        depth--;
        if (depth == 0) {
          return i;
        }
      }
    }
    return -1;
  }

  int _getOffsetSize(int size) {
    if (size > 0xffffffff) {
      return 8;
    } else if (size > 0xffff) {
      return 4;
    } else if (size > 0xff) {
      return 2;
    } else {
      return 1;
    }
  }

  int _getOffset(ByteData data, int offset, int offsetSize,
      {required Endian endian}) {
    switch (offsetSize) {
      case 1:
        return data.getUint8(offset);
      case 2:
        return data.getUint16(offset, endian);
      case 4:
        return data.getUint32(offset, endian);
      case 8:
        return data.getUint64(offset, endian);
      default:
        throw ('Unknown offset size $offsetSize');
    }
  }
}

class _GVariantTableValue {
  final String type;
  final ByteData value;

  const _GVariantTableValue(this.type, this.value);
}

class _GVariantTable {
  final ByteData data;
  final ByteData fullData;
  final Endian endian;
  late final int _nBloomWords;
  late final int _bloomOffset;
  late final int _nBuckets;
  late final int _bucketOffset;
  late final int _nHashItems;
  late final int _hashOffset;

  _GVariantTable(this.data, this.fullData, this.endian) {
    var offset = 0;
    _nBloomWords = data.getUint32(offset + 0, endian) & 0x3ffffff;
    _nBuckets = data.getUint32(offset + 4, endian);
    offset += 8;
    _bloomOffset = offset;
    offset += _nBloomWords * 4;
    _bucketOffset = offset;
    offset += _nBuckets * 4;
    _hashOffset = offset;

    _nHashItems = (data.lengthInBytes - _hashOffset) ~/ 24;
  }

  Future<List<String>> list(String dir) async {
    var dirHash = _hashKey(dir);
    var children = <String>[];

    for (var i = 0; i < _nHashItems; i++) {
      var parent = _getParent(i);
      if (parent != 0xffffffff && _getHash(parent) == dirHash) {
        children.add(_getKey(i));
      }
    }

    return children;
  }

  _GVariantTableValue? lookup(String key) {
    var hash = _hashKey(key);
    var bucket = hash % _nBuckets;
    var start = data.getUint32(_bucketOffset + bucket * 4, endian);
    var end = bucket + 1 < _nBuckets
        ? data.getUint32(_bucketOffset + (bucket + 1) * 4, endian)
        : _nHashItems;
    start = 0;
    end = _nHashItems;

    for (var i = start; i < end; i++) {
      if (_getHash(i) == hash &&
          _getKey(i, recurse: true) == key &&
          _getType(i) == 'v') {
        return _GVariantTableValue(_getType(i), _getValue(i));
      }
    }

    return null;
  }

  /// Gets the hash for a DConf key.
  int _hashKey(String key) {
    var hashValue = 5381;
    for (var o in utf8.encode(key)) {
      // Use bytes as signed 8 bit numbers.
      if (o >= 128) {
        o -= 256;
      }
      hashValue = (hashValue * 33 + o) & 0xffffffff;
    }
    return hashValue;
  }

  int _getHash(int index) {
    return data.getUint32(_getHashItemOffset(index) + 0, endian);
  }

  int _getParent(int index) {
    return data.getUint32(_getHashItemOffset(index) + 4, endian);
  }

  /// Gets the key name for a hash item.
  String _getKey(int index, {bool recurse = false}) {
    var parent = recurse ? _getParent(index) : 0xffffffff;
    var parentKey =
        parent != 0xffffffff ? _getKey(parent, recurse: recurse) : '';

    var offset = _getHashItemOffset(index);
    var keyStart = data.getUint32(offset + 8, endian);
    var keySize = data.getUint16(offset + 12, endian);
    return parentKey + utf8.decode(data.buffer.asUint8List(keyStart, keySize));
  }

  String _getType(int index) {
    return ascii.decode([data.getUint8(_getHashItemOffset(index) + 14)]);
  }

  ByteData _getValue(int index) {
    var offset = _getHashItemOffset(index);

    var valueStart = data.getUint32(offset + 16, endian);
    var valueEnd = data.getUint32(offset + 20, endian);
    return ByteData.sublistView(fullData, valueStart, valueEnd);
  }

  int _getHashItemOffset(int index) {
    return _hashOffset + index * 24;
  }
}
