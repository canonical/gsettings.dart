import 'dart:convert';
import 'dart:typed_data';

import 'package:dbus/dbus.dart';

class GVariantCodec {
  GVariantCodec();

  Uint8List encode(DBusValue value) {
    throw ('Not implemented');
  }

  /// Parse a single GVariant value. [type] is expected to be a valid single type.
  DBusValue decode(String type, ByteData data, {required Endian endian}) {
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
        if (data.lengthInBytes < 1) {
          throw ('Invalid length of ${data.lengthInBytes} for string GVariant');
        }
        if (data.getUint8(data.lengthInBytes - 1) != 0) {
          throw ('Missing trailing nul character for string GVariant');
        }
        return DBusString(utf8.decode(data.buffer
            .asUint8List(data.offsetInBytes, data.lengthInBytes - 1)));
      case 'o': // object path
        if (data.lengthInBytes < 1) {
          throw ('Invalid length of ${data.lengthInBytes} for object path GVariant');
        }
        if (data.getUint8(data.lengthInBytes - 1) != 0) {
          throw ('Missing trailing nul character for object path GVariant');
        }
        return DBusObjectPath(utf8.decode(data.buffer
            .asUint8List(data.offsetInBytes, data.lengthInBytes - 1)));
      case 'g': // signature
        if (data.lengthInBytes < 1) {
          throw ('Invalid length of ${data.lengthInBytes} for signature GVariant');
        }
        if (data.getUint8(data.lengthInBytes - 1) != 0) {
          throw ('Missing trailing nul character for object path GVariant');
        }
        return DBusSignature(utf8.decode(data.buffer
            .asUint8List(data.offsetInBytes, data.lengthInBytes - 1)));
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
        return DBusVariant(decode(childType, childData, endian: endian));
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
    var childTypes = <String>[];
    var childSizes = <int>[];
    while (offset < type.length - 1) {
      var start = offset;
      var end = _validateType(type, start);
      var childType = type.substring(start, end + 1);
      childTypes.add(childType);
      childSizes.add(_getElementSize(childType));
      offset = end + 1;
    }

    // Check if the sizes of the elements can be determined before parsing.
    // The last element can be variable, as it takes up the remaining space.
    var variableSize = false;
    for (var i = 0; i < childSizes.length - 1; i++) {
      if (childSizes[i] == -1) {
        variableSize = true;
        break;
      }
    }

    if (variableSize) {
      return _parseGVariantVariableStruct(childTypes, data, endian: endian);
    } else {
      return _parseGVariantFixedStruct(childTypes, data, endian: endian);
    }
  }

  DBusStruct _parseGVariantFixedStruct(List<String> childTypes, ByteData data,
      {required Endian endian}) {
    var children = <DBusValue>[];
    var offset = 0;
    for (var i = 0; i < childTypes.length; i++) {
      var start = _align(offset, _getAlignment(childTypes[i]));
      var size = _getElementSize(childTypes[i]);
      if (size < 0) {
        size = data.lengthInBytes - start;
      }
      children.add(decode(
          childTypes[i], ByteData.sublistView(data, start, start + size),
          endian: endian));
      offset += size;
    }

    return DBusStruct(children);
  }

  DBusStruct _parseGVariantVariableStruct(
      List<String> childTypes, ByteData data,
      {required Endian endian}) {
    var offsetSize = _getOffsetSize(data.lengthInBytes);
    var children = <DBusValue>[];
    var offset = 0;
    for (var i = 0; i < childTypes.length; i++) {
      var start = _align(offset, _getAlignment(childTypes[i]));
      int end;
      if (i < childTypes.length - 1) {
        end = _getOffset(
            data, data.lengthInBytes - offsetSize * (i + 1), offsetSize,
            endian: endian);
      } else {
        end = data.lengthInBytes - (childTypes.length - 1) * offsetSize;
      }
      children.add(decode(childTypes[i], ByteData.sublistView(data, start, end),
          endian: endian));
      offset = end;
    }

    return DBusStruct(children);
  }

  DBusDict _parseGVariantDict(String type, ByteData data,
      {required Endian endian}) {
    if (!type.startsWith('a{') || !type.endsWith('}')) {
      throw ('Invalid dict type: $type');
    }
    var keyStart = 2;
    var keyEnd = _validateType(type, keyStart);
    var keyType = type.substring(keyStart, keyEnd + 1);
    var valueStart = keyEnd + 1;
    var valueEnd = _validateType(type, valueStart);
    var valueType = type.substring(valueStart, valueEnd + 1);
    if (valueEnd != type.length - 2) {
      throw ('Invalid dict type: $type');
    }
    // Data is stored as an array, this could be optimised to avoid being unpacked and repacked as a dict.
    var array =
        _parseGVariantArray('($keyType$valueType)', data, endian: endian);
    var values = <DBusValue, DBusValue>{};
    for (var child in array.children) {
      var keyValue = child as DBusStruct;
      values[keyValue.children[0]] = keyValue.children[1];
    }
    return DBusDict(DBusSignature(keyType), DBusSignature(valueType), values);
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
      children.add(decode(childType, childData, endian: endian));
    }

    return DBusArray(DBusSignature(childType), children);
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
      children.add(decode(childType, childData, endian: endian));
      start = end;
    }

    return DBusArray(DBusSignature(childType), children);
  }

  DBusMaybe _parseGVariantMaybe(String childType, ByteData data,
      {required Endian endian}) {
    var value =
        data.lengthInBytes > 0 ? decode(childType, data, endian: endian) : null;
    return DBusMaybe(DBusSignature(childType), value);
  }

  int _align(int offset, int alignment) {
    var x = offset % alignment;
    return x == 0 ? offset : offset + (alignment - x);
  }

  int _getElementSize(String type) {
    /// Containers are variable length.
    if (type.startsWith('a') || type.startsWith('m')) {
      return -1;
    }

    if (type.startsWith('(') || type.startsWith('{')) {
      var size = 0;
      var offset = 1;
      while (offset < type.length - 1) {
        var end = _validateType(type, offset) + 1;
        var s = _getElementSize(type.substring(offset, end));
        if (s < 0) {
          return -1;
        }
        size += s;
        offset = end;
      }
      return size;
    }

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
      case 'v': // variant
        return -1; // variable size
      default:
        throw ArgumentError.value(type, 'type', 'Unknown type');
    }
  }

  int _getAlignment(String type) {
    if (type.startsWith('a') || type.startsWith('m')) {
      return _getAlignment(type.substring(1));
    }
    if (type.startsWith('(') || type.startsWith('{')) {
      var alignment = 1;
      var offset = 1;
      while (offset < type.length - 1) {
        var end = _validateType(type, offset) + 1;
        var a = _getAlignment(type.substring(offset, end));
        if (a > alignment) {
          alignment = a;
        }
        offset = end;
      }
      return alignment;
    }

    switch (type) {
      case 'y': // byte
      case 'b': // boolean
      case 's': // string
      case 'o': // object path
      case 'g': // signature
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
      case 'v': // variant
        return 8;
      default:
        throw ArgumentError.value(type, 'type', 'Unknown type');
    }
  }

  /// Check [value] contains a valid type and return the index of the end of the current child type.
  int _validateType(String value, int index) {
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
    } else if ('ybnqiuxtdsogvm'.contains(value[index])) {
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
