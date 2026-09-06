class PlotMeasurement {
  const PlotMeasurement({
    required this.name,
    required this.value,
    required this.unit,
  });

  final String name;
  final double value;
  final String unit;
}

List<PlotMeasurement> parsePlotMeasurements(String line) {
  var text = line.trim();
  text = text.replaceFirst(RegExp(r'^\[\d{2}:\d{2}:\d{2}\.\d{3}\]\s*'), '');

  final prefixMatch = RegExp(r'^([^:]+):\s*(.*)$').firstMatch(text);
  if (prefixMatch == null) return const [];
  final prefix = prefixMatch.group(1)!.trim();
  var payload = prefixMatch.group(2)!.trim();
  payload = payload.replaceAll(
    RegExp(r'\b\d{2}:\d{2}:\d{2}(?:\.\d{3})?\b'),
    ' ',
  );

  // Some firmware repeats the log prefix before every value (RPM: RPM M1:0).
  payload = payload.replaceAll(
    RegExp('(?:^|\\s)${RegExp.escape(prefix)}(?=\\s)', caseSensitive: false),
    ' ',
  );

  final matches = RegExp(
    r'(?:^|[,;]|\s+-\s+|\s+)\s*'
    r'([^:;,]+?)\s*:\s*'
    r'([-+]?(?:\d+(?:[.,]\d*)?|[.,]\d+))'
    r'([^\s,;:]*)',
  ).allMatches(payload);

  return matches
      .map((match) {
        var name = match.group(1)!.trim();
        if (name.contains(' - ')) name = name.split(' - ').last.trim();
        if (name.contains('. ')) name = name.split('. ').last.trim();
        final value = double.parse(match.group(2)!.replaceAll(',', '.'));
        return PlotMeasurement(
          name: name,
          value: value,
          unit: match.group(3)?.trim() ?? '',
        );
      })
      .where((measurement) => measurement.name.isNotEmpty)
      .toList();
}
