import 'dart:convert';
import 'dart:io';

class SavedFlashImage {
  const SavedFlashImage({
    required this.address,
    required this.path,
    required this.enabled,
  });

  final String address;
  final String path;
  final bool enabled;

  Map<String, Object> toJson() => {
    'address': address,
    'path': path,
    'enabled': enabled,
  };

  static SavedFlashImage? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final address = value['address'];
    final path = value['path'];
    final enabled = value['enabled'];
    if (address is! String || path is! String || enabled is! bool) return null;
    return SavedFlashImage(address: address, path: path, enabled: enabled);
  }
}

abstract class FlashProfileStore {
  Future<List<SavedFlashImage>?> loadImages();
  Future<void> saveImages(List<SavedFlashImage> images);
  Future<String?> loadProjectPath();
  Future<void> saveProjectPath(String? path);
}

class LocalFlashProfileStore implements FlashProfileStore {
  LocalFlashProfileStore({File? file}) : file = file ?? File(defaultPath());

  final File file;

  static String defaultPath() {
    final appImage = Platform.environment['APPIMAGE'];
    final executable = appImage != null && appImage.isNotEmpty
        ? appImage
        : Platform.resolvedExecutable;
    return '${File(executable).parent.path}${Platform.pathSeparator}esp_loader_profile.json';
  }

  @override
  Future<List<SavedFlashImage>?> loadImages() async {
    if (!await file.exists()) return null;
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic> || decoded['images'] is! List) {
      throw const FormatException('Invalid local profile.');
    }
    return (decoded['images'] as List)
        .map(SavedFlashImage.fromJson)
        .whereType<SavedFlashImage>()
        .toList();
  }

  @override
  Future<void> saveImages(List<SavedFlashImage> images) async {
    final existing = await _readObject();
    final contents = const JsonEncoder.withIndent('  ').convert({
      ...existing,
      'version': 1,
      'images': images.map((image) => image.toJson()).toList(),
    });
    await file.writeAsString('$contents\n', flush: true);
  }

  @override
  Future<String?> loadProjectPath() async {
    if (!await file.exists()) return null;
    final value = (await _readObject())['projectPath'];
    return value is String && value.isNotEmpty ? value : null;
  }

  @override
  Future<void> saveProjectPath(String? path) async {
    final existing = await _readObject();
    final contents = const JsonEncoder.withIndent('  ')
        .convert({...existing, 'version': 1, 'projectPath': path});
    await file.writeAsString('$contents\n', flush: true);
  }

  Future<Map<String, dynamic>> _readObject() async {
    if (!await file.exists()) return {};
    final decoded = jsonDecode(await file.readAsString());
    return decoded is Map<String, dynamic> ? decoded : {};
  }
}
