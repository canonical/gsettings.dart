import 'dart:io';
import 'dart:typed_data';

import 'package:dbus/dbus.dart';
import 'package:gsettings/gsettings.dart';
import 'package:gsettings/src/gvariant_codec.dart';
import 'package:test/test.dart';

class MockDConfServer extends DBusClient {
  MockDConfServer(DBusAddress clientAddress) : super(clientAddress);

  Future<void> start() async {
    await requestName('ca.desrt.dconf');
  }
}

void main() {
  test('gvariant decode', () async {
    var codec = GVariantCodec();

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
  });

  test('dconf read all', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var dconf = MockDConfServer(clientAddress);
    await dconf.start();

    var client = DConfClient(bus: DBusClient(clientAddress));

    Future<void> listDir(String dir) async {
      var names = await client.list(dir);
      for (var name in names) {
        var fullName = dir + name;
        if (name.endsWith('/')) {
          await listDir(fullName);
        } else {
          var value = await client.lookup(fullName);
          print('$fullName = $value');
        }
      }
    }

    await listDir('/');

    await client.close();
  });

  test('list schemas', () async {
    print(await listGSettingsSchemas());
  });

  test('list schema', () async {
    var schema = GSettingsSchema('org.gnome.desktop.sound');
    print(await schema.list());
  });
}
