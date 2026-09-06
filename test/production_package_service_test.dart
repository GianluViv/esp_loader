import 'dart:io';

import 'package:archive/archive.dart';
import 'package:esp_loader/firmware_bundle_service.dart';
import 'package:esp_loader/production_package_service.dart';
import 'package:esp_loader/project_import_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  setUp(
    () async => root = await Directory.systemTemp.createTemp('production_'),
  );
  tearDown(() async => root.delete(recursive: true));

  test('exports a self-contained ZIP that imports after extraction', () async {
    final boot = File('${root.path}/bootloader.bin')
      ..writeAsBytesSync([1, 2, 3]);
    final app = File('${root.path}/firmware.bin')
      ..writeAsBytesSync([4, 5, 6, 7]);
    final zip = '${root.path}/release.zip';
    await ProductionPackageService.export(
      ProductionPackageRequest(
        outputPath: zip,
        projectName: 'GS240A',
        sourceType: 'PlatformIO',
        environment: 'esp32dev',
        chip: 'ESP32',
        flashMode: 'DIO',
        flashFrequency: '40 MHz',
        flashSize: '4 MB',
        images: [
          FirmwareImage(address: '0x1000', path: boot.path),
          FirmwareImage(address: '0x10000', path: app.path),
        ],
      ),
    );

    final archive = ZipDecoder().decodeBytes(File(zip).readAsBytesSync());
    expect(archive.findFile('production_manifest.json'), isNotNull);
    expect(archive.findFile('binaries/bootloader.bin'), isNotNull);
    final extracted = Directory('${root.path}/extracted')..createSync();
    for (final entry in archive.files.where((entry) => entry.isFile)) {
      final output = File('${extracted.path}/${entry.name}');
      output.parent.createSync(recursive: true);
      output.writeAsBytesSync(entry.content as List<int>);
    }
    final imported = await ProductionPackageService.importFolder(extracted);
    expect(imported.chip, 'ESP32');
    expect(imported.images.map((image) => image.address), [
      '0x1000',
      '0x10000',
    ]);
    final project = await ProjectImportService.import(extracted.path);
    expect(project.type, EspProjectType.production);

    final direct = await ProjectImportService.importZip(zip);
    expect(direct.type, EspProjectType.production);
    expect(direct.bundle.images, hasLength(2));
    expect(File(direct.bundle.images.first.path).existsSync(), isTrue);
  });

  test('rejects a binary changed after package extraction', () async {
    final folder = Directory('${root.path}/package')..createSync();
    final binary = File('${folder.path}/firmware.bin')..writeAsBytesSync([1]);
    File('${folder.path}/production_manifest.json').writeAsStringSync('''
{"format":"esp-loader-production","version":1,"device":{"chip":"esp32"},"images":[{"address":"0x10000","file":"firmware.bin","size":1,"sha256":"invalid"}]}
''');
    expect(
      ProductionPackageService.importFolder(folder),
      throwsA(isA<FormatException>()),
    );
    expect(binary.existsSync(), isTrue);
  });
}
