import 'dart:io';

import 'package:esp_loader/local_profile_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late File profile;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('esp_loader_profile_');
    profile = File('${directory.path}/esp_loader_profile.json');
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('round-trips flash images in a local JSON file', () async {
    final store = LocalFlashProfileStore(file: profile);
    const images = [
      SavedFlashImage(
        address: '0x0000',
        path: '/build/boot.bin',
        enabled: true,
      ),
      SavedFlashImage(
        address: '0x8000',
        path: '/build/part.bin',
        enabled: false,
      ),
    ];

    await store.saveImages(images);
    await store.saveProjectPath('/projects/vmc');
    final loaded = await store.loadImages();

    expect(profile.path, startsWith(directory.path));
    expect(loaded, hasLength(2));
    expect(loaded![0].address, '0x0000');
    expect(loaded[0].path, '/build/boot.bin');
    expect(loaded[0].enabled, isTrue);
    expect(loaded[1].enabled, isFalse);
    expect(await store.loadProjectPath(), '/projects/vmc');
  });

  test('returns null when no local profile exists', () async {
    final store = LocalFlashProfileStore(file: profile);
    expect(await store.loadImages(), isNull);
  });

  test('rejects an invalid local profile', () async {
    await profile.writeAsString('{"version": 1}');
    final store = LocalFlashProfileStore(file: profile);
    expect(store.loadImages(), throwsFormatException);
  });
}
