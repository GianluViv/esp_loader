import 'package:esp_loader/plot_data_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extracts numeric colon fields without the log category', () {
    final values = parsePlotMeasurements(
      '[22:19:43.627]  RPM: RPM M1:0  RPM M2:0',
    );
    expect(values.map((item) => item.name), ['M1', 'M2']);
    expect(values.map((item) => item.value), [0, 0]);
  });

  test('extracts decimal values and units', () {
    final values = parsePlotMeasurements(
      '[22:19:43.627]  tRH: T1: 28.56°C, RH1: 52.44%',
    );
    expect(values.map((item) => item.name), ['T1', 'RH1']);
    expect(values.map((item) => item.value), [28.56, 52.44]);
    expect(values.map((item) => item.unit), ['°C', '%']);
  });

  test('extracts fields from status and descriptive probe lines', () {
    final status = parsePlotMeasurements(
      'STAT: 06/09/2026 Dom 22:19:43 - V1 - V1: 40 - V2: 0 - TIME: 109',
    );
    expect(status.map((item) => item.name), ['V1', 'V2', 'TIME']);

    final probes = parsePlotMeasurements(
      'tRH: Sonde analogiche - IO34: 0 IO36: 0°C',
    );
    expect(probes.map((item) => item.name), ['IO34', 'IO36']);
  });

  test('supports descriptive firmware labels separated by semicolons', () {
    final values = parsePlotMeasurements(
      'MOTORI: Motore Destro: 42; Motore Sinistro: -38.5 rpm',
    );
    expect(values.map((item) => item.name), [
      'Motore Destro',
      'Motore Sinistro',
    ]);
    expect(values.map((item) => item.value), [42, -38.5]);
  });

  test('ignores equals fields and nonnumeric colon fields', () {
    final values = parsePlotMeasurements(
      'MESH: ESP-NOW seq=94 ch=6 state: ready',
    );
    expect(values, isEmpty);
  });
}
