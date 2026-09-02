import 'package:esp_loader/esptool_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recognizes chip from current esptool output', () {
    expect(detectEspChip('Detecting chip type... ESP32-S3'), 'ESP32-S3');
    expect(detectEspChip('Chip is ESP32-C6 (QFN40)'), 'ESP32-C6');
  });

  test('does not confuse an ESP32 variant with base ESP32', () {
    expect(detectEspChip('Chip is ESP32-S2'), 'ESP32-S2');
  });

  test('returns null for unrelated output', () {
    expect(detectEspChip('No serial data received.'), isNull);
  });

  test('extracts detected flash size', () {
    expect(detectFlashSize('Detected flash size: 16MB'), '16 MB');
    expect(detectFlashSize('Flash size: 4096 KB'), '4096 KB');
    expect(detectFlashSize('Manufacturer: ef'), isNull);
  });
}
