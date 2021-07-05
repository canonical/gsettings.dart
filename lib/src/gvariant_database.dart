import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dbus/dbus.dart';

class GVariantDatabase {
  final String path;

  GVariantDatabase(this.path);

  Future<DBusValue?> lookup(String key) async {
    var data = File(path).readAsBytesSync();
    var blob = ByteData.view(data.buffer);

    // Check for correct signature and detect endianess.
    var signature0 = blob.getUint32(0, Endian.little);
    var signature1 = blob.getUint32(4, Endian.little);
    var version = blob.getUint32(8, Endian.little);
    Endian endian;
    if (signature0 == 1918981703 && signature1 == 1953390953 && version == 0) {
      endian = Endian.little;
      /*} else if (signature0 == && signature1 == && version == 0) {
         endian = Endian.big;*/
    } else {
      throw ('Invalid signature');
    }

    var rootStart = blob.getUint32(16, endian);
    var rootEnd = blob.getUint32(20, endian);
    var root = ByteData.sublistView(blob, rootStart, rootEnd);

    var offset = 0;
    var nBloomWords = root.getUint32(offset + 0, endian) & 0x3ffffff;
    var nBuckets = root.getUint32(offset + 4, endian);
    offset += 8;
    //var bloomOffset = offset; // FIXME
    offset += nBloomWords * 4;
    var bucketOffset = offset;
    offset += nBuckets * 4;
    var hashOffset = offset;

    var nHashItems = (root.lengthInBytes - hashOffset) ~/ 24;

    var hash = _hashKey(key);
    var bucket = hash % nBuckets;
    var start = root.getUint32(bucketOffset + bucket * 4, endian);
    var end = bucket + 1 < nBuckets
        ? root.getUint32(bucketOffset + (bucket + 1) * 4, endian)
        : nHashItems;
    start = 0;
    end = nHashItems;

    for (var i = start; i < end; i++) {
      var offset = hashOffset + i * 24;

      var hashValue = root.getUint32(offset + 0, endian);
      if (hashValue != hash) {
        continue;
      }

      if (_getKey(root, hashOffset, i, endian: endian) != key) {
        continue;
      }

      var type = root.getUint8(offset + 14);
      if (type != 118) {
        // 'v'
        continue;
      }

      var valueStart = root.getUint32(offset + 16, endian);
      var valueEnd = root.getUint32(offset + 20, endian);

      var value = root.buffer.asUint8List(valueStart, valueEnd - valueStart);

      print('$key=$value');

      return _parseGVariant(type, value, endian: endian);
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

  /// Gets the key name for a hash item.
  String _getKey(ByteData data, int hashOffset, int index,
      {required Endian endian}) {
    var offset = hashOffset + index * 24;

    var parent = data.getUint32(offset + 4, endian);
    var parentKey = parent != 0xffffffff
        ? _getKey(data, hashOffset, parent, endian: endian)
        : '';

    var keyStart = data.getUint32(offset + 8, endian);
    var keySize = data.getUint16(offset + 12, endian);
    return parentKey + utf8.decode(data.buffer.asUint8List(keyStart, keySize));
  }

  DBusValue _parseGVariant(int type, Uint8List data, {required Endian endian}) {
    var blob = ByteData.sublistView(data);
    switch (type) {
      case 98: // 'b' - boolean
        if (data.length != 1) {
          throw ('Invalid length of ${data.length} for boolean GVariant');
        }
        return DBusBoolean(data[0] != 0);
      case 121: // 'y' - byte
        if (data.length != 1) {
          throw ('Invalid length of ${data.length} for byte GVariant');
        }
        return DBusByte(data[0]);
      case 110: // 'n' - int16
        if (data.length != 2) {
          throw ('Invalid length of ${data.length} for int16 GVariant');
        }
        return DBusInt16(blob.getInt16(0, endian));
      case 113: // 'q' - uint16
        if (data.length != 2) {
          throw ('Invalid length of ${data.length} for uint16 GVariant');
        }
        return DBusUint16(blob.getUint16(0, endian));
      case 105: // 'i' - int32
        if (data.length != 4) {
          throw ('Invalid length of ${data.length} for int32 GVariant');
        }
        return DBusInt32(blob.getInt32(0, endian));
      case 117: // 'u' - uint32
        if (data.length != 4) {
          throw ('Invalid length of ${data.length} for uint32 GVariant');
        }
        return DBusUint32(blob.getUint32(0, endian));
      case 120: // 'x' - int64
        if (data.length != 4) {
          throw ('Invalid length of ${data.length} for int64 GVariant');
        }
        return DBusInt64(blob.getInt64(0, endian));
      case 116: // 't' - uint64
        if (data.length != 4) {
          throw ('Invalid length of ${data.length} for uint64 GVariant');
        }
        return DBusUint64(blob.getUint64(0, endian));
      case 100: // 'd' - double
        return DBusDouble(blob.getFloat64(0, endian));
      case 115: // 's' - string
        return DBusString(utf8.decode(data));
      case 111: // 'o' - object path
        return DBusObjectPath(utf8.decode(data));
      case 103: // 'g' - signature
        return DBusSignature(utf8.decode(data));
      case 118: // 'v' - variant
        var childType = data.last;
        var childData = Uint8List.sublistView(data, 0, data.length - 2);
        return _parseGVariant(childType, childData, endian: endian);
      default:
        throw ('Unsupported GVariant type $type');
    }
  }
}
