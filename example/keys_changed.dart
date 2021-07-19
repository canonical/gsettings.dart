import 'package:gsettings/gsettings.dart';

void main() async {
  var settings = GSettings('org.gnome.desktop.interface');
  await for (var keys in settings.keysChanged) {
    for (var key in keys) {
      var value = await settings.get(key);
      print('$key = $value');
    }
  }
  await settings.close();
}
