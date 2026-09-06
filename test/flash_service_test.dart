import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:esp_loader/flash_service.dart';
import 'package:flutter_test/flutter_test.dart';

class TestProcess implements Process {
  final out = StreamController<List<int>>();
  final err = StreamController<List<int>>();
  final done = Completer<int>();
  bool killed = false;
  void finish(int code) {
    if (done.isCompleted) return;
    out.close();
    err.close();
    done.complete(code);
  }

  @override
  Stream<List<int>> get stdout => out.stream;
  @override
  Stream<List<int>> get stderr => err.stream;
  @override
  Future<int> get exitCode => done.future;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    finish(-1);
    return true;
  }

  @override
  int get pid => 123;
  @override
  IOSink get stdin => throw UnimplementedError();
}

void main() {
  late Directory directory;
  late File binary;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('flash_test_');
    binary = await File('${directory.path}/app with spaces.bin')
        .writeAsBytes(List.filled(32, 0));
  });
  tearDown(() => directory.delete(recursive: true));

  FlashRequest request({
    List<FlashImage>? images,
    String port = 'COM7',
    String? firmwareChip,
    String size = '4 MB',
  }) => FlashRequest(
    port: port,
    baud: '921600',
    chip: 'ESP32-S3',
    mode: 'DIO',
    frequency: '80 MHz',
    size: size,
    firmwareChip: firmwareChip,
    images: images ?? [FlashImage('0x10000', binary.path)],
  );

  test(
    'builds ordered arguments and preserves paths as individual arguments',
    () async {
      final args = await request(
        images: [
          FlashImage('0x10000', binary.path),
          FlashImage('0x0', binary.path),
        ],
      ).arguments();
      expect(args, [
        '--chip',
        'esp32s3',
        '--port',
        'COM7',
        '--baud',
        '921600',
        'write-flash',
        '--flash-mode',
        'dio',
        '--flash-freq',
        '80m',
        '--flash-size',
        '4MB',
        '0x0',
        binary.path,
        '0x10000',
        binary.path,
      ]);
    },
  );
  test('rejects missing port, no images and firmware mismatch', () async {
    await expectLater(request(port: '').arguments(), throwsFormatException);
    await expectLater(request(images: []).arguments(), throwsFormatException);
    await expectLater(
      request(firmwareChip: 'esp32c3').arguments(),
      throwsFormatException,
    );
  });
  test('rejects missing and empty binaries', () async {
    await expectLater(
      request(images: [const FlashImage('0x0', '/missing.bin')]).arguments(),
      throwsFormatException,
    );
    await binary.writeAsBytes([]);
    await expectLater(request().arguments(), throwsFormatException);
  });
  test('rejects malformed and out-of-range addresses', () async {
    for (final address in ['0x', '-1', 'xyz', '0x100000000']) {
      await expectLater(
        request(images: [FlashImage(address, binary.path)]).arguments(),
        throwsFormatException,
      );
    }
  });
  test('rejects sector overlap even when byte ranges do not overlap', () async {
    await expectLater(
      request(
        images: [
          FlashImage('0x0', binary.path),
          FlashImage('0x100', binary.path),
        ],
      ).arguments(),
      throwsFormatException,
    );
    await expectLater(
      request(
        images: [
          FlashImage('0x0', binary.path),
          FlashImage('0x10', binary.path),
        ],
      ).arguments(),
      throwsFormatException,
    );
  });
  test('accepts adjacent sectors and rejects flash overflow', () async {
    await request(
      images: [
        FlashImage('0x0', binary.path),
        FlashImage('0x1000', binary.path),
      ],
    ).arguments();
    await expectLater(
      request(images: [FlashImage('0x3ffff0', binary.path)]).arguments(),
      throwsFormatException,
    );
    expect(await request(size: 'Detect').arguments(), contains('detect'));
  });
  test('parses split CR progress and resets for a new image', () {
    final parser = FlashProgress();
    expect(parser.add('Writing at 0x0000 (2'), isNull);
    expect(parser.add('5 %)\r'), .25);
    expect(parser.add('Writing at 0x1000 [======] 100.0% 10/10 bytes\n'), 1);
    expect(parser.add('Compressing 50%\n'), isNull);
    expect(parser.add('Writing at 0x2000 (1 %)\r'), .01);
  });

  TestProcess version([String value = '5.0.0']) {
    final process = TestProcess();
    process.out.add(utf8.encode('esptool v$value\n'));
    process.finish(0);
    return process;
  }

  test('invalid input never starts a process', () async {
    final service = FlashService(
      launch: (_, _) => throw StateError('must not launch'),
    );
    await expectLater(
      service.program(
        request(port: ''),
        onLog: (_) {},
        onProgress: (_) {},
      ),
      throwsFormatException,
    );
  });
  test('streams output and only finishes after a successful exit', () async {
    final writer = TestProcess();
    final started = Completer<void>();
    final logs = <String>[];
    final progress = <double>[];
    final service = FlashService(
      launch: (_, args) async {
        if (args.last == 'version') return version();
        expect(args, contains(binary.path));
        started.complete();
        return writer;
      },
    );
    final operation = service.program(
      request(),
      onLog: logs.add,
      onProgress: progress.add,
    );
    await started.future;
    writer.out.add(utf8.encode('Writing at 0x10000 (50 %)\r'));
    writer.err.add(utf8.encode('diagnostic\n'));
    await Future<void>.delayed(Duration.zero);
    expect(progress, [.5]);
    writer.finish(0);
    await operation;
    expect(progress.last, 1);
    expect(logs.join(), contains('diagnostic'));
  });
  test(
    'v4 compatibility changes command flags without changing file paths',
    () async {
      final service = FlashService(
        launch: (_, args) async {
          if (args.last == 'version') return version('4.8.1');
          expect(args, contains('write_flash'));
          expect(args, contains('--flash_mode'));
          expect(args, contains(binary.path));
          return TestProcess()..finish(0);
        },
      );
      await service.program(request(), onLog: (_) {}, onProgress: (_) {});
    },
  );
  test('failed write is never retried and does not report success', () async {
    var writes = 0;
    final values = <double>[];
    final service = FlashService(
      launch: (_, args) async {
        if (args.last == 'version') return version();
        writes++;
        return TestProcess()
          ..err.add(utf8.encode('device disconnected'))
          ..finish(2);
      },
    );
    await expectLater(
      service.program(request(), onLog: (_) {}, onProgress: values.add),
      throwsA(isA<ProcessException>()),
    );
    expect(writes, 1);
    expect(values, isEmpty);
  });
  test('cancels a running process and waits for exit', () async {
    final writer = TestProcess();
    final started = Completer<void>();
    final service = FlashService(
      launch: (_, args) async {
        if (args.last == 'version') return version();
        started.complete();
        return writer;
      },
    );
    final result = expectLater(
      service.program(request(), onLog: (_) {}, onProgress: (_) {}),
      throwsA(isA<FlashCancelled>()),
    );
    await started.future;
    service.cancel();
    await result;
    expect(writer.killed, isTrue);
  });
  test('cancellation during launch kills the late process', () async {
    final launched = Completer<Process>();
    final started = Completer<void>();
    final service = FlashService(
      launch: (_, _) {
        started.complete();
        return launched.future;
      },
    );
    final result = expectLater(
      service.program(request(), onLog: (_) {}, onProgress: (_) {}),
      throwsA(isA<FlashCancelled>()),
    );
    await started.future;
    service.cancel();
    final process = TestProcess();
    launched.complete(process);
    await result;
    expect(process.killed, isTrue);
  });
  test('timeout kills the writer and reports failure', () async {
    final writer = TestProcess();
    final service = FlashService(
      timeout: const Duration(milliseconds: 20),
      launch: (_, args) async => args.last == 'version' ? version() : writer,
    );
    await expectLater(
      service.program(request(), onLog: (_) {}, onProgress: (_) {}),
      throwsA(isA<TimeoutException>()),
    );
    expect(writer.killed, isTrue);
  });
  test('missing executable falls back without retrying writes', () async {
    var probes = 0;
    final service = FlashService(
      launch: (exe, args) async {
        if (args.last == 'version' && probes++ == 0) {
          throw ProcessException(exe, args, 'missing', 2);
        }
        return args.last == 'version' ? version() : (TestProcess()..finish(0));
      },
    );
    await service.program(request(), onLog: (_) {}, onProgress: (_) {});
    expect(probes, 2);
  });
  test('real process streams are drained before returning', () async {
    final log = StringBuffer();
    final service = FlashService(
      launch: (_, args) => Process.start('/bin/sh', [
        '-c',
        args.last == 'version' ? "printf 'esptool v5.0.0\\n'" : "printf 'Writing at 0x10000 (50 %%)\\r'; printf 'device output\\n' >&2",
      ]),
    );
    await service.program(request(), onLog: log.write, onProgress: (_) {});
    expect(log.toString(), contains('device output'));
    expect(log.toString(), contains('Writing at'));
  }, skip: !Platform.isLinux);

  test('timeout forcibly terminates a process ignoring SIGTERM', () async {
    Process? writer;
    final service = FlashService(
      timeout: const Duration(milliseconds: 200),
      launch: (_, args) async {
        if (args.last == 'version') return version();
        return writer = await Process.start('/bin/sh', [
          '-c',
          "trap '' TERM; read input",
        ]);
      },
    );
    await expectLater(
      service.program(request(), onLog: (_) {}, onProgress: (_) {}),
      throwsA(isA<TimeoutException>()),
    );
    expect(await writer!.exitCode, isNot(0));
  }, skip: !Platform.isLinux);

  test(
    'rejects concurrent operations and cancels before validation finishes',
    () async {
      final service = FlashService(
        launch: (_, _) => throw StateError('must not launch'),
      );
      final first = expectLater(
        service.program(request(), onLog: (_) {}, onProgress: (_) {}),
        throwsA(isA<FlashCancelled>()),
      );
      await expectLater(
        service.program(request(), onLog: (_) {}, onProgress: (_) {}),
        throwsStateError,
      );
      service.cancel();
      await first;
    },
  );
  const eraseRequest = EraseRequest(
    port: 'COM7',
    baud: '115200',
    chip: 'ESP32-S3',
  );
  for (final major in [4, 5]) {
    test(
      'erase uses v$major syntax and no firmware or force arguments',
      () async {
        final service = FlashService(
          launch: (_, args) async {
            if (args.last == 'version') return version('$major.0.0');
            expect(args, [
              '--chip',
              'esp32s3',
              '--port',
              'COM7',
              '--baud',
              '115200',
              major == 4 ? 'erase_flash' : 'erase-flash',
            ]);
            return TestProcess()..finish(0);
          },
        );
        await service.erase(eraseRequest, onLog: (_) {});
      },
    );
  }
  test('invalid erase connection never launches a process', () async {
    final service = FlashService(
      launch: (_, _) => throw StateError('must not launch'),
    );
    for (final invalid in [
      const EraseRequest(port: '', baud: '115200', chip: 'ESP32'),
      const EraseRequest(port: 'COM7', baud: '0', chip: 'ESP32'),
      const EraseRequest(port: 'COM7', baud: '115200', chip: 'unknown'),
    ]) {
      await expectLater(
        service.erase(invalid, onLog: (_) {}),
        throwsFormatException,
      );
    }
  });
  test('erase failure preserves diagnostics without retrying', () async {
    var erases = 0;
    final log = StringBuffer();
    final service = FlashService(
      launch: (_, args) async {
        if (args.last == 'version') return version();
        erases++;
        return TestProcess()
          ..err.add(utf8.encode('erase denied'))
          ..finish(2);
      },
    );
    await expectLater(
      service.erase(eraseRequest, onLog: log.write),
      throwsA(isA<ProcessException>()),
    );
    expect(erases, 1);
    expect(log.toString(), contains('erase denied'));
  });
  test('erase excludes programming and can be stopped', () async {
    final process = TestProcess();
    final started = Completer<void>();
    final service = FlashService(
      launch: (_, args) async {
        if (args.last == 'version') return version();
        started.complete();
        return process;
      },
    );
    final result = expectLater(
      service.erase(eraseRequest, onLog: (_) {}),
      throwsA(isA<FlashCancelled>()),
    );
    await started.future;
    await expectLater(
      service.program(request(), onLog: (_) {}, onProgress: (_) {}),
      throwsStateError,
    );
    service.cancel();
    await result;
    expect(process.killed, isTrue);
  });
  test('erase timeout terminates the process', () async {
    final process = TestProcess();
    final service = FlashService(
      timeout: const Duration(milliseconds: 20),
      launch: (_, args) async => args.last == 'version' ? version() : process,
    );
    await expectLater(
      service.erase(eraseRequest, onLog: (_) {}),
      throwsA(isA<TimeoutException>()),
    );
    expect(process.killed, isTrue);
  });
}
