import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';

import 'esptool_service.dart';
import 'firmware_bundle_service.dart';
import 'partition_table.dart';
import 'serial_port_service.dart';

void main() => runApp(const EspLoaderApp());

class EspLoaderApp extends StatefulWidget {
  const EspLoaderApp({super.key});
  @override
  State<EspLoaderApp> createState() => _EspLoaderAppState();
}

class _EspLoaderAppState extends State<EspLoaderApp> {
  ThemeMode mode = ThemeMode.dark;
  @override
  Widget build(BuildContext context) => FluentApp(
    title: 'ESP Loader',
    debugShowCheckedModeBanner: false,
    themeMode: mode,
    theme: FluentThemeData(
      brightness: Brightness.light,
      accentColor: Colors.blue,
    ),
    darkTheme: FluentThemeData(
      brightness: Brightness.dark,
      accentColor: Colors.blue,
    ),
    home: AppShell(mode: mode, onMode: (v) => setState(() => mode = v)),
  );
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.mode, required this.onMode});
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onMode;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int selected = 0;
  bool showLog = false;
  @override
  Widget build(BuildContext context) => NavigationView(
    pane: NavigationPane(
      selected: selected,
      onChanged: (v) => setState(() => selected = v),
      displayMode: PaneDisplayMode.auto,
      items: [
        PaneItem(
          icon: const Icon(FluentIcons.installation),
          title: const Text('Programming'),
          body: FlashPage(
            showLog: showLog,
            onToggleLog: () => setState(() => showLog = !showLog),
          ),
        ),
        PaneItem(
          icon: const Icon(FluentIcons.command_prompt),
          title: const Text('Monitor'),
          body: const MonitorPage(),
        ),
        PaneItem(
          icon: const Icon(FluentIcons.chart),
          title: const Text('Plot'),
          body: const PlotPage(),
        ),
      ],
      footerItems: [
        PaneItemSeparator(),
        PaneItem(
          icon: const Icon(FluentIcons.settings),
          title: const Text('Settings'),
          body: SettingsPage(mode: widget.mode, onMode: widget.onMode),
        ),
      ],
    ),
    paneBodyBuilder: (_, body) => Column(
      children: [
        Expanded(child: body ?? const SizedBox()),
        if (showLog) const _TechnicalLog(),
      ],
    ),
  );
}

class FlashPage extends StatefulWidget {
  const FlashPage({
    super.key,
    required this.showLog,
    required this.onToggleLog,
  });

  final bool showLog;
  final VoidCallback onToggleLog;
  @override
  State<FlashPage> createState() => _FlashPageState();
}

class _FlashTarget {
  _FlashTarget(this.address, this.path)
    : enabled = true,
      addressController = TextEditingController(text: address),
      pathController = TextEditingController(text: path);

  bool enabled;
  String address;
  String path;
  final TextEditingController addressController;
  final TextEditingController pathController;

  void setAddress(String value) {
    address = value;
    addressController.text = value;
  }

  void setPath(String value) {
    path = value;
    pathController.text = value;
  }

  void dispose() {
    addressController.dispose();
    pathController.dispose();
  }
}

class _FlashPageState extends State<FlashPage> {
  bool autoload = true, monitorAfter = true, busy = false;
  double progress = 0;
  Timer? timer;
  Timer? connectionMessageTimer;
  Timer? compatibilityMessageTimer;
  String chip = 'ESP32-S3', port = '', baud = '921600';
  String spiMode = 'DIO', flashFrequency = '80 MHz', flashSize = '16 MB';
  String detectedConfiguration = 'Not detected';
  List<SerialPortInfo> serialPorts = const [];
  bool scanningPorts = false;
  String? serialError;
  bool testingConnection = false;
  String? connectionMessage;
  bool connectionTestFailed = false;
  String? buildChip;
  String? detectedChip;
  String? compatibilityMessage;
  bool compatibilityFailed = false;
  String? targetMessage;
  bool targetMessageIsError = false;
  final targets = <_FlashTarget>[
    _FlashTarget('0x0000', 'bootloader.bin'),
    _FlashTarget('0x8000', 'partitions.bin'),
    _FlashTarget('0x10000', 'esp_loader_demo.bin'),
  ];

  @override
  void initState() {
    super.initState();
    _refreshSerialPorts();
  }

  Future<void> _refreshSerialPorts() async {
    setState(() {
      scanningPorts = true;
      serialError = null;
    });
    try {
      final found = await SerialPortService.discover();
      if (!mounted) return;
      setState(() {
        serialPorts = found;
        if (!found.any((item) => item.port == port)) {
          port = found.isEmpty ? '' : found.first.port;
        }
        scanningPorts = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        scanningPorts = false;
        serialError = error.toString();
      });
    }
  }

  Future<void> _testConnection() async {
    if (port.isEmpty || testingConnection) return;
    connectionMessageTimer?.cancel();
    setState(() {
      testingConnection = true;
      connectionMessage = null;
    });
    try {
      final result = await EspToolService.testConnection(
        port: port,
        baud: baud,
      );
      if (!mounted) return;
      setState(() {
        chip = result.chip;
        detectedChip = result.chip;
        spiMode = 'DIO';
        flashFrequency = _recommendedFlashFrequency(result.chip);
        if (result.flashSize != null) flashSize = result.flashSize!;
        detectedConfiguration = result.flashSize == null
            ? '${result.chip} · flash size not detected'
            : '${result.chip} · ${result.flashSize}';
        for (final target in targets.where(
          (item) => _isBootloader(item.path),
        )) {
          target.setAddress(_bootloaderOffset);
        }
        testingConnection = false;
        connectionTestFailed = false;
        connectionMessage = '${result.chip} successfully detected on $port.';
        _updateCompatibility();
      });
      connectionMessageTimer = Timer(const Duration(seconds: 5), () {
        if (!mounted || connectionTestFailed) return;
        setState(() => connectionMessage = null);
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        testingConnection = false;
        connectionTestFailed = true;
        connectionMessage = _connectionError(error);
      });
    }
  }

  String _connectionError(Object error) {
    if (error is ProcessException) {
      final details = error.message.trim();
      return details.isEmpty
          ? 'No ESP detected on $port.'
          : 'No ESP detected on $port. $details';
    }
    return error.toString().replaceFirst('Bad state: ', '');
  }

  String _recommendedFlashFrequency(String detectedChip) {
    const fastFlashChips = {'ESP32-S3', 'ESP32-C5', 'ESP32-C6', 'ESP32-P4'};
    return fastFlashChips.contains(detectedChip) ? '80 MHz' : '40 MHz';
  }

  void _updateCompatibility() {
    compatibilityMessageTimer?.cancel();
    if (buildChip == null || detectedChip == null) {
      compatibilityMessage = buildChip == null
          ? null
          : 'Firmware target: $buildChip. Press Test to verify the device.';
      compatibilityFailed = false;
      return;
    }
    compatibilityFailed = buildChip != detectedChip;
    compatibilityMessage = compatibilityFailed
        ? 'Incompatible device: the firmware targets $buildChip, but the connected device is $detectedChip.'
        : 'Compatible device: firmware and connected hardware both target $buildChip.';
    if (!compatibilityFailed) {
      compatibilityMessageTimer = Timer(const Duration(seconds: 5), () {
        if (!mounted || compatibilityFailed) return;
        setState(() => compatibilityMessage = null);
      });
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    connectionMessageTimer?.cancel();
    compatibilityMessageTimer?.cancel();
    for (final target in targets) {
      target.dispose();
    }
    super.dispose();
  }

  String _fileName(String path) => path.split(RegExp(r'[\\/]')).last;

  bool _isBootloader(String path) =>
      _fileName(path).toLowerCase().contains('bootloader');

  bool _isPartitionTable(String path) {
    final name = _fileName(path).toLowerCase();
    return name == 'partitions.bin' ||
        name == 'partition-table.bin' ||
        name == 'partition_table.bin' ||
        name.contains('partition');
  }

  String get _bootloaderOffset => chip == 'ESP32' ? '0x1000' : '0x0000';

  String _hex(int value) => '0x${value.toRadixString(16).toUpperCase()}';

  Future<void> _pickTarget(_FlashTarget target) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['bin'],
      dialogTitle: 'Select binary file',
    );
    final path = result?.files.single.path;
    if (path == null) return;

    target.setPath(path);
    try {
      final bundle = await FirmwareBundleService.findForBinary(path);
      if (bundle != null) {
        _applyFirmwareBundle(bundle);
        if (mounted) setState(() {});
        return;
      }
    } on Object catch (error) {
      targetMessageIsError = true;
      targetMessage = 'Unable to read build metadata: $error';
    }
    if (_isBootloader(path)) {
      target.setAddress(_bootloaderOffset);
      await _loadSiblingBins(path);
    }
    if (_isPartitionTable(path)) {
      target.setAddress('0x8000');
      await _applyPartitionTable(path);
    }
    if (mounted) setState(() {});
  }

  void _applyFirmwareBundle(FirmwareBundle bundle) {
    for (final target in targets) {
      target.dispose();
    }
    targets
      ..clear()
      ..addAll(
        bundle.images.map((image) => _FlashTarget(image.address, image.path)),
      );
    buildChip = bundle.chip;
    if (bundle.chip != null) chip = bundle.chip!;
    if (bundle.flashMode != null) spiMode = bundle.flashMode!.toUpperCase();
    if (bundle.flashFrequency != null) {
      flashFrequency = bundle.flashFrequency!;
    }
    if (bundle.flashSize != null) flashSize = bundle.flashSize!;
    targetMessageIsError = false;
    targetMessage =
        '${bundle.images.length} images imported from flasher_args.json.';
    _updateCompatibility();
  }

  Future<void> _loadSiblingBins(String bootloaderPath) async {
    try {
      final files =
          File(bootloaderPath).parent
              .listSync()
              .whereType<File>()
              .where((file) => file.path.toLowerCase().endsWith('.bin'))
              .toList()
            ..sort((a, b) => _fileName(a.path).compareTo(_fileName(b.path)));
      final imported = <_FlashTarget>[];
      for (final file in files) {
        final existing = targets.where(
          (target) =>
              target.path == file.path ||
              _fileName(target.path).toLowerCase() ==
                  _fileName(file.path).toLowerCase(),
        );
        if (existing.isNotEmpty) {
          existing.first.setPath(file.path);
          imported.add(existing.first);
        } else {
          imported.add(_FlashTarget('0x', file.path));
        }
      }
      for (final oldTarget in targets.where(
        (target) => !imported.contains(target),
      )) {
        oldTarget.dispose();
      }
      targets
        ..clear()
        ..addAll(imported);
      final partition = targets.where(
        (target) => _isPartitionTable(target.path),
      );
      if (partition.isNotEmpty) {
        partition.first.setAddress('0x8000');
        await _applyPartitionTable(partition.first.path);
      }
    } on FileSystemException catch (error) {
      targetMessageIsError = true;
      targetMessage = 'Unable to read the folder: ${error.message}';
    }
  }

  Future<void> _applyPartitionTable(String path) async {
    try {
      final partitions = parseEspPartitionTable(await File(path).readAsBytes());
      final appTargets = targets
          .where(
            (target) =>
                !_isBootloader(target.path) &&
                !_isPartitionTable(target.path) &&
                target.path.toLowerCase().endsWith('.bin'),
          )
          .toList();
      final preferredApp = partitions.where((entry) => entry.isApp).toList()
        ..sort((a, b) {
          int rank(EspPartition p) =>
              p.subtype == 0 ? 0 : (p.subtype == 0x10 ? 1 : 2);
          return rank(a).compareTo(rank(b));
        });

      for (final target in appTargets) {
        final name = _fileName(target.path)
            .toLowerCase()
            .replaceAll('.bin', '');
        if (name.contains('boot_app0')) {
          target.setAddress('0xE000');
          continue;
        }
        EspPartition? match;
        for (final entry in partitions) {
          final label = entry.label.toLowerCase();
          if (name == label || name.contains(label)) {
            match = entry;
            break;
          }
        }
        if (match != null) target.setAddress(_hex(match.offset));
      }
      final unresolved =
          appTargets
              .where((target) => target.addressController.text == '0x')
              .where(
                (target) => !target.path.toLowerCase().contains('boot_app0'),
              )
              .toList()
            ..sort((a, b) {
              int size(_FlashTarget target) {
                try {
                  return File(target.path).lengthSync();
                } on FileSystemException {
                  return 0;
                }
              }

              return size(b).compareTo(size(a));
            });
      if (unresolved.isNotEmpty && preferredApp.isNotEmpty) {
        unresolved.first.setAddress(_hex(preferredApp.first.offset));
      }
      targetMessageIsError = false;
      targetMessage =
          '${partitions.length} partitions read: binary addresses updated.';
    } on Object catch (error) {
      targetMessageIsError = true;
      targetMessage = 'Unable to read partitions.bin: $error';
    }
  }

  void _addTarget() {
    setState(() => targets.add(_FlashTarget('0x', '')));
  }

  void _removeTarget(int index) {
    final removed = targets.removeAt(index);
    removed.dispose();
    setState(() {});
  }

  void start() {
    timer?.cancel();
    setState(() {
      busy = true;
      progress = 0;
    });
    timer = Timer.periodic(const Duration(milliseconds: 120), (t) {
      if (!mounted) return;
      setState(() => progress = math.min(1, progress + .025));
      if (progress >= 1) {
        t.cancel();
        setState(() => busy = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) => ScaffoldPage.scrollable(
    header: const PageHeader(title: Text('Programming')),
    children: [
      _Card(
        child: Wrap(
          spacing: 14,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            _Combo(
              'Chip',
              170,
              chip,
              const [
                'ESP32',
                'ESP32-S2',
                'ESP32-S3',
                'ESP32-C2',
                'ESP32-C3',
                'ESP32-C5',
                'ESP32-C6',
                'ESP32-H2',
                'ESP32-P4',
                'ESP8266',
              ],
              (v) {
                setState(() {
                  chip = v;
                  for (final target in targets.where(
                    (t) => _isBootloader(t.path),
                  )) {
                    target.setAddress(_bootloaderOffset);
                  }
                });
              },
            ),
            _SerialCombo(
              width: 250,
              value: port,
              ports: serialPorts,
              scanning: scanningPorts,
              onChanged: (value) => setState(() => port = value),
            ),
            _Combo('Baud', 140, baud, const [
              '115200',
              '460800',
              '921600',
              '1500000',
            ], (v) => setState(() => baud = v)),
            Button(
              onPressed:
                  busy || scanningPorts || testingConnection || port.isEmpty
                  ? null
                  : _testConnection,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (testingConnection)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: ProgressRing(strokeWidth: 2),
                    )
                  else
                    const Icon(FluentIcons.plug_connected, size: 14),
                  const SizedBox(width: 6),
                  const Text('Test'),
                ],
              ),
            ),
            Button(
              onPressed: busy || scanningPorts ? null : _refreshSerialPorts,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (scanningPorts)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: ProgressRing(strokeWidth: 2),
                    )
                  else
                    const Icon(FluentIcons.refresh, size: 14),
                  const SizedBox(width: 6),
                  Text(scanningPorts ? 'Scanning…' : 'Refresh'),
                ],
              ),
            ),
            IconButton(
              key: const Key('technical-log-button'),
              icon: Icon(widget.showLog ? FluentIcons.view : FluentIcons.hide3),
              onPressed: widget.onToggleLog,
            ),
          ],
        ),
      ),
      if (serialError != null || (!scanningPorts && serialPorts.isEmpty)) ...[
        const SizedBox(height: 8),
        InfoBar(
          title: Text(
            serialError == null
                ? 'No serial ports found'
                : 'Serial port detection',
          ),
          content: Text(
            serialError ??
                'Connect the device and press Refresh to scan again.',
          ),
          severity: serialError == null
              ? InfoBarSeverity.warning
              : InfoBarSeverity.error,
        ),
      ],
      if (connectionMessage != null) ...[
        const SizedBox(height: 8),
        InfoBar(
          title: Text(
            connectionTestFailed ? 'Connection failed' : 'ESP detected',
          ),
          content: Text(connectionMessage!),
          severity: connectionTestFailed
              ? InfoBarSeverity.error
              : InfoBarSeverity.success,
        ),
      ],
      if (compatibilityMessage != null) ...[
        const SizedBox(height: 8),
        InfoBar(
          title: Text(
            compatibilityFailed
                ? 'Firmware compatibility error'
                : 'Firmware compatibility',
          ),
          content: Text(compatibilityMessage!),
          severity: compatibilityFailed
              ? InfoBarSeverity.error
              : detectedChip == null
              ? InfoBarSeverity.info
              : InfoBarSeverity.success,
        ),
      ],
      const SizedBox(height: 14),
      _Card(
        title: 'Flash images',
        trailing: Button(
          onPressed: busy ? null : _addTarget,
          child: const Text('＋ Add binary'),
        ),
        child: Column(
          children: [
            const Row(
              children: [
                SizedBox(width: 40),
                SizedBox(width: 130, child: Text('Address')),
                Expanded(child: Text('Binary file')),
                SizedBox(width: 35),
              ],
            ),
            for (var i = 0; i < targets.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 40,
                      child: Checkbox(
                        checked: targets[i].enabled,
                        onChanged: busy
                            ? null
                            : (v) => setState(
                                () => targets[i].enabled = v ?? false,
                              ),
                      ),
                    ),
                    SizedBox(
                      width: 120,
                      child: TextBox(
                        controller: targets[i].addressController,
                        enabled: !busy,
                        placeholder: '0x',
                        onChanged: (value) => targets[i].address = value,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: TextBox(
                              controller: targets[i].pathController,
                              enabled: !busy,
                              placeholder: 'Choose file…',
                              onChanged: (value) => targets[i].path = value,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Button(
                            onPressed: busy
                                ? null
                                : () => _pickTarget(targets[i]),
                            child: const Icon(FluentIcons.open_file, size: 14),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(FluentIcons.delete, size: 14),
                      onPressed: busy ? null : () => _removeTarget(i),
                    ),
                  ],
                ),
              ),
            if (targetMessage != null) ...[
              const SizedBox(height: 8),
              InfoBar(
                title: Text(targetMessageIsError ? 'Error' : 'Partition table'),
                content: Text(targetMessage!),
                severity: targetMessageIsError
                    ? InfoBarSeverity.error
                    : InfoBarSeverity.success,
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 14),
      _Card(
        title: 'Flash configuration',
        child: Wrap(
          spacing: 14,
          runSpacing: 12,
          children: [
            _Combo('SPI mode', 135, spiMode, const [
              'Keep',
              'QIO',
              'QOUT',
              'DIO',
              'DOUT',
            ], (value) => setState(() => spiMode = value)),
            _Combo('Frequency', 135, flashFrequency, const [
              'Keep',
              '20 MHz',
              '40 MHz',
              '80 MHz',
            ], (value) => setState(() => flashFrequency = value)),
            _Combo('Size', 135, flashSize, [
              'Detect',
              '1 MB',
              '2 MB',
              '4 MB',
              '8 MB',
              '16 MB',
              '32 MB',
              if (!const {
                'Detect',
                '1 MB',
                '2 MB',
                '4 MB',
                '8 MB',
                '16 MB',
                '32 MB',
              }.contains(flashSize))
                flashSize,
            ], (value) => setState(() => flashSize = value)),
            SizedBox(
              width: 190,
              child: InfoLabel(
                label: 'Detection',
                child: Padding(
                  padding: EdgeInsets.only(top: 7),
                  child: Text(
                    detectedConfiguration,
                    style: TextStyle(color: Color(0xff67c980)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      _Card(
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _Toggle(
                    'Autoload',
                    'Reflash when files change',
                    autoload,
                    (v) => setState(() => autoload = v),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: _Toggle(
                    'Monitor after flashing',
                    'Automatically reopen the serial port',
                    monitorAfter,
                    (v) => setState(() => monitorAfter = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ProgressBar(value: progress * 100),
                      const SizedBox(height: 6),
                      Text(
                        busy
                            ? 'Writing · ${(progress * 100).round()}%'
                            : progress >= 1
                            ? 'Programming completed · verification OK'
                            : '${targets.length} segments ready · $port',
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                Button(
                  onPressed: busy ? null : () {},
                  child: const Text('Erase flash'),
                ),
                const SizedBox(width: 8),
                Button(
                  onPressed: busy
                      ? () {
                          timer?.cancel();
                          setState(() => busy = false);
                        }
                      : null,
                  child: const Text('Stop'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('start-flash-button'),
                  onPressed: busy || compatibilityFailed ? null : start,
                  child: const Text('Program'),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
    ],
  );
}

class MonitorPage extends StatefulWidget {
  const MonitorPage({super.key});
  @override
  State<MonitorPage> createState() => _MonitorPageState();
}

class _MonitorPageState extends State<MonitorPage> {
  bool connected = true, paused = false, wrap = true, timestamps = true;
  final send = TextEditingController();
  final lines = [
    'ESP-ROM:esp32s3-20210327',
    'rst:0x1 (POWERON),boot:0x8 (SPI_FAST_FLASH_BOOT)',
    'I (311) cpu_start: Pro cpu start user code',
    'I (347) app_init: ESP Loader demo firmware',
    'I (352) wifi: mode : sta',
    'sensor.temp=23.72 sensor.pressure=1008.4',
    'ready>',
  ];
  @override
  void dispose() {
    send.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaffoldPage(
    header: const PageHeader(title: Text('Serial monitor')),
    content: Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      child: Column(
        children: [
          _Card(
            child: Column(
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  children: [
                    _Combo('Port', 235, 'COM7 · USB JTAG/serial', const [
                      'COM7 · USB JTAG/serial',
                      'COM12 · CP210x UART',
                      '/dev/ttyUSB0',
                    ], (_) {}),
                    _Combo('Baud', 125, '115200', const [
                      '9600',
                      '115200',
                      '460800',
                      '921600',
                    ], (_) {}),
                    _Combo('Data bit', 90, '8', const ['7', '8'], (_) {}),
                    _Combo('Stop bit', 90, '1', const [
                      '1',
                      '1.5',
                      '2',
                    ], (_) {}),
                    _Combo('Parity', 110, 'None', const [
                      'None',
                      'Even',
                      'Odd',
                    ], (_) {}),
                    Button(
                      onPressed: () {},
                      child: const Icon(FluentIcons.refresh, size: 14),
                    ),
                    FilledButton(
                      key: const Key('monitor-connect-button'),
                      onPressed: () => setState(() => connected = !connected),
                      child: Text(connected ? 'Disconnect' : 'Connect'),
                    ),
                    Button(
                      onPressed: connected ? () {} : null,
                      child: const Text('Reset'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: connected
                            ? const Color(0xff65cf7c)
                            : const Color(0xff999999),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(connected ? 'Connected · 115200 8N1' : 'Disconnected'),
                    const Spacer(),
                    const Text('Buffer 7 / 10,000 lines'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              ToggleButton(
                checked: paused,
                onChanged: (v) => setState(() => paused = v),
                child: Text(paused ? 'Resume' : 'Pause'),
              ),
              const SizedBox(width: 7),
              Button(
                onPressed: () => setState(lines.clear),
                child: const Text('Clear'),
              ),
              const SizedBox(width: 7),
              ToggleButton(
                checked: wrap,
                onChanged: (v) => setState(() => wrap = v),
                child: const Text('Wrap'),
              ),
              const SizedBox(width: 7),
              ToggleButton(
                checked: timestamps,
                onChanged: (v) => setState(() => timestamps = v),
                child: const Text('Timestamp'),
              ),
              const Spacer(),
              Button(onPressed: () {}, child: const Text('Save')),
              const SizedBox(width: 7),
              Button(onPressed: () {}, child: const Text('Copy visible')),
            ],
          ),
          const SizedBox(height: 9),
          const Row(
            children: [
              Expanded(
                child: TextBox(
                  placeholder: 'Search visible log…',
                  prefix: Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(FluentIcons.search, size: 14),
                  ),
                ),
              ),
              SizedBox(width: 9),
              SizedBox(
                width: 230,
                child: TextBox(placeholder: 'Include: wifi, sensor…'),
              ),
              SizedBox(width: 9),
              SizedBox(
                width: 230,
                child: TextBox(placeholder: 'Exclude: debug…'),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xff111315),
                border: Border.all(color: const Color(0xff34383d)),
                borderRadius: BorderRadius.circular(5),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  lines
                      .asMap()
                      .entries
                      .map(
                        (e) =>
                            '${timestamps ? '[22:14:${(31 + e.key).toString().padLeft(2, '0')}.042]  ' : ''}${e.value}',
                      )
                      .join('\n'),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.55,
                    color: Color(0xffd7e0e8),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: TextBox(
                  controller: send,
                  enabled: connected,
                  placeholder: 'Send to serial port…',
                  onSubmitted: (_) => transmit(),
                ),
              ),
              const SizedBox(width: 8),
              _Combo('', 110, 'CR + LF', const [
                'None',
                'LF',
                'CR + LF',
              ], (_) {}),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: connected ? transmit : null,
                child: const Text('Send'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  void transmit() {
    final v = send.text.trim();
    if (v.isNotEmpty) setState(() => lines.add('> $v'));
    send.clear();
  }
}

class PlotPage extends StatefulWidget {
  const PlotPage({super.key});
  @override
  State<PlotPage> createState() => _PlotPageState();
}

class _PlotPageState extends State<PlotPage> {
  bool a = true, b = true, paused = false;
  @override
  Widget build(BuildContext context) => ScaffoldPage.scrollable(
    header: const PageHeader(title: Text('Plot')),
    children: [
      const _Intro(
        'Real-time serial data',
        'Preview of numeric values extracted from received lines.',
      ),
      const SizedBox(height: 16),
      _Card(
        child: Row(
          children: [
            Checkbox(
              checked: a,
              onChanged: (v) => setState(() => a = v ?? false),
            ),
            const Text('Temperature'),
            const SizedBox(width: 20),
            Checkbox(
              checked: b,
              onChanged: (v) => setState(() => b = v ?? false),
            ),
            const Text('Pressure'),
            const Spacer(),
            ToggleButton(
              checked: paused,
              onChanged: (v) => setState(() => paused = v),
              child: Text(paused ? 'Resume' : 'Pause'),
            ),
            const SizedBox(width: 8),
            Button(onPressed: () {}, child: const Text('Clear')),
          ],
        ),
      ),
      const SizedBox(height: 14),
      _Card(
        child: SizedBox(
          height: 390,
          width: double.infinity,
          child: CustomPaint(painter: _Chart(a, b)),
        ),
      ),
      const SizedBox(height: 14),
      const Row(
        children: [
          Expanded(
            child: _Metric('Temperature', '23.72 °C', Color(0xff59a8ff)),
          ),
          SizedBox(width: 12),
          Expanded(child: _Metric('Pressure', '1008.4 hPa', Color(0xffffb44c))),
          SizedBox(width: 12),
          Expanded(child: _Metric('Samples', '1,248', Color(0xff6fd58a))),
        ],
      ),
    ],
  );
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.mode, required this.onMode});
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onMode;
  @override
  Widget build(BuildContext context) => ScaffoldPage.scrollable(
    header: const PageHeader(title: Text('Settings')),
    children: [
      _Card(
        title: 'Appearance',
        child: Row(
          children: [
            const Expanded(child: Text('Application theme')),
            SizedBox(
              width: 160,
              child: ComboBox<ThemeMode>(
                value: mode,
                isExpanded: true,
                items: const [
                  ComboBoxItem(value: ThemeMode.system, child: Text('System')),
                  ComboBoxItem(value: ThemeMode.light, child: Text('Light')),
                  ComboBoxItem(value: ThemeMode.dark, child: Text('Dark')),
                ],
                onChanged: (v) {
                  if (v != null) onMode(v);
                },
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      _Card(
        title: 'Espressif tools',
        child: Column(
          children: [
            InfoLabel(
              label: 'esptool path',
              child: TextBox(
                placeholder: 'Automatically detect in the application folder',
              ),
            ),
            SizedBox(height: 12),
            InfoBar(
              title: Text('Demo mode'),
              content: Text('No external write command is executed.'),
              severity: InfoBarSeverity.info,
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      const _Card(
        title: 'Behavior',
        child: Column(
          children: [
            _Setting(
              'Remember last port',
              'Restore port and baud rate at startup',
            ),
            SizedBox(height: 14),
            _Setting(
              'Reopen monitor after flashing',
              'Wait 600 ms before connecting',
            ),
            SizedBox(height: 14),
            _Setting(
              'Confirm flash erase',
              'Ask for confirmation before erase-flash',
            ),
          ],
        ),
      ),
    ],
  );
}

class _Card extends StatelessWidget {
  const _Card({this.title, this.trailing, required this.child});
  final String? title;
  final Widget? trailing;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final t = FluentTheme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.resources.cardBackgroundFillColorDefault,
        border: Border.all(color: t.resources.cardStrokeColorDefault),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Row(
              children: [
                Expanded(child: Text(title!, style: t.typography.subtitle)),
                ...?trailing == null ? null : [trailing!],
              ],
            ),
            const SizedBox(height: 13),
          ],
          child,
        ],
      ),
    );
  }
}

class _Combo extends StatelessWidget {
  const _Combo(this.label, this.width, this.value, this.values, this.change);
  final String label, value;
  final double width;
  final List<String> values;
  final ValueChanged<String> change;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: InfoLabel(
      label: label,
      child: ComboBox<String>(
        value: value,
        isExpanded: true,
        items: values
            .map(
              (v) => ComboBoxItem(
                value: v,
                child: Text(v, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: (v) {
          if (v != null) change(v);
        },
      ),
    ),
  );
}

class _SerialCombo extends StatelessWidget {
  const _SerialCombo({
    required this.width,
    required this.value,
    required this.ports,
    required this.scanning,
    required this.onChanged,
  });

  final double width;
  final String value;
  final List<SerialPortInfo> ports;
  final bool scanning;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: InfoLabel(
      label: 'Serial port',
      child: ComboBox<String>(
        value: ports.any((item) => item.port == value) ? value : null,
        placeholder: Text(scanning ? 'Scanning…' : 'No ports found'),
        isExpanded: true,
        items: ports
            .map(
              (item) => ComboBoxItem(
                value: item.port,
                child: Text(item.displayName, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: scanning
            ? null
            : (selected) {
                if (selected != null) onChanged(selected);
              },
      ),
    ),
  );
}

class _Intro extends StatelessWidget {
  const _Intro(this.title, this.body);
  final String title, body;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: FluentTheme.of(context).typography.subtitle),
      const SizedBox(height: 4),
      Text(body),
    ],
  );
}

class _Toggle extends StatelessWidget {
  const _Toggle(this.title, this.body, this.value, this.change);
  final String title, body;
  final bool value;
  final ValueChanged<bool> change;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      ToggleSwitch(checked: value, onChanged: change),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title),
            Text(body, style: FluentTheme.of(context).typography.caption),
          ],
        ),
      ),
    ],
  );
}

class _Setting extends StatefulWidget {
  const _Setting(this.title, this.body);
  final String title, body;
  @override
  State<_Setting> createState() => _SettingState();
}

class _SettingState extends State<_Setting> {
  bool value = true;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title),
            Text(
              widget.body,
              style: FluentTheme.of(context).typography.caption,
            ),
          ],
        ),
      ),
      ToggleSwitch(checked: value, onChanged: (v) => setState(() => value = v)),
    ],
  );
}

class _TechnicalLog extends StatelessWidget {
  const _TechnicalLog();
  @override
  Widget build(BuildContext context) => Container(
    height: 155,
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: const BoxDecoration(
      color: Color(0xff101214),
      border: Border(top: BorderSide(color: Color(0xff3b3f44))),
    ),
    child: const SelectableText(
      r'$ esptool --port COM7 --baud 921600 write-flash ...'
      '\n[demo] Chip is ESP32-S3 (revision v0.2)'
      '\n[demo] Stub flasher running...',
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 12,
        height: 1.5,
        color: Color(0xffa9bac7),
      ),
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.color);
  final String label, value;
  final Color color;
  @override
  Widget build(BuildContext context) => _Card(
    child: Row(
      children: [
        Container(width: 4, height: 38, color: color),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: FluentTheme.of(context).typography.caption),
            Text(value, style: FluentTheme.of(context).typography.subtitle),
          ],
        ),
      ],
    ),
  );
}

class _Chart extends CustomPainter {
  const _Chart(this.a, this.b);
  final bool a, b;
  @override
  void paint(Canvas c, Size s) {
    final grid = Paint()
      ..color = const Color(0xff394149)
      ..strokeWidth = .7;
    for (var i = 0; i <= 6; i++) {
      final y = s.height * i / 6;
      c.drawLine(Offset(0, y), Offset(s.width, y), grid);
    }
    for (var i = 0; i <= 10; i++) {
      final x = s.width * i / 10;
      c.drawLine(Offset(x, 0), Offset(x, s.height), grid);
    }
    void line(Color color, double phase, double base, double amp) {
      final p = Path();
      for (var i = 0; i <= 160; i++) {
        final x = s.width * i / 160,
            y =
                s.height *
                (base +
                    math.sin(i / 10 + phase) * amp +
                    math.sin(i / 3.7) * amp * .18);
        if (i == 0) {
          p.moveTo(x, y);
        } else {
          p.lineTo(x, y);
        }
      }
      c.drawPath(
        p,
        Paint()
          ..color = color
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }

    if (a) line(const Color(0xff59a8ff), 0, .35, .08);
    if (b) line(const Color(0xffffb44c), 1.4, .68, .12);
  }

  @override
  bool shouldRepaint(covariant _Chart old) => old.a != a || old.b != b;
}
