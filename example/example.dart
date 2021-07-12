import 'package:dbus/dbus.dart';
import 'package:gsettings/gsettings.dart';

void main() async {
  var schema = GSettingsSchema('org.gnome.desktop.interface');
  var value = await schema.get('font-name');
  var font = (value as DBusString).value;
  print('Current font set to: $font');
}
