import 'dart:convert';
import 'dart:io';

class FirmwareImage {
  const FirmwareImage({required this.address, required this.path});

  final String address;
  final String path;
}

class FirmwareBundle {
  const FirmwareBundle({
    required this.manifestPath,
    required this.images,
    this.chip,
    this.flashMode,
    this.flashFrequency,
    this.flashSize,
  });

  final String manifestPath;
  final List<FirmwareImage> images;
  final String? chip;
  final String? flashMode;
  final String? flashFrequency;
  final String? flashSize;
}

class FirmwareBundleService {
  static Future<FirmwareBundle?> findForBinary(String binaryPath) async {
    var directory = File(binaryPath).parent;
    for (var depth = 0; depth < 6; depth++) {
      final manifest = File(
        '${directory.path}${Platform.pathSeparator}flasher_args.json',
      );
      if (await manifest.exists()) return parseManifest(manifest);
      final parent = directory.parent;
      if (parent.path == directory.path) break;
      directory = parent;
    }
    return null;
  }

  static Future<FirmwareBundle> parseManifest(File manifest) async {
    final decoded = jsonDecode(await manifest.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid flasher_args.json root');
    }
    final rawFiles = decoded['flash_files'];
    if (rawFiles is! Map || rawFiles.isEmpty) {
      throw const FormatException('flasher_args.json has no flash_files');
    }
    final images = <FirmwareImage>[];
    for (final item in rawFiles.entries) {
      final address = item.key.toString();
      final rawPath = item.value.toString();
      final file = File(rawPath);
      final resolved = file.isAbsolute
          ? file.path
          : '${manifest.parent.path}${Platform.pathSeparator}$rawPath';
      images.add(FirmwareImage(address: address, path: resolved));
    }
    images.sort((a, b) => _address(a.address).compareTo(_address(b.address)));

    final settings = decoded['flash_settings'];
    final extra = decoded['extra_esptool_args'];
    return FirmwareBundle(
      manifestPath: manifest.path,
      images: images,
      chip: extra is Map ? normalizeEspChip(extra['chip']?.toString()) : null,
      flashMode: settings is Map ? settings['flash_mode']?.toString() : null,
      flashFrequency: settings is Map
          ? normalizeFlashFrequency(settings['flash_freq']?.toString())
          : null,
      flashSize: settings is Map
          ? normalizeFlashSize(settings['flash_size']?.toString())
          : null,
    );
  }

  static int _address(String value) =>
      int.tryParse(value.trim().replaceFirst(RegExp(r'^0x'), ''), radix: 16) ??
      0;
}

String? normalizeEspChip(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final compact = value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  const chips = {
    'ESP32': 'ESP32',
    'ESP32S2': 'ESP32-S2',
    'ESP32S3': 'ESP32-S3',
    'ESP32C2': 'ESP32-C2',
    'ESP32C3': 'ESP32-C3',
    'ESP32C5': 'ESP32-C5',
    'ESP32C6': 'ESP32-C6',
    'ESP32H2': 'ESP32-H2',
    'ESP32P4': 'ESP32-P4',
    'ESP8266': 'ESP8266',
  };
  return chips[compact] ?? value.toUpperCase();
}

String? normalizeFlashFrequency(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final match = RegExp(r'(\d+)').firstMatch(value);
  return match == null ? null : '${match.group(1)} MHz';
}

String? normalizeFlashSize(String? value) {
  if (value == null || value.trim().isEmpty || value == 'detect') return null;
  final match = RegExp(
    r'(\d+)\s*(KB|MB)',
    caseSensitive: false,
  ).firstMatch(value);
  return match == null
      ? null
      : '${match.group(1)} ${match.group(2)!.toUpperCase()}';
}
