import 'dart:async';
import 'dart:io';

class EspToolCandidate {
  const EspToolCandidate(this.executable, [this.prefixArguments = const []]);

  final String executable;
  final List<String> prefixArguments;
}

class EspToolValidation {
  const EspToolValidation({required this.path, required this.version});

  final String path;
  final String version;
}

typedef EspToolProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

List<EspToolCandidate> espToolCandidates({
  String? configuredPath,
  String? applicationExecutable,
  bool? windows,
}) {
  final isWindows = windows ?? Platform.isWindows;
  final result = <EspToolCandidate>[];
  final seen = <String>{};

  void add(String executable, [List<String> prefixArguments = const []]) {
    final key =
        '${isWindows ? executable.toLowerCase() : executable}\u0000'
        '${prefixArguments.join('\u0000')}';
    if (seen.add(key)) {
      result.add(EspToolCandidate(executable, prefixArguments));
    }
  }

  final configured = configuredPath?.trim();
  if (configured != null && configured.isNotEmpty) add(configured);

  final executable = applicationExecutable ?? Platform.resolvedExecutable;
  final applicationDirectory = File(executable).parent.path;
  if (isWindows) {
    add('$applicationDirectory${Platform.pathSeparator}esptool.exe');
    add('esptool.exe');
    add('esptool.py');
    add('py', const ['-m', 'esptool']);
    add('python', const ['-m', 'esptool']);
  } else {
    add('$applicationDirectory${Platform.pathSeparator}esptool');
    add('$applicationDirectory${Platform.pathSeparator}esptool.py');
    add('esptool');
    add('esptool.py');
    add('python3', const ['-m', 'esptool']);
    add('python', const ['-m', 'esptool']);
  }
  return result;
}

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
    String? configuredPath,
    void Function(String message)? onStatus,
  }) async {
    try {
      return await _testConnection(
        port: port,
        baud: baud,
        configuredPath: configuredPath,
      );
    } on EspToolNotFoundException {
      onStatus?.call('esptool is missing. Installing it automatically...');
      await install(onStatus: onStatus);
      onStatus?.call('esptool installed. Testing the ESP connection...');
      return _testConnection(
        port: port,
        baud: baud,
        configuredPath: configuredPath,
      );
    }
  }

  static Future<EspConnectionResult> _testConnection({
    required String port,
    required String baud,
    String? configuredPath,
  }) async {
    Object? lastError;
    for (final candidate in espToolCandidates(configuredPath: configuredPath)) {
      try {
        return await _run(candidate.executable, [
          ...candidate.prefixArguments,
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

  static Future<EspToolValidation> validateExecutable(
    String path, {
    EspToolProcessRunner? run,
  }) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Select an esptool executable.');
    }
    final file = File(trimmed);
    if (!await file.exists()) {
      throw FormatException('esptool was not found at $trimmed');
    }
    final absolutePath = file.absolute.path;
    final runner =
        run ?? (executable, arguments) => Process.run(executable, arguments);
    late final ProcessResult process;
    try {
      process = await runner(absolutePath, const [
        'version',
      ]).timeout(const Duration(seconds: 15));
    } on Object catch (error) {
      throw StateError('Unable to run esptool: $error');
    }
    final output = '${process.stdout}\n${process.stderr}'.trim();
    if (process.exitCode != 0) {
      throw StateError(
        'esptool version check failed (exit ${process.exitCode}). $output',
      );
    }
    final major = detectEsptoolMajor(output);
    if (major == null) {
      throw const FormatException(
        'The selected file did not report a recognizable esptool version.',
      );
    }
    if (major < 4) {
      throw FormatException('esptool 4 or newer is required; found $major.');
    }
    final version = RegExp(
      r'(?:esptool(?:\.py)?\s+v?|^v?)(\d+(?:\.\d+)+)',
      multiLine: true,
      caseSensitive: false,
    ).firstMatch(output)?.group(1);
    return EspToolValidation(
      path: absolutePath,
      version: version ?? major.toString(),
    );
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

int? detectEsptoolMajor(String output) {
  final match = RegExp(
    r'(?:esptool(?:\.py)?\s+v?|^v?)(\d+)\.',
    multiLine: true,
    caseSensitive: false,
  ).firstMatch(output);
  return match == null ? null : int.parse(match.group(1)!);
}
