import 'dart:async';
import 'dart:io';

class EspConnectionResult {
  const EspConnectionResult({
    required this.chip,
    required this.output,
    this.flashSize,
  });

  final String chip;
  final String output;
  final String? flashSize;
}

class EspToolService {
  static Future<EspConnectionResult> testConnection({
    required String port,
    required String baud,
    void Function(String message)? onStatus,
  }) async {
    try {
      return await _testConnection(port: port, baud: baud);
    } on EspToolNotFoundException {
      onStatus?.call('esptool is missing. Installing it automatically...');
      await install(onStatus: onStatus);
      onStatus?.call('esptool installed. Testing the ESP connection...');
      return _testConnection(port: port, baud: baud);
    }
  }

  static Future<EspConnectionResult> _testConnection({
    required String port,
    required String baud,
  }) async {
    final attempts = Platform.isWindows
        ? const [
            ('esptool.exe', <String>[]),
            ('esptool.py', <String>[]),
            ('py', ['-m', 'esptool']),
            ('python', ['-m', 'esptool']),
          ]
        : const [
            ('esptool', <String>[]),
            ('esptool.py', <String>[]),
            ('python3', ['-m', 'esptool']),
          ];

    Object? lastError;
    for (final attempt in attempts) {
      try {
        return await _run(attempt.$1, [
          ...attempt.$2,
          '--port',
          port,
          '--baud',
          baud,
          'flash-id',
        ]);
      } on ProcessException catch (error) {
        lastError = error;
        if (error.errorCode != 2 && !_moduleIsMissing(error.message)) rethrow;
      }
    }
    throw EspToolNotFoundException('esptool was not found. ${lastError ?? ''}');
  }

  static Future<void> install({void Function(String message)? onStatus}) async {
    final interpreters = Platform.isWindows
        ? const [('py', <String>[]), ('python', <String>[])]
        : const [('python3', <String>[]), ('python', <String>[])];
    Object? lastError;
    for (final interpreter in interpreters) {
      try {
        onStatus?.call('Installing esptool with ${interpreter.$1}...');
        final process = await Process.run(interpreter.$1, [
          ...interpreter.$2,
          '-m',
          'pip',
          'install',
          '--user',
          '--upgrade',
          '--disable-pip-version-check',
          'esptool',
        ]).timeout(const Duration(minutes: 5));
        final output = '${process.stdout}\n${process.stderr}'.trim();
        if (process.exitCode == 0) return;
        lastError = output;
      } on Object catch (error) {
        lastError = error;
      }
    }
    throw StateError('Automatic esptool installation failed. $lastError');
  }

  static bool _moduleIsMissing(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('no module named') &&
        normalized.contains('esptool');
  }

  static Future<EspConnectionResult> _run(
    String executable,
    List<String> arguments,
  ) async {
    final process = await Process.start(executable, arguments);
    final stdoutFuture = process.stdout
        .transform(systemEncoding.decoder)
        .join();
    final stderrFuture = process.stderr
        .transform(systemEncoding.decoder)
        .join();
    int exitCode;
    try {
      exitCode = await process.exitCode.timeout(const Duration(seconds: 20));
    } on TimeoutException {
      process.kill();
      throw TimeoutException('The device did not respond within 20 seconds.');
    }
    final output = '${await stdoutFuture}\n${await stderrFuture}'.trim();
    if (exitCode != 0) {
      throw ProcessException(executable, arguments, output, exitCode);
    }
    final chip = detectEspChip(output);
    if (chip == null) {
      throw FormatException('Unknown ESP type. Output: $output');
    }
    return EspConnectionResult(
      chip: chip,
      output: output,
      flashSize: detectFlashSize(output),
    );
  }
}

class EspToolNotFoundException implements Exception {
  const EspToolNotFoundException(this.message);

  final String message;

  @override
  String toString() => message;
}

String? detectFlashSize(String output) {
  final match = RegExp(
    r'(?:detected\s+)?flash\s+size\s*:\s*(\d+)\s*(KB|MB)',
    caseSensitive: false,
  ).firstMatch(output);
  if (match == null) return null;
  return '${match.group(1)} ${match.group(2)!.toUpperCase()}';
}

String? detectEspChip(String output) {
  final normalized = output.toUpperCase();
  const chips = [
    'ESP32-P4',
    'ESP32-C6',
    'ESP32-C5',
    'ESP32-C3',
    'ESP32-C2',
    'ESP32-S3',
    'ESP32-S2',
    'ESP32-H2',
    'ESP32',
    'ESP8266',
  ];
  for (final chip in chips) {
    if (normalized.contains(chip)) return chip;
  }
  return null;
}
