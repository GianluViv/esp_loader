# Contributing to ESP Loader

ESP Loader welcomes focused bug fixes, tests, documentation improvements, and features that fit its Windows/Linux Espressif workflow. The project has no formal release yet, so discuss large behavior or format changes in an issue before investing substantial work.

## Set up the project

Install Flutter with desktop support and esptool 4 or newer, then clone and run the application:

```bash
git clone https://github.com/GianluViv/esp_loader.git
cd esp_loader
flutter pub get
flutter run -d linux
```

Use `flutter run -d windows` on Windows. Ensure your account can access the serial device; Linux systems commonly grant this through the `dialout` group.

## Validate changes

Run:

```bash
flutter analyze
flutter test
```

Add tests when changing parsers, flash validation, command construction, file handling, process lifecycle, or serial behavior. Hardware-dependent changes should state the operating system, board/chip, esptool version, trigger, and observed result in the pull request.

## Code and documentation style

- Follow `dart format` and the repository's Flutter lint configuration.
- Keep OS and file-system behavior explicit and testable.
- Keep process execution and parsing logic outside widgets when practical.
- Preserve complete error information in the technical log while keeping operator messages concise.
- Use **ESP Loader** in prose and `esp_loader` only for technical identifiers.
- Document implemented behavior and limitations; do not describe planned functionality as available.

## Issues

Before opening an issue, check existing reports. Include concise reproduction steps, operating system, ESP Loader revision, esptool version, chip/board, build system, and sanitized relevant output. Do not publish credentials, private firmware, serial numbers, or security-sensitive details.

Follow [SECURITY.md](SECURITY.md) for vulnerabilities involving command execution, firmware packages, paths, archives, or serial devices.

## Pull requests

Keep each pull request centered on one problem. Explain the trigger, resulting behavior, important tradeoffs, and validation performed. Update the README, roadmap, architecture notes, or changelog when behavior or public expectations change.

The project license has not yet been selected. Licensing terms should be made explicit before outside contributions are merged or a public release is promoted.
