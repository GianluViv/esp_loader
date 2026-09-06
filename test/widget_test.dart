import 'package:esp_loader/esptool_service.dart';

import 'dart:async';

import 'package:esp_loader/flash_service.dart';
import 'package:esp_loader/local_profile_service.dart';
import 'package:esp_loader/serial_port_service.dart';
import 'package:esp_loader/main.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpDesktop(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const EspLoaderApp());
    await tester.pumpAndSettle();
  }

  testWidgets('shows the desktop navigation', (tester) async {
    await pumpDesktop(tester);
    expect(find.text('ESP Loader'), findsNothing);
    expect(find.text('Programming'), findsWidgets);
    expect(find.text('Monitor'), findsOneWidget);
    expect(find.text('Plot'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
  testWidgets('toggles technical log from serial controls', (tester) async {
    await pumpDesktop(tester);
    expect(find.textContaining('No operations yet.'), findsNothing);
    await tester.tap(find.byKey(const Key('technical-log-button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('No operations yet.'), findsOneWidget);
  });
  testWidgets('Plot discovers and selects numeric serial values', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final lines = StreamController<String>();
    addTearDown(lines.close);
    await tester.pumpWidget(FluentApp(home: PlotPage(lines: lines.stream)));
    lines.add('[22:19:43.627] tRH: T1: 28.56°C, RH1: 52.44%');
    await tester.pumpAndSettle();
    expect(find.text('T1: 28.56 °C'), findsOneWidget);
    expect(find.text('RH1: 52.44 %'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('plot-T1')));
    await tester.pump();
    expect(find.text('Select one or more detected values.'), findsNothing);
    await tester.tap(find.text('Clear samples'));
    await tester.pump();
    expect(find.text('T1: —'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 150));
  });
  testWidgets('program cannot start without a serial port', (tester) async {
    await pumpDesktop(tester);
    await tester.pumpWidget(
      FluentApp(
        home: FlashPage(
          showLog: false,
          onToggleLog: () {},
          onLog: (_) {},
          discoverPorts: () async => [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('start-flash-button')),
    );
    expect(button.onPressed, isNull);
    expect(find.text('Preview command'), findsOneWidget);
    expect(
      find.text('Program when a selected binary is rebuilt'),
      findsOneWidget,
    );
    expect(
      find.text('Reconnect it if it was active before programming'),
      findsOneWidget,
    );
  });
  Future<void> pumpProgrammer(
    WidgetTester tester,
    FlashService service, {
    Future<EspConnectionResult> Function({
      required String port,
      required String baud,
    })?
    testDevice,
    Future<List<SerialPortInfo>> Function()? discoverPorts,
    Future<bool> Function()? beforeFlash,
    Future<void> Function(bool resume)? afterFlash,
    FlashProfileStore? profileStore,
  }) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      FluentApp(
        home: FlashPage(
          showLog: false,
          onToggleLog: () {},
          onLog: (_) {},
          programmer: service,
          beforeFlash: beforeFlash,
          afterFlash: afterFlash,
          profileStore: profileStore,
          testDevice: testDevice,
          discoverPorts:
              discoverPorts ?? () async => [const SerialPortInfo('TEST_PORT')],
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Program forwards selected images and waits for process success',
    (tester) async {
      final service = ControlledFlashService();
      await pumpProgrammer(tester, service);
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pump();
      await tester.tap(find.byKey(const Key('start-flash-button')));
      await tester.pump();
      expect(service.request!.port, 'TEST_PORT');
      expect(service.request!.images.length, 2);
      expect(find.text('Writing current image · 40%'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('start-flash-button')))
            .onPressed,
        isNull,
      );
      expect(
        tester.widget<TextBox>(find.byType(TextBox).first).enabled,
        isFalse,
      );
      service.result.complete();
      await tester.pumpAndSettle();
      expect(find.text('Programming completed'), findsOneWidget);
    },
  );

  testWidgets('Stop displays cancellation without a success message', (
    tester,
  ) async {
    final service = ControlledFlashService();
    await pumpProgrammer(tester, service);
    await tester.tap(find.byKey(const Key('start-flash-button')));
    await tester.pump();
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    expect(service.cancelled, isTrue);
    expect(find.textContaining('Programming interrupted.'), findsOneWidget);
    expect(find.text('Programming completed'), findsNothing);
  });

  testWidgets('disposing the page cancels its operation', (tester) async {
    final service = ControlledFlashService();
    await pumpProgrammer(tester, service);
    await tester.tap(find.byKey(const Key('start-flash-button')));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(service.cancelled, isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets('erase confirmation can be cancelled without launching', (
    tester,
  ) async {
    final service = ControlledFlashService();
    await pumpProgrammer(tester, service);
    await tester.tap(find.byKey(const Key('erase-flash-button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('TEST_PORT'), findsWidgets);
    expect(service.eraseRequest, isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(service.eraseRequest, isNull);
  });

  testWidgets('confirmed erase waits for completion and locks Program', (
    tester,
  ) async {
    final service = ControlledFlashService();
    await pumpProgrammer(tester, service);
    await tester.tap(find.byKey(const Key('erase-flash-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-erase-button')));
    await tester.pump(const Duration(seconds: 1));
    expect(service.eraseRequest!.port, 'TEST_PORT');
    expect(find.text('Erasing flash…'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('start-flash-button')))
          .onPressed,
      isNull,
    );
    service.result.complete();
    await tester.pumpAndSettle();
    expect(find.text('Flash erased successfully'), findsOneWidget);
  });

  testWidgets('program suspends and restores an active monitor', (
    tester,
  ) async {
    final service = ControlledFlashService();
    var suspended = false;
    bool? restored;
    await pumpProgrammer(
      tester,
      service,
      beforeFlash: () async {
        suspended = true;
        return true;
      },
      afterFlash: (resume) async => restored = resume,
    );
    await tester.tap(find.byKey(const Key('start-flash-button')));
    await tester.pump();
    expect(suspended, isTrue);
    expect(restored, isNull);
    service.result.complete();
    await tester.pumpAndSettle();
    expect(restored, isTrue);
  });

  testWidgets('restores and updates the local flash image profile', (
    tester,
  ) async {
    final store = MemoryProfileStore([
      const SavedFlashImage(
        address: '0x1000',
        path: '/project/build/firmware.bin',
        enabled: true,
      ),
    ]);
    await pumpProgrammer(tester, ControlledFlashService(), profileStore: store);
    expect(
      tester
          .widget<TextBox>(find.byKey(const ValueKey('flash-path-0')))
          .controller!
          .text,
      '/project/build/firmware.bin',
    );
    await tester.enterText(
      find.byKey(const ValueKey('flash-path-0')),
      '/project/build/new.bin',
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(store.saved.single.path, '/project/build/new.bin');
  });

  testWidgets('Stop during erase shows an erase-specific result', (
    tester,
  ) async {
    final service = ControlledFlashService();
    await pumpProgrammer(tester, service);
    await tester.tap(find.byKey(const Key('erase-flash-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-erase-button')));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    expect(service.cancelled, isTrue);
    expect(find.textContaining('Erase interrupted.'), findsOneWidget);
    expect(find.text('Flash erased successfully'), findsNothing);
  });
  testWidgets('Test configures flash settings and preserves firmware offsets', (
    tester,
  ) async {
    await pumpProgrammer(
      tester,
      ControlledFlashService(),
      testDevice: ({required port, required baud}) async =>
          const EspConnectionResult(
            chip: 'ESP32',
            flashSize: '4 MB',
            output: 'test',
          ),
    );
    await tester.enterText(find.byType(TextBox).first, '0x2000');
    await tester.tap(find.byKey(const Key('test-device-button')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextBox>(find.byType(TextBox).first).controller!.text,
      '0x2000',
    );
    expect(find.text('4 MB'), findsWidgets);
    expect(find.text('40 MHz'), findsOneWidget);
    expect(find.text('ESP32 · 4 MB'), findsOneWidget);
    final testTop = tester.getTopLeft(
      find.byKey(const Key('test-device-button')),
    );
    final configurationTop = tester.getTopLeft(
      find.text('Flash configuration'),
    );
    expect(testTop.dy, lessThan(configurationTop.dy));
  });

  testWidgets('Test suspends and restores an active serial monitor', (
    tester,
  ) async {
    var monitorSuspended = false;
    bool? monitorRestored;
    await pumpProgrammer(
      tester,
      ControlledFlashService(),
      beforeFlash: () async {
        monitorSuspended = true;
        return true;
      },
      afterFlash: (resume) async => monitorRestored = resume,
      testDevice: ({required port, required baud}) async {
        expect(monitorSuspended, isTrue);
        return const EspConnectionResult(
          chip: 'ESP32',
          flashSize: '4 MB',
          output: 'test',
        );
      },
    );
    await tester.tap(find.byKey(const Key('test-device-button')));
    await tester.pumpAndSettle();
    expect(monitorRestored, isTrue);
  });

  testWidgets('failed Test clears previous device detection', (tester) async {
    var attempts = 0;
    await pumpProgrammer(
      tester,
      ControlledFlashService(),
      testDevice: ({required port, required baud}) async {
        if (attempts++ > 0) throw StateError('Disconnected');
        return const EspConnectionResult(
          chip: 'ESP32',
          flashSize: '4 MB',
          output: 'test',
        );
      },
    );
    await tester.tap(find.byKey(const Key('test-device-button')));
    await tester.pumpAndSettle();
    expect(find.text('ESP32 · 4 MB'), findsOneWidget);
    await tester.tap(find.byKey(const Key('test-device-button')));
    await tester.pumpAndSettle();
    expect(find.text('Not detected'), findsOneWidget);
    expect(find.text('ESP32 · 4 MB'), findsNothing);
  });

  testWidgets('Refresh clears detection when the selected port disappears', (
    tester,
  ) async {
    var scans = 0;
    await pumpProgrammer(
      tester,
      ControlledFlashService(),
      discoverPorts: () async => [
        SerialPortInfo(scans++ == 0 ? 'FIRST_PORT' : 'SECOND_PORT'),
      ],
      testDevice: ({required port, required baud}) async =>
          const EspConnectionResult(
            chip: 'ESP32',
            flashSize: '4 MB',
            output: 'test',
          ),
    );
    await tester.tap(find.byKey(const Key('test-device-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('SECOND_PORT'), findsOneWidget);
    expect(find.text('Not detected'), findsOneWidget);
    expect(find.textContaining('successfully detected'), findsNothing);
  });
}

class ControlledFlashService extends FlashService {
  final result = Completer<void>();
  FlashRequest? request;
  EraseRequest? eraseRequest;
  @override
  Future<void> erase(
    EraseRequest request, {
    required void Function(String) onLog,
  }) async {
    eraseRequest = request;
    await result.future;
  }

  bool cancelled = false;
  @override
  Future<void> program(
    FlashRequest request, {
    required void Function(String) onLog,
    required void Function(double) onProgress,
  }) async {
    this.request = request;
    onLog('Test process output\n');
    onProgress(.4);
    await result.future;
    onProgress(1);
  }

  @override
  void cancel() {
    cancelled = true;
    if ((request != null || eraseRequest != null) && !result.isCompleted) {
      result.completeError(FlashCancelled());
    }
  }
}

class MemoryProfileStore implements FlashProfileStore {
  MemoryProfileStore(this.initial);

  final List<SavedFlashImage> initial;
  List<SavedFlashImage> saved = const [];
  String? projectPath;

  @override
  Future<List<SavedFlashImage>?> loadImages() async => initial;

  @override
  Future<void> saveImages(List<SavedFlashImage> images) async => saved = images;

  @override
  Future<String?> loadProjectPath() async => projectPath;

  @override
  Future<void> saveProjectPath(String? path) async => projectPath = path;
}
