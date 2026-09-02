import 'dart:typed_data';

import 'package:esp_loader/partition_table.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodes ESP-IDF partition offsets and labels', () {
    final bytes = Uint8List(64);
    final data = ByteData.sublistView(bytes);
    void entry(int position, String label, int type, int subtype, int offset) {
      data.setUint16(position, 0x50aa, Endian.little);
      bytes[position + 2] = type;
      bytes[position + 3] = subtype;
      data.setUint32(position + 4, offset, Endian.little);
      data.setUint32(position + 8, 0x10000, Endian.little);
      bytes.setRange(
        position + 12,
        position + 12 + label.length,
        label.codeUnits,
      );
    }

    entry(0, 'nvs', 1, 2, 0x9000);
    entry(32, 'factory', 0, 0, 0x10000);

    final partitions = parseEspPartitionTable(bytes);
    expect(partitions, hasLength(2));
    expect(partitions.first.label, 'nvs');
    expect(partitions.first.offset, 0x9000);
    expect(partitions.last.isApp, isTrue);
    expect(partitions.last.offset, 0x10000);
  });

  test('rejects data that is not an ESP partition table', () {
    expect(
      () => parseEspPartitionTable(Uint8List(32)),
      throwsA(isA<FormatException>()),
    );
  });
}
