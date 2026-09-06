import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import 'esptool_service.dart';
import 'firmware_bundle_service.dart';
import 'flash_service.dart';
import 'local_profile_service.dart';
import 'partition_table.dart';
import 'project_import_service.dart';
import 'production_package_service.dart';
import 'serial_port_service.dart';
import 'serial_monitor_service.dart';

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
  final technicalLog = ValueNotifier<String>('No operations yet.');
  final monitorKey = GlobalKey<_MonitorPageState>();
  final profileStore = LocalFlashProfileStore();

  void appendLog(String text) {
    technicalLog.value = technicalLog.value == 'No operations yet.'
        ? text
        : technicalLog.value + text;
  }

  @override
  void dispose() {
    technicalLog.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      FlashPage(
        showLog: showLog,
        onLog: appendLog,
        onToggleLog: () => setState(() => showLog = !showLog),
        beforeFlash: () async =>
            await monitorKey.currentState?.suspendForFlash() ?? false,
        afterFlash: (resume) async {
          if (resume) await monitorKey.currentState?.resumeAfterFlash();
        },
        profileStore: profileStore,
      ),
      MonitorPage(key: monitorKey),
      const PlotPage(),
      SettingsPage(mode: widget.mode, onMode: widget.onMode),
    ];
    return NavigationView(
      pane: NavigationPane(
        selected: selected,
        onChanged: (v) => setState(() => selected = v),
        displayMode: PaneDisplayMode.auto,
        items: [
          PaneItem(
            icon: const Icon(FluentIcons.installation),
            title: const Text('Programming'),
            body: const SizedBox(),
          ),
          PaneItem(
            icon: const Icon(FluentIcons.command_prompt),
            title: const Text('Monitor'),
            body: const SizedBox(),
          ),
          PaneItem(
            icon: const Icon(FluentIcons.chart),
            title: const Text('Plot'),
            body: const SizedBox(),
          ),
        ],
        footerItems: [
          PaneItemSeparator(),
          PaneItem(
            icon: const Icon(FluentIcons.settings),
            title: const Text('Settings'),
            body: const SizedBox(),
          ),
        ],
      ),
      paneBodyBuilder: (_, _) => Column(
        children: [
          Expanded(
            child: IndexedStack(index: selected, children: pages),
          ),
          if (showLog)
            ValueListenableBuilder<String>(
              valueListenable: technicalLog,
              builder: (_, text, _) => _TechnicalLog(text),
            ),
        ],
      ),
    );
  }
}

class FlashPage extends StatefulWidget {
  const FlashPage({
    super.key,
    required this.showLog,
    required this.onToggleLog,
    required this.onLog,
    this.programmer,
    this.discoverPorts,
    this.testDevice,
    this.beforeFlash,
    this.afterFlash,
    this.profileStore,
    this.selectProjectDirectory,
  });

  final Future<EspConnectionResult> Function({
    required String port,
    required String baud,
  })?
  testDevice;
  final FlashService? programmer;
  final Future<List<SerialPortInfo>> Function()? discoverPorts;
  final ValueChanged<String> onLog;
  final bool showLog;
  final VoidCallback onToggleLog;
  final Future<bool> Function()? beforeFlash;
  final Future<void> Function(bool resume)? afterFlash;
  final FlashProfileStore? profileStore;
  final Future<String?> Function()? selectProjectDirectory;
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
  bool busy = false;
  bool firmwareConfigured = false;
  bool importing = false;
  bool stopping = false;
  bool erasing = false;
  bool get locked => busy || testingConnection || importing;
  late final programmer = widget.programmer ?? FlashService();
  String operationStatus = 'Ready';
  double progress = 0;
  Timer? connectionMessageTimer;
  Timer? compatibilityMessageTimer;
  String chip = 'ESP32-S3', port = '', baud = '921600';
  String spiMode = 'DIO', flashFrequency = '80 MHz', flashSize = '16 MB';
  String detectedConfiguration = 'Not detected';
  List<SerialPortInfo> serialPorts = const [];
  bool scanningPorts = false;
  String? serialError;
  bool testingConnection = false;
  bool autoload = false;
  bool monitorAfterFlashing = true;
  Timer? autoloadTimer;
  Timer? profileSaveTimer;
  final autoloadSignatures = <String, String>{};
  final autoloadCandidates = <String, ({String signature, int polls})>{};
  bool autoloadPending = false;
  String? projectPath;
  String? projectBuildPath;
  String? projectType;
  String? projectEnvironment;
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
    _loadLocalProfile();
  }

  Future<void> _refreshSerialPorts() async {
    setState(() {
      scanningPorts = true;
      serialError = null;
    });
    try {
      final found =
          await (widget.discoverPorts ?? SerialPortService.discover)();
      if (!mounted) return;
      setState(() {
        serialPorts = found;
        if (!found.any((item) => item.port == port)) {
          port = found.isEmpty ? '' : found.first.port;
          _clearDetection();
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

  void _clearDetection() {
    connectionMessageTimer?.cancel();
    detectedChip = null;
    detectedConfiguration = 'Not detected';
    connectionMessage = null;
    connectionTestFailed = false;
    _updateCompatibility();
  }

  Future<void> _testConnection() async {
    if (port.isEmpty || testingConnection) return;
    connectionMessageTimer?.cancel();
    setState(() {
      testingConnection = true;
      connectionMessage = null;
    });
    try {
      final result = await (widget.testDevice ?? EspToolService.testConnection)(
        port: port,
        baud: baud,
      );
      if (!mounted) return;
      widget.onLog('${result.output}\n');
      setState(() {
        chip = result.chip;
        detectedChip = result.chip;
        if (!firmwareConfigured) {
          spiMode = 'DIO';
          flashFrequency = _recommendedFlashFrequency(result.chip);
          if (result.flashSize != null) flashSize = result.flashSize!;
          for (final target in targets.where(
            (item) => _isBootloader(item.path),
          )) {
            target.setAddress(_bootloaderOffset);
          }
        }
        detectedConfiguration = result.flashSize == null
            ? '${result.chip} · flash size not detected'
            : '${result.chip} · ${result.flashSize}';
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
        _clearDetection();
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
    programmer.cancel();
    autoloadTimer?.cancel();
    profileSaveTimer?.cancel();
    unawaited(_saveLocalProfile());
    connectionMessageTimer?.cancel();
    compatibilityMessageTimer?.cancel();
    for (final target in targets) {
      target.dispose();
    }
    super.dispose();
  }

  Future<void> _loadLocalProfile() async {
    final store = widget.profileStore;
    if (store == null) return;
    try {
      final saved = await store.loadImages();
      final savedProjectPath = await store.loadProjectPath();
      if (!mounted || saved == null) return;
      for (final target in targets) {
        target.dispose();
      }
      setState(() {
        targets
          ..clear()
          ..addAll(
            saved.map(
              (image) =>
                  _FlashTarget(image.address, image.path)
                    ..enabled = image.enabled,
            ),
          );
        firmwareConfigured = saved.any((image) => image.path.isNotEmpty);
        projectPath = savedProjectPath;
      });
    } on Object catch (error) {
      widget.onLog('Unable to load local profile: $error\n');
    }
  }

  void _saveLocalProfileSoon() {
    if (widget.profileStore == null) return;
    profileSaveTimer?.cancel();
    profileSaveTimer = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(_saveLocalProfile()),
    );
  }

  Future<void> _saveLocalProfile() async {
    final store = widget.profileStore;
    if (store == null) return;
    final images = targets
        .map(
          (target) => SavedFlashImage(
            address: target.addressController.text,
            path: target.pathController.text,
            enabled: target.enabled,
          ),
        )
        .toList();
    try {
      await store.saveImages(images);
    } on Object catch (error) {
      widget.onLog('Unable to save local profile: $error\n');
    }
  }

  Future<void> _selectProject() async {
    if (locked) return;
    final selected =
        await (widget.selectProjectDirectory ??
            () => FilePicker.platform.getDirectoryPath(
              dialogTitle: 'Select ESP project folder',
            ))();
    if (selected == null || !mounted) return;
    setState(() {
      importing = true;
      targetMessage = 'Detecting project structure…';
      targetMessageIsError = false;
    });
    try {
      final result = await ProjectImportService.import(selected);
      if (!mounted) return;
      _applyProject(result);
      await widget.profileStore?.saveProjectPath(selected);
      _saveLocalProfileSoon();
      setState(() {});
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          targetMessageIsError = true;
          targetMessage = error.toString().replaceFirst(
            'FormatException: ',
            '',
          );
        });
      }
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  Future<void> _openProductionZip() async {
    if (locked) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      dialogTitle: 'Open ESP Loader production ZIP',
    );
    final path = result?.files.single.path;
    if (path == null || !mounted) return;
    setState(() {
      importing = true;
      targetMessage = 'Extracting and verifying production package…';
      targetMessageIsError = false;
    });
    try {
      final project = await ProjectImportService.importZip(path);
      if (!mounted) return;
      _applyProject(project);
      await widget.profileStore?.saveProjectPath(project.projectPath);
      _saveLocalProfileSoon();
      setState(() {});
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          targetMessageIsError = true;
          targetMessage = error.toString().replaceFirst(
            'FormatException: ',
            '',
          );
        });
      }
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  Future<void> _exportProduction() async {
    if (locked) return;
    final enabled = targets
        .where((target) => target.enabled)
        .map(
          (target) => FirmwareImage(
            address: target.addressController.text,
            path: target.pathController.text,
          ),
        )
        .toList();
    final baseName = projectPath == null
        ? 'esp-firmware'
        : Directory(projectPath!).uri.pathSegments
              .where((segment) => segment.isNotEmpty)
              .last;
    final output = await FilePicker.platform.saveFile(
      dialogTitle: 'Export production package',
      fileName: '$baseName-production.zip',
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    if (output == null || !mounted) return;
    setState(() {
      importing = true;
      targetMessageIsError = false;
      targetMessage = 'Creating production package…';
    });
    try {
      await ProductionPackageService.export(
        ProductionPackageRequest(
          outputPath: output,
          projectName: baseName,
          sourceType: projectType ?? 'Manual',
          environment: projectEnvironment,
          chip: chip,
          flashMode: spiMode,
          flashFrequency: flashFrequency,
          flashSize: flashSize,
          images: enabled,
        ),
      );
      if (mounted) {
        setState(() {
          targetMessage =
              'Production package exported: ${output.toLowerCase().endsWith('.zip') ? output : '$output.zip'}';
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          targetMessageIsError = true;
          targetMessage = error.toString().replaceFirst(
            'FormatException: ',
            '',
          );
        });
      }
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  void _applyProject(ProjectImportResult result) {
    projectPath = result.projectPath;
    projectBuildPath = result.buildPath;
    projectType = result.typeLabel;
    projectEnvironment = result.environment;
    _applyFirmwareBundle(result.bundle);
    targetMessageIsError = false;
    targetMessage =
        '${result.typeLabel} project detected: '
        '${result.bundle.images.length} flash images imported'
        '${result.environment == null ? '.' : ' from ${result.environment}.'}';
  }

  Future<void> _startAutoloadFlash() async {
    final selectedProject = projectPath;
    if (selectedProject != null) {
      try {
        final result = await ProjectImportService.import(selectedProject);
        if (!mounted || !autoload) return;
        setState(() => _applyProject(result));
        _saveLocalProfileSoon();
      } on Object catch (error) {
        if (mounted) {
          setState(() {
            targetMessageIsError = true;
            targetMessage = 'Autoload could not refresh the project: $error';
          });
        }
        return;
      }
    }
    await start(automatic: true);
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
    if (locked) return;
    setState(() => importing = true);
    try {
      await _importTarget(target);
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  Future<void> _importTarget(_FlashTarget target) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['bin'],
      dialogTitle: 'Select binary file',
    );
    final path = result?.files.single.path;
    if (path == null || !mounted) return;

    firmwareConfigured = true;
    target.setPath(path);
    try {
      final bundle = await FirmwareBundleService.findForBinary(path);
      if (!mounted) return;
      if (bundle != null) {
        _applyFirmwareBundle(bundle);
        _saveLocalProfileSoon();
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
    _saveLocalProfileSoon();
    if (mounted) setState(() {});
  }

  void _applyFirmwareBundle(FirmwareBundle bundle) {
    firmwareConfigured = true;
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
    _saveLocalProfileSoon();
  }

  void _removeTarget(int index) {
    final removed = targets.removeAt(index);
    removed.dispose();
    setState(() {});
    _saveLocalProfileSoon();
  }

  FlashRequest _request() => FlashRequest(
    port: port,
    baud: baud,
    chip: chip,
    mode: spiMode,
    frequency: flashFrequency,
    size: flashSize,
    firmwareChip: buildChip,
    images: targets
        .where((target) => target.enabled)
        .map(
          (target) => FlashImage(
            target.addressController.text,
            target.pathController.text,
          ),
        )
        .toList(),
  );

  Map<String, String> _currentImageSignatures() {
    final result = <String, String>{};
    for (final target in targets.where((target) => target.enabled)) {
      final path = target.pathController.text.trim();
      if (path.isEmpty) continue;
      try {
        final stat = File(path).statSync();
        if (stat.type == FileSystemEntityType.file) {
          result[path] = '${stat.modified.microsecondsSinceEpoch}:${stat.size}';
        }
      } on FileSystemException {
        // A build can replace a binary briefly; wait for the next poll.
      }
    }
    final build = projectBuildPath;
    if (build != null) {
      for (final name in ['flasher_args.json', 'flash_args']) {
        final path = '$build${Platform.pathSeparator}$name';
        try {
          final stat = File(path).statSync();
          if (stat.type == FileSystemEntityType.file) {
            result[path] =
                '${stat.modified.microsecondsSinceEpoch}:${stat.size}';
          }
        } on FileSystemException {
          // The manifest may be replaced while the build is completing.
        }
      }
    }
    return result;
  }

  void _setAutoload(bool enabled) {
    autoloadTimer?.cancel();
    autoloadCandidates.clear();
    autoloadSignatures
      ..clear()
      ..addAll(_currentImageSignatures());
    setState(() => autoload = enabled);
    if (enabled) {
      autoloadTimer = Timer.periodic(
        const Duration(milliseconds: 300),
        (_) => _pollAutoload(),
      );
    }
  }

  void _pollAutoload() {
    if (!mounted || !autoload) return;
    final current = _currentImageSignatures();
    var stableChange = false;
    for (final entry in current.entries) {
      final previous = autoloadSignatures[entry.key];
      if (previous == null) {
        autoloadSignatures[entry.key] = entry.value;
        continue;
      }
      if (previous == entry.value) {
        autoloadCandidates.remove(entry.key);
        continue;
      }
      final candidate = autoloadCandidates[entry.key];
      if (candidate == null || candidate.signature != entry.value) {
        autoloadCandidates[entry.key] = (signature: entry.value, polls: 1);
      } else if (candidate.polls >= 2) {
        stableChange = true;
      } else {
        autoloadCandidates[entry.key] = (
          signature: entry.value,
          polls: candidate.polls + 1,
        );
      }
    }
    autoloadSignatures.removeWhere((path, _) => !current.containsKey(path));
    if (!stableChange) return;
    autoloadCandidates.clear();
    autoloadSignatures
      ..clear()
      ..addAll(current);
    if (locked || scanningPorts) {
      autoloadPending = true;
    } else {
      unawaited(_startAutoloadFlash());
    }
  }

  Future<void> start({bool preview = false, bool automatic = false}) async {
    if (locked || scanningPorts) return;
    final request = _request();
    var resumeMonitor = false;
    setState(() {
      busy = !preview;
      importing = preview;
      stopping = false;
      progress = 0;
      operationStatus = automatic
          ? 'Rebuild detected · validating images…'
          : 'Validating images…';
    });
    try {
      if (preview) {
        final args = await request.arguments();
        if (!mounted) return;
        widget.onLog(
          'Preview: esptool ${args.map((arg) => '"$arg"').join(' ')}\n',
        );
        if (!widget.showLog) widget.onToggleLog();
        setState(
          () =>
              operationStatus = 'Validation passed · command in technical log',
        );
      } else {
        resumeMonitor = await widget.beforeFlash?.call() ?? false;
        await programmer.program(
          request,
          onLog: (text) {
            if (mounted) {
              widget.onLog(text);
              if (text.startsWith(r'$ ') && !stopping) {
                setState(() => operationStatus = 'Connecting to device…');
              }
            }
          },
          onProgress: (value) {
            if (mounted && !stopping) {
              setState(() {
                progress = value;
                operationStatus =
                    'Writing current image · ${(value * 100).round()}%';
              });
            }
          },
        );
        if (mounted) setState(() => operationStatus = 'Programming completed');
      }
    } on Object catch (error) {
      if (mounted) {
        widget.onLog('$error\n');
        setState(
          () => operationStatus = error is ProcessException
              ? 'Programming failed (exit ${error.errorCode}) · see technical log'
              : error
                    .toString()
                    .replaceFirst('FormatException: ', '')
                    .replaceFirst('Bad state: ', ''),
        );
      }
    } finally {
      if (!preview && monitorAfterFlashing) {
        await widget.afterFlash?.call(resumeMonitor);
      }
      if (mounted) {
        setState(() {
          busy = false;
          importing = false;
          stopping = false;
        });
        if (autoloadPending && autoload) {
          autoloadPending = false;
          unawaited(_startAutoloadFlash());
        }
      }
    }
  }

  Future<void> eraseFlash() async {
    if (locked || scanningPorts || port.isEmpty) return;
    final request = EraseRequest(port: port, baud: baud, chip: chip);
    setState(() => importing = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => ContentDialog(
          title: const Text('Erase entire flash?'),
          content: Text(
            'Delete all firmware and stored data on ${request.chip} at ${request.port}? This cannot be undone.',
          ),
          actions: [
            Button(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('confirm-erase-button'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Erase all'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
      setState(() {
        importing = false;
        busy = true;
        erasing = true;
        stopping = false;
        progress = 0;
        operationStatus = 'Erasing flash…';
      });
      await programmer.erase(
        request,
        onLog: (text) {
          if (mounted) widget.onLog(text);
        },
      );
      if (mounted) {
        setState(() {
          progress = 1;
          operationStatus = 'Flash erased successfully';
        });
      }
    } on Object catch (error) {
      if (mounted) {
        widget.onLog('$error\n');
        setState(
          () => operationStatus = error is FlashCancelled
              ? 'Erase interrupted. Flash contents may already be erased or incomplete.'
              : error is ProcessException
              ? 'Erase failed (exit ${error.errorCode}) · see technical log'
              : 'Erase failed: $error',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          importing = false;
          busy = false;
          erasing = false;
          stopping = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => ScaffoldPage.scrollable(
    header: const PageHeader(title: Text('Programming')),
    children: [
      _InputLock(
        locked: locked,
        child: _Card(
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
                    if (!firmwareConfigured) {
                      for (final target in targets.where(
                        (t) => _isBootloader(t.path),
                      )) {
                        target.setAddress(_bootloaderOffset);
                      }
                    }
                  });
                },
              ),
              _SerialCombo(
                width: 250,
                value: port,
                ports: serialPorts,
                scanning: scanningPorts,
                onChanged: (value) => setState(() {
                  port = value;
                  _clearDetection();
                }),
              ),
              _Combo('Baud', 140, baud, const [
                '115200',
                '460800',
                '921600',
                '1500000',
              ], (v) => setState(() => baud = v)),
              Button(
                onPressed: locked || scanningPorts || port.isEmpty
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
                onPressed: locked || scanningPorts ? null : _refreshSerialPorts,
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
                icon: Icon(
                  widget.showLog ? FluentIcons.view : FluentIcons.hide3,
                ),
                onPressed: widget.onToggleLog,
              ),
            ],
          ),
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
        trailing: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              key: const Key('select-project-folder'),
              onPressed: locked ? null : _selectProject,
              child: const Text('Select project folder'),
            ),
            Button(
              key: const Key('open-production-zip'),
              onPressed: locked ? null : _openProductionZip,
              child: const Text('Open production ZIP'),
            ),
            Button(
              key: const Key('export-production-package'),
              onPressed: locked ? null : _exportProduction,
              child: const Text('Export for production'),
            ),
            Button(
              onPressed: locked ? null : _addTarget,
              child: const Text('＋ Add binary'),
            ),
          ],
        ),
        child: Column(
          children: [
            if (projectPath != null) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${projectType ?? 'Saved project'}'
                  '${projectEnvironment == null ? '' : ' · $projectEnvironment'}\n'
                  '$projectPath'
                  '${projectBuildPath == null ? '' : '\nBuild: $projectBuildPath'}',
                  style: const TextStyle(
                    color: Color(0xffaab3bc),
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
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
                        onChanged: locked
                            ? null
                            : (v) {
                                setState(() => targets[i].enabled = v ?? false);
                                _saveLocalProfileSoon();
                              },
                      ),
                    ),
                    SizedBox(
                      width: 120,
                      child: TextBox(
                        controller: targets[i].addressController,
                        enabled: !locked,
                        placeholder: '0x',
                        onChanged: (value) {
                          firmwareConfigured = true;
                          targets[i].address = value;
                          _saveLocalProfileSoon();
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: TextBox(
                              key: ValueKey('flash-path-$i'),
                              controller: targets[i].pathController,
                              enabled: !locked,
                              placeholder: 'Choose file…',
                              onChanged: (value) {
                                firmwareConfigured = true;
                                targets[i].path = value;
                                _saveLocalProfileSoon();
                              },
                            ),
                          ),
                          const SizedBox(width: 6),
                          Button(
                            onPressed: locked
                                ? null
                                : () => _pickTarget(targets[i]),
                            child: const Icon(FluentIcons.open_file, size: 14),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(FluentIcons.delete, size: 14),
                      onPressed: locked ? null : () => _removeTarget(i),
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
      _InputLock(
        locked: locked,
        child: _Card(
          title: 'Flash configuration',
          child: Wrap(
            spacing: 14,
            runSpacing: 12,
            children: [
              _Combo(
                'SPI mode',
                135,
                spiMode,
                const ['Keep', 'QIO', 'QOUT', 'DIO', 'DOUT'],
                (value) => setState(() {
                  firmwareConfigured = true;
                  spiMode = value;
                }),
              ),
              _Combo(
                'Frequency',
                135,
                flashFrequency,
                const ['Keep', '20 MHz', '40 MHz', '80 MHz'],
                (value) => setState(() {
                  firmwareConfigured = true;
                  flashFrequency = value;
                }),
              ),
              _Combo(
                'Size',
                135,
                flashSize,
                [
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
                ],
                (value) => setState(() {
                  firmwareConfigured = true;
                  flashSize = value;
                }),
              ),
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
                    'Program when a selected binary is rebuilt',
                    autoload,
                    locked ? null : _setAutoload,
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: _Toggle(
                    'Monitor after flashing',
                    'Reconnect it if it was active before programming',
                    monitorAfterFlashing,
                    (value) => setState(() => monitorAfterFlashing = value),
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
                      ProgressBar(value: erasing ? null : progress * 100),
                      const SizedBox(height: 6),
                      Text(operationStatus),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                Button(
                  key: const Key('erase-flash-button'),
                  onPressed: locked || scanningPorts || port.isEmpty
                      ? null
                      : eraseFlash,
                  child: const Text('Erase flash'),
                ),
                const SizedBox(width: 8),
                Button(
                  onPressed: busy && !stopping
                      ? () {
                          setState(() {
                            stopping = true;
                            operationStatus = 'Stopping…';
                          });
                          programmer.cancel();
                        }
                      : null,
                  child: const Text('Stop'),
                ),
                const SizedBox(width: 8),
                Button(
                  onPressed: locked || scanningPorts
                      ? null
                      : () => start(preview: true),
                  child: const Text('Preview command'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('start-flash-button'),
                  onPressed:
                      locked ||
                          scanningPorts ||
                          port.isEmpty ||
                          compatibilityFailed
                      ? null
                      : () => start(),
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
  const MonitorPage({super.key, this.monitor, this.discoverPorts});

  final SerialMonitorService? monitor;
  final Future<List<SerialPortInfo>> Function()? discoverPorts;

  @override
  State<MonitorPage> createState() => _MonitorPageState();
}

class _MonitorPageState extends State<MonitorPage> {
  static const maxLines = 10000;
  late final SerialMonitorService monitor =
      widget.monitor ?? SerialMonitorService();
  StreamSubscription<String>? subscription;
  final scroll = ScrollController();
  final send = TextEditingController();
  final search = TextEditingController();
  final include = TextEditingController();
  final exclude = TextEditingController();
  final lines = <_MonitorLine>[];
  final termLines = <String, List<_MonitorLine>>{};
  final detectedPrefixes = <String, String>{};
  final selectedPrefixes = <String>[];
  List<SerialPortInfo> ports = const [];
  String port = '', baud = '115200', dataBits = '8', stopBits = '1';
  String parity = 'None', terminator = 'CR + LF';
  bool connected = false, connecting = false, paused = false, wrap = true;
  bool timestamps = true, scanning = false;
  String selectedLogTab = 'All';
  String? error;

  @override
  void initState() {
    super.initState();
    subscription = monitor.lines.listen(_receive, onError: _serialError);
    _refreshPorts();
    for (final controller in [search, include, exclude]) {
      controller.addListener(_filtersChanged);
    }
  }

  @override
  void dispose() {
    subscription?.cancel();
    monitor.dispose();
    scroll.dispose();
    send.dispose();
    search.dispose();
    include.dispose();
    exclude.dispose();
    super.dispose();
  }

  void _filtersChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshPorts() async {
    if (connected || connecting) return;
    setState(() {
      scanning = true;
      error = null;
    });
    try {
      final found =
          await (widget.discoverPorts ?? SerialPortService.discover)();
      if (!mounted) return;
      setState(() {
        ports = found;
        if (!found.any((item) => item.port == port)) {
          port = found.isEmpty ? '' : found.first.port;
        }
      });
    } on Object catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    } finally {
      if (mounted) setState(() => scanning = false);
    }
  }

  SerialSettings get _settings => SerialSettings(
    port: port,
    baudRate: int.parse(baud),
    dataBits: int.parse(dataBits),
    stopBits: int.parse(stopBits),
    parity: switch (parity) {
      'Even' => SerialParity.even,
      'Odd' => SerialParity.odd,
      _ => SerialParity.none,
    },
  );

  Future<void> _toggleConnection() async {
    if (connecting) return;
    setState(() {
      connecting = true;
      error = null;
    });
    try {
      if (connected) {
        await monitor.disconnect();
        if (mounted) setState(() => connected = false);
      } else {
        await monitor.connect(_settings);
        if (mounted) setState(() => connected = true);
      }
    } on Object catch (exception) {
      await monitor.disconnect();
      if (mounted) {
        setState(() {
          connected = false;
          error = exception.toString().replaceFirst('Bad state: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => connecting = false);
    }
  }

  Future<bool> suspendForFlash() async {
    if (!connected && !monitor.isConnected) return false;
    await monitor.disconnect();
    if (mounted) {
      setState(() {
        connected = false;
        connecting = false;
        error = null;
      });
    }
    return true;
  }

  Future<void> resumeAfterFlash() async {
    if (connected || connecting || port.isEmpty) return;
    setState(() {
      connecting = true;
      error = null;
    });
    try {
      await monitor.connect(_settings);
      if (mounted) setState(() => connected = true);
    } on Object catch (exception) {
      await monitor.disconnect();
      if (mounted) {
        setState(() {
          connected = false;
          error = 'Monitor reconnect failed: ${exception.toString()}';
        });
      }
    } finally {
      if (mounted) setState(() => connecting = false);
    }
  }

  void _receive(String value) {
    final prefix = detectSerialLogPrefix(value);
    final entry = _MonitorLine(DateTime.now(), value, prefix);
    lines.add(entry);
    if (lines.length > maxLines) lines.removeRange(0, lines.length - maxLines);
    if (prefix != null) {
      detectedPrefixes.putIfAbsent(prefix.toLowerCase(), () => prefix);
    }
    for (final term in selectedPrefixes) {
      if (prefix?.toLowerCase() != term.toLowerCase()) continue;
      final queue = termLines.putIfAbsent(term.toLowerCase(), () => []);
      queue.add(entry);
      if (queue.length > maxLines) {
        queue.removeRange(0, queue.length - maxLines);
      }
    }
    if (!paused && mounted) {
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
    }
  }

  void _serialError(Object exception, StackTrace stackTrace) {
    monitor.disconnect();
    if (!mounted) return;
    setState(() {
      connected = false;
      error = exception.toString().replaceFirst('Bad state: ', '');
    });
  }

  void _scrollToEnd() {
    if (scroll.hasClients) scroll.jumpTo(scroll.position.maxScrollExtent);
  }

  List<String> get proposedPrefixes {
    final query = include.text.trim().toLowerCase();
    return detectedPrefixes.values
        .where(
          (prefix) => query.isEmpty || prefix.toLowerCase().contains(query),
        )
        .toList();
  }

  bool _isPrefixSelected(String prefix) => selectedPrefixes.any(
    (selected) => selected.toLowerCase() == prefix.toLowerCase(),
  );

  void _selectPrefix(String prefix, bool selected) {
    final key = prefix.toLowerCase();
    setState(() {
      if (selected && !_isPrefixSelected(prefix)) {
        selectedPrefixes.add(prefix);
        termLines[key] = lines
            .where((entry) => entry.prefix?.toLowerCase() == key)
            .toList();
      } else if (!selected) {
        selectedPrefixes.removeWhere((item) => item.toLowerCase() == key);
        termLines.remove(key);
        if (selectedLogTab.toLowerCase() == key) selectedLogTab = 'All';
      }
    });
  }

  List<_MonitorLine> get visibleLines => _applyCommonFilters(lines);

  List<_MonitorLine> get currentVisibleLines {
    if (selectedLogTab != 'All') {
      return _applyCommonFilters(
        termLines[selectedLogTab.toLowerCase()] ?? const <_MonitorLine>[],
      );
    }
    return visibleLines;
  }

  List<_MonitorLine> _applyCommonFilters(List<_MonitorLine> source) {
    final query = search.text.toLowerCase();
    final rejected = exclude.text
        .toLowerCase()
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    return source.where((entry) {
      final value = entry.text.toLowerCase();
      return (query.isEmpty || value.contains(query)) &&
          !rejected.any(value.contains);
    }).toList();
  }

  String _formatLine(_MonitorLine entry) {
    if (!timestamps) return entry.text;
    String two(int value) => value.toString().padLeft(2, '0');
    String three(int value) => value.toString().padLeft(3, '0');
    final time = entry.receivedAt;
    return '[${two(time.hour)}:${two(time.minute)}:${two(time.second)}.${three(time.millisecond)}]  ${entry.text}';
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
                    _SerialCombo(
                      width: 235,
                      value: port,
                      ports: ports,
                      scanning: scanning,
                      enabled: !connected && !connecting,
                      onChanged: (value) => setState(() => port = value),
                    ),
                    _Combo(
                      'Baud',
                      125,
                      baud,
                      const ['9600', '115200', '460800', '921600'],
                      (value) => setState(() => baud = value),
                      enabled: !connected && !connecting,
                    ),
                    _Combo(
                      'Data bit',
                      90,
                      dataBits,
                      const ['7', '8'],
                      (value) => setState(() => dataBits = value),
                      enabled: !connected && !connecting,
                    ),
                    _Combo(
                      'Stop bit',
                      90,
                      stopBits,
                      const ['1', '2'],
                      (value) => setState(() => stopBits = value),
                      enabled: !connected && !connecting,
                    ),
                    _Combo(
                      'Parity',
                      110,
                      parity,
                      const ['None', 'Even', 'Odd'],
                      (value) => setState(() => parity = value),
                      enabled: !connected && !connecting,
                    ),
                    Button(
                      onPressed: connected || connecting || scanning
                          ? null
                          : _refreshPorts,
                      child: const Icon(FluentIcons.refresh, size: 14),
                    ),
                    FilledButton(
                      key: const Key('monitor-connect-button'),
                      onPressed: connecting || (!connected && port.isEmpty)
                          ? null
                          : _toggleConnection,
                      child: Text(
                        connecting
                            ? 'Please wait…'
                            : connected
                            ? 'Disconnect'
                            : 'Connect',
                      ),
                    ),
                    Button(
                      onPressed: connected ? _reset : null,
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
                    Text(
                      connected
                          ? 'Connected · $baud $dataBits${parity == 'None'
                                ? 'N'
                                : parity == 'Even'
                                ? 'E'
                                : 'O'}$stopBits'
                          : 'Disconnected',
                    ),
                    const Spacer(),
                    Text('Buffer ${lines.length} / $maxLines lines'),
                  ],
                ),
              ],
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            InfoBar(
              title: const Text('Serial monitor error'),
              content: Text(error!),
              severity: InfoBarSeverity.error,
              onClose: () => setState(() => error = null),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              ToggleButton(
                checked: paused,
                onChanged: (v) {
                  setState(() => paused = v);
                  if (!v) {
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _scrollToEnd(),
                    );
                  }
                },
                child: Text(paused ? 'Resume' : 'Pause'),
              ),
              const SizedBox(width: 7),
              Button(
                onPressed: () => setState(() {
                  lines.clear();
                  for (final queue in termLines.values) {
                    queue.clear();
                  }
                }),
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
              Button(
                onPressed: lines.isEmpty ? null : _save,
                child: const Text('Save'),
              ),
              const SizedBox(width: 7),
              Button(
                onPressed: currentVisibleLines.isEmpty ? null : _copyVisible,
                child: const Text('Copy visible'),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: TextBox(
                  controller: search,
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
                child: TextBox(
                  controller: include,
                  placeholder: 'Filter detected prefixes…',
                ),
              ),
              SizedBox(width: 9),
              SizedBox(
                width: 230,
                child: TextBox(
                  controller: exclude,
                  placeholder: 'Exclude: debug…',
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _prefixSelector(),
          const SizedBox(height: 6),
          Expanded(child: _logArea()),
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
              _Combo('', 110, terminator, const [
                'None',
                'LF',
                'CR + LF',
              ], (value) => setState(() => terminator = value)),
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

  Widget _logArea() {
    if (selectedPrefixes.isEmpty) return _logViewport(visibleLines);
    final names = ['All', ...selectedPrefixes];
    return Column(
      children: [
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: names.length,
            separatorBuilder: (_, _) => const SizedBox(width: 4),
            itemBuilder: (_, index) {
              final name = names[index];
              return ToggleButton(
                key: ValueKey('monitor-tab-$name'),
                checked: selectedLogTab == name,
                onChanged: (_) {
                  setState(() => selectedLogTab = name);
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _scrollToEnd(),
                  );
                },
                child: Text(name),
              );
            },
          ),
        ),
        const SizedBox(height: 5),
        Expanded(child: _logViewport(currentVisibleLines)),
      ],
    );
  }

  Widget _prefixSelector() {
    final prefixes = proposedPrefixes;
    if (prefixes.isEmpty) {
      return SizedBox(
        height: 24,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            detectedPrefixes.isEmpty
                ? 'Debug prefixes will appear as serial lines arrive.'
                : 'No matching debug prefixes.',
            style: const TextStyle(color: Color(0xff8d969f), fontSize: 12),
          ),
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 76),
      child: SingleChildScrollView(
        child: Wrap(
          spacing: 14,
          runSpacing: 5,
          children: [
            for (final prefix in prefixes)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    key: ValueKey('prefix-checkbox-$prefix'),
                    checked: _isPrefixSelected(prefix),
                    onChanged: (value) => _selectPrefix(prefix, value ?? false),
                  ),
                  const SizedBox(width: 5),
                  Text(prefix),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _logViewport(List<_MonitorLine> entries) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xff111315),
      border: Border.all(color: const Color(0xff34383d)),
      borderRadius: BorderRadius.circular(5),
    ),
    child: SingleChildScrollView(
      controller: scroll,
      child: wrap
          ? _terminalText(entries)
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _terminalText(entries),
            ),
    ),
  );

  Widget _terminalText(List<_MonitorLine> entries) => SelectableText(
    entries.map(_formatLine).join('\n'),
    style: const TextStyle(
      fontFamily: 'monospace',
      fontSize: 13,
      height: 1.55,
      color: Color(0xffd7e0e8),
    ),
  );
  void transmit() {
    final value = send.text;
    if (value.isEmpty || !connected) return;
    try {
      monitor.send(value, terminator);
      send.clear();
    } on Object catch (exception) {
      setState(
        () => error = exception.toString().replaceFirst('Bad state: ', ''),
      );
    }
  }

  Future<void> _reset() async {
    try {
      await monitor.reset();
    } on Object catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    }
  }

  void _copyVisible() {
    Clipboard.setData(
      ClipboardData(text: currentVisibleLines.map(_formatLine).join('\n')),
    );
  }

  Future<void> _save() async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save serial log',
      fileName: 'serial-monitor.log',
    );
    if (path == null) return;
    try {
      await File(path)
          .writeAsString(lines.map(_formatLine).join('\n'), flush: true);
    } on Object catch (exception) {
      if (mounted) setState(() => error = 'Unable to save log: $exception');
    }
  }
}

class _MonitorLine {
  const _MonitorLine(this.receivedAt, this.text, this.prefix);
  final DateTime receivedAt;
  final String text;
  final String? prefix;
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
            _Intro(
              'Confirm flash erase',
              'Always ask before erasing the entire flash',
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
            Text(title!, style: t.typography.subtitle),
            if (trailing != null) ...[const SizedBox(height: 8), trailing!],
            const SizedBox(height: 13),
          ],
          child,
        ],
      ),
    );
  }
}

class _Combo extends StatelessWidget {
  const _Combo(
    this.label,
    this.width,
    this.value,
    this.values,
    this.change, {
    this.enabled = true,
  });
  final String label, value;
  final double width;
  final List<String> values;
  final ValueChanged<String> change;
  final bool enabled;
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
        onChanged: enabled
            ? (v) {
                if (v != null) change(v);
              }
            : null,
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
    this.enabled = true,
  });

  final double width;
  final String value;
  final List<SerialPortInfo> ports;
  final bool scanning;
  final ValueChanged<String> onChanged;
  final bool enabled;

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
        onChanged: scanning || !enabled
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
  final ValueChanged<bool>? change;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      ToggleSwitch(
        key: ValueKey('toggle-$title'),
        checked: value,
        onChanged: change,
      ),
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
  const _TechnicalLog(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    height: 155,
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: const BoxDecoration(
      color: Color(0xff101214),
      border: Border(top: BorderSide(color: Color(0xff3b3f44))),
    ),
    child: SingleChildScrollView(
      child: SelectableText(
        text,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.5,
          color: Color(0xffa9bac7),
        ),
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

class _InputLock extends StatelessWidget {
  const _InputLock({required this.locked, required this.child});
  final bool locked;
  final Widget child;
  @override
  Widget build(BuildContext context) => ExcludeFocus(
    excluding: locked,
    child: AbsorbPointer(absorbing: locked, child: child),
  );
}
