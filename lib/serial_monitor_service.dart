import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';

enum SerialParity { none, even, odd }

String? detectSerialLogPrefix(String line) {
  final clean = line
      .replaceAll(RegExp(r'\x1B\[[0-9;]*[A-Za-z]'), '')
      .trimLeft();
  final espLog = RegExp(
    r'^[EWIDV]\s+\([^)]*\)\s+([A-Za-z_][A-Za-z0-9_.-]*)\s*:',
  ).firstMatch(clean);
  if (espLog != null) return espLog.group(1);
  return RegExp(r'^([A-Za-z_][A-Za-z0-9_.-]*)\s*:').firstMatch(clean)?.group(1);
}

class SerialSettings {
  const SerialSettings({
    required this.port,
    required this.baudRate,
    this.dataBits = 8,
    this.stopBits = 1,
    this.parity = SerialParity.none,
  });

  final String port;
  final int baudRate;
  final int dataBits;
  final int stopBits;
  final SerialParity parity;

  void validate() {
    if (port.trim().isEmpty) {
      throw const FormatException('Select a serial port.');
    }
    if (baudRate <= 0) {
      throw const FormatException('Invalid baud rate.');
    }
    if (dataBits != 7 && dataBits != 8) {
      throw const FormatException('Data bits must be 7 or 8.');
    }
    if (stopBits != 1 && stopBits != 2) {
      throw const FormatException('Stop bits must be 1 or 2.');
    }
  }
}

abstract class SerialConnection {
  Stream<List<int>> get bytes;
  void write(Uint8List data);
  Future<void> reset();
  Future<void> close();
}

typedef SerialConnectionFactory = SerialConnection Function(
  SerialSettings settings,
);

class SerialMonitorService {
  SerialMonitorService({SerialConnectionFactory? createConnection})
    : _createConnection = createConnection ?? NativeSerialConnection.new;

  final SerialConnectionFactory _createConnection;
  final _lines = StreamController<String>.broadcast();
  SerialConnection? _connection;
  StreamSubscription<String>? _subscription;

  Stream<String> get lines => _lines.stream;
  bool get isConnected => _connection != null;

  Future<void> connect(SerialSettings settings) async {
    if (isConnected) {
      throw StateError('The serial port is already connected.');
    }
    settings.validate();
    final connection = _createConnection(settings);
    _connection = connection;
    try {
      _subscription = connection.bytes
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen(
            _lines.add,
            onError: _lines.addError,
            onDone: () {
              if (!_lines.isClosed) {
                _lines.addError(
                  StateError('The serial device was disconnected.'),
                );
              }
            },
            cancelOnError: false,
          );
    } on Object {
      _connection = null;
      await connection.close();
      rethrow;
    }
  }

  void send(String text, String terminator) {
    final connection = _connection;
    if (connection == null) {
      throw StateError('The serial port is not connected.');
    }
    final suffix = switch (terminator) {
      'LF' => '\n',
      'CR + LF' => '\r\n',
      _ => '',
    };
    connection.write(Uint8List.fromList(utf8.encode('$text$suffix')));
  }

  Future<void> reset() async {
    final connection = _connection;
    if (connection == null) {
      throw StateError('The serial port is not connected.');
    }
    await connection.reset();
  }

  Future<void> disconnect() async {
    final connection = _connection;
    _connection = null;
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    await connection?.close();
  }

  Future<void> dispose() async {
    await disconnect();
    await _lines.close();
  }
}

class NativeSerialConnection implements SerialConnection {
  NativeSerialConnection(SerialSettings settings)
    : _port = SerialPort(settings.port) {
    if (!_port.openReadWrite()) {
      final error = SerialPort.lastError;
      _port.dispose();
      throw StateError(
        'Unable to open ${settings.port}: ${error?.message ?? 'unknown error'}',
      );
    }
    final config = SerialPortConfig();
    try {
      config
        ..baudRate = settings.baudRate
        ..bits = settings.dataBits
        ..stopBits = settings.stopBits
        ..parity = switch (settings.parity) {
          SerialParity.none => SerialPortParity.none,
          SerialParity.even => SerialPortParity.even,
          SerialParity.odd => SerialPortParity.odd,
        }
        ..setFlowControl(SerialPortFlowControl.none);
      _port.config = config;
    } on Object {
      _port.close();
      _port.dispose();
      rethrow;
    }
    _bytes = StreamController<List<int>>.broadcast(
      onListen: _startPolling,
      onCancel: _stopPolling,
    );
  }

  final SerialPort _port;
  late final StreamController<List<int>> _bytes;
  Timer? _pollTimer;
  bool _closed = false;

  @override
  Stream<List<int>> get bytes => _bytes.stream;

  void _startPolling() {
    if (_closed || _pollTimer != null) return;
    _pollTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      try {
        final available = _port.bytesAvailable;
        if (available > 0) _bytes.add(_port.read(available));
      } on Object catch (error, stackTrace) {
        _stopPolling();
        if (!_bytes.isClosed) _bytes.addError(error, stackTrace);
      }
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  void write(Uint8List data) {
    final written = _port.write(data, timeout: 1000);
    if (written != data.length) {
      throw StateError('Only $written of ${data.length} bytes were sent.');
    }
  }

  @override
  Future<void> reset() async {
    final config = _port.config;
    config
      ..dtr = SerialPortDtr.off
      ..rts = SerialPortRts.on;
    _port.config = config;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    config
      ..dtr = SerialPortDtr.off
      ..rts = SerialPortRts.off;
    _port.config = config;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _stopPolling();
    await _bytes.close();
    if (_port.isOpen) _port.close();
    _port.dispose();
  }
}
