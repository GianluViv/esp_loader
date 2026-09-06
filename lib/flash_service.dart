import 'dart:async';
import 'dart:io';

class FlashImage {
  const FlashImage(this.address, this.path);
  final String address;
  final String path;
}

class FlashRequest {
  const FlashRequest({
    required this.port,
    required this.baud,
    required this.chip,
    required this.mode,
    required this.frequency,
    required this.size,
    required this.images,
    this.firmwareChip,
  });
  final String port, baud, chip, mode, frequency, size;
  final String? firmwareChip;
  final List<FlashImage> images;

  Future<List<String>> arguments() async {
    String normalizeChip(String value) =>
        value.toLowerCase().replaceAll('-', '');
    final target = normalizeChip(chip);
    final connection = _connectionArguments(port, baud, chip);
    if (firmwareChip != null && normalizeChip(firmwareChip!) != target) {
      throw const FormatException(
        'The selected chip does not match the firmware target.',
      );
    }
    final flashMode = mode.toLowerCase();
    final flashFrequency = frequency.toLowerCase().replaceAll(' mhz', 'm');
    final flashSize = size.replaceAll(' ', '').toUpperCase();
    final sizeMatch = RegExp(r'^(\d+)(KB|MB)$').firstMatch(flashSize);
    final capacity = sizeMatch == null
        ? null
        : int.parse(sizeMatch[1]!) *
              (sizeMatch[2] == 'MB' ? 1024 * 1024 : 1024);
    if (!{'keep', 'dio', 'dout', 'qio', 'qout'}.contains(flashMode) ||
        !{'keep', '20m', '26m', '40m', '80m'}.contains(flashFrequency) ||
        (capacity == null && !{'DETECT', 'KEEP'}.contains(flashSize))) {
      throw const FormatException('Invalid flash configuration.');
    }
    if (images.isEmpty) {
      throw const FormatException('Enable at least one binary.');
    }
    final segments = <({int offset, int length, String path})>[];
    for (final image in images) {
      final address = image.address.trim();
      if (!RegExp(r'^(0[xX][0-9a-fA-F]+|[0-9]+)$').hasMatch(address)) {
        throw FormatException('Invalid address: ${image.address}');
      }
      final offset = int.tryParse(address);
      if (offset == null || offset < 0 || offset > 0xffffffff) {
        throw FormatException('Address out of range: $address');
      }
      final file = File(image.path);
      if (image.path.trim().isEmpty || !await file.exists()) {
        throw FormatException('Binary not found: ${image.path}');
      }
      final handle = await file.open();
      late final int length;
      try {
        length = await handle.length();
        await handle.read(1);
      } finally {
        await handle.close();
      }
      if (length == 0) throw FormatException('Empty binary: ${image.path}');
      if (offset + length > (capacity ?? 0x100000000)) {
        throw FormatException('Binary exceeds flash size: ${image.path}');
      }
      segments.add((offset: offset, length: length, path: file.absolute.path));
    }
    segments.sort((a, b) => a.offset.compareTo(b.offset));
    for (var i = 1; i < segments.length; i++) {
      final previous = segments[i - 1];
      // esptool erases whole 4 KiB sectors, including partially used ones.
      final erasedEnd =
          ((previous.offset + previous.length + 4095) ~/ 4096) * 4096;
      if ((segments[i].offset ~/ 4096) * 4096 < erasedEnd) {
        throw FormatException(
          'Flash sectors overlap: ${previous.path} and ${segments[i].path}',
        );
      }
    }
    return [
      ...connection,
      'write-flash',
      '--flash-mode',
      flashMode,
      '--flash-freq',
      flashFrequency,
      '--flash-size',
      capacity == null ? flashSize.toLowerCase() : flashSize,
      for (final segment in segments) ...[
        '0x${segment.offset.toRadixString(16)}',
        segment.path,
      ],
    ];
  }
}

List<String> _connectionArguments(String port, String baud, String chip) {
  final target = chip.toLowerCase().replaceAll('-', '');
  if (port.trim().isEmpty) {
    throw const FormatException('Select a serial port.');
  }
  if ((int.tryParse(baud) ?? 0) <= 0) {
    throw const FormatException('Invalid baud rate.');
  }
  if (!{
    'esp8266',
    'esp32',
    'esp32s2',
    'esp32s3',
    'esp32c2',
    'esp32c3',
    'esp32c5',
    'esp32c6',
    'esp32h2',
    'esp32p4',
  }.contains(target)) {
    throw const FormatException('Unsupported chip.');
  }
  return ['--chip', target, '--port', port, '--baud', baud];
}

class EraseRequest {
  const EraseRequest({
    required this.port,
    required this.baud,
    required this.chip,
  });
  final String port, baud, chip;
  List<String> arguments() => [
    ..._connectionArguments(port, baud, chip),
    'erase-flash',
  ];
}

class FlashCancelled implements Exception {
  FlashCancelled([this.operation = 'Programming']);
  final String operation;
  @override
  String toString() =>
      '$operation interrupted. Flash contents may be incomplete.';
}

typedef ProcessLauncher = Future<Process> Function(String, List<String>);

/// Owns a single operation, including tool discovery and process termination.
class FlashService {
  FlashService({
    ProcessLauncher? launch,
    this.timeout = const Duration(minutes: 10),
  }) : _launch =
           launch ??
           ((exe, args) => Process.start(
             exe,
             args,
             environment: {'PYTHONUNBUFFERED': '1'},
           ));
  final ProcessLauncher _launch;
  final Duration timeout;
  Process? _process;
  Timer? _killTimer;
  bool _cancelled = false;
  bool _running = false;
  String _operation = 'Programming';

  void cancel() {
    _cancelled = true;
    final process = _process;
    if (process != null) {
      process.kill();
      _killTimer ??= Timer(
        const Duration(seconds: 2),
        () => process.kill(ProcessSignal.sigkill),
      );
    }
  }

  void _checkCancelled() {
    if (_cancelled) throw FlashCancelled(_operation);
  }

  Future<void> program(
    FlashRequest request, {
    required void Function(String) onLog,
    required void Function(double) onProgress,
  }) => _operate(request.arguments, onLog: onLog, onProgress: onProgress);

  Future<void> erase(
    EraseRequest request, {
    required void Function(String) onLog,
  }) => _operate(
    () async => request.arguments(),
    operation: 'Erase',
    onLog: onLog,
    onProgress: (_) {},
  );

  Future<void> _operate(
    Future<List<String>> Function() buildArguments, {
    String operation = 'Programming',
    required void Function(String) onLog,
    required void Function(double) onProgress,
  }) async {
    if (_running) throw StateError('A flash operation is already running.');
    _running = true;
    _operation = operation;
    _cancelled = false;
    try {
      final arguments = await buildArguments();
      _checkCancelled();
      final candidates = Platform.isWindows
          ? [
              ('esptool.exe', <String>[]),
              ('esptool.py', <String>[]),
              ('py', ['-m', 'esptool']),
              ('python', ['-m', 'esptool']),
            ]
          : [
              ('esptool', <String>[]),
              ('esptool.py', <String>[]),
              ('python3', ['-m', 'esptool']),
            ];
      (String, List<String>)? tool;
      var legacy = false;
      for (final candidate in candidates) {
        _checkCancelled();
        try {
          final probe = await _execute(
            candidate.$1,
            [...candidate.$2, 'version'],
            const Duration(seconds: 15),
            (_) {},
          );
          _checkCancelled();
          final version = RegExp(
            r'(?:esptool(?:\.py)?\s+v?|^v?)(\d+)\.',
            multiLine: true,
            caseSensitive: false,
          ).firstMatch(probe.$2);
          if (probe.$1 == 0 && version != null) {
            final major = int.parse(version[1]!);
            if (major < 4) continue;
            legacy = major == 4;
            tool = candidate;
            break;
          }
          onLog('Tool probe ${candidate.$1}: ${probe.$2}\n');
        } on ProcessException catch (error) {
          if (error.errorCode != 2) rethrow;
        }
      }
      if (tool == null) {
        throw StateError(
          'esptool 4 or newer was not found. Install it or add it to PATH.',
        );
      }
      _checkCancelled();
      final args = [
        ...tool.$2,
        ...arguments.map(
          (arg) =>
              legacy &&
                  (arg == 'write-flash' ||
                      arg == 'erase-flash' ||
                      arg.startsWith('--flash-'))
              ? arg.replaceAll('-', '_').replaceFirst('__', '--')
              : arg,
        ),
      ];
      onLog(
        '\$ ${tool.$1} ${args.map((arg) => '"${arg.replaceAll('"', '\\"')}"').join(' ')}\n',
      );
      final tracker = FlashProgress();
      final result = await _execute(tool.$1, args, timeout, (chunk) {
        onLog(chunk);
        final progress = tracker.add(chunk);
        if (progress != null) onProgress(progress);
      });
      _checkCancelled();
      if (result.$1 != 0) {
        throw ProcessException(tool.$1, args, result.$2, result.$1);
      }
      onProgress(1);
    } finally {
      _process = null;
      _killTimer?.cancel();
      _killTimer = null;
      _running = false;
    }
  }

  Future<(int, String)> _execute(
    String exe,
    List<String> args,
    Duration limit,
    void Function(String) onOutput,
  ) async {
    _checkCancelled();
    final process = await _launch(exe, args);
    _process = process;
    if (_cancelled) cancel();
    final output = StringBuffer();
    void receive(String chunk) {
      output.write(chunk);
      onOutput(chunk);
    }

    final stdout = process.stdout
        .transform(systemEncoding.decoder)
        .listen(receive);
    final stderr = process.stderr
        .transform(systemEncoding.decoder)
        .listen(receive);
    final drained = Future.wait([
      stdout.asFuture<void>(),
      stderr.asFuture<void>(),
    ]);
    try {
      final result = await Future.wait<Object?>([process.exitCode, drained])
          .timeout(limit);
      return (result.first as int, output.toString());
    } on TimeoutException {
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
        await process.exitCode;
      }
      throw TimeoutException(
        'esptool timed out. Flash contents may be incomplete.',
      );
    } finally {
      await stdout.cancel();
      await stderr.cancel();
      _process = null;
      _killTimer?.cancel();
      _killTimer = null;
    }
  }
}

/// esptool reports percentages per image, not for the complete operation.
class FlashProgress {
  String _pending = '';
  double? add(String chunk) {
    _pending += chunk;
    final lines = _pending.split(RegExp(r'[\r\n]'));
    _pending = lines.removeLast();
    double? result;
    for (final line in lines) {
      if (!RegExp(r'Writing at', caseSensitive: false).hasMatch(line)) continue;
      final match = RegExp(r'(\d+(?:\.\d+)?)\s*%').firstMatch(line);
      if (match != null) result = (double.parse(match[1]!) / 100).clamp(0, 1);
    }
    return result;
  }
}
