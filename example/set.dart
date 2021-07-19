import 'package:dbus/dbus.dart';
import 'package:gsettings/gsettings.dart';

void main() async {
  var settings = GSettings('org.gnome.desktop.interface');
  await settings.set({'show-battery-percentage': DBusBoolean(true)});
  await settings.close();
}
