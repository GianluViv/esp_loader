import 'dart:convert';
import 'dart:io';

import 'package:esp_loader/app_settings_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late File settingsFile;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('app_settings_test_');
    settingsFile = File(
      '${directory.path}${Platform.pathSeparator}esp_loader_settings.json',
    );
  });

  tearDown(() => directory.delete(recursive: true));

  test('persists and reloads the explicit esptool path', () async {
    final store = LocalAppSettingsStore(file: settingsFile);

    expect(await store.loadEsptoolPath(), isNull);
    await store.saveEsptoolPath('/tools/esptool');

    expect(await store.loadEsptoolPath(), '/tools/esptool');
    expect(jsonDecode(await settingsFile.readAsString()), {
      'version': 1,
      'esptoolPath': '/tools/esptool',
    });
  });

  test('empty path restores automatic discovery', () async {
    final store = LocalAppSettingsStore(file: settingsFile);
    await store.saveEsptoolPath('  ');

    expect(await store.loadEsptoolPath(), isNull);
  });

  test('rejects malformed settings', () async {
    await settingsFile.writeAsString('[]');

    await expectLater(
      LocalAppSettingsStore(file: settingsFile).loadEsptoolPath(),
      throwsFormatException,
    );
  });
}
