[![Pub Package](https://img.shields.io/pub/v/gsettings.svg)](https://pub.dev/packages/gsettings)
[![codecov](https://codecov.io/gh/canonical/gsettings.dart/branch/main/graph/badge.svg?token=89Z2W8Z33D)](https://codecov.io/gh/canonical/gsettings.dart)

Provides a client to use [GSettings](https://developer.gnome.org/gio/stable/GSettings.html) - a settings database used for storing user preferences on Linux.

```dart
import 'package:dbus/dbus.dart';
import 'package:gsettings/gsettings.dart';

void main() async {
  var settings = GSettings('org.gnome.desktop.interface');
  var value = await settings.get('font-name');
  var font = (value as DBusString).value;
  print('Current font set to: $font');
  await settings.close();
}
```

## Contributing to gsettings.dart

We welcome contributions! See the [contribution guide](CONTRIBUTING.md) for more details.
