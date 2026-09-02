import 'dart:io';

class SerialPortInfo {
  const SerialPortInfo(this.port, [this.description]);

  final String port;
  final String? description;

  String get displayName {
    final detail = description?.trim();
    return detail == null || detail.isEmpty || detail == port
        ? port
        : '$port · $detail';
  }
}

class SerialPortService {
  static Future<List<SerialPortInfo>> discover() async {
    if (Platform.isWindows) return _discoverWindows();
    if (Platform.isLinux) return _discoverUnix(const ['ttyUSB', 'ttyACM']);
    if (Platform.isMacOS) {
      return _discoverUnix(const ['cu.usb', 'tty.usb', 'cu.SLAB', 'cu.wch']);
    }
    return const [];
  }

  static Future<List<SerialPortInfo>> _discoverWindows() async {
    final result = await Process.run('powershell.exe', const [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      r'Get-CimInstance Win32_SerialPort | ForEach-Object { "$($_.DeviceID)`t$($_.Name)" }',
    ]).timeout(const Duration(seconds: 8));
    if (result.exitCode != 0) {
      throw ProcessException(
        'powershell.exe',
        const [],
        result.stderr.toString().trim(),
        result.exitCode,
      );
    }
    return parseWindowsSerialPorts(result.stdout.toString());
  }

  static Future<List<SerialPortInfo>> _discoverUnix(
    List<String> prefixes,
  ) async {
    final devices = <SerialPortInfo>[];
    final directory = Directory('/dev');
    for (final entity in directory.listSync(followLinks: false)) {
      final name = entity.path.split('/').last;
      if (prefixes.any(name.startsWith)) {
        devices.add(SerialPortInfo(entity.path));
      }
    }
    devices.sort((a, b) => a.port.compareTo(b.port));
    return devices;
  }
}

List<SerialPortInfo> parseWindowsSerialPorts(String output) {
  final ports = <SerialPortInfo>[];
  for (final rawLine in output.split(RegExp(r'[\r\n]+'))) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    final columns = line.split('\t');
    final port = columns.first.trim();
    if (!RegExp(r'^COM\d+$', caseSensitive: false).hasMatch(port)) continue;
    final description = columns.length > 1
        ? columns.sublist(1).join(' ').trim()
        : null;
    ports.add(SerialPortInfo(port.toUpperCase(), description));
  }
  ports.sort((a, b) {
    int number(String value) => int.tryParse(value.substring(3)) ?? 0;
    return number(a.port).compareTo(number(b.port));
  });
  return ports;
}
