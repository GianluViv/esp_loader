# Changelog

All notable changes to ESP Loader will be documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

ESP Loader has no official releases yet. The package version in Flutter metadata is not a published release history.

## Unreleased

### Added

- Windows and Linux Flutter desktop application.
- Serial-port, Espressif chip, and flash-size detection.
- ESP-IDF, PlatformIO, Arduino exported-build, and generic build import.
- `flasher_args.json` and binary partition-table parsing.
- Multi-image flash, full-chip erase, validation, command preview, progress, cancellation, and timeouts.
- Firmware-target and connected-device compatibility checks.
- Production ZIP import/export with size and SHA-256 verification.
- Real serial monitor with RX/TX, filters, prefix tabs, reset, copy, and save.
- Flash/monitor coordination and firmware autoload.
- Serial plotting through explicit `PLOT:` records and compatibility prefixes.
- Portable persistence of the flash-image list and selected project.
- Persistent selection, validation, and shared discovery of an explicit esptool executable.
- Official esptool 5.4.0 standalone executables bundled for Windows and Linux x86_64 packages.
- MIT licensing for ESP Loader, copyright 2026 Gianluca Vivenzi.

### Known limitations

- No public Windows or Linux package is available.
- Windows runtime and per-family hardware validation are incomplete.
- Automatic serial reconnection is not implemented.
- Full-chip erase does not automatically release and reopen an active serial monitor connection.
- Autoload, monitor coordination, and plotting need further physical-device validation.
- Theme and broader UI settings are not persisted yet.
