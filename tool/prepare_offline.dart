import 'dart:convert';
import 'dart:io';

void main() {
  final root = Directory('build/web');
  if (!File('${root.path}/main.dart.js').existsSync()) {
    throw StateError('Run flutter build web first.');
  }
  final version = DateTime.now().toUtc().microsecondsSinceEpoch.toString();
  final worker = File('${root.path}/zizouit_service_worker.js');
  worker.writeAsStringSync(
    File('web/zizouit_service_worker.js')
        .readAsStringSync()
        .replaceAll('__BUILD_VERSION__', version),
  );
  final assets = <String>['offline-assets.json'];
  for (final file in root.listSync(recursive: true).whereType<File>()) {
    final relative = file.path
        .substring(root.path.length + 1)
        .replaceAll('\\', '/');
    if (relative.endsWith('.symbols') ||
        relative.endsWith('.map') ||
        relative.endsWith('service_worker.js') ||
        relative == 'offline-assets.json') {
      continue;
    }
    assets.add(relative);
  }
  assets.sort();
  File('${root.path}/offline-assets.json')
      .writeAsStringSync(jsonEncode({'version': version, 'assets': assets}));
  stdout.writeln(
    'Offline shell prepared: ${assets.length} assets, version $version.',
  );
}
