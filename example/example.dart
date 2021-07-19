import 'package:dbus/dbus.dart';
import 'package:gsettings/gsettings.dart';

void main() async {
  var settings = GSettings('org.gnome.desktop.interface');
  var value = await settings.get('font-name');
  var font = (value as DBusString).value;
  print('Current font set to: $font');
  await settings.close();
}
