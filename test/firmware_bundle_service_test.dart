import 'dart:io';

import 'package:esp_loader/firmware_bundle_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('imports ESP-IDF images and settings from flasher_args.json', () async {
    final root = await Directory.systemTemp.createTemp('esp_loader_manifest_');
    addTearDown(() => root.delete(recursive: true));
    final bootloader = Directory('${root.path}/bootloader')..createSync();
    final selected = File('${bootloader.path}/bootloader.bin')
      ..writeAsBytesSync([]);
    File('${root.path}/flasher_args.json').writeAsStringSync('''
{
  "flash_files": {
    "0x0": "bootloader/bootloader.bin",
    "0x8000": "partition_table/partition-table.bin",
    "0x10000": "sample.bin"
  },
  "flash_settings": {
    "flash_mode": "dio",
    "flash_freq": "80m",
    "flash_size": "16MB"
  },
  "extra_esptool_args": {"chip": "esp32s3"}
}
''');

    final bundle = await FirmwareBundleService.findForBinary(selected.path);
    expect(bundle, isNotNull);
    expect(bundle!.chip, 'ESP32-S3');
    expect(bundle.flashMode, 'dio');
    expect(bundle.flashFrequency, '80 MHz');
    expect(bundle.flashSize, '16 MB');
    expect(bundle.images.map((image) => image.address), [
      '0x0',
      '0x8000',
      '0x10000',
    ]);
    expect(bundle.images.first.path, '${root.path}/bootloader/bootloader.bin');
  });

  test('normalizes chip identifiers for compatibility checks', () {
    expect(normalizeEspChip('esp32s3'), 'ESP32-S3');
    expect(normalizeEspChip('ESP32-C6'), 'ESP32-C6');
  });
}
