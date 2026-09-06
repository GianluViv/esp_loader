import 'dart:io';

import 'package:esp_loader/project_import_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  setUp(
    () async => root = await Directory.systemTemp.createTemp('esp_project_'),
  );
  tearDown(() async => root.delete(recursive: true));

  File make(String relative, [String contents = '']) {
    final file = File('${root.path}/$relative');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
    return file;
  }

  test('detects a PlatformIO project and its compiled environment', () async {
    make(
      'platformio.ini',
      '[env:esp32dev]\nplatform = espressif32\nboard = esp32dev\n',
    );
    make('.pio/build/esp32dev/bootloader.bin');
    make('.pio/build/esp32dev/partitions.bin');
    make('.pio/build/esp32dev/firmware.bin');
    final bootApp = make('framework/boot_app0.bin');
    make('.pio/build/esp32dev/idedata.json', '''
{"extra":{"flash_images":[
  {"offset":"0x1000","path":"${root.path}/.pio/build/esp32dev/bootloader.bin"},
  {"offset":"0x8000","path":"${root.path}/.pio/build/esp32dev/partitions.bin"},
  {"offset":"0xe000","path":"${bootApp.path}"}
],"application_offset":"0x10000"}}
''');

    final result = await ProjectImportService.import(root.path);

    expect(result.type, EspProjectType.platformIo);
    expect(result.environment, 'esp32dev');
    expect(result.bundle.chip, 'ESP32');
    expect(result.bundle.flashFrequency, '40 MHz');
    expect(result.bundle.flashSize, '4 MB');
    expect(result.bundle.images.map((image) => image.address), [
      '0x1000',
      '0x8000',
      '0xe000',
      '0x10000',
    ]);
  });

  test('detects ESP-IDF and uses flasher_args.json as authority', () async {
    make('CMakeLists.txt', 'project(sample)');
    make('build/bootloader/bootloader.bin');
    make('build/partition_table/partition-table.bin');
    make('build/sample.bin');
    make('build/flasher_args.json', '''
{"flash_files":{"0x0":"bootloader/bootloader.bin","0x8000":"partition_table/partition-table.bin","0x10000":"sample.bin"},"extra_esptool_args":{"chip":"esp32s3"}}
''');

    final result = await ProjectImportService.import(root.path);
    expect(result.type, EspProjectType.espIdf);
    expect(result.bundle.chip, 'ESP32-S3');
    expect(result.bundle.images, hasLength(3));
  });

  test('detects Arduino exported binaries inside the sketch project', () async {
    final name = root.path.split(Platform.pathSeparator).last;
    make('$name.ino', 'void setup() {}');
    make('build/esp32/Sketch.ino.bootloader.bin');
    make('build/esp32/Sketch.ino.partitions.bin');
    make('build/esp32/Sketch.ino.bin');

    final result = await ProjectImportService.import(root.path);
    expect(result.type, EspProjectType.arduino);
    expect(result.bundle.images, hasLength(3));
    expect(result.bundle.images.last.address, '0x10000');
  });

  test('reports a detected project that has not been built', () async {
    make('platformio.ini', '[env:test]');
    expect(
      ProjectImportService.import(root.path),
      throwsA(isA<FormatException>()),
    );
  });
}
