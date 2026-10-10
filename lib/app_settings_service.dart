import 'dart:convert';
import 'dart:io';

abstract class AppSettingsStore {
  Future<String?> loadEsptoolPath();
  Future<void> saveEsptoolPath(String? path);
}

class LocalAppSettingsStore implements AppSettingsStore {
  LocalAppSettingsStore({File? file}) : file = file ?? File(defaultPath());

  final File file;

  static String defaultPath() {
    final appImage = Platform.environment['APPIMAGE'];
    final executable = appImage != null && appImage.isNotEmpty
        ? appImage
        : Platform.resolvedExecutable;
    return '${File(executable).parent.path}${Platform.pathSeparator}'
        'esp_loader_settings.json';
  }

  @override
  Future<String?> loadEsptoolPath() async {
    if (!await file.exists()) return null;
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid application settings.');
    }
    final path = decoded['esptoolPath'];
    return path is String && path.trim().isNotEmpty ? path : null;
  }

  @override
  Future<void> saveEsptoolPath(String? path) async {
    final contents = const JsonEncoder.withIndent(' ').convert({
      'version': 1,
      'esptoolPath': path?.trim().isEmpty == true ? null : path,
    });
    await file.writeAsString('$contents\n', flush: true);
  }
}
