import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
  onScreenshot:
      (String name, List<int> bytes, [Map<String, Object?>? args]) async {
        final folder = Directory('docs/screenshots/about-you-2');
        await folder.create(recursive: true);
        final file = File('${folder.path}/$name.png');
        if (await file.exists()) {
          final backup = Directory(
            'backups/about-you-pass2/previous-screenshots',
          );
          await backup.create(recursive: true);
          await file.copy(
            '${backup.path}/$name-${DateTime.now().microsecondsSinceEpoch}.png',
          );
        }
        await file.writeAsBytes(bytes);
        return true;
      },
);
