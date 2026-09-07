# ESP Loader Roadmap

ESP Loader is under active development and has no official release yet. Version labels below describe intended milestones; they do not claim that matching binaries have been published.

## Current baseline

The application already contains real device detection, ESP-IDF build import, partition parsing, flashing, erase, serial monitoring, autoload, production-package handling, and plotting code. Flash and erase passed physical-device tests on Linux on September 6, 2026. The remaining work is primarily validation, resilience, settings, packaging, and release preparation.

## v0.1 — Build understanding and device inspection

Implemented:

- Windows and Linux Flutter desktop UI;
- serial-port discovery;
- non-destructive chip and flash-size detection;
- ESP-IDF `flasher_args.json` import;
- binary `partitions.bin` parsing;
- firmware-image and offset reconstruction;
- firmware-target and connected-device compatibility checks;
- PlatformIO, Arduino exported-build, and generic Espressif build import;
- manual image and flash-parameter editing.

Remaining validation:

- record physical test coverage per supported chip family;
- complete Windows runtime testing;
- expand malformed-manifest and unusual partition-layout fixtures.

## v0.2 — Flashing and production workflows

Implemented:

- real multi-image writes through esptool 4 and 5;
- full-chip erase with explicit confirmation;
- command preview and complete technical output;
- per-image progress, cancellation, and timeout handling;
- file, address, flash-capacity, and erase-sector overlap validation;
- production ZIP export/import with SHA-256 and size verification;
- portable persistence of image paths, offsets, enabled states, and project path.

Remaining validation and hardening:

- repeat flash, erase, timeout, and cancellation tests on Windows;
- test production packages across clean Windows and Linux machines;
- document the chip family and board used for every physical test;
- decide whether combined firmware-image generation belongs in the supported workflow.

## v0.3 — Serial monitor

Implemented:

- real serial RX/TX;
- configurable baud, data bits, stop bits, parity, and TX terminator;
- bounded line buffer, pause/resume, timestamps, wrap, search, and exclusions;
- detected-prefix tabs for plain and ESP-IDF log formats;
- copy, save, and DTR/RTS reset controls;
- serial-port release before flashing and optional reopen afterward.

Remaining:

- automatic reconnection after USB removal and re-enumeration;
- Linux and Windows hardware tests for disconnects, partial UTF-8 input, TX, reset, and long sessions;
- persistence of serial and monitor settings;
- virtual serial-port integration tests where practical.

## v0.4 — Autoload and serial plot

Implemented:

- polling of enabled binaries and relevant project metadata;
- stability checks before an automatic flash;
- queued rebuild handling during an active device operation;
- project re-import before automatic programming;
- explicit `PLOT:` protocol and compatibility prefix filter;
- two-occurrence discovery within five seconds;
- up to eight acquired series and 600 samples per series;
- pause, clear, current values, and automatic chart scaling.

Remaining:

- hardware-test autoload during real build output replacement;
- verify monitor suspension/reopen around automatic writes;
- test plotting against the GS240A reference stream;
- add plot zoom and configurable time windows;
- persist plot source, selected variables, and related settings;
- consider configurable structured formats after the dedicated protocol is stable.

## v1.0 — Public stable release

Required before the milestone:

- choose and add an open-source license;
- complete Windows runtime and representative device-family validation;
- produce a portable Windows package and Linux AppImage;
- decide how esptool and its licenses are bundled or installed;
- add startup dependency and Linux serial-permission diagnostics;
- add screenshots and release artifacts with SHA-256 checksums;
- replace placeholder settings with functional configuration or remove them;
- publish a support matrix backed by recorded physical tests;
- complete a security review of command execution, ZIP/file handling, firmware parsing, and serial access.

## Later ideas

- reusable named profile import/export;
- optional combined firmware images;
- hexadecimal serial display and transmission;
- optional ELF address decoding;
- localization.

## Validation policy

Automated tests cover parsers, validation, command syntax, subprocess behavior, serial services, profiles, plotting, and key widgets. Release readiness also requires hardware evidence. A feature should remain marked **In development** until its important Windows/Linux and device-disconnection paths have been exercised outside tests.
