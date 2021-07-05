[![Pub Package](https://img.shields.io/pub/v/dconf.svg)](https://pub.dev/packages/dconf)

Provides a client to use [DConf](https://gitlab.gnome.org/GNOME/dconf/) - a database used for storing user preferences on Linux.

```dart
import 'package:dconf/dconf.dart';

var client = DConfClient();
await client.close();
```

## Contributing to dconf.dart

We welcome contributions! See the [contribution guide](CONTRIBUTING.md) for more details.
