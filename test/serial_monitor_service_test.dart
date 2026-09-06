import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:esp_loader/serial_monitor_service.dart';
import 'package:esp_loader/serial_port_service.dart';
import 'package:esp_loader/main.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSerialConnection implements SerialConnection {
  final controller = StreamController<List<int>>();
  final writes = <List<int>>[];
  bool resetCalled = false;
  bool closed = false;

  @override
  Stream<List<int>> get bytes => controller.stream;

  @override
  void write(Uint8List data) => writes.add(data.toList());

  @override
  Future<void> reset() async => resetCalled = true;

  @override
  Future<void> close() async {
    closed = true;
    if (!controller.isClosed) await controller.close();
  }
}

void main() {
  const settings = SerialSettings(port: 'TEST', baudRate: 115200);

  group('detectSerialLogPrefix', () {
    test('detects plain debug prefixes', () {
      expect(detectSerialLogPrefix('MESH: seq=68'), 'MESH');
      expect(detectSerialLogPrefix('tRH: T1: 27.90°C'), 'tRH');
      expect(detectSerialLogPrefix('  WIFI: connected'), 'WIFI');
    });

    test('detects ESP_LOG tags, including ANSI-colored output', () {
      expect(detectSerialLogPrefix('I (123) MESH: connected'), 'MESH');
      expect(
        detectSerialLogPrefix('\x1b[0;32mI (456) esp_logi: ready\x1b[0m'),
        'esp_logi',
      );
    });

    test('ignores lines without a leading debug prefix', () {
      expect(detectSerialLogPrefix('ordinary output'), isNull);
      expect(detectSerialLogPrefix('I am not an ESP log'), isNull);
    });
  });

  test('validates serial settings before opening the port', () async {
    var opened = false;
    final service = SerialMonitorService(
      createConnection: (_) {
        opened = true;
        return FakeSerialConnection();
      },
    );
    await expectLater(
      service.connect(const SerialSettings(port: '', baudRate: 115200)),
      throwsFormatException,
    );
    expect(opened, isFalse);
    await service.dispose();
  });

  test('reassembles lines and split UTF-8 characters', () async {
    final connection = FakeSerialConnection();
    final service = SerialMonitorService(createConnection: (_) => connection);
    final received = <String>[];
    service.lines.listen(received.add, onError: (_) {});
    await service.connect(settings);

    final bytes = utf8.encode(
      'tRH: T1: 27.90°C, RH1: 53.82%\r\n'
      'MESH: seq=68 ch=6\nRPM: RPM M1:0',
    );
    final degree = bytes.indexOf(0xc2);
    connection.controller.add(bytes.sublist(0, degree + 1));
    connection.controller.add(bytes.sublist(degree + 1));
    await connection.controller.close();
    await Future<void>.delayed(Duration.zero);

    expect(received, [
      'tRH: T1: 27.90°C, RH1: 53.82%',
      'MESH: seq=68 ch=6',
      'RPM: RPM M1:0',
    ]);
    await service.dispose();
  });

  test('sends each supported terminator as exact UTF-8 bytes', () async {
    final connection = FakeSerialConnection();
    final service = SerialMonitorService(createConnection: (_) => connection);
    await service.connect(settings);
    service.send('cmd', 'None');
    service.send('cmd', 'LF');
    service.send('cmd', 'CR + LF');
    expect(connection.writes.map(utf8.decode), ['cmd', 'cmd\n', 'cmd\r\n']);
    await service.dispose();
  });

  test('reset and disconnect are forwarded to the active connection', () async {
    final connection = FakeSerialConnection();
    final service = SerialMonitorService(createConnection: (_) => connection);
    await service.connect(settings);
    await service.reset();
    expect(connection.resetCalled, isTrue);
    await service.disconnect();
    expect(connection.closed, isTrue);
    expect(service.isConnected, isFalse);
    await service.dispose();
  });

  test(
    'rejects concurrent connections and operations while disconnected',
    () async {
      final connection = FakeSerialConnection();
      final service = SerialMonitorService(createConnection: (_) => connection);
      expect(() => service.send('x', 'None'), throwsStateError);
      await expectLater(service.reset(), throwsStateError);
      await service.connect(settings);
      await expectLater(service.connect(settings), throwsStateError);
      await service.dispose();
    },
  );

  test(
    'forwards stream errors without losing the connection cleanup path',
    () async {
      final connection = FakeSerialConnection();
      final service = SerialMonitorService(createConnection: (_) => connection);
      final error = Completer<Object>();
      service.lines.listen((_) {}, onError: error.complete);
      await service.connect(settings);
      connection.controller.addError(StateError('unplugged'));
      expect(await error.future, isA<StateError>());
      await service.disconnect();
      expect(connection.closed, isTrue);
      await service.dispose();
    },
  );

  Future<(SerialMonitorService, FakeSerialConnection)> pumpMonitor(
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final connection = FakeSerialConnection();
    final service = SerialMonitorService(createConnection: (_) => connection);
    await tester.pumpWidget(
      FluentApp(
        home: MonitorPage(
          monitor: service,
          discoverPorts: () async => [
            const SerialPortInfo('TEST_PORT', 'GS240A'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (service, connection);
  }

  testWidgets('connects at the GS240A defaults and renders real lines', (
    tester,
  ) async {
    final (_, connection) = await pumpMonitor(tester);
    expect(find.text('Disconnected'), findsOneWidget);
    await tester.tap(find.byKey(const Key('monitor-connect-button')));
    await tester.pumpAndSettle();
    expect(find.text('Connected · 115200 8N1'), findsOneWidget);

    connection.controller.add(
      utf8.encode('ALL: All. M1: 27\r\ntRH: T1: 27.90°C, RH1: 53.82%\r\n'),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('ALL: All. M1: 27'), findsOneWidget);
    expect(find.textContaining('T1: 27.90°C'), findsOneWidget);
    expect(find.text('Buffer 2 / 10000 lines'), findsOneWidget);
  });

  testWidgets('Pause retains incoming lines and Resume displays them', (
    tester,
  ) async {
    final (_, connection) = await pumpMonitor(tester);
    await tester.tap(find.byKey(const Key('monitor-connect-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();
    connection.controller.add(utf8.encode('WIFI: Task WiFi: 58 Status: 3\n'));
    await tester.pump();
    expect(find.textContaining('WIFI: Task WiFi'), findsNothing);
    await tester.tap(find.text('Resume'));
    await tester.pumpAndSettle();
    expect(find.textContaining('WIFI: Task WiFi'), findsOneWidget);
  });

  testWidgets('sends text with the selected terminator', (tester) async {
    final (_, connection) = await pumpMonitor(tester);
    await tester.tap(find.byKey(const Key('monitor-connect-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextBox, 'Send to serial port…'),
      'status',
    );
    await tester.tap(find.text('Send'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(utf8.decode(connection.writes.single), 'status\r\n');
  });

  testWidgets('discovers prefixes and creates selected live tabs', (
    tester,
  ) async {
    final (_, connection) = await pumpMonitor(tester);
    await tester.tap(find.byKey(const Key('monitor-connect-button')));
    await tester.pumpAndSettle();
    connection.controller.add(
      utf8.encode(
        'MESH: seq=68 ch=6\n'
        'tRH: T1: 27.90°C, RH1: 53.82%\n'
        'WIFI: Task WiFi: 58 Status: 3\n'
        'STAT: MESH is mentioned but is not the prefix\n'
        'I (123) NET: connected\n',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('prefix-checkbox-MESH')), findsOneWidget);
    expect(find.byKey(const ValueKey('prefix-checkbox-tRH')), findsOneWidget);
    expect(find.byKey(const ValueKey('prefix-checkbox-NET')), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextBox, 'Filter detected prefixes…'),
      'mes',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('prefix-checkbox-MESH')), findsOneWidget);
    expect(find.byKey(const ValueKey('prefix-checkbox-tRH')), findsNothing);
    await tester.enterText(
      find.widgetWithText(TextBox, 'Filter detected prefixes…'),
      '',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('prefix-checkbox-MESH')));
    await tester.tap(find.byKey(const ValueKey('prefix-checkbox-tRH')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('monitor-tab-All')), findsOneWidget);
    expect(find.byKey(const ValueKey('monitor-tab-MESH')), findsOneWidget);
    expect(find.byKey(const ValueKey('monitor-tab-tRH')), findsOneWidget);
    expect(find.text('All'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('monitor-tab-MESH')));
    await tester.pumpAndSettle();
    expect(find.textContaining('MESH: seq=68'), findsOneWidget);
    expect(find.textContaining('tRH: T1'), findsNothing);
    expect(find.textContaining('WIFI: Task'), findsNothing);
    expect(find.textContaining('STAT: MESH'), findsNothing);

    connection.controller.add(utf8.encode('MESH: seq=69 ch=6\n'));
    await tester.pumpAndSettle();
    expect(find.textContaining('MESH: seq=69'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('monitor-tab-All')));
    await tester.pumpAndSettle();
    expect(find.textContaining('WIFI: Task'), findsOneWidget);
    expect(find.textContaining('STAT: MESH'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('prefix-checkbox-NET')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('monitor-tab-NET')));
    await tester.pumpAndSettle();
    expect(find.textContaining('I (123) NET: connected'), findsOneWidget);
  });

  testWidgets('one selected prefix creates its own tab', (tester) async {
    final (_, connection) = await pumpMonitor(tester);
    await tester.tap(find.byKey(const Key('monitor-connect-button')));
    await tester.pumpAndSettle();
    connection.controller.add(
      utf8.encode('STAT: contains MESH later\nMESH: starts correctly\n'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('prefix-checkbox-MESH')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('monitor-tab-All')), findsOneWidget);
    expect(find.byKey(const ValueKey('monitor-tab-MESH')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('monitor-tab-MESH')));
    await tester.pumpAndSettle();
    expect(find.textContaining('MESH: starts correctly'), findsOneWidget);
    expect(find.textContaining('STAT: contains MESH'), findsNothing);
  });
}
