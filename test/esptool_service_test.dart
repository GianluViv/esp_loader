import 'dart:io';

import 'package:esp_loader/esptool_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recognizes chip from current esptool output', () {
    expect(detectEspChip('Detecting chip type... ESP32-S3'), 'ESP32-S3');
    expect(detectEspChip('Chip is ESP32-C6 (QFN40)'), 'ESP32-C6');
  });

  test('does not confuse an ESP32 variant with base ESP32', () {
    expect(detectEspChip('Chip is ESP32-S2'), 'ESP32-S2');
  });

  test('returns null for unrelated output', () {
    expect(detectEspChip('No serial data received.'), isNull);
  });

  test('extracts detected flash size', () {
    expect(detectFlashSize('Detected flash size: 16MB'), '16 MB');
    expect(detectFlashSize('Flash size: 4096 KB'), '4096 KB');
    expect(detectFlashSize('Manufacturer: ef'), isNull);
  });

  test('missing esptool exception has a readable message', () {
    const error = EspToolNotFoundException('esptool was not found.');
    expect(error.toString(), 'esptool was not found.');
  });

  test(
    'configured and application-local tools precede automatic discovery',
    () {
      final candidates = espToolCandidates(
        configuredPath: '/custom/esptool',
        applicationExecutable: '/opt/esp-loader/esp_loader',
        windows: false,
      );

      expect(candidates.first.executable, '/custom/esptool');
      expect(candidates[1].executable, '/opt/esp-loader/esptool');
      expect(candidates[2].executable, '/opt/esp-loader/esptool.py');
      expect(
        candidates.map((candidate) => candidate.executable),
        contains('esptool'),
      );
    },
  );

  test('detects supported esptool version formats', () {
    expect(detectEsptoolMajor('esptool v5.1.0'), 5);
    expect(detectEsptoolMajor('esptool.py 4.8.1'), 4);
    expect(detectEsptoolMajor('unrelated output'), isNull);
  });

  test('validates and normalizes an explicit esptool executable', () async {
    final directory = await Directory.systemTemp.createTemp('esptool_test_');
    addTearDown(() => directory.delete(recursive: true));
    final executable = await File(
      '${directory.path}${Platform.pathSeparator}esptool',
    ).writeAsString('test');

    final validation = await EspToolService.validateExecutable(
      executable.path,
      run: (path, arguments) async {
        expect(path, executable.absolute.path);
        expect(arguments, ['version']);
        return ProcessResult(1, 0, 'esptool v5.1.0', '');
      },
    );

    expect(validation.path, executable.absolute.path);
    expect(validation.version, '5.1.0');
  });

  test('rejects missing and obsolete explicit esptool executables', () async {
    await expectLater(
      EspToolService.validateExecutable('/definitely/missing/esptool'),
      throwsFormatException,
    );

    final directory = await Directory.systemTemp.createTemp('esptool_old_');
    addTearDown(() => directory.delete(recursive: true));
    final executable = await File(
      '${directory.path}${Platform.pathSeparator}esptool',
    ).writeAsString('test');
    await expectLater(
      EspToolService.validateExecutable(
        executable.path,
        run: (_, _) async => ProcessResult(1, 0, 'esptool v3.3.0', ''),
      ),
      throwsFormatException,
    );
  });
}
