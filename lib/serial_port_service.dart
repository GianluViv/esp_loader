import 'dart:io';

import 'package:flutter_libserialport/flutter_libserialport.dart';

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
    try {
      final result = await Process.run('powershell.exe', const [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'''
$descriptions = @{}
Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -match '\((COM\d+)\)' } |
  ForEach-Object { $descriptions[$Matches[1].ToUpperInvariant()] = $_.Name }

$ports = [System.Collections.Generic.HashSet[string]]::new(
  [System.StringComparer]::OrdinalIgnoreCase
)

$serialMap = Get-ItemProperty `
  -LiteralPath 'HKLM:\HARDWARE\DEVICEMAP\SERIALCOMM' `
  -ErrorAction SilentlyContinue
if ($serialMap) {
  $serialMap.PSObject.Properties |
    Where-Object { $_.Name -notlike 'PS*' -and $_.Value -match '^COM\d+$' } |
    ForEach-Object { [void]$ports.Add([string]$_.Value) }
}

Get-CimInstance Win32_SerialPort -ErrorAction SilentlyContinue |
  Where-Object { $_.DeviceID -match '^COM\d+$' } |
  ForEach-Object {
    $port = $_.DeviceID.ToUpperInvariant()
    [void]$ports.Add($port)
    if (-not $descriptions.ContainsKey($port)) { $descriptions[$port] = $_.Name }
  }

$ports | ForEach-Object {
  $port = $_.ToUpperInvariant()
  "$port`t$($descriptions[$port])"
}
''',
      ]).timeout(const Duration(seconds: 8));
      if (result.exitCode == 0) {
        final ports = parseWindowsSerialPorts(result.stdout.toString());
        if (ports.isNotEmpty) return ports;
      }
    } on Exception {
      // La libreria nativa sottostante resta disponibile come fallback quando
      // PowerShell, CIM o il registro non sono accessibili.
    }

    return SerialPort.availablePorts
        .map((port) => SerialPortInfo(port.toUpperCase()))
        .toList()
      ..sort((a, b) => _compareWindowsPorts(a.port, b.port));
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
  final ports = <String, SerialPortInfo>{};
  for (final rawLine in output.split(RegExp(r'[\r\n]+'))) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    final columns = line.split('\t');
    final port = columns.first.trim();
    if (!RegExp(r'^COM\d+$', caseSensitive: false).hasMatch(port)) continue;
    final description = columns.length > 1
        ? columns.sublist(1).join(' ').trim()
        : null;
    final normalizedPort = port.toUpperCase();
    final previous = ports[normalizedPort];
    ports[normalizedPort] = SerialPortInfo(
      normalizedPort,
      description?.isNotEmpty == true ? description : previous?.description,
    );
  }
  return ports.values.toList()
    ..sort((a, b) => _compareWindowsPorts(a.port, b.port));
}

int _compareWindowsPorts(String a, String b) {
  int number(String value) => int.tryParse(value.substring(3)) ?? 0;
  return number(a).compareTo(number(b));
}
