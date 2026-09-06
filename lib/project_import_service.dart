import 'dart:convert';
import 'dart:io';

import 'firmware_bundle_service.dart';
import 'production_package_service.dart';

enum EspProjectType { production, platformIo, espIdf, arduino, generic }

class ProjectImportResult {
  const ProjectImportResult({
    required this.type,
    required this.projectPath,
    required this.buildPath,
    required this.bundle,
    this.environment,
  });

  final EspProjectType type;
  final String projectPath;
  final String buildPath;
  final FirmwareBundle bundle;
  final String? environment;

  String get typeLabel => switch (type) {
    EspProjectType.production => 'Production package',
    EspProjectType.platformIo => 'PlatformIO',
    EspProjectType.espIdf => 'ESP-IDF',
    EspProjectType.arduino => 'Arduino',
    EspProjectType.generic => 'Generic ESP build',
  };
}

class ProjectImportService {
  static Future<ProjectImportResult> importZip(String zipPath) async {
    final imported = await ProductionPackageService.importZip(File(zipPath));
    return ProjectImportResult(
      type: EspProjectType.production,
      projectPath: imported.folder.path,
      buildPath: imported.folder.path,
      bundle: imported.bundle,
      environment: File(zipPath).uri.pathSegments.last,
    );
  }

  static Future<ProjectImportResult> import(String projectPath) async {
    final project = Directory(projectPath);
    if (!await project.exists()) {
      throw const FormatException(
        'The selected project folder does not exist.',
      );
    }
    final productionManifest = File(
      _join(project.path, ProductionPackageService.manifestName),
    );
    if (await productionManifest.exists()) {
      return ProjectImportResult(
        type: EspProjectType.production,
        projectPath: project.path,
        buildPath: project.path,
        bundle: await ProductionPackageService.importFolder(project),
      );
    }
    if (await File(_join(project.path, 'platformio.ini')).exists()) {
      return _platformIo(project);
    }
    if (await File(_join(project.path, 'CMakeLists.txt')).exists()) {
      final manifest = File(_join(project.path, 'build/flasher_args.json'));
      if (await manifest.exists()) {
        return ProjectImportResult(
          type: EspProjectType.espIdf,
          projectPath: project.path,
          buildPath: manifest.parent.path,
          bundle: await FirmwareBundleService.parseManifest(manifest),
        );
      }
      throw const FormatException(
        'ESP-IDF project detected, but build/flasher_args.json was not found. Build the project first.',
      );
    }
    final manifests = _find(
      project,
      (file) => file.path.endsWith('flasher_args.json'),
    );
    if (manifests.isNotEmpty) {
      final manifest = _newest(manifests);
      return ProjectImportResult(
        type: EspProjectType.generic,
        projectPath: project.path,
        buildPath: manifest.parent.path,
        bundle: await FirmwareBundleService.parseManifest(manifest),
      );
    }
    final sketches = project
        .listSync()
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.ino'))
        .toList();
    if (sketches.isNotEmpty) return _arduino(project);
    throw const FormatException(
      'No PlatformIO, ESP-IDF, Arduino, or Espressif build was found in this folder.',
    );
  }

  static Future<ProjectImportResult> _platformIo(Directory project) async {
    final buildRoot = Directory(_join(project.path, '.pio/build'));
    if (!await buildRoot.exists()) {
      throw const FormatException(
        'PlatformIO project detected, but .pio/build was not found. Build the project first.',
      );
    }
    final builds = buildRoot
        .listSync()
        .whereType<Directory>()
        .where((dir) => File(_join(dir.path, 'firmware.bin')).existsSync())
        .toList();
    if (builds.isEmpty) {
      throw const FormatException(
        'No compiled PlatformIO environment was found.',
      );
    }
    builds.sort((a, b) => _modified(b).compareTo(_modified(a)));
    final build = builds.first;
    final ini = await File(_join(project.path, 'platformio.ini'))
        .readAsString();
    final environment = build.path.split(Platform.pathSeparator).last;
    final block =
        RegExp(
          '^\\[env:${RegExp.escape(environment)}\\]([\\s\\S]*?)(?=^\\[|\\z)',
          multiLine: true,
        ).firstMatch(ini)?.group(1) ??
        ini;
    final board = RegExp(
      r'^\s*board\s*=\s*([^;\s]+)',
      multiLine: true,
    ).firstMatch(block)?.group(1);
    final chip = _chipFromText('$board $block');
    final bundle = await _platformIoBundle(build, chip: chip);
    return ProjectImportResult(
      type: EspProjectType.platformIo,
      projectPath: project.path,
      buildPath: build.path,
      environment: environment,
      bundle: bundle,
    );
  }

  static Future<FirmwareBundle> _platformIoBundle(
    Directory build, {
    String? chip,
  }) async {
    final metadata = File(_join(build.path, 'idedata.json'));
    if (await metadata.exists()) {
      final decoded = jsonDecode(await metadata.readAsString());
      final extra = decoded is Map<String, dynamic> ? decoded['extra'] : null;
      final flashImages = extra is Map ? extra['flash_images'] : null;
      final applicationOffset = extra is Map
          ? extra['application_offset']?.toString()
          : null;
      if (flashImages is List && applicationOffset != null) {
        final images = <FirmwareImage>[];
        for (final raw in flashImages.whereType<Map>()) {
          final address = raw['offset']?.toString();
          final path = raw['path']?.toString();
          if (address != null && path != null && File(path).existsSync()) {
            images.add(FirmwareImage(address: address, path: path));
          }
        }
        final application = File(_join(build.path, 'firmware.bin'));
        if (await application.exists()) {
          images.add(
            FirmwareImage(address: applicationOffset, path: application.path),
          );
        }
        images.sort((a, b) => _offset(a.address).compareTo(_offset(b.address)));
        if (images.isNotEmpty) {
          final effectiveChip = chip ?? 'ESP32';
          return FirmwareBundle(
            manifestPath: metadata.path,
            images: images,
            chip: effectiveChip,
            flashMode: 'dio',
            flashFrequency: effectiveChip == 'ESP32' ? '40 MHz' : '80 MHz',
            flashSize: effectiveChip == 'ESP32' ? '4 MB' : '16 MB',
          );
        }
      }
    }
    final effectiveChip = chip ?? 'ESP32';
    final fallback = _bundleFromBins(build, chip: effectiveChip);
    return FirmwareBundle(
      manifestPath: fallback.manifestPath,
      images: fallback.images,
      chip: fallback.chip,
      flashMode: 'dio',
      flashFrequency: effectiveChip == 'ESP32' ? '40 MHz' : '80 MHz',
      flashSize: effectiveChip == 'ESP32' ? '4 MB' : '16 MB',
    );
  }

  static Future<ProjectImportResult> _arduino(Directory project) async {
    final binaries = _find(
      project,
      (file) => file.path.toLowerCase().endsWith('.ino.bin'),
    );
    if (binaries.isEmpty) {
      throw const FormatException(
        'Arduino project detected, but no build output was found inside the project. Configure Arduino to export binaries into the project folder.',
      );
    }
    final application = _newest(binaries);
    final build = application.parent;
    return ProjectImportResult(
      type: EspProjectType.arduino,
      projectPath: project.path,
      buildPath: build.path,
      bundle: _bundleFromBins(build, chip: _chipFromText(build.path)),
    );
  }

  static FirmwareBundle _bundleFromBins(Directory build, {String? chip}) {
    final files = build.listSync().whereType<File>().toList();
    File? named(String fragment) {
      for (final file in files) {
        if (file.path.toLowerCase().contains(fragment)) return file;
      }
      return null;
    }

    final effectiveChip = chip ?? 'ESP32';
    final bootOffset = effectiveChip == 'ESP32' ? '0x1000' : '0x0000';
    final images = <FirmwareImage>[];
    final boot = named('bootloader.bin');
    final partitions = named('partitions.bin') ?? named('partition-table.bin');
    final bootApp = named('boot_app0.bin');
    final application = named('firmware.bin') ?? named('.ino.bin');
    if (boot != null) {
      images.add(FirmwareImage(address: bootOffset, path: boot.path));
    }
    if (partitions != null) {
      images.add(FirmwareImage(address: '0x8000', path: partitions.path));
    }
    if (bootApp != null) {
      images.add(FirmwareImage(address: '0xE000', path: bootApp.path));
    }
    if (application != null) {
      images.add(FirmwareImage(address: '0x10000', path: application.path));
    }
    if (images.isEmpty) {
      throw const FormatException('No flashable binaries found.');
    }
    return FirmwareBundle(
      manifestPath: build.path,
      images: images,
      chip: effectiveChip,
    );
  }

  static String? _chipFromText(String text) {
    final compact = text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    for (final chip in [
      'esp32s3',
      'esp32s2',
      'esp32c6',
      'esp32c5',
      'esp32c3',
      'esp32c2',
      'esp32h2',
      'esp32p4',
      'esp8266',
      'esp32',
    ]) {
      if (compact.contains(chip)) return normalizeEspChip(chip);
    }
    return null;
  }

  static List<File> _find(Directory root, bool Function(File) accept) {
    final result = <File>[];
    void visit(Directory directory, int depth) {
      if (depth > 5) return;
      for (final entity in directory.listSync(followLinks: false)) {
        if (entity is File && accept(entity)) result.add(entity);
        if (entity is Directory &&
            !entity.path.contains('${Platform.pathSeparator}.git')) {
          visit(entity, depth + 1);
        }
      }
    }

    visit(root, 0);
    return result;
  }

  static File _newest(List<File> files) {
    files.sort((a, b) => _modified(b).compareTo(_modified(a)));
    return files.first;
  }

  static DateTime _modified(FileSystemEntity entity) =>
      entity.statSync().modified;
  static int _offset(String value) =>
      int.tryParse(value.trim().replaceFirst(RegExp(r'^0x'), ''), radix: 16) ??
      0;
  static String _join(String base, String child) =>
      '$base${Platform.pathSeparator}${child.replaceAll('/', Platform.pathSeparator)}';
}
