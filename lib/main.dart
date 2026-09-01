import 'dart:async';
import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';

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
    titleBar: TitleBar(
      isBackButtonVisible: false,
      title: const Text('ESP Loader'),
      endHeader: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _Badge(),
          const SizedBox(width: 8),
          IconButton(
            key: const Key('technical-log-button'),
            icon: Icon(showLog ? FluentIcons.view : FluentIcons.hide3),
            onPressed: () => setState(() => showLog = !showLog),
          ),
          const SizedBox(width: 8),
        ],
      ),
    ),
    pane: NavigationPane(
      selected: selected,
      onChanged: (v) => setState(() => selected = v),
      displayMode: PaneDisplayMode.auto,
      items: [
        PaneItem(
          icon: const Icon(FluentIcons.installation),
          title: const Text('Programmazione'),
          body: const FlashPage(),
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
          title: const Text('Impostazioni'),
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
  const FlashPage({super.key});
  @override
  State<FlashPage> createState() => _FlashPageState();
}

class _FlashPageState extends State<FlashPage> {
  bool autoload = true, monitorAfter = true, busy = false;
  double progress = 0;
  Timer? timer;
  String chip = 'ESP32-S3', port = 'COM7 · USB JTAG/serial', baud = '921600';
  final targets = <List<Object>>[
    [true, '0x0000', 'bootloader.bin'],
    [true, '0x8000', 'partition-table.bin'],
    [true, '0x10000', 'esp_loader_demo.bin'],
  ];
  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
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
    header: const PageHeader(title: Text('Programmazione')),
    children: [
      const _Intro(
        'Prepara il dispositivo',
        'Configura la porta e i segmenti da scrivere. Le operazioni di questa demo sono simulate.',
      ),
      const SizedBox(height: 16),
      _Card(
        child: Wrap(
          spacing: 14,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            _Combo('Chip', 170, chip, const [
              'ESP32',
              'ESP32-S3',
              'ESP32-C3',
              'ESP32-C6',
            ], (v) => setState(() => chip = v)),
            _Combo('Porta seriale', 250, port, const [
              'COM7 · USB JTAG/serial',
              'COM12 · CP210x UART',
              '/dev/ttyUSB0',
            ], (v) => setState(() => port = v)),
            _Combo('Baud', 140, baud, const [
              '115200',
              '460800',
              '921600',
              '1500000',
            ], (v) => setState(() => baud = v)),
            Button(
              onPressed: busy ? null : () {},
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(FluentIcons.refresh, size: 14),
                  SizedBox(width: 6),
                  Text('Aggiorna'),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      _Card(
        title: 'Immagini flash',
        trailing: Button(
          onPressed: busy
              ? null
              : () => setState(() => targets.add([true, '0x', 'Scegli file…'])),
          child: const Text('＋ Aggiungi binario'),
        ),
        child: Column(
          children: [
            const Row(
              children: [
                SizedBox(width: 40),
                SizedBox(width: 130, child: Text('Indirizzo')),
                Expanded(child: Text('File binario')),
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
                        checked: targets[i][0] as bool,
                        onChanged: busy
                            ? null
                            : (v) => setState(() => targets[i][0] = v ?? false),
                      ),
                    ),
                    SizedBox(
                      width: 120,
                      child: TextBox(
                        enabled: !busy,
                        placeholder: targets[i][1] as String,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextBox(
                        enabled: !busy,
                        placeholder: targets[i][2] as String,
                        suffix: const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Icon(FluentIcons.open_file, size: 14),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(FluentIcons.delete, size: 14),
                      onPressed: busy
                          ? null
                          : () => setState(() => targets.removeAt(i)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      _Card(
        title: 'Configurazione flash',
        child: Wrap(
          spacing: 14,
          runSpacing: 12,
          children: [
            _Combo('SPI mode', 135, 'DIO', const [
              'Keep',
              'QIO',
              'QOUT',
              'DIO',
              'DOUT',
            ], (_) {}),
            _Combo('Frequenza', 135, '80 MHz', const [
              'Keep',
              '20 MHz',
              '40 MHz',
              '80 MHz',
            ], (_) {}),
            _Combo('Dimensione', 135, '16 MB', const [
              'Rileva',
              '2 MB',
              '4 MB',
              '8 MB',
              '16 MB',
            ], (_) {}),
            SizedBox(
              width: 190,
              child: InfoLabel(
                label: 'Rilevamento',
                child: Padding(
                  padding: EdgeInsets.only(top: 7),
                  child: Text(
                    'ESP32-S3 · 16 MB',
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
                    'Riprogramma alla modifica dei file',
                    autoload,
                    (v) => setState(() => autoload = v),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: _Toggle(
                    'Monitor dopo il flash',
                    'Riapre la seriale automaticamente',
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
                            ? 'Scrittura in corso · ${(progress * 100).round()}%'
                            : progress >= 1
                            ? 'Programmazione completata · verifica OK'
                            : '${targets.length} segmenti pronti · $port',
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                Button(
                  onPressed: busy ? null : () {},
                  child: const Text('Cancella flash'),
                ),
                const SizedBox(width: 8),
                Button(
                  onPressed: busy
                      ? () {
                          timer?.cancel();
                          setState(() => busy = false);
                        }
                      : null,
                  child: const Text('Interrompi'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('start-flash-button'),
                  onPressed: busy ? null : start,
                  child: const Text('Programma'),
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
    header: const PageHeader(title: Text('Monitor seriale')),
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
                    _Combo('Porta', 235, 'COM7 · USB JTAG/serial', const [
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
                    _Combo('Parità', 110, 'Nessuna', const [
                      'Nessuna',
                      'Pari',
                      'Dispari',
                    ], (_) {}),
                    Button(
                      onPressed: () {},
                      child: const Icon(FluentIcons.refresh, size: 14),
                    ),
                    FilledButton(
                      key: const Key('monitor-connect-button'),
                      onPressed: () => setState(() => connected = !connected),
                      child: Text(connected ? 'Disconnetti' : 'Connetti'),
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
                    Text(connected ? 'Connesso · 115200 8N1' : 'Non connesso'),
                    const Spacer(),
                    const Text('Buffer 7 / 10.000 righe'),
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
                child: Text(paused ? 'Riprendi' : 'Pausa'),
              ),
              const SizedBox(width: 7),
              Button(
                onPressed: () => setState(lines.clear),
                child: const Text('Pulisci'),
              ),
              const SizedBox(width: 7),
              ToggleButton(
                checked: wrap,
                onChanged: (v) => setState(() => wrap = v),
                child: const Text('A capo'),
              ),
              const SizedBox(width: 7),
              ToggleButton(
                checked: timestamps,
                onChanged: (v) => setState(() => timestamps = v),
                child: const Text('Timestamp'),
              ),
              const Spacer(),
              Button(onPressed: () {}, child: const Text('Salva')),
              const SizedBox(width: 7),
              Button(onPressed: () {}, child: const Text('Copia visibile')),
            ],
          ),
          const SizedBox(height: 9),
          const Row(
            children: [
              Expanded(
                child: TextBox(
                  placeholder: 'Cerca nel log visibile…',
                  prefix: Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(FluentIcons.search, size: 14),
                  ),
                ),
              ),
              SizedBox(width: 9),
              SizedBox(
                width: 230,
                child: TextBox(placeholder: 'Includi: wifi, sensor…'),
              ),
              SizedBox(width: 9),
              SizedBox(
                width: 230,
                child: TextBox(placeholder: 'Escludi: debug…'),
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
                  placeholder: 'Invia alla seriale…',
                  onSubmitted: (_) => transmit(),
                ),
              ),
              const SizedBox(width: 8),
              _Combo('', 110, 'CR + LF', const [
                'Nessuno',
                'LF',
                'CR + LF',
              ], (_) {}),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: connected ? transmit : null,
                child: const Text('Invia'),
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
        'Dati seriali in tempo reale',
        'Anteprima dei valori numerici estratti dalle righe ricevute.',
      ),
      const SizedBox(height: 16),
      _Card(
        child: Row(
          children: [
            Checkbox(
              checked: a,
              onChanged: (v) => setState(() => a = v ?? false),
            ),
            const Text('Temperatura'),
            const SizedBox(width: 20),
            Checkbox(
              checked: b,
              onChanged: (v) => setState(() => b = v ?? false),
            ),
            const Text('Pressione'),
            const Spacer(),
            ToggleButton(
              checked: paused,
              onChanged: (v) => setState(() => paused = v),
              child: Text(paused ? 'Riprendi' : 'Pausa'),
            ),
            const SizedBox(width: 8),
            Button(onPressed: () {}, child: const Text('Pulisci')),
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
            child: _Metric('Temperatura', '23,72 °C', Color(0xff59a8ff)),
          ),
          SizedBox(width: 12),
          Expanded(
            child: _Metric('Pressione', '1008,4 hPa', Color(0xffffb44c)),
          ),
          SizedBox(width: 12),
          Expanded(child: _Metric('Campioni', '1.248', Color(0xff6fd58a))),
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
    header: const PageHeader(title: Text('Impostazioni')),
    children: [
      _Card(
        title: 'Aspetto',
        child: Row(
          children: [
            const Expanded(child: Text('Tema dell’applicazione')),
            SizedBox(
              width: 160,
              child: ComboBox<ThemeMode>(
                value: mode,
                isExpanded: true,
                items: const [
                  ComboBoxItem(value: ThemeMode.system, child: Text('Sistema')),
                  ComboBoxItem(value: ThemeMode.light, child: Text('Chiaro')),
                  ComboBoxItem(value: ThemeMode.dark, child: Text('Scuro')),
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
        title: 'Strumenti Espressif',
        child: Column(
          children: [
            InfoLabel(
              label: 'Percorso esptool',
              child: TextBox(
                placeholder: 'Rilevamento automatico nella cartella dell’app',
              ),
            ),
            SizedBox(height: 12),
            InfoBar(
              title: Text('Modalità demo'),
              content: Text('Nessun comando esterno viene eseguito.'),
              severity: InfoBarSeverity.info,
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      const _Card(
        title: 'Comportamento',
        child: Column(
          children: [
            _Setting(
              'Ricorda l’ultima porta',
              'Ripristina porta e baud rate all’avvio',
            ),
            SizedBox(height: 14),
            _Setting(
              'Riapri il monitor dopo il flash',
              'Attende 600 ms prima della connessione',
            ),
            SizedBox(height: 14),
            _Setting(
              'Conferma cancellazione flash',
              'Richiede conferma prima di erase-flash',
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

class _Badge extends StatelessWidget {
  const _Badge();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xff225b35),
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Row(
      children: [
        Icon(FluentIcons.plug_connected, size: 12, color: Color(0xff8be3a1)),
        SizedBox(width: 6),
        Text('COM7', style: TextStyle(fontSize: 12, color: Color(0xffd7f5df))),
      ],
    ),
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
