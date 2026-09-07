# Public Project Metadata and Release Checklist

## GitHub description

Suggested description (111 characters):

> Smart Windows/Linux firmware loader with ESP-IDF build import, Espressif chip detection, and serial monitoring.

## GitHub topics

Suggested topics:

```text
esp32
espressif
esp-idf
esptool
firmware
flasher
serial-monitor
flutter
embedded
cross-platform
```

## Screenshot checklist

Capture screenshots only after the relevant workflow has been validated and the UI is ready to represent publicly. Proposed future paths:

- `docs/images/programming.png` — complete programming page with a real imported layout;
- `docs/images/chip-detection.png` — detected chip, flash size, and compatibility state;
- `docs/images/esp-idf-import.png` — imported bootloader, partition table, application, and offsets;
- `docs/images/serial-monitor.png` — real monitor data and prefix tabs;
- `docs/images/serial-plot.png` — selected `PLOT:` variables and chart.

Do not add these paths to the README until the files exist.

## First release checklist

- Choose and add an open-source license.
- Decide whether the current Flutter metadata version represents the first release; update it before packaging if necessary.
- Run `flutter analyze` and `flutter test` from a clean checkout.
- Record Windows and Linux runtime results.
- Record physical-device results by chip family.
- Confirm esptool installation or bundling behavior and include required third-party licenses.
- Build and test the portable Windows package.
- Build and test the Linux AppImage on more than one supported distribution.
- Add the screenshot set and verify README rendering.
- Update `CHANGELOG.md` and move relevant Unreleased entries into the release version.
- Publish release notes describing supported workflows and known limitations.
- Attach SHA-256 checksums for every downloadable artifact.
- Link the README installation section directly to the GitHub release page only after artifacts exist.

## Suggested release assets

```text
ESP-Loader-<version>-windows.zip
ESP-Loader-<version>-linux-x86_64.AppImage
SHA256SUMS.txt
```

Artifact names and architectures must reflect the packages actually produced. Do not advertise installers or architectures that have not been built and tested.
