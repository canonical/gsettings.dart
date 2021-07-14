import 'package:dbus/dbus.dart';

class GVariantTextCodec {
  GVariantTextCodec();

  /// Encode a value using GVariant text format.
  String encode(DBusValue value) {
    var buffer = StringBuffer();
    _encode(buffer, value);
    return buffer.toString();
  }

  /// Parse a single GVariant value. [type] is expected to be a valid single type.
  DBusValue decode(String type, String data) {
    switch (type) {
      case 'b': // boolean
        bool value;
        if (data == 'true') {
          value = true;
        } else if (data == 'false') {
          value = false;
        } else {
          throw "Invalid boolean encoding: '$data'";
        }
        return DBusBoolean(value);
      case 'y': // byte
        return DBusByte(0);
      case 'n': // int16
        return DBusInt16(0);
      case 'q': // uint16
        return DBusUint16(0);
      case 'i': // int32
        return DBusInt32(0);
      case 'u': // uint32
        return DBusUint32(0);
      case 'x': // int64
        return DBusInt64(0);
      case 't': // uint64
        return DBusUint64(0);
      case 'd': // double
        return DBusDouble(0);
      case 's': // string
        return DBusString(_decodeString(data));
      case 'o': // object path
        if (!data.startsWith('objectpath ')) {
          throw "Invalid object path encoding: '$data'";
        }
        return DBusObjectPath(_decodeString(data.substring(11)));
      case 'g': // signature
        if (!data.startsWith('signature ')) {
          throw "Invalid signature encoding: '$data'";
        }
        return DBusObjectPath(_decodeString(data.substring(11)));
      default:
        throw ("Unsupported GVariant type: '$type'");
    }
  }

  void _encode(StringBuffer buffer, DBusValue value) {
    if (value is DBusBoolean) {
      buffer.write(value.value ? 'true' : 'false');
    } else if (value is DBusByte) {
      buffer.write('0x' + value.value.toRadixString(16).padLeft(2, '0'));
    } else if (value is DBusInt16) {
      buffer.write(value.value.toString());
    } else if (value is DBusUint16) {
      buffer.write(value.value.toString());
    } else if (value is DBusInt32) {
      buffer.write(value.value.toString());
    } else if (value is DBusUint32) {
      buffer.write(value.value.toString());
    } else if (value is DBusInt64) {
      buffer.write(value.value.toString());
    } else if (value is DBusUint64) {
      buffer.write(value.value.toString());
    } else if (value is DBusDouble) {
      buffer.write(value.value.toString());
    } else if (value is DBusObjectPath) {
      buffer.write('objectpath ');
      _writeString(buffer, value.value);
    } else if (value is DBusSignature) {
      buffer.write('signature ');
      _writeString(buffer, value.value);
    } else if (value is DBusString) {
      _writeString(buffer, value.value);
    } else if (value is DBusVariant) {
      buffer.write('<');
      _encode(buffer, value.value);
      buffer.write('>');
    } else if (value is DBusMaybe) {
      if (value.value != null) {
        var childBuffer = StringBuffer();
        _encode(childBuffer, value.value!);
        var childText = childBuffer.toString();
        if (childText.endsWith('nothing')) {
          buffer.write('just ');
        }
        buffer.write(childText);
      } else {
        buffer.write('nothing');
      }
    } else if (value is DBusStruct) {
      buffer.write('(');
      for (var child in value.children) {
        if (child != value.children.first) {
          buffer.write(', ');
        }
        _encode(buffer, child);
      }
      buffer.write(')');
    } else if (value is DBusArray) {
      buffer.write('[');
      for (var child in value.children) {
        if (child != value.children.first) {
          buffer.write(', ');
        }
        _encode(buffer, child);
      }
      buffer.write(']');
    } else if (value is DBusDict) {
      buffer.write('{');
      var first = true;
      for (var entry in value.children.entries) {
        if (!first) {
          buffer.write(', ');
        }
        first = false;
        _encode(buffer, entry.key);
        buffer.write(': ');
        _encode(buffer, entry.value);
      }
      buffer.write('}');
    } else {
      throw ("Unsupported DBus type: '$value'");
    }
  }

  void _writeString(StringBuffer buffer, String value) {
    var quote = value.contains("'") ? '"' : "'";
    buffer.write(quote);
    for (var rune in value.runes) {
      switch (rune) {
        case 7: // bell
          buffer.write(r'\a');
          break;
        case 8: // backspace
          buffer.write(r'\b');
          break;
        case 9: // tab
          buffer.write(r'\t');
          break;
        case 10: // newline
          buffer.write(r'\n');
          break;
        case 11: // vertical tab
          buffer.write(r'\v');
          break;
        case 12: // form feed
          buffer.write(r'\f');
          break;
        case 13: // carriage return
          buffer.write(r'\r');
          break;
        case 34: // double quote
          buffer.write(quote == '"' ? r'\"' : '"');
          break;
        case 39: // single quote
          buffer.write(quote == "'" ? r"\'" : "'");
          break;
        case 92: // backslash
          buffer.write(r'\\');
          break;
        default:
          // FIXME: Need to check if printable, but doesn't seem to be a Dart method to do that?
          if (rune < 32 || rune == 0x7f) {
            buffer.write(r'\u${rune.toRadixString(16).padLeft(' ', 4)}');
          } else {
            buffer.writeCharCode(rune);
          }
      }
    }
    buffer.write(quote);
  }

  String _decodeString(String data) {
    return '';
  }
}
