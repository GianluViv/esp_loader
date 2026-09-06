import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import 'firmware_bundle_service.dart';

class ProductionPackageRequest {
  const ProductionPackageRequest({
    required this.outputPath,
    required this.projectName,
    required this.sourceType,
    required this.chip,
    required this.flashMode,
    required this.flashFrequency,
    required this.flashSize,
    required this.images,
    this.environment,
  });

  final String outputPath;
  final String projectName;
  final String sourceType;
  final String? environment;
  final String chip;
  final String flashMode;
  final String flashFrequency;
  final String flashSize;
  final List<FirmwareImage> images;
}

class ProductionPackageService {
  static const manifestName = 'production_manifest.json';

  static Future<void> export(ProductionPackageRequest request) async {
    if (request.images.isEmpty) {
      throw const FormatException('Enable at least one binary to export.');
    }
    final archive = Archive();
    final manifestImages = <Map<String, Object>>[];
    final usedNames = <String>{};
    final usedAddresses = <int>{};
    for (var index = 0; index < request.images.length; index++) {
      final image = request.images[index];
      final addressText = image.address.trim();
      if (!RegExp(r'^(0[xX][0-9a-fA-F]+|[0-9]+)$').hasMatch(addressText)) {
        throw FormatException('Invalid address: ${image.address}');
      }
      final address = int.tryParse(addressText);
      if (address == null || !usedAddresses.add(address)) {
        throw FormatException('Duplicate or invalid address: ${image.address}');
      }
      final source = File(image.path);
      if (!await source.exists()) {
        throw FormatException('Binary not found: ${image.path}');
      }
      final bytes = await source.readAsBytes();
      if (bytes.isEmpty) throw FormatException('Empty binary: ${image.path}');
      var name = source.uri.pathSegments.last;
      if (!usedNames.add(name.toLowerCase())) {
        name = '${index + 1}_$name';
        usedNames.add(name.toLowerCase());
      }
      final relative = 'binaries/$name';
      archive.addFile(ArchiveFile(relative, bytes.length, bytes));
      manifestImages.add({
        'address': '0x${address.toRadixString(16)}',
        'file': relative,
        'size': bytes.length,
        'sha256': sha256.convert(bytes).toString(),
      });
    }
    final manifest = const JsonEncoder.withIndent('  ').convert({
      'format': 'esp-loader-production',
      'version': 1,
      'project': request.projectName,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'minimumEspLoaderVersion': '1.0.0',
      'source': {
        'type': request.sourceType,
        if (request.environment != null) 'environment': request.environment,
      },
      'device': {
        'chip': request.chip,
        'flashMode': request.flashMode,
        'flashFrequency': request.flashFrequency,
        'flashSize': request.flashSize,
      },
      'images': manifestImages,
    });
    final manifestBytes = utf8.encode('$manifest\n');
    archive.addFile(
      ArchiveFile(manifestName, manifestBytes.length, manifestBytes),
    );
    final encoded = ZipEncoder().encode(archive);
    final output = File(
      request.outputPath.toLowerCase().endsWith('.zip')
          ? request.outputPath
          : '${request.outputPath}.zip',
    );
    await output.writeAsBytes(encoded, flush: true);
  }

  static Future<FirmwareBundle> importFolder(Directory folder) async {
    final manifestFile = File(
      '${folder.path}${Platform.pathSeparator}$manifestName',
    );
    if (!await manifestFile.exists()) {
      throw const FormatException('production_manifest.json was not found.');
    }
    final decoded = jsonDecode(await manifestFile.readAsString());
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != 'esp-loader-production' ||
        decoded['version'] != 1 ||
        decoded['images'] is! List) {
      throw const FormatException('Invalid or unsupported production package.');
    }
    final images = <FirmwareImage>[];
    for (final raw in decoded['images'] as List) {
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('Invalid production image entry.');
      }
      final address = raw['address'];
      final relative = raw['file'];
      final expectedSize = raw['size'];
      final expectedHash = raw['sha256'];
      if (address is! String ||
          relative is! String ||
          expectedSize is! int ||
          expectedHash is! String ||
          relative.contains('..') ||
          File(relative).isAbsolute) {
        throw const FormatException('Invalid production image entry.');
      }
      final file = File(
        '${folder.path}${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}',
      );
      if (!await file.exists()) {
        throw FormatException('Package binary not found: $relative');
      }
      final bytes = await file.readAsBytes();
      if (bytes.length != expectedSize ||
          sha256.convert(bytes).toString() != expectedHash) {
        throw FormatException('Integrity check failed: $relative');
      }
      images.add(FirmwareImage(address: address, path: file.path));
    }
    final device = decoded['device'];
    if (device is! Map) throw const FormatException('Missing device settings.');
    return FirmwareBundle(
      manifestPath: manifestFile.path,
      images: images,
      chip: normalizeEspChip(device['chip']?.toString()),
      flashMode: device['flashMode']?.toString(),
      flashFrequency: device['flashFrequency']?.toString(),
      flashSize: device['flashSize']?.toString(),
    );
  }

  static Future<({Directory folder, FirmwareBundle bundle})> importZip(
    File zipFile,
  ) async {
    if (!await zipFile.exists()) {
      throw const FormatException('Production ZIP was not found.');
    }
    final zipBytes = await zipFile.readAsBytes();
    final packageId = sha256.convert(zipBytes).toString().substring(0, 20);
    final folder = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}esp_loader_packages'
      '${Platform.pathSeparator}$packageId',
    );
    if (await folder.exists()) await folder.delete(recursive: true);
    await folder.create(recursive: true);
    try {
      final archive = ZipDecoder().decodeBytes(zipBytes, verify: true);
      for (final entry in archive.files) {
        final relative = entry.name.replaceAll('\\', '/');
        if (relative.isEmpty ||
            relative.startsWith('/') ||
            relative.contains('../') ||
            relative.contains(':')) {
          throw const FormatException('Unsafe path in production ZIP.');
        }
        final output = File(
          '${folder.path}${Platform.pathSeparator}'
          '${relative.replaceAll('/', Platform.pathSeparator)}',
        );
        if (entry.isFile) {
          await output.parent.create(recursive: true);
          await output.writeAsBytes(entry.content as List<int>, flush: true);
        }
      }
      final bundle = await importFolder(folder);
      return (folder: folder, bundle: bundle);
    } on Object {
      if (await folder.exists()) await folder.delete(recursive: true);
      rethrow;
    }
  }
}
