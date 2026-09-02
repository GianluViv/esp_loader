# ESP Loader — Work Plan

## 1. Goal

Build a Windows and Linux Flutter desktop application for:

1. programming Espressif microcontrollers through the official command-line
   tools;
2. monitoring a serial port, with automatic transitions between programming
   and monitoring.

The interface must remain simple for operators while retaining complete command
output in a normally hidden technical panel.

## 2. Reference projects

### `proto_flutter`

Reference for Flutter desktop structure, Windows and Linux targets, Windows
release scripts, Linux AppImage distribution, and general desktop conventions.

### `collaudo_ariosa_global`

Reference for external `esptool` processes, asynchronous output capture, serial
port discovery, binary selection, flash erasing, process interruption, Windows
tool bundling, Fluent UI, and desktop-window handling.

## 3. Design principles

- One codebase for Windows and Linux.
- Separate UI, configuration, serial services, and external processes.
- Keep operational logic independent from Flutter widgets.
- Ensure exclusive access to a port between flashing and monitoring.
- Retain technical output without showing it in the primary workflow.
- Support persistent configuration and reusable programming profiles.
- Remain usable at reduced window sizes.
- Make long operations cancellable and expose status and progress.
- Keep user-facing strings ready for future localization and language selection.

## 4. Current status — September 2, 2026

| Area | Status | Notes |
| --- | --- | --- |
| Desktop UI and navigation | **complete** | Programming, Monitor, Plot, and Settings pages are available |
| `.bin` selection | **complete** | File picker on every row, with row addition and removal |
| Firmware-folder import | **complete** | Selecting `bootloader.bin` imports all sibling `.bin` files |
| ESP-IDF build import | **complete** | Imports paths, offsets, target, and settings from `flasher_args.json` |
| Partition table | **complete** | Parses `partitions.bin` and populates matching offsets |
| Serial-port enumeration | **partial** | Real on the Programming page for Windows and Linux; Monitor is simulated |
| Device test | **complete** | Non-destructive chip and flash-size detection through `esptool flash-id` |
| Firmware/device compatibility | **complete** | Compares manifest target with detected hardware and blocks mismatches |
| Flash parameters | **partial** | Updated by Test and editable, but not yet used for real flashing |
| Programming and erasing | **simulated** | No write or erase command is executed yet |
| Serial monitor | **simulated** | UI exists; serial communication is not connected |
| Autoload | **simulated** | UI exists; file watching is not implemented |
| Plot | **simulated** | UI and data are demonstrative |
| Native icons | **complete** | Windows resources and Linux GTK/desktop integration |
| Distribution | **partial** | Linux bundle verified; AppImage generation remains to be implemented |
| Automated tests | **partial** | Partition parser, esptool output, Windows port parsing, and core widgets |

Partition offsets come from `partitions.bin`. Bootloader, partition-table, and
`boot_app0.bin` offsets are editable suggestions based on the ESP family and
Espressif conventions.

## 5. Delivery phases

### Phase 1 — UI demonstration — complete

- Fluent light and dark themes;
- desktop navigation and Programming, Monitor, Plot, and Settings pages;
- normally hidden technical panel;
- simulated programming, success, error, cancellation, monitor, and plot states;
- responsive Windows/Linux layout;
- dynamic binary list with address and individual enablement;
- add/remove rows; reordering remains planned;
- simulated Program, Stop, and Erase flash actions;
- binary combination remains planned.

### Phase 2 — Specification consolidation

- finalize supported Espressif families;
- define the required Flash Download Tool feature matrix;
- define binary-row limits and behavior;
- define profile format and portability;
- finalize autoload, monitor, and plot behavior;
- decide whether ELF decoding is required;
- prioritize essential and advanced features.

### Phase 3 — Application architecture

Create separate modules for configuration and persistence, chip models, flash
targets, profiles, port discovery, Espressif processes, programming, erasing,
serial monitoring, autoload, technical logging, and operation coordination.

A central state machine will cover idle, monitor connected, preparing,
programming, erasing, completed, error, and cancellation states.

### Phase 4 — Espressif tool integration

- detect bundled tools automatically;
- provide platform-specific Windows and Linux executables;
- allow a manual tool path as fallback;
- build verifiable command arguments;
- capture stdout and stderr in real time;
- interpret progress and relevant status messages;
- implement timeout and controlled interruption;
- preserve the complete technical log.

### Phase 5 — Programming engine

- select or detect the chip;
- program multiple binaries at configurable addresses;
- apply baud, SPI mode, frequency, and flash size;
- erase and stop operations;
- validate files, addresses, sizes, and overlaps before writing;
- save, duplicate, export, and import profiles;
- optionally combine binaries;
- show a clear final result without requiring the technical log.

### Phase 6 — Autoload

- watch one or more configured files;
- debounce repeated compiler events;
- verify file stability and readability;
- prevent duplicate programming;
- queue changes detected during a flash operation;
- expose watching, change detected, waiting, flashing, and result states;
- allow temporary suspension;
- optionally reopen the monitor after successful programming.

### Phase 7 — Serial monitor

- enumerate and refresh Windows/Linux ports;
- configure line settings fully;
- open and close robustly;
- receive without blocking the UI;
- support configurable text and hexadecimal display;
- transmit with a configurable terminator;
- control DTR/RTS and reset when supported;
- provide pause, bounded buffers, timestamps, search, filters, copy, and save;
- handle device removal and reconnection.

### Phase 8 — Flash/monitor coordination

```text
close monitor → acquire exclusive port → flash
→ optional reset → configurable delay → reopen monitor
```

This must also work with autoload and handle failures, cancellation, and physical
disconnection.

### Phase 9 — Plotting and analysis

- extract numeric values using separators, regular expressions, or structured
  formats;
- display multiple series;
- support pause, zoom, clear, and time windows;
- coordinate the plot with the terminal;
- optionally decode addresses through ELF files if approved in Phase 2.

### Phase 10 — Settings and profiles

Persist the last port and serial configuration, programming profiles, files,
addresses, flash parameters, autoload options, post-flash behavior, monitor
filters, theme, window size, and window position. Prefer relative paths and
support profile import/export.

### Phase 11 — Testing

- command-construction tests;
- Espressif-output parser tests;
- flash-segment validation tests;
- autoload and debounce tests;
- serial buffer, search, and filter tests;
- virtual-port tests;
- physical-device tests for every supported family;
- disconnection, timeout, incomplete-file, and interrupted-flash tests;
- Windows and Linux verification.

### Phase 12 — Distribution

- Windows bundle and optional portable executable;
- Linux AppImage;
- platform-specific Espressif utilities and licenses;
- startup dependency checks;
- Linux serial-permission diagnostics;
- installation and troubleshooting guide.

## 6. Milestones

| Milestone | Result |
| --- | --- |
| M1 | UI demonstration approved |
| M2 | Functional specification frozen |
| M3 | Real flashing works on Windows and Linux |
| M4 | Reliable autoload |
| M5 | Complete serial monitor |
| M6 | Automatic flash/monitor integration |
| M7 | Agreed plotting and advanced features |
| M8 | Tested, distributable release |

## 7. Next operational step

Connect **Program** to a real `esptool` service while keeping process logic out
of the widgets. Before writing, the service must:

1. validate the port, files, addresses, sizes, and overlaps;
2. build and expose the `write-flash` command for inspection;
3. capture output, errors, and progress in real time;
4. support controlled process interruption;
5. report a clear result and preserve the complete technical log.

Real flash erasing will only be connected after this validation path. Serial
monitoring, flash coordination, and autoload follow. The final Linux release
will be generated as an AppImage.
