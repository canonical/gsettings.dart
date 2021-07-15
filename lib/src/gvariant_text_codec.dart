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
        return DBusByte(int.parse(data));
      case 'n': // int16
        return DBusInt16(int.parse(data));
      case 'q': // uint16
        return DBusUint16(int.parse(data));
      case 'i': // int32
        return DBusInt32(int.parse(data));
      case 'u': // uint32
        return DBusUint32(int.parse(data));
      case 'x': // int64
        return DBusInt64(int.parse(data));
      case 't': // uint64
        return DBusUint64(int.parse(data));
      case 'd': // double
        return DBusDouble(double.parse(data));
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
          // There's not a dart method to check if a character is "printable", so we use:
          //     00 -      1f - C0 control
          //     7f           - delete
          //     80 -      9f - C1 control
          //   e000 -    f8ff - private use
          //   fff0 -    ffff - specials
          //  1ff80 -   1ffff - unassigned
          //  2ff80 -   2ffff - unassigned
          //  3ff80 -   3ffff - unassigned
          //  4ff80 -   4ffff - unassigned
          //  5ff80 -   5ffff - unassigned
          //  6ff80 -   6ffff - unassigned
          //  7ff80 -   7ffff - unassigned
          //  8ff80 -   8ffff - unassigned
          //  9ff80 -   9ffff - unassigned
          //  aff80 -   affff - unassigned
          //  bff80 -   bffff - unassigned
          //  cff80 -   cffff - unassigned
          //  dff80 -   dffff - unassigned
          //  eff80 -   effff - unassigned
          //  f0000 -   fffff - supplementary private use area A
          // 100000 -  10fffd - supplementary private use area B
          if (rune <= 0x1f ||
              (rune >= 0x7f && rune <= 0x9f) ||
              (rune >= 0xe000 && rune <= 0xf8ff) ||
              (rune >= 0xfff0 && rune <= 0xffff) ||
              (rune >= 0x1ff80 && rune <= 0x1ffff) ||
              (rune >= 0x2ff80 && rune <= 0x2ffff) ||
              (rune >= 0x3ff80 && rune <= 0x3ffff) ||
              (rune >= 0x4ff80 && rune <= 0x4ffff) ||
              (rune >= 0x5ff80 && rune <= 0x5ffff) ||
              (rune >= 0x6ff80 && rune <= 0x6ffff) ||
              (rune >= 0x7ff80 && rune <= 0x7ffff) ||
              (rune >= 0x8ff80 && rune <= 0x8ffff) ||
              (rune >= 0x9ff80 && rune <= 0x9ffff) ||
              (rune >= 0xaff80 && rune <= 0xaffff) ||
              (rune >= 0xbff80 && rune <= 0xbffff) ||
              (rune >= 0xcff80 && rune <= 0xcffff) ||
              (rune >= 0xdff80 && rune <= 0xdffff) ||
              (rune >= 0xeff80 && rune <= 0xeffff) ||
              (rune >= 0x100000 && rune <= 0x10fffd)) {
            int padding;
            String prefix;
            if (rune <= 0xffff) {
              padding = 4;
              prefix = 'u';
            } else {
              padding = 8;
              prefix = 'U';
            }
            var hex = rune.toRadixString(16).padLeft(padding, '0');
            buffer.write('\\$prefix$hex');
          } else {
            buffer.writeCharCode(rune);
          }
      }
    }
    buffer.write(quote);
  }

  String _decodeString(String data) {
    var buffer = StringBuffer();
    var quote = data[0];
    if (quote != "'" && quote != '"') {
      throw 'Missing quote on string';
    }
    if (data[data.length - 1] != quote) {
      throw 'Missing end quote on string';
    }
    for (var i = 1; i < data.length - 1; i++) {
      var c = data[i];
      if (c == r'\') {
        i++;
        var remaining = data.length - 1 - i;
        if (remaining <= 0) {
          throw 'Escape character at end of string';
        }
        switch (data[i]) {
          case 'a': // bell
            buffer.writeCharCode(7);
            break;
          case 'b': // backspace
            buffer.writeCharCode(8);
            break;
          case 't': // tab
            buffer.writeCharCode(9);
            break;
          case 'n': // newline
            buffer.writeCharCode(10);
            break;
          case 'v': // vertical tab
            buffer.writeCharCode(11);
            break;
          case 'f': // form feed
            buffer.writeCharCode(12);
            break;
          case 'r': // carriage return
            buffer.writeCharCode(13);
            break;
          case 'u':
            if (remaining < 5) {
              throw ('Not enough space for unicode character');
            }
            buffer.writeCharCode(
                int.parse(data.substring(i + 1, i + 5), radix: 16));
            i += 4;
            break;
          case 'U':
            if (remaining < 9) {
              throw ('Not enough space for unicode character');
            }
            buffer.writeCharCode(
                int.parse(data.substring(i + 1, i + 9), radix: 16));
            i += 8;
            break;
          case '"':
          case "'":
          case r'\':
          default:
            buffer.write(data[i]);
            break;
        }
      } else {
        buffer.write(data[i]);
      }
    }
    return buffer.toString();
  }
}
