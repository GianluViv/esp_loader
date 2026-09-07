import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:esp_loader/esptool_service.dart';
import 'package:esp_loader/local_profile_service.dart';
import 'package:esp_loader/main.dart';
import 'package:esp_loader/serial_monitor_service.dart';
import 'package:esp_loader/serial_port_service.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _ScreenshotProfile implements FlashProfileStore {
  _ScreenshotProfile(this.images, {this.projectPath});

  final List<SavedFlashImage> images;
  final String? projectPath;

  @override
  Future<List<SavedFlashImage>?> loadImages() async => images;

  @override
  Future<String?> loadProjectPath() async => projectPath;

  @override
  Future<void> saveImages(List<SavedFlashImage> images) async {}

  @override
  Future<void> saveProjectPath(String? path) async {}
}

class _ScreenshotSerialConnection implements SerialConnection {
  final controller = StreamController<List<int>>();

  @override
  Stream<List<int>> get bytes => controller.stream;

  @override
  void write(Uint8List data) {}

  @override
  Future<void> reset() async {}

  @override
  Future<void> close() async {
    if (!controller.isClosed) await controller.close();
  }
}

void main() {
  const screenshotKey = Key('documentation-screenshot');

  setUpAll(() async {
    Future<void> loadFont(String family, String path) async {
      final bytes = File(path).readAsBytesSync();
      final data = ByteData.view(bytes.buffer);
      await (FontLoader(family)..addFont(Future.value(data))).load();
    }

    await loadFont('DocSans', '/usr/share/fonts/TTF/DejaVuSans.ttf');
    await loadFont('monospace', '/usr/share/fonts/TTF/DejaVuSansMono.ttf');
  });

  Future<void> pumpScreenshot(WidgetTester tester, Widget page) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      FluentApp(
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        darkTheme: FluentThemeData(
          brightness: Brightness.dark,
          accentColor: Colors.blue,
          fontFamily: 'DocSans',
        ),
        home: RepaintBoundary(key: screenshotKey, child: page),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> capture(WidgetTester tester, String name) async {
    await expectLater(
      find.byKey(screenshotKey),
      matchesGoldenFile('../docs/images/$name.png'),
    );
  }

  Future<EspConnectionResult> detectedDevice({
    required String port,
    required String baud,
  }) async => const EspConnectionResult(
    chip: 'ESP32-S3',
    flashSize: '16 MB',
    output: 'Chip is ESP32-S3\nDetected flash size: 16MB\nCrystal is 40MHz',
  );

  testWidgets('programming screenshot', (tester) async {
    await pumpScreenshot(
      tester,
      FlashPage(
        showLog: false,
        onToggleLog: () {},
        onLog: (_) {},
        discoverPorts: () async => [
          const SerialPortInfo('/dev/ttyUSB0', 'ESP32-S3 USB JTAG/serial'),
        ],
        profileStore: _ScreenshotProfile(const [
          SavedFlashImage(
            address: '0x0000',
            path: '/firmware/bootloader/bootloader.bin',
            enabled: true,
          ),
          SavedFlashImage(
            address: '0x8000',
            path: '/firmware/partition_table/partition-table.bin',
            enabled: true,
          ),
          SavedFlashImage(
            address: '0x10000',
            path: '/firmware/environment_controller.bin',
            enabled: true,
          ),
        ]),
      ),
    );
    await capture(tester, 'programming');
  });

  testWidgets('chip detection screenshot', (tester) async {
    await pumpScreenshot(
      tester,
      FlashPage(
        showLog: false,
        onToggleLog: () {},
        onLog: (_) {},
        discoverPorts: () async => [
          const SerialPortInfo('/dev/ttyUSB0', 'ESP32-S3 USB JTAG/serial'),
        ],
        testDevice: detectedDevice,
        profileStore: _ScreenshotProfile(const []),
      ),
    );
    await tester.tap(find.byKey(const Key('test-device-button')));
    await tester.pumpAndSettle();
    await capture(tester, 'chip-detection');
  });

  testWidgets('ESP-IDF import screenshot', (tester) async {
    final root = Directory.systemTemp.createTempSync(
      'esp_loader_greenhouse_controller_',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/CMakeLists.txt')
      ..createSync()
      ..writeAsStringSync('project(greenhouse_controller)');
    for (final relative in [
      'build/bootloader/bootloader.bin',
      'build/partition_table/partition-table.bin',
      'build/greenhouse_controller.bin',
    ]) {
      File('${root.path}/$relative')
        ..createSync(recursive: true)
        ..writeAsBytesSync([1, 2, 3]);
    }
    File('${root.path}/build/flasher_args.json').writeAsStringSync('''
{
  "flash_files": {
    "0x0": "bootloader/bootloader.bin",
    "0x8000": "partition_table/partition-table.bin",
    "0x10000": "greenhouse_controller.bin"
  },
  "flash_settings": {
    "flash_mode": "dio",
    "flash_freq": "80m",
    "flash_size": "16MB"
  },
  "extra_esptool_args": {"chip": "esp32s3"}
}
''');

    await pumpScreenshot(
      tester,
      FlashPage(
        showLog: false,
        onToggleLog: () {},
        onLog: (_) {},
        discoverPorts: () async => [
          const SerialPortInfo('/dev/ttyUSB0', 'ESP32-S3 USB JTAG/serial'),
        ],
        testDevice: detectedDevice,
        profileStore: _ScreenshotProfile(const []),
        selectProjectDirectory: () async => root.path,
      ),
    );
    await tester.tap(find.byKey(const Key('select-project-folder')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key('test-device-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await capture(tester, 'esp-idf-import');
  });

  testWidgets('serial monitor screenshot', (tester) async {
    final connection = _ScreenshotSerialConnection();
    final monitor = SerialMonitorService(createConnection: (_) => connection);
    await pumpScreenshot(
      tester,
      MonitorPage(
        monitor: monitor,
        discoverPorts: () async => [
          const SerialPortInfo('/dev/ttyUSB0', 'GS240A controller'),
        ],
      ),
    );
    await tester.tap(find.byKey(const Key('monitor-connect-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    connection.controller.add(
      utf8.encode(
        'I (128) SYSTEM: GS240A ready\n'
        'WIFI: connected, RSSI: -57 dBm\n'
        'tRH: T1: 24.68°C, RH1: 51.32%\n'
        'RPM: M1: 1180 rpm, M2: 1176 rpm\n'
        'PLOT: temperature:24.68°C, humidity:51.32%\n',
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('prefix-checkbox-tRH')));
    await tester.pump();
    await capture(tester, 'serial-monitor');
  });

  testWidgets('serial plot screenshot', (tester) async {
    final lines = StreamController<String>();
    addTearDown(lines.close);
    var now = DateTime(2026, 9, 7, 12);
    await pumpScreenshot(tester, PlotPage(lines: lines.stream, now: () => now));
    for (var index = 0; index < 2; index++) {
      lines.add(
        'PLOT: temperature:${24.2 + index / 10}°C, '
        'humidity:${50.8 + index / 5}%, motor:${1140 + index * 4}rpm',
      );
      now = now.add(const Duration(milliseconds: 500));
      await tester.pump();
    }
    await tester.tap(find.byKey(const ValueKey('plot-temperature')));
    await tester.tap(find.byKey(const ValueKey('plot-humidity')));
    await tester.tap(find.byKey(const ValueKey('plot-motor')));
    for (var index = 0; index < 28; index++) {
      lines.add(
        'PLOT: temperature:${24.4 + index * 0.035}°C, '
        'humidity:${51.1 + index * 0.08}%, '
        'motor:${1150 + (index % 8) * 9}rpm',
      );
      now = now.add(const Duration(milliseconds: 500));
      await tester.pump();
    }
    await capture(tester, 'serial-plot');
  });
}
