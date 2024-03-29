import 'dart:io';
import 'dart:typed_data';

import 'package:dbus/dbus.dart';
import 'package:gsettings/gsettings.dart';
import 'package:gsettings/src/dconf_client.dart';
import 'package:gsettings/src/gvariant_binary_codec.dart';
import 'package:gsettings/src/gvariant_text_codec.dart';
import 'package:test/test.dart';

// Unknown DBus value type that can't be encoded.
class UnknownValue extends DBusValue {
  @override
  DBusSignature get signature => DBusSignature('%');

  @override
  dynamic toNative() => '%';
}

class MockDConfWriter extends DBusObject {
  final MockDConfServer server;

  MockDConfWriter(this.server, String name)
      : super(DBusObjectPath('/ca/desrt/dconf/Writer/$name'));

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != 'ca.desrt.dconf.Writer') {
      return DBusMethodErrorResponse.unknownInterface();
    }

    switch (methodCall.name) {
      case 'Change':
        var blob = methodCall.values[0].asByteArray().toList();
        return handleChange(blob);
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }

  DBusMethodResponse handleChange(List<int> blob) {
    var codec = GVariantBinaryCodec();
    var data = ByteData.view(Uint8List.fromList(blob).buffer);
    var changeset = codec
        .decode('a{smv}', data, endian: Endian.host)
        .asDict()
        .map((key, value) =>
            MapEntry(key.asString(), value.asMaybe()?.asVariant()));
    for (var entry in changeset.entries) {
      if (entry.value == null) {
        server.values.remove(entry.key);
      } else {
        server.values[entry.key] = entry.value!;
      }
    }
    return DBusMethodSuccessResponse([DBusString('')]);
  }

  Future<void> emitNotify(String prefix, Iterable<String> paths,
      {String tag = ''}) async {
    await emitSignal('ca.desrt.dconf.Writer', 'Notify',
        [DBusString(prefix), DBusArray.string(paths), DBusString(tag)]);
  }
}

class MockDConfServer extends DBusClient {
  // Written values.
  final values = <String, DBusValue>{};

  late final MockDConfWriter _writer;

  MockDConfServer(DBusAddress clientAddress,
      {Map<String, DBusValue> values = const {}})
      : super(clientAddress) {
    this.values.addAll(values);
    _writer = MockDConfWriter(this, 'test');
  }

  Future<void> start() async {
    await requestName('ca.desrt.dconf');
    await registerObject(_writer);
  }

  Future<void> setValue(String path, DBusValue value) async {
    var i = path.lastIndexOf('/');
    String prefix;
    List<String> paths;
    if (i >= 0) {
      prefix = path.substring(0, i + 1);
      paths = [path.substring(i + 1)];
    } else {
      prefix = path;
      paths = [];
    }
    values[path] = value;
    await _writer.emitNotify(prefix, paths);
  }
}

void main() {
  group('GVariant', () {
    test('text encode', () async {
      var codec = GVariantTextCodec();

      expect(codec.encode(DBusBoolean(false)), equals('false'));
      expect(codec.encode(DBusBoolean(true)), equals('true'));

      expect(codec.encode(DBusByte(0x00)), equals('0x00'));
      expect(codec.encode(DBusByte(0xde)), equals('0xde'));
      expect(codec.encode(DBusByte(0xff)), equals('0xff'));

      expect(codec.encode(DBusInt16(0)), equals('0'));
      expect(codec.encode(DBusInt16(32767)), equals('32767'));
      expect(codec.encode(DBusInt16(-1)), equals('-1'));
      expect(codec.encode(DBusInt16(-32768)), equals('-32768'));

      expect(codec.encode(DBusUint16(0)), equals('0'));
      expect(codec.encode(DBusUint16(65535)), equals('65535'));

      expect(codec.encode(DBusInt32(0)), equals('0'));
      expect(codec.encode(DBusInt32(2147483647)), equals('2147483647'));
      expect(codec.encode(DBusInt32(-1)), equals('-1'));
      expect(codec.encode(DBusInt32(-2147483648)), equals('-2147483648'));

      expect(codec.encode(DBusUint32(0)), equals('0'));
      expect(codec.encode(DBusUint32(4294967295)), equals('4294967295'));

      expect(codec.encode(DBusInt64(0)), equals('0'));
      expect(codec.encode(DBusInt64(9223372036854775807)),
          equals('9223372036854775807'));
      expect(codec.encode(DBusInt64(-1)), equals('-1'));
      expect(codec.encode(DBusInt64(-9223372036854775808)),
          equals('-9223372036854775808'));

      expect(codec.encode(DBusUint64(0)), equals('0'));
      //FIXMEexpect(codec.encode(DBusUint64(0xffffffffffffffff)), equals('18446744073709551615'));

      expect(codec.encode(DBusDouble(0)), equals('0.0'));
      expect(codec.encode(DBusDouble(3.14159)), equals('3.14159'));
      expect(codec.encode(DBusDouble(-3.14159)), equals('-3.14159'));

      expect(codec.encode(DBusString('')), equals("''"));
      expect(codec.encode(DBusString('hello world')), equals("'hello world'"));
      expect(codec.encode(DBusString("hello 'world'")),
          equals('"hello \'world\'"'));
      expect(codec.encode(DBusString('hello "world"')),
          equals("'hello \"world\"'"));
      expect(codec.encode(DBusString('\'hello\' "world"')),
          equals('"\'hello\' \\"world\\""'));
      expect(
          codec.encode(DBusString(r'hello\world')), equals(r"'hello\\world'"));
      expect(codec.encode(DBusString('😄🙃🤪🧐')), equals("'😄🙃🤪🧐'"));
      expect(codec.encode(DBusString('\u0007\b\f\n\r\t\v')),
          equals(r"'\a\b\f\n\r\t\v'"));
      expect(codec.encode(DBusString('\x9f')), equals(r"'\u009f'"));
      expect(codec.encode(DBusString('\uffff')), equals(r"'\uffff'"));
      expect(codec.encode(DBusString('\u{100000}')), equals(r"'\U00100000'"));

      expect(codec.encode(DBusObjectPath('/')), equals("objectpath '/'"));
      expect(codec.encode(DBusObjectPath('/com/example/Foo')),
          equals("objectpath '/com/example/Foo'"));

      expect(codec.encode(DBusSignature('')), equals("signature ''"));
      expect(codec.encode(DBusSignature('a{sv}')), equals("signature 'a{sv}'"));

      expect(codec.encode(DBusVariant(DBusInt32(42))), equals('<42>'));
      expect(
          codec.encode(DBusVariant(DBusString('hello'))), equals("<'hello'>"));

      expect(
          codec.encode(DBusMaybe(DBusSignature('i'), null)), equals('nothing'));
      expect(codec.encode(DBusMaybe(DBusSignature('i'), DBusInt32(42))),
          equals('42'));
      expect(
          codec.encode(DBusMaybe(
              DBusSignature('mms'), DBusMaybe(DBusSignature('ms'), null))),
          equals('just nothing'));

      expect(codec.encode(DBusStruct([])), equals('()'));
      expect(codec.encode(DBusStruct([DBusInt32(42), DBusString('hello')])),
          equals("(42, 'hello')"));

      expect(codec.encode(DBusArray.int32([])), equals('[]'));
      expect(codec.encode(DBusArray.int32([1, 2, 3])), equals('[1, 2, 3]'));

      expect(codec.encode(DBusDict(DBusSignature('s'), DBusSignature('i'), {})),
          equals('{}'));
      expect(
          codec.encode(DBusDict(DBusSignature('s'), DBusSignature('i'), {
            DBusString('one'): DBusInt32(1),
            DBusString('two'): DBusInt32(2),
            DBusString('three'): DBusInt32(3)
          })),
          equals("{'one': 1, 'two': 2, 'three': 3}"));

      expect(() => codec.encode(UnknownValue()), throwsFormatException);
    });

    test('text decode', () async {
      var codec = GVariantTextCodec();

      expect(codec.decode('b', 'false'), equals(DBusBoolean(false)));
      expect(codec.decode('b', 'true'), equals(DBusBoolean(true)));
      expect(() => codec.decode('b', ''), throwsFormatException);
      expect(() => codec.decode('b', '!'), throwsFormatException);

      expect(codec.decode('y', '0x00'), equals(DBusByte(0x00)));
      expect(codec.decode('y', '0xde'), equals(DBusByte(0xde)));
      expect(codec.decode('y', '0xff'), equals(DBusByte(0xff)));
      expect(() => codec.decode('y', ''), throwsFormatException);
      expect(() => codec.decode('y', '!'), throwsFormatException);

      expect(codec.decode('n', '0'), equals(DBusInt16(0)));
      expect(codec.decode('n', '32767'), equals(DBusInt16(32767)));
      expect(codec.decode('n', '-1'), equals(DBusInt16(-1)));
      expect(codec.decode('n', '-32768'), equals(DBusInt16(-32768)));
      expect(() => codec.decode('n', ''), throwsFormatException);
      expect(() => codec.decode('n', '!'), throwsFormatException);

      expect(codec.decode('q', '0'), equals(DBusUint16(0)));
      expect(codec.decode('q', '65535'), equals(DBusUint16(65535)));
      expect(() => codec.decode('q', ''), throwsFormatException);
      expect(() => codec.decode('q', '!'), throwsFormatException);

      expect(codec.decode('i', '0'), equals(DBusInt32(0)));
      expect(codec.decode('i', '2147483647'), equals(DBusInt32(2147483647)));
      expect(codec.decode('i', '-1'), equals(DBusInt32(-1)));
      expect(codec.decode('i', '-2147483648'), equals(DBusInt32(-2147483648)));
      expect(() => codec.decode('i', ''), throwsFormatException);
      expect(() => codec.decode('i', '!'), throwsFormatException);

      expect(codec.decode('u', '0'), equals(DBusUint32(0)));
      expect(codec.decode('u', '4294967295'), equals(DBusUint32(4294967295)));
      expect(() => codec.decode('u', ''), throwsFormatException);
      expect(() => codec.decode('u', '!'), throwsFormatException);

      expect(codec.decode('x', '0'), equals(DBusInt64(0)));
      expect(codec.decode('x', '9223372036854775807'),
          equals(DBusInt64(9223372036854775807)));
      expect(codec.decode('x', '-1'), equals(DBusInt64(-1)));
      expect(codec.decode('x', '-9223372036854775808'),
          equals(DBusInt64(-9223372036854775808)));
      expect(() => codec.decode('x', ''), throwsFormatException);
      expect(() => codec.decode('x', '!'), throwsFormatException);

      expect(codec.decode('t', '0'), equals(DBusUint64(0)));
      //expect(codec.decode('t', '18446744073709551615'), equals(DBusUint64(0xffffffffffffffff)));
      expect(() => codec.decode('t', ''), throwsFormatException);
      expect(() => codec.decode('t', '!'), throwsFormatException);

      expect(codec.decode('d', '0.0'), equals(DBusDouble(0)));
      expect(codec.decode('d', '3.14159'), equals(DBusDouble(3.14159)));
      expect(codec.decode('d', '-3.14159'), equals(DBusDouble(-3.14159)));
      expect(() => codec.decode('d', ''), throwsFormatException);
      expect(() => codec.decode('d', '!'), throwsFormatException);

      expect(codec.decode('s', "''"), equals(DBusString('')));
      expect(codec.decode('s', "'hello world'"),
          equals(DBusString('hello world')));
      expect(codec.decode('s', '"hello \'world\'"'),
          equals(DBusString("hello 'world'")));
      expect(codec.decode('s', "'hello \"world\"'"),
          equals(DBusString('hello "world"')));
      expect(codec.decode('s', '"\'hello\' \\"world\\""'),
          equals(DBusString('\'hello\' "world"')));
      expect(codec.decode('s', r"'hello\\world'"),
          equals(DBusString(r'hello\world')));
      expect(codec.decode('s', "'😄🙃🤪🧐'"), equals(DBusString('😄🙃🤪🧐')));
      expect(codec.decode('s', r"'\a\b\f\n\r\t\v'"),
          equals(DBusString('\u0007\b\f\n\r\t\v')));
      expect(codec.decode('s', r"'\u009f'"), equals(DBusString('\x9f')));
      expect(codec.decode('s', r"'\ue000'"), equals(DBusString('\ue000')));
      expect(
          codec.decode('s', r"'\U00100000'"), equals(DBusString('\u{100000}')));
      expect(() => codec.decode('s', "'Hello world"), throwsFormatException);
      expect(() => codec.decode('s', "Hello world'"), throwsFormatException);
      expect(() => codec.decode('s', '"Hello world'), throwsFormatException);
      expect(() => codec.decode('s', 'Hello world"'), throwsFormatException);
      expect(() => codec.decode('s', '"Hello world\''), throwsFormatException);
      expect(() => codec.decode('s', '\'Hello world"'), throwsFormatException);
      expect(() => codec.decode('s', "'Hello world\\'"), throwsFormatException);
      expect(() => codec.decode('s', r"'\u'"), throwsFormatException);
      expect(() => codec.decode('s', r"'\u0'"), throwsFormatException);
      expect(() => codec.decode('s', r"'\U'"), throwsFormatException);
      expect(() => codec.decode('s', r"'\U0'"), throwsFormatException);
      expect(() => codec.decode('s', ''), throwsFormatException);
      expect(() => codec.decode('s', '!'), throwsFormatException);

      expect(codec.decode('o', "objectpath '/'"), equals(DBusObjectPath('/')));
      expect(codec.decode('o', "objectpath '/com/example/Foo'"),
          equals(DBusObjectPath('/com/example/Foo')));
      expect(() => codec.decode('o', "objectpath'/'"), throwsFormatException);
      expect(() => codec.decode('o', "'/'"), throwsFormatException);
      expect(() => codec.decode('o', ''), throwsFormatException);
      expect(() => codec.decode('o', '!'), throwsFormatException);

      expect(codec.decode('g', "signature ''"), equals(DBusSignature('')));
      expect(codec.decode('g', "signature 'a{sv}'"),
          equals(DBusSignature('a{sv}')));
      expect(() => codec.decode('g', "signature''"), throwsFormatException);
      expect(() => codec.decode('g', "''"), throwsFormatException);
      expect(() => codec.decode('g', ''), throwsFormatException);
      expect(() => codec.decode('g', '!'), throwsFormatException);

      expect(codec.decode('mi', 'nothing'),
          equals(DBusMaybe(DBusSignature('i'), null)));
      expect(codec.decode('mi', '42'),
          equals(DBusMaybe(DBusSignature('i'), DBusInt32(42))));
      expect(
          codec.decode('mms', 'just nothing'),
          equals(DBusMaybe(
              DBusSignature('ms'), DBusMaybe(DBusSignature('s'), null))));
      expect(() => codec.decode('mi', ''), throwsFormatException);
      expect(() => codec.decode('mi', '!'), throwsFormatException);

      expect(codec.decode('()', '()'), equals(DBusStruct([])));
      expect(codec.decode('(is)', "(42,'hello')"),
          equals(DBusStruct([DBusInt32(42), DBusString('hello')])));
      expect(codec.decode('(is)', "(42, 'hello')"),
          equals(DBusStruct([DBusInt32(42), DBusString('hello')])));
      expect(() => codec.decode('(is)', "(42 'hello')"), throwsFormatException);
      expect(() => codec.decode('(is)', "42,'hello')"), throwsFormatException);
      expect(() => codec.decode('(is)', "(42,'hello'"), throwsFormatException);
      expect(() => codec.decode('(is)', ''), throwsFormatException);
      expect(() => codec.decode('(is)', '!'), throwsFormatException);

      expect(codec.decode('ai', '[]'), equals(DBusArray.int32([])));
      expect(codec.decode('ai', '[1,2,3]'), equals(DBusArray.int32([1, 2, 3])));
      expect(
          codec.decode('ai', '[1, 2, 3]'), equals(DBusArray.int32([1, 2, 3])));
      expect(() => codec.decode('ai', '1, 2, 3]'), throwsFormatException);
      expect(() => codec.decode('ai', '[1, 2, 3'), throwsFormatException);
      expect(() => codec.decode('ai', '[1 2 3]'), throwsFormatException);
      expect(() => codec.decode('ai', ''), throwsFormatException);
      expect(() => codec.decode('ai', '!'), throwsFormatException);

      expect(codec.decode('a{si}', '{}'),
          equals(DBusDict(DBusSignature('s'), DBusSignature('i'), {})));
      expect(
          codec.decode('a{si}', "{'one': 1, 'two': 2, 'three': 3}"),
          equals(DBusDict(DBusSignature('s'), DBusSignature('i'), {
            DBusString('one'): DBusInt32(1),
            DBusString('two'): DBusInt32(2),
            DBusString('three'): DBusInt32(3)
          })));
      expect(
          codec.decode('a{si}', "{'one':1,'two':2,'three':3}"),
          equals(DBusDict(DBusSignature('s'), DBusSignature('i'), {
            DBusString('one'): DBusInt32(1),
            DBusString('two'): DBusInt32(2),
            DBusString('three'): DBusInt32(3)
          })));
      expect(() => codec.decode('a{si}', "'one':1,'two':2,'three':3}"),
          throwsFormatException);
      expect(() => codec.decode('a{si}', "{'one':1,'two':2,'three':3"),
          throwsFormatException);
      expect(() => codec.decode('a{si}', "{'one':1 'two':2 'three':3}"),
          throwsFormatException);
      expect(() => codec.decode('a{si}', "{'one' 1, 'two' 2, 'three' 3}"),
          throwsFormatException);
      expect(() => codec.decode('a{si}', ''), throwsFormatException);
      expect(() => codec.decode('a{si}', '!'), throwsFormatException);

      expect(() => codec.decode('b', 'false false'), throwsFormatException);
      expect(() => codec.decode('%', 'false'), throwsArgumentError);
    });

    test('binary encode', () async {
      var codec = GVariantBinaryCodec();

      expect(codec.encode(DBusBoolean(false), endian: Endian.little),
          equals([0x00]));
      expect(codec.encode(DBusBoolean(true), endian: Endian.little),
          equals([0x01]));

      expect(
          codec.encode(DBusByte(0x00), endian: Endian.little), equals([0x00]));
      expect(
          codec.encode(DBusByte(0xde), endian: Endian.little), equals([0xde]));
      expect(
          codec.encode(DBusByte(0xff), endian: Endian.little), equals([0xff]));

      expect(codec.encode(DBusInt16(0), endian: Endian.little),
          equals([0x00, 0x00]));
      expect(codec.encode(DBusInt16(32767), endian: Endian.little),
          equals([0xff, 0x7f]));
      expect(codec.encode(DBusInt16(32767), endian: Endian.big),
          equals([0x7f, 0xff]));
      expect(codec.encode(DBusInt16(-1), endian: Endian.little),
          equals([0xff, 0xff]));
      expect(codec.encode(DBusInt16(-32768), endian: Endian.little),
          equals([0x00, 0x80]));
      expect(codec.encode(DBusInt16(-32768), endian: Endian.big),
          equals([0x80, 0x00]));

      expect(codec.encode(DBusUint16(0), endian: Endian.little),
          equals([0x00, 0x00]));
      expect(codec.encode(DBusUint16(255), endian: Endian.little),
          equals([0xff, 0x00]));
      expect(codec.encode(DBusUint16(255), endian: Endian.big),
          equals([0x00, 0xff]));
      expect(codec.encode(DBusUint16(65535), endian: Endian.little),
          equals([0xff, 0xff]));

      expect(codec.encode(DBusInt32(0), endian: Endian.little),
          equals([0x00, 0x00, 0x00, 0x00]));
      expect(codec.encode(DBusInt32(2147483647), endian: Endian.little),
          equals([0xff, 0xff, 0xff, 0x7f]));
      expect(codec.encode(DBusInt32(2147483647), endian: Endian.big),
          equals([0x7f, 0xff, 0xff, 0xff]));
      expect(codec.encode(DBusInt32(-1), endian: Endian.little),
          equals([0xff, 0xff, 0xff, 0xff]));
      expect(codec.encode(DBusInt32(-2147483648), endian: Endian.little),
          equals([0x00, 0x00, 0x00, 0x80]));
      expect(codec.encode(DBusInt32(-2147483648), endian: Endian.big),
          equals([0x80, 0x00, 0x00, 0x00]));

      expect(codec.encode(DBusUint32(0), endian: Endian.little),
          equals([0x00, 0x00, 0x00, 0x00]));
      expect(codec.encode(DBusUint32(255), endian: Endian.little),
          equals([0xff, 0x00, 0x00, 0x00]));
      expect(codec.encode(DBusUint32(255), endian: Endian.big),
          equals([0x00, 0x00, 0x00, 0xff]));
      expect(codec.encode(DBusUint32(4294967295), endian: Endian.little),
          equals([0xff, 0xff, 0xff, 0xff]));

      expect(codec.encode(DBusInt64(0), endian: Endian.little),
          equals([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]));
      expect(
          codec.encode(DBusInt64(9223372036854775807), endian: Endian.little),
          equals([0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x7f]));
      expect(codec.encode(DBusInt64(9223372036854775807), endian: Endian.big),
          equals([0x7f, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]));
      expect(codec.encode(DBusInt64(-1), endian: Endian.little),
          equals([0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]));
      expect(
          codec.encode(DBusInt64(-9223372036854775808), endian: Endian.little),
          equals([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80]));
      expect(codec.encode(DBusInt64(-9223372036854775808), endian: Endian.big),
          equals([0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]));

      expect(codec.encode(DBusUint64(0), endian: Endian.little),
          equals([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]));
      expect(codec.encode(DBusUint64(255), endian: Endian.little),
          equals([0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]));
      expect(codec.encode(DBusUint64(255), endian: Endian.big),
          equals([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff]));
      expect(
          codec.encode(DBusUint64(0xffffffffffffffff), endian: Endian.little),
          equals([0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]));

      expect(codec.encode(DBusDouble(0), endian: Endian.little),
          equals([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]));
      expect(codec.encode(DBusDouble(3.14159), endian: Endian.little),
          equals([0x6e, 0x86, 0x1b, 0xf0, 0xf9, 0x21, 0x09, 0x40]));
      expect(codec.encode(DBusDouble(3.14159), endian: Endian.big),
          equals([0x40, 0x09, 0x21, 0xf9, 0xf0, 0x1b, 0x86, 0x6e]));
      expect(codec.encode(DBusDouble(-3.14159), endian: Endian.little),
          equals([0x6e, 0x86, 0x1b, 0xf0, 0xf9, 0x21, 0x09, 0xc0]));

      expect(
          codec.encode(DBusString(''), endian: Endian.little), equals([0x00]));
      expect(codec.encode(DBusString('hello'), endian: Endian.little),
          equals([0x68, 0x65, 0x6c, 0x6c, 0x6f, 0x00]));
      expect(
          codec.encode(DBusString('😄🙃🤪🧐'), endian: Endian.little),
          equals([
            0xf0,
            0x9f,
            0x98,
            0x84,
            0xf0,
            0x9f,
            0x99,
            0x83,
            0xf0,
            0x9f,
            0xa4,
            0xaa,
            0xf0,
            0x9f,
            0xa7,
            0x90,
            0
          ]));

      expect(codec.encode(DBusObjectPath('/'), endian: Endian.little),
          equals([0x2f, 0x00]));

      expect(codec.encode(DBusSignature(''), endian: Endian.little),
          equals([0x00]));
      expect(
          codec.encode(DBusSignature('ynqiuxtdsogasa{sv}(ii)'),
              endian: Endian.little),
          equals([
            0x79,
            0x6e,
            0x71,
            0x69,
            0x75,
            0x78,
            0x74,
            0x64,
            0x73,
            0x6f,
            0x67,
            0x61,
            0x73,
            0x61,
            0x7b,
            0x73,
            0x76,
            0x7d,
            0x28,
            0x69,
            0x69,
            0x29,
            0x00
          ]));

      expect(codec.encode(DBusVariant(DBusByte(0x80)), endian: Endian.little),
          equals([0x80, 0x00, 0x79]));
      expect(
          codec.encode(DBusVariant(DBusString('hello')), endian: Endian.little),
          equals([0x68, 0x65, 0x6c, 0x6c, 0x6f, 0x00, 0x00, 0x73]));

      // Empty maybe
      expect(
          codec.encode(DBusMaybe(DBusSignature('s'), null),
              endian: Endian.little),
          equals([]));
      expect(
          codec.encode(DBusMaybe(DBusSignature('i'), null),
              endian: Endian.little),
          equals([]));
      // Variable length value, has null padding.
      expect(
          codec.encode(DBusMaybe(DBusSignature('s'), DBusString('hello')),
              endian: Endian.little),
          equals([0x68, 0x65, 0x6c, 0x6c, 0x6f, 0x00, 0x00]));
      // Fixed length value.
      expect(
          codec.encode(DBusMaybe(DBusSignature('i'), DBusInt32(42)),
              endian: Endian.little),
          equals([0x2a, 0x00, 0x00, 0x00]));

      expect(codec.encode(DBusStruct([]), endian: Endian.little), equals([]));
      expect(
          codec.encode(DBusStruct([DBusByte(0xde), DBusByte(0xad)]),
              endian: Endian.little),
          equals([0xde, 0xad]));
      // Mixed alignment
      expect(
          codec.encode(DBusStruct([DBusByte(42), DBusInt32(-1)]),
              endian: Endian.little),
          equals([0x2a, 0x00, 0x00, 0x00, 0xff, 0xff, 0xff, 0xff]));
      expect(
          codec.encode(DBusStruct([DBusInt32(-1), DBusByte(42)]),
              endian: Endian.little),
          equals([0xff, 0xff, 0xff, 0xff, 0x2a, 0x00, 0x00, 0x00]));
      // First element is fixed size, second is variable - no offsets required
      expect(
          codec.encode(DBusStruct([DBusByte(42), DBusString('hello')]),
              endian: Endian.little),
          equals([0x2a, 0x68, 0x65, 0x6c, 0x6c, 0x6f, 0x00]));
      // First element is variable size, second is fixed - offset required
      expect(
          codec.encode(DBusStruct([DBusString('hello'), DBusByte(42)]),
              endian: Endian.little),
          equals([0x68, 0x65, 0x6c, 0x6c, 0x6f, 0x00, 0x2a, 0x06]));
      // Multiple offsets required (in reverse order)
      expect(
          codec.encode(
              DBusStruct(
                  [DBusString('hello'), DBusString('world'), DBusString('!')]),
              endian: Endian.little),
          equals([
            0x68,
            0x65,
            0x6c,
            0x6c,
            0x6f,
            0x00,
            0x77,
            0x6f,
            0x72,
            0x6c,
            0x64,
            0x00,
            0x21,
            0x00,
            0x0c,
            0x06
          ]));

      expect(
          codec.encode(DBusArray.byte([]), endian: Endian.little), equals([]));
      expect(codec.encode(DBusArray.byte([1, 2, 3]), endian: Endian.little),
          equals([0x01, 0x02, 0x03]));
      expect(
          codec.encode(DBusArray.string(['hello', 'world']),
              endian: Endian.little),
          equals([
            0x68,
            0x65,
            0x6c,
            0x6c,
            0x6f,
            0x00,
            0x77,
            0x6f,
            0x72,
            0x6c,
            0x64,
            0x00,
            0x06,
            0x0c
          ]));

      expect(
          codec.encode(DBusDict(DBusSignature('s'), DBusSignature('i'), {}),
              endian: Endian.little),
          equals([]));
      // Fixed size keys
      expect(
          codec.encode(
              DBusDict(DBusSignature('y'), DBusSignature('y'),
                  {DBusByte(0): DBusByte(255), DBusByte(1): DBusByte(254)}),
              endian: Endian.little),
          equals([0x00, 0xff, 0x01, 0xfe]));
      // Variable sized keys
      expect(
          codec.encode(
              DBusDict(DBusSignature('s'), DBusSignature('i'), {
                DBusString('one'): DBusInt32(1),
                DBusString('two'): DBusInt32(2)
              }),
              endian: Endian.little),
          equals([
            0x6f,
            0x6e,
            0x65,
            0x00,
            0x01,
            0x00,
            0x00,
            0x00,
            0x04,
            0x00,
            0x00,
            0x00,
            0x74,
            0x77,
            0x6f,
            0x00,
            0x02,
            0x00,
            0x00,
            0x00,
            0x04,
            0x09,
            0x15
          ]));
    });

    test('binary decode', () async {
      var codec = GVariantBinaryCodec();

      ByteData makeBuffer(List<int> data) {
        return ByteData.view(Uint8List.fromList(data).buffer);
      }

      expect(codec.decode('b', makeBuffer([0x00]), endian: Endian.little),
          equals(DBusBoolean(false)));
      expect(codec.decode('b', makeBuffer([0x01]), endian: Endian.little),
          equals(DBusBoolean(true)));

      expect(codec.decode('y', makeBuffer([0x00]), endian: Endian.little),
          equals(DBusByte(0x00)));
      expect(codec.decode('y', makeBuffer([0xde]), endian: Endian.little),
          equals(DBusByte(0xde)));
      expect(codec.decode('y', makeBuffer([0xff]), endian: Endian.little),
          equals(DBusByte(0xff)));

      expect(codec.decode('n', makeBuffer([0x00, 0x00]), endian: Endian.little),
          equals(DBusInt16(0)));
      expect(codec.decode('n', makeBuffer([0xff, 0x7f]), endian: Endian.little),
          equals(DBusInt16(32767)));
      expect(codec.decode('n', makeBuffer([0x7f, 0xff]), endian: Endian.big),
          equals(DBusInt16(32767)));
      expect(codec.decode('n', makeBuffer([0xff, 0xff]), endian: Endian.little),
          equals(DBusInt16(-1)));
      expect(codec.decode('n', makeBuffer([0x00, 0x80]), endian: Endian.little),
          equals(DBusInt16(-32768)));
      expect(codec.decode('n', makeBuffer([0x80, 0x00]), endian: Endian.big),
          equals(DBusInt16(-32768)));

      expect(codec.decode('q', makeBuffer([0x00, 0x00]), endian: Endian.little),
          equals(DBusUint16(0)));
      expect(codec.decode('q', makeBuffer([0xff, 0x00]), endian: Endian.little),
          equals(DBusUint16(255)));
      expect(codec.decode('q', makeBuffer([0x00, 0xff]), endian: Endian.big),
          equals(DBusUint16(255)));
      expect(codec.decode('q', makeBuffer([0xff, 0xff]), endian: Endian.little),
          equals(DBusUint16(65535)));

      expect(
          codec.decode('i', makeBuffer([0x00, 0x00, 0x00, 0x00]),
              endian: Endian.little),
          equals(DBusInt32(0)));
      expect(
          codec.decode('i', makeBuffer([0xff, 0xff, 0xff, 0x7f]),
              endian: Endian.little),
          equals(DBusInt32(2147483647)));
      expect(
          codec.decode('i', makeBuffer([0x7f, 0xff, 0xff, 0xff]),
              endian: Endian.big),
          equals(DBusInt32(2147483647)));
      expect(
          codec.decode('i', makeBuffer([0xff, 0xff, 0xff, 0xff]),
              endian: Endian.little),
          equals(DBusInt32(-1)));
      expect(
          codec.decode('i', makeBuffer([0x00, 0x00, 0x00, 0x80]),
              endian: Endian.little),
          equals(DBusInt32(-2147483648)));
      expect(
          codec.decode('i', makeBuffer([0x80, 0x00, 0x00, 0x00]),
              endian: Endian.big),
          equals(DBusInt32(-2147483648)));

      expect(
          codec.decode('u', makeBuffer([0x00, 0x00, 0x00, 0x00]),
              endian: Endian.little),
          equals(DBusUint32(0)));
      expect(
          codec.decode('u', makeBuffer([0xff, 0x00, 0x00, 0x00]),
              endian: Endian.little),
          equals(DBusUint32(255)));
      expect(
          codec.decode('u', makeBuffer([0x00, 0x00, 0x00, 0xff]),
              endian: Endian.big),
          equals(DBusUint32(255)));
      expect(
          codec.decode('u', makeBuffer([0xff, 0xff, 0xff, 0xff]),
              endian: Endian.little),
          equals(DBusUint32(4294967295)));

      expect(
          codec.decode(
              'x', makeBuffer([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
              endian: Endian.little),
          equals(DBusInt64(0)));
      expect(
          codec.decode(
              'x', makeBuffer([0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x7f]),
              endian: Endian.little),
          equals(DBusInt64(9223372036854775807)));
      expect(
          codec.decode(
              'x', makeBuffer([0x7f, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]),
              endian: Endian.big),
          equals(DBusInt64(9223372036854775807)));
      expect(
          codec.decode(
              'x', makeBuffer([0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]),
              endian: Endian.little),
          equals(DBusInt64(-1)));
      expect(
          codec.decode(
              'x', makeBuffer([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80]),
              endian: Endian.little),
          equals(DBusInt64(-9223372036854775808)));
      expect(
          codec.decode(
              'x', makeBuffer([0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
              endian: Endian.big),
          equals(DBusInt64(-9223372036854775808)));

      expect(
          codec.decode(
              't', makeBuffer([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
              endian: Endian.little),
          equals(DBusUint64(0)));
      expect(
          codec.decode(
              't', makeBuffer([0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
              endian: Endian.little),
          equals(DBusUint64(255)));
      expect(
          codec.decode(
              't', makeBuffer([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff]),
              endian: Endian.big),
          equals(DBusUint64(255)));
      expect(
          codec.decode(
              't', makeBuffer([0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]),
              endian: Endian.little),
          equals(DBusUint64(0xffffffffffffffff)));

      expect(
          codec.decode(
              'd', makeBuffer([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
              endian: Endian.little),
          equals(DBusDouble(0)));
      expect(
          codec.decode(
              'd', makeBuffer([0x6e, 0x86, 0x1b, 0xf0, 0xf9, 0x21, 0x09, 0x40]),
              endian: Endian.little),
          equals(DBusDouble(3.14159)));
      expect(
          codec.decode(
              'd', makeBuffer([0x40, 0x09, 0x21, 0xf9, 0xf0, 0x1b, 0x86, 0x6e]),
              endian: Endian.big),
          equals(DBusDouble(3.14159)));
      expect(
          codec.decode(
              'd', makeBuffer([0x6e, 0x86, 0x1b, 0xf0, 0xf9, 0x21, 0x09, 0xc0]),
              endian: Endian.little),
          equals(DBusDouble(-3.14159)));

      expect(codec.decode('s', makeBuffer([0x00]), endian: Endian.little),
          equals(DBusString('')));
      expect(
          codec.decode('s', makeBuffer([0x68, 0x65, 0x6c, 0x6c, 0x6f, 0x00]),
              endian: Endian.little),
          equals(DBusString('hello')));
      expect(
          codec.decode(
              's',
              makeBuffer([
                0xf0,
                0x9f,
                0x98,
                0x84,
                0xf0,
                0x9f,
                0x99,
                0x83,
                0xf0,
                0x9f,
                0xa4,
                0xaa,
                0xf0,
                0x9f,
                0xa7,
                0x90,
                0
              ]),
              endian: Endian.little),
          equals(DBusString('😄🙃🤪🧐')));

      expect(codec.decode('o', makeBuffer([0x2f, 0x00]), endian: Endian.little),
          equals(DBusObjectPath('/')));

      expect(codec.decode('g', makeBuffer([0x00]), endian: Endian.little),
          equals(DBusSignature('')));
      expect(
          codec.decode(
              'g',
              makeBuffer([
                0x79,
                0x6e,
                0x71,
                0x69,
                0x75,
                0x78,
                0x74,
                0x64,
                0x73,
                0x6f,
                0x67,
                0x61,
                0x73,
                0x61,
                0x7b,
                0x73,
                0x76,
                0x7d,
                0x28,
                0x69,
                0x69,
                0x29,
                0x00
              ]),
              endian: Endian.little),
          equals(DBusSignature('ynqiuxtdsogasa{sv}(ii)')));

      expect(
          codec.decode('v', makeBuffer([0x80, 0x00, 0x79]),
              endian: Endian.little),
          equals(DBusVariant(DBusByte(0x80))));
      expect(
          codec.decode(
              'v', makeBuffer([0x68, 0x65, 0x6c, 0x6c, 0x6f, 0x00, 0x00, 0x73]),
              endian: Endian.little),
          equals(DBusVariant(DBusString('hello'))));

      // Empty maybe.
      expect(codec.decode('ms', makeBuffer([]), endian: Endian.little),
          equals(DBusMaybe(DBusSignature('s'), null)));
      expect(codec.decode('mi', makeBuffer([]), endian: Endian.little),
          equals(DBusMaybe(DBusSignature('i'), null)));
      // Variable length value, has null padding.
      expect(
          codec.decode(
              'ms', makeBuffer([0x68, 0x65, 0x6c, 0x6c, 0x6f, 0x00, 0x00]),
              endian: Endian.little),
          equals(DBusMaybe(DBusSignature('s'), DBusString('hello'))));
      // Fixed length value.
      expect(
          codec.decode('mi', makeBuffer([0x2a, 0x00, 0x00, 0x00]),
              endian: Endian.little),
          equals(DBusMaybe(DBusSignature('i'), DBusInt32(42))));

      expect(
          codec.decode('(yy)', makeBuffer([0xde, 0xad]), endian: Endian.little),
          equals(DBusStruct([DBusByte(0xde), DBusByte(0xad)])));
      // Mixed alignment
      expect(
          codec.decode('(yi)',
              makeBuffer([0x2a, 0x00, 0x00, 0x00, 0xff, 0xff, 0xff, 0xff]),
              endian: Endian.little),
          equals(DBusStruct([DBusByte(42), DBusInt32(-1)])));
      expect(
          codec.decode('(iy)',
              makeBuffer([0xff, 0xff, 0xff, 0xff, 0x2a, 0x00, 0x00, 0x00]),
              endian: Endian.little),
          equals(DBusStruct([DBusInt32(-1), DBusByte(42)])));
      // First element is fixed size, second is variable - no offsets required
      expect(
          codec.decode(
              '(ys)', makeBuffer([0x2a, 0x68, 0x65, 0x6c, 0x6c, 0x6f, 0x00]),
              endian: Endian.little),
          equals(DBusStruct([DBusByte(42), DBusString('hello')])));
      // First element is variable size, second is fixed - offset required
      expect(
          codec.decode('(sy)',
              makeBuffer([0x68, 0x65, 0x6c, 0x6c, 0x6f, 0x00, 0x2a, 0x06]),
              endian: Endian.little),
          equals(DBusStruct([DBusString('hello'), DBusByte(42)])));
      // Multiple offsets required (in reverse order)
      expect(
          codec.decode(
              '(sss)',
              makeBuffer([
                0x68,
                0x65,
                0x6c,
                0x6c,
                0x6f,
                0x00,
                0x77,
                0x6f,
                0x72,
                0x6c,
                0x64,
                0x00,
                0x21,
                0x00,
                0x0c,
                0x06
              ]),
              endian: Endian.little),
          equals(DBusStruct(
              [DBusString('hello'), DBusString('world'), DBusString('!')])));

      expect(codec.decode('ay', makeBuffer([]), endian: Endian.little),
          equals(DBusArray.byte([])));
      expect(
          codec.decode('ay', makeBuffer([0x01, 0x02, 0x03]),
              endian: Endian.little),
          equals(DBusArray.byte([1, 2, 3])));
      expect(
          codec.decode(
              'as',
              makeBuffer([
                0x68,
                0x65,
                0x6c,
                0x6c,
                0x6f,
                0x00,
                0x77,
                0x6f,
                0x72,
                0x6c,
                0x64,
                0x00,
                0x06,
                0x0c
              ]),
              endian: Endian.little),
          equals(DBusArray.string(['hello', 'world'])));

      expect(codec.decode('a{si}', makeBuffer([]), endian: Endian.little),
          equals(DBusDict(DBusSignature('s'), DBusSignature('i'), {})));
      // Fixed size keys
      expect(
          codec.decode('a{yy}', makeBuffer([0x00, 0xff, 0x01, 0xfe]),
              endian: Endian.little),
          equals(DBusDict(DBusSignature('y'), DBusSignature('y'),
              {DBusByte(0): DBusByte(255), DBusByte(1): DBusByte(254)})));
      // Variable sized keys
      expect(
          codec.decode(
              'a{si}',
              makeBuffer([
                0x6f,
                0x6e,
                0x65,
                0x00,
                0x01,
                0x00,
                0x00,
                0x00,
                0x04,
                0x00,
                0x00,
                0x00,
                0x74,
                0x77,
                0x6f,
                0x00,
                0x02,
                0x00,
                0x00,
                0x00,
                0x04,
                0x09,
                0x15
              ]),
              endian: Endian.little),
          equals(DBusDict(DBusSignature('s'), DBusSignature('i'), {
            DBusString('one'): DBusInt32(1),
            DBusString('two'): DBusInt32(2)
          })));
    });
  });

  group('DConf', () {
    test('dconf client', () async {
      var server = DBusServer();
      addTearDown(() async => await server.close());
      var clientAddress = await server
          .listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

      var dconfServer = MockDConfServer(clientAddress);
      addTearDown(() async => await dconfServer.close());
      await dconfServer.start();

      var client = DConfClient(sessionBus: DBusClient(clientAddress));
      addTearDown(() async => await client.close());

      expect(await client.list('/'), equals(['com/']));
      expect(await client.list('/com/'), equals(['example/']));
      expect(await client.list('/com/example/'),
          equals(['test1/', 'relocatable1/']));
      expect(
          await client.list('/com/example/test1/'),
          equals([
            'boolean-value',
            'uint32-value',
            'signature-value',
            'string-value',
            'int32-value',
            'flags-value',
            'enum-value',
            'int16-value',
            'uint16-value',
            'range-value',
            'int64-value',
            'uint64-value',
            'object-path-value',
            'double-value',
            'byte-value'
          ]));

      expect(await client.read('/com/example/test1/string-value'),
          equals(DBusString('Hello World')));

      expect(
          await client.write(
              {'/com/example/test2/string-value': DBusString('Hello World')}),
          equals(''));
      expect(dconfServer.values['/com/example/test2/string-value'],
          equals(DBusString('Hello World')));
    });
  });

  group('GSettings', () {
    setUp(() async {
      // Check have the environment set up to only access the test schemas and dconf database, not the system ones.
      var testPath = '${Directory.current.path}/test';
      var dataDirs = Platform.environment['XDG_DATA_DIRS'];
      var expectedDataDirs = testPath;
      var validDataDirs = dataDirs == 'test' || dataDirs == expectedDataDirs;
      var dconfProfile = Platform.environment['DCONF_PROFILE'];
      var expectedDConfProfile = '$testPath/dconf/test-profile';
      var validDConfProfile = dconfProfile == expectedDConfProfile;
      var expectedConfigHome = testPath;
      var configHome = Platform.environment['XDG_CONFIG_HOME'];
      var validConfigHome = configHome == expectedConfigHome;
      if (!validDataDirs || !validDConfProfile || !validConfigHome) {
        fail(
            'Environment not setup to run GSettings tests, please re-run with XDG_DATA_DIRS=$expectedDataDirs XDG_CONFIG_HOME=$expectedConfigHome DCONF_PROFILE=$expectedDConfProfile dart test');
      }
    });

    test('list schemas', () async {
      var schemas = await listGSettingsSchemas();
      expect(
          schemas,
          equals([
            'com.example.Test1',
            'com.example.Test2',
            'com.example.Relocatable'
          ]));
    });

    test('unknown schema', () async {
      var settings = GSettings('com.example.DoesNotExist');
      addTearDown(() async => await settings.close());
      expect(() async => await settings.list(),
          throwsA(isA<GSettingsSchemaNotInstalledException>()));
    });

    test('list keys', () async {
      var settings = GSettings('com.example.Test1');
      addTearDown(() async => await settings.close());
      expect(
          await settings.list(),
          containsAll([
            'boolean-value',
            'byte-value',
            'int16-value',
            'uint16-value',
            'int32-value',
            'uint32-value',
            'int64-value',
            'uint64-value',
            'double-value',
            'string-value',
            'enum-value',
            'flags-value',
            'object-path-value',
            'signature-value'
          ]));
    });

    test('get - preset', () async {
      // Test1 schema has values set in DConf.
      var settings = GSettings('com.example.Test1');
      addTearDown(() async => await settings.close());

      expect(await settings.isSet('boolean-value'), isTrue);
      expect(await settings.getDefault('boolean-value'),
          equals(DBusBoolean(false)));
      expect(await settings.get('boolean-value'), equals(DBusBoolean(true)));

      expect(await settings.isSet('byte-value'), isTrue);
      expect(await settings.getDefault('byte-value'), equals(DBusByte(0)));
      expect(await settings.get('byte-value'), equals(DBusByte(0x2a)));

      expect(await settings.isSet('int16-value'), isTrue);
      expect(await settings.getDefault('int16-value'), equals(DBusInt16(0)));
      expect(await settings.get('int16-value'), equals(DBusInt16(-16)));

      expect(await settings.isSet('uint16-value'), isTrue);
      expect(await settings.getDefault('uint16-value'), equals(DBusUint16(0)));
      expect(await settings.get('uint16-value'), equals(DBusUint16(16)));

      expect(await settings.isSet('int32-value'), isTrue);
      expect(await settings.getDefault('int32-value'), equals(DBusInt32(0)));
      expect(await settings.get('int32-value'), equals(DBusInt32(-32)));

      expect(await settings.isSet('uint32-value'), isTrue);
      expect(await settings.getDefault('uint32-value'), equals(DBusUint32(0)));
      expect(await settings.get('uint32-value'), equals(DBusUint32(32)));

      expect(await settings.isSet('int64-value'), isTrue);
      expect(await settings.getDefault('int64-value'), equals(DBusInt64(0)));
      expect(await settings.get('int64-value'), equals(DBusInt64(-64)));

      expect(await settings.isSet('uint64-value'), isTrue);
      expect(await settings.getDefault('uint64-value'), equals(DBusUint64(0)));
      expect(await settings.get('uint64-value'), equals(DBusUint64(64)));

      expect(await settings.isSet('double-value'), isTrue);
      expect(await settings.getDefault('double-value'), equals(DBusDouble(0)));
      expect(await settings.get('double-value'), equals(DBusDouble(3.14159)));

      expect(await settings.isSet('string-value'), isTrue);
      expect(await settings.getDefault('string-value'), equals(DBusString('')));
      expect(await settings.get('string-value'),
          equals(DBusString('Hello World')));

      expect(await settings.isSet('enum-value'), isTrue);
      expect(
          await settings.getDefault('enum-value'), equals(DBusString('enum0')));
      expect(await settings.get('enum-value'), equals(DBusString('enum1')));

      expect(await settings.isSet('flags-value'), isTrue);
      expect(await settings.getDefault('flags-value'),
          equals(DBusArray.string([])));
      expect(await settings.get('flags-value'),
          equals(DBusArray.string(['flag1', 'flag4'])));

      expect(await settings.isSet('range-value'), isTrue);
      expect(await settings.getDefault('range-value'), equals(DBusUint32(0)));
      expect(await settings.get('range-value'), equals(DBusUint32(32)));

      expect(await settings.isSet('object-path-value'), isTrue);
      expect(await settings.getDefault('object-path-value'),
          equals(DBusObjectPath('/')));
      expect(await settings.get('object-path-value'),
          equals(DBusObjectPath('/com/example/Test2')));

      expect(await settings.isSet('signature-value'), isTrue);
      expect(await settings.getDefault('signature-value'),
          equals(DBusSignature('')));
      expect(await settings.get('signature-value'),
          equals(DBusSignature('a{sv}')));
    });

    test('get - unset', () async {
      // Test2 schema has no values set in DConf.
      var settings = GSettings('com.example.Test2');
      addTearDown(() async => await settings.close());

      expect(await settings.isSet('boolean-value'), isFalse);
      expect(await settings.get('boolean-value'), equals(DBusBoolean(false)));

      expect(await settings.isSet('byte-value'), isFalse);
      expect(await settings.get('byte-value'), equals(DBusByte(0)));

      expect(await settings.isSet('int16-value'), isFalse);
      expect(await settings.get('int16-value'), equals(DBusInt16(0)));

      expect(await settings.isSet('uint16-value'), isFalse);
      expect(await settings.get('uint16-value'), equals(DBusUint16(0)));

      expect(await settings.isSet('int32-value'), isFalse);
      expect(await settings.get('int32-value'), equals(DBusInt32(0)));

      expect(await settings.isSet('uint32-value'), isFalse);
      expect(await settings.get('uint32-value'), equals(DBusUint32(0)));

      expect(await settings.isSet('int64-value'), isFalse);
      expect(await settings.get('int64-value'), equals(DBusInt64(0)));

      expect(await settings.isSet('uint64-value'), isFalse);
      expect(await settings.get('uint64-value'), equals(DBusUint64(0)));

      expect(await settings.isSet('double-value'), isFalse);
      expect(await settings.get('double-value'), equals(DBusDouble(0.0)));

      expect(await settings.isSet('string-value'), isFalse);
      expect(await settings.get('string-value'), equals(DBusString('')));

      expect(await settings.isSet('enum-value'), isFalse);
      expect(await settings.get('enum-value'), equals(DBusString('enum0')));

      expect(await settings.isSet('flags-value'), isFalse);
      expect(await settings.get('flags-value'), equals(DBusArray.string([])));

      expect(await settings.isSet('range-value'), isFalse);
      expect(await settings.get('range-value'), equals(DBusUint32(0)));

      expect(await settings.isSet('object-path-value'), isFalse);
      expect(
          await settings.get('object-path-value'), equals(DBusObjectPath('/')));

      expect(await settings.isSet('signature-value'), isFalse);
      expect(await settings.get('signature-value'), equals(DBusSignature('')));
    });

    test('unknown key', () async {
      var settings = GSettings('com.example.Test1');
      addTearDown(() async => await settings.close());
      expect(() async => await settings.get('no-such-key'),
          throwsA(isA<GSettingsUnknownKeyException>()));
    });

    test('set', () async {
      var server = DBusServer();
      addTearDown(() async => await server.close());
      var clientAddress = await server
          .listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

      var dconfServer = MockDConfServer(clientAddress);
      addTearDown(() async => await dconfServer.close());
      await dconfServer.start();

      var settings =
          GSettings('com.example.Test2', sessionBus: DBusClient(clientAddress));
      addTearDown(() async => await settings.close());

      await settings.set('boolean-value', DBusBoolean(true));
      expect(dconfServer.values['/com/example/test2/boolean-value'],
          equals(DBusBoolean(true)));

      await settings.set('byte-value', DBusByte(0x2a));
      expect(dconfServer.values['/com/example/test2/byte-value'],
          equals(DBusByte(0x2a)));

      await settings.set('int16-value', DBusInt16(-16));
      expect(dconfServer.values['/com/example/test2/int16-value'],
          equals(DBusInt16(-16)));

      await settings.set('uint16-value', DBusUint16(16));
      expect(dconfServer.values['/com/example/test2/uint16-value'],
          equals(DBusUint16(16)));

      await settings.set('int32-value', DBusInt32(-32));
      expect(dconfServer.values['/com/example/test2/int32-value'],
          equals(DBusInt32(-32)));

      await settings.set('uint32-value', DBusUint32(32));
      expect(dconfServer.values['/com/example/test2/uint32-value'],
          equals(DBusUint32(32)));

      await settings.set('int64-value', DBusInt64(-64));
      expect(dconfServer.values['/com/example/test2/int64-value'],
          equals(DBusInt64(-64)));

      await settings.set('uint64-value', DBusUint64(64));
      expect(dconfServer.values['/com/example/test2/uint64-value'],
          equals(DBusUint64(64)));

      await settings.set('double-value', DBusDouble(3.14159));
      expect(dconfServer.values['/com/example/test2/double-value'],
          equals(DBusDouble(3.14159)));

      await settings.set('string-value', DBusString('Hello World'));
      expect(dconfServer.values['/com/example/test2/string-value'],
          equals(DBusString('Hello World')));

      await settings.set('enum-value', DBusString('enum1'));
      expect(dconfServer.values['/com/example/test2/enum-value'],
          equals(DBusString('enum1')));

      await settings.set('flags-value', DBusArray.string(['flag1', 'flag4']));
      expect(dconfServer.values['/com/example/test2/flags-value'],
          equals(DBusArray.string(['flag1', 'flag4'])));

      await settings.set('range-value', DBusUint32(32));
      expect(dconfServer.values['/com/example/test2/range-value'],
          equals(DBusUint32(32)));

      await settings.set(
          'object-path-value', DBusObjectPath('/com/example/Test2'));
      expect(dconfServer.values['/com/example/test2/object-path-value'],
          equals(DBusObjectPath('/com/example/Test2')));

      await settings.set('signature-value', DBusSignature('a{sv}'));
      expect(dconfServer.values['/com/example/test2/signature-value'],
          equals(DBusSignature('a{sv}')));
    });

    test('unset', () async {
      var server = DBusServer();
      addTearDown(() async => await server.close());
      var clientAddress = await server
          .listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

      var dconfServer = MockDConfServer(clientAddress, values: {
        '/com/example/test2/boolean-value': DBusBoolean(true),
        '/com/example/test2/byte-value': DBusByte(0x2a),
        '/com/example/test2/int16-value': DBusInt16(-16),
        '/com/example/test2/uint16-value': DBusUint16(16),
        '/com/example/test2/int32-value': DBusInt32(-32),
        '/com/example/test2/uint32-value': DBusUint32(32),
        '/com/example/test2/int64-value': DBusInt64(-64),
        '/com/example/test2/uint64-value': DBusUint64(64),
        '/com/example/test2/double-value': DBusDouble(3.14159),
        '/com/example/test2/string-value': DBusString('Hello World'),
        '/com/example/test2/enum-value': DBusString('enum1'),
        '/com/example/test2/flags-value': DBusArray.string(['flag1', 'flag4']),
        '/com/example/test2/range-value': DBusUint32(32),
        '/com/example/test2/object-path-value':
            DBusObjectPath('/com/example/Test2'),
        '/com/example/test2/signature-value': DBusSignature('a{sv}')
      });
      addTearDown(() async => await dconfServer.close());
      await dconfServer.start();

      var settings =
          GSettings('com.example.Test2', sessionBus: DBusClient(clientAddress));

      expect(dconfServer.values.containsKey('/com/example/test2/boolean-value'),
          isTrue);
      await settings.unset('boolean-value');
      expect(dconfServer.values.containsKey('/com/example/test2/boolean-value'),
          isFalse);

      expect(dconfServer.values.containsKey('/com/example/test2/byte-value'),
          isTrue);
      await settings.unset('byte-value');
      expect(dconfServer.values.containsKey('/com/example/test2/byte-value'),
          isFalse);

      expect(dconfServer.values.containsKey('/com/example/test2/int16-value'),
          isTrue);
      await settings.unset('int16-value');
      expect(dconfServer.values.containsKey('/com/example/test2/int16-value'),
          isFalse);

      expect(dconfServer.values.containsKey('/com/example/test2/uint16-value'),
          isTrue);
      await settings.unset('uint16-value');
      expect(dconfServer.values.containsKey('/com/example/test2/uint16-value'),
          isFalse);

      expect(dconfServer.values.containsKey('/com/example/test2/int32-value'),
          isTrue);
      await settings.unset('int32-value');
      expect(dconfServer.values.containsKey('/com/example/test2/int32-value'),
          isFalse);

      expect(dconfServer.values.containsKey('/com/example/test2/uint32-value'),
          isTrue);
      await settings.unset('uint32-value');
      expect(dconfServer.values.containsKey('/com/example/test2/uint32-value'),
          isFalse);

      expect(dconfServer.values.containsKey('/com/example/test2/int64-value'),
          isTrue);
      await settings.unset('int64-value');
      expect(dconfServer.values.containsKey('/com/example/test2/int64-value'),
          isFalse);

      expect(dconfServer.values.containsKey('/com/example/test2/uint64-value'),
          isTrue);
      await settings.unset('uint64-value');
      expect(dconfServer.values.containsKey('/com/example/test2/uint64-value'),
          isFalse);

      expect(dconfServer.values.containsKey('/com/example/test2/double-value'),
          isTrue);
      await settings.unset('double-value');
      expect(dconfServer.values.containsKey('/com/example/test2/double-value'),
          isFalse);

      expect(dconfServer.values.containsKey('/com/example/test2/string-value'),
          isTrue);
      await settings.unset('string-value');
      expect(dconfServer.values.containsKey('/com/example/test2/string-value'),
          isFalse);

      expect(dconfServer.values.containsKey('/com/example/test2/enum-value'),
          isTrue);
      await settings.unset('enum-value');
      expect(dconfServer.values.containsKey('/com/example/test2/enum-value'),
          isFalse);

      expect(dconfServer.values.containsKey('/com/example/test2/flags-value'),
          isTrue);
      await settings.unset('flags-value');
      expect(dconfServer.values.containsKey('/com/example/test2/flags-value'),
          isFalse);

      expect(dconfServer.values.containsKey('/com/example/test2/range-value'),
          isTrue);
      await settings.unset('range-value');
      expect(dconfServer.values.containsKey('/com/example/test2/range-value'),
          isFalse);

      expect(
          dconfServer.values
              .containsKey('/com/example/test2/object-path-value'),
          isTrue);
      await settings.unset('object-path-value');
      expect(
          dconfServer.values
              .containsKey('/com/example/test2/object-path-value'),
          isFalse);

      expect(
          dconfServer.values.containsKey('/com/example/test2/signature-value'),
          isTrue);
      await settings.unset('signature-value');
      expect(
          dconfServer.values.containsKey('/com/example/test2/signature-value'),
          isFalse);
    });

    test('set multiple', () async {
      var server = DBusServer();
      addTearDown(() async => await server.close());
      var clientAddress = await server
          .listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

      var dconfServer = MockDConfServer(clientAddress,
          values: {'/com/example/test2/int32-value': DBusInt32(-32)});
      addTearDown(() async => await dconfServer.close());
      await dconfServer.start();

      var settings =
          GSettings('com.example.Test2', sessionBus: DBusClient(clientAddress));

      await settings.setAll({
        'boolean-value': DBusBoolean(true),
        'int32-value': null,
        'string-value': DBusString('Hello World')
      });
      expect(
          dconfServer.values,
          equals({
            '/com/example/test2/boolean-value': DBusBoolean(true),
            '/com/example/test2/string-value': DBusString('Hello World')
          }));
    });

    test('key changed', () async {
      var server = DBusServer();
      addTearDown(() async => await server.close());
      var clientAddress = await server
          .listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

      var dconfServer = MockDConfServer(clientAddress);
      addTearDown(() async => await dconfServer.close());
      await dconfServer.start();

      var bus = DBusClient(clientAddress);
      var settings = GSettings('com.example.Test2', sessionBus: bus);
      addTearDown(() async => await settings.close());

      expect(
          settings.keysChanged,
          emitsInOrder([
            ['int32-value']
          ]));

      // Do round trip to server to ensure change is subscribed to.
      await bus.ping();

      await dconfServer.setValue(
          '/com/example/test2/int32-value', DBusInt32(-32));
    });

    test('relocatable schema - get', () async {
      var settings = GSettings('com.example.Relocatable',
          path: '/com/example/relocatable1/');
      addTearDown(() async => await settings.close());
      expect(await settings.get('boolean-value'), equals(DBusBoolean(true)));
    });

    test('relocatable schema - get unset', () async {
      var settings = GSettings('com.example.Relocatable',
          path: '/com/example/relocatable2/');
      addTearDown(() async => await settings.close());
      expect(await settings.get('boolean-value'), equals(DBusBoolean(false)));
    });

    test('non-relocatable schema with path', () async {
      var settings =
          GSettings('com.example.Test1', path: '/com/example/relocatable1/');
      expect(() async => await settings.get('boolean-value'),
          throwsA(isA<GSettingsException>()));
    });

    test('relocatable schema - no path', () async {
      var settings = GSettings('com.example.Relocatable');
      addTearDown(() async => await settings.close());
      expect(() async => await settings.get('boolean-value'),
          throwsA(isA<GSettingsException>()));
    });

    test('relocatable schema - empty path', () async {
      expect(() => GSettings('com.example.Relocatable', path: ''),
          throwsArgumentError);
    });

    test('relocatable schema - missing leading slash', () async {
      expect(
          () => GSettings('com.example.Relocatable',
              path: 'com/example/relocatable1/'),
          throwsArgumentError);
    });

    test('relocatable schema - missing trailing slash', () async {
      expect(
          () => GSettings('com.example.Relocatable',
              path: '/com/example/relocatable1'),
          throwsArgumentError);
    });

    test('relocatable schema - missing element', () async {
      expect(
          () =>
              GSettings('com.example.Relocatable', path: '/com//relocatable1/'),
          throwsArgumentError);
    });

    test('memory backend', () async {
      var settings =
          GSettings('com.example.Test2', backend: GSettingsMemoryBackend());

      // Memory backend never emits key change events.
      settings.keysChanged.listen(expectAsync1((keys) {}, count: 0));

      // Check can write and read back a value in the memory backend.
      addTearDown(() async => await settings.close());
      expect(await settings.isSet('string-value'), isFalse);
      expect(await settings.getDefault('string-value'), equals(DBusString('')));
      expect(await settings.get('string-value'), equals(DBusString('')));
      await settings.set('string-value', DBusString('Hello World'));
      expect(await settings.get('string-value'),
          equals(DBusString('Hello World')));
      expect(await settings.isSet('string-value'), isTrue);

      // Check can clear a value.
      await settings.set('uint32-value', DBusUint32(42));
      expect(await settings.isSet('uint32-value'), isTrue);
      await settings.unset('uint32-value');
      expect(await settings.isSet('uint32-value'), isFalse);

      // Check value doesn't persist.
      var settings2 =
          GSettings('com.example.Test2', backend: GSettingsMemoryBackend());
      addTearDown(() async => await settings2.close());
      expect(await settings2.get('string-value'), equals(DBusString('')));
    });

    test('keyfile backend', () async {
      // Make a temporary location for the keyfile
      var dir = await Directory.systemTemp.createTemp('gsettings-dart-test');
      var file = File('${dir.path}/keyfile');
      addTearDown(() async {
        await dir.delete(recursive: true);
      });

      var settings = GSettings('com.example.Test2',
          backend: GSettingsKeyfileBackend(file: file));
      addTearDown(() async => await settings.close());

      // Check can write and read back a value.
      expect(await settings.isSet('string-value'), isFalse);
      expect(await settings.getDefault('string-value'), equals(DBusString('')));
      expect(await settings.get('string-value'), equals(DBusString('')));
      await settings.set('string-value', DBusString('Hello World'));
      expect(await settings.get('string-value'),
          equals(DBusString('Hello World')));
      expect(await settings.isSet('string-value'), isTrue);

      // Check can clear a value.
      await settings.set('uint32-value', DBusUint32(42));
      expect(await settings.isSet('uint32-value'), isTrue);
      await settings.unset('uint32-value');
      expect(await settings.isSet('uint32-value'), isFalse);

      // Check value persists.
      var settings2 = GSettings('com.example.Test2',
          backend: GSettingsKeyfileBackend(file: file));
      addTearDown(() async => await settings2.close());
      expect(await settings2.get('string-value'),
          equals(DBusString('Hello World')));

      // Use second schema on same file.
      var settings3 = GSettings('com.example.Test1',
          backend: GSettingsKeyfileBackend(file: file));
      addTearDown(() async => await settings3.close());
      await settings3.set('int32-value', DBusUint32(99));

      // Check file contents.
      expect(
          await file.readAsString(),
          equals('[com/example/test1]\n'
              'int32-value=99\n'
              '\n'
              '[com/example/test2]\n'
              'string-value=\'Hello World\'\n'
              ''));
    });

    test('keyfile backend - key changed', () async {
      // Make a temporary location for the keyfile
      var dir = await Directory.systemTemp.createTemp('gsettings-dart-test');
      var file = File('${dir.path}/keyfile');
      addTearDown(() async {
        await dir.delete(recursive: true);
      });

      var settings1 = GSettings('com.example.Test2',
          backend: GSettingsKeyfileBackend(file: file));
      addTearDown(() async => await settings1.close());

      expect(
          settings1.keysChanged,
          emitsInOrder([
            ['int32-value']
          ]));

      // Read to ensure the above subscription is ready.
      expect(await settings1.get('int32-value'), equals(DBusInt32(0)));

      // Check a second client changing a value notifies the first client.
      var settings2 = GSettings('com.example.Test2',
          backend: GSettingsKeyfileBackend(file: file));
      addTearDown(() async => await settings2.close());
      await settings2.set('int32-value', DBusInt32(42));
    });

    test('keyfile backend - invalid file', () async {
      // Make a temporary location for the keyfile
      var dir = await Directory.systemTemp.createTemp('gsettings-dart-test');
      var file = File('${dir.path}/keyfile');
      addTearDown(() async {
        await dir.delete(recursive: true);
      });

      // Not a keyfile.
      await file.writeAsString('INVALID\n');
      var settings1 = GSettings('com.example.Test2',
          backend: GSettingsKeyfileBackend(file: file));
      addTearDown(() async => await settings1.close());
      expect(await settings1.get('int32-value'), equals(DBusInt32(0)));

      // Missing section.
      await file.writeAsString('number=42\n');
      var settings2 = GSettings('com.example.Test2',
          backend: GSettingsKeyfileBackend(file: file));
      addTearDown(() async => await settings2.close());
      expect(await settings2.get('int32-value'), equals(DBusInt32(0)));

      // Missing '=' in key value.
      await file.writeAsString('[com/example]\nnumber\n');
      var settings3 = GSettings('com.example.Test2',
          backend: GSettingsKeyfileBackend(file: file));
      addTearDown(() async => await settings3.close());
      expect(await settings3.get('int32-value'), equals(DBusInt32(0)));
    });
  });
}
