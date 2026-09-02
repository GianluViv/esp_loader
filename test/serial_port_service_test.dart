import 'package:esp_loader/serial_port_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses and naturally orders Windows serial ports', () {
    final ports = parseWindowsSerialPorts(
      'COM12\tUSB Serial Port (COM12)\r\nCOM3\tCP210x (COM3)\r\n',
    );

    expect(ports.map((item) => item.port), ['COM3', 'COM12']);
    expect(ports.first.displayName, 'COM3 · CP210x (COM3)');
  });

  test('ignores unrelated PowerShell output', () {
    final ports = parseWindowsSerialPorts('warning\nCOM7\tUSB JTAG/serial\n');
    expect(ports, hasLength(1));
    expect(ports.single.port, 'COM7');
  });
}
