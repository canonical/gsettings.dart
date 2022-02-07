import 'package:gsettings/gsettings.dart';

void main() async {
  var schemas = await listGSettingsSchemas();
  for (var schema in schemas) {
    print(schema);
  }
}
