import 'dart:typed_data';

class EspPartition {
  const EspPartition({
    required this.label,
    required this.type,
    required this.subtype,
    required this.offset,
    required this.size,
  });

  final String label;
  final int type;
  final int subtype;
  final int offset;
  final int size;

  bool get isApp => type == 0;
}

/// Decodes the ESP-IDF binary partition-table format.
List<EspPartition> parseEspPartitionTable(Uint8List bytes) {
  const entrySize = 32;
  final result = <EspPartition>[];
  final data = ByteData.sublistView(bytes);
  for (
    var position = 0;
    position + entrySize <= bytes.length;
    position += entrySize
  ) {
    final magic = data.getUint16(position, Endian.little);
    if (magic == 0xffff) break;
    // 0xEBEB identifies the final MD5 record, not a partition.
    if (magic == 0xebeb) break;
    if (magic != 0x50aa) {
      throw const FormatException('Invalid ESP partition table');
    }
    final labelBytes = bytes.sublist(position + 12, position + 28);
    final zero = labelBytes.indexOf(0);
    final label = String.fromCharCodes(
      zero < 0 ? labelBytes : labelBytes.sublist(0, zero),
    );
    result.add(
      EspPartition(
        label: label,
        type: bytes[position + 2],
        subtype: bytes[position + 3],
        offset: data.getUint32(position + 4, Endian.little),
        size: data.getUint32(position + 8, Endian.little),
      ),
    );
  }
  if (result.isEmpty) {
    throw const FormatException('Empty ESP partition table');
  }
  return result;
}
