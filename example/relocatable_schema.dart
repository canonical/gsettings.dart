import 'package:gsettings/gsettings.dart';

void main() async {
  var settings = GSettings('org.gnome.desktop.notifications.application',
      path: '/org/gnome/desktop/notifications/application/org-gnome-terminal/');
  var id = (await settings.get('application-id')).asString();
  var enable = (await settings.get('enable')).asBoolean();
  print('Notifications for $id: $enable');
  await settings.close();
}
