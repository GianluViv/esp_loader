# ESP Loader

ESP Loader is a Flutter desktop application for preparing, programming, and
diagnosing Espressif devices on Windows and Linux.

The project is under development. Hardware detection and flash-image setup are
already operational. Flash writing, the serial monitor, autoload, and plotting
still use demonstration behavior.

## Available features

- Fluent interface with light and dark themes;
- detection of available serial ports;
- connected-chip detection through `esptool flash-id`;
- flash-memory size detection;
- automatic selection of recommended flash parameters for the detected chip;
- individual `.bin` file selection;
- automatic import of all `.bin` files next to `bootloader.bin`;
- ESP-IDF import through `flasher_args.json`, including binaries stored in
  `bootloader/` and `partition_table/` subdirectories;
- compatibility check between the firmware target and the chip detected by
  **Test**, with programming disabled on mismatch;
- parsing of the ESP-IDF binary `partitions.bin` format;
- automatic completion of offsets for images matched to partitions;
- manual address editing and individual image enablement;
- show/hide technical log panel;
- native Windows and Linux application icons;
- Linux desktop assets prepared for a future AppImage release.

## Features still simulated

- actual flash programming and erasing;
- programming progress and interruption;
- serial monitoring, transmission, and reset;
- autoload when configured files change;
- serial-data acquisition and plotting.

The **Test** button performs a real, non-destructive device query. It does not
write to or erase flash memory.

## Development requirements

- Flutter with Windows/Linux desktop support;
- `esptool` available in `PATH` for device testing;
- permission to access the selected serial port;
- on Linux, membership in the group allowed to use serial ports, commonly
  `dialout`.

The application searches for `esptool`, `esptool.py`, and the fallback Python
module invocation `python -m esptool` or `python3 -m esptool`.

## Running

Linux:

```bash
flutter pub get
flutter run -d linux
```

Windows:

```powershell
flutter pub get
flutter run -d windows
```

## Verification

```bash
flutter analyze
flutter test
```

## Programming-page workflow

1. Select a serial port and press **Test**.
2. Check the chip, memory size, and values shown under **Flash configuration**.
3. Select `bootloader.bin` to import the other `.bin` files in its folder.
4. For ESP-IDF builds, the application searches parent directories for
   `flasher_args.json` and imports its exact files, offsets, target, and flash
   settings.
5. When no manifest is available, `partitions.bin` is parsed to populate image
   offsets.
6. Press **Test** to compare the connected chip with the firmware target.
7. Always review files and addresses before actual programming is enabled.

Partition offsets come from the firmware partition table. Bootloader,
partition-table, and `boot_app0.bin` addresses are suggestions based on the
selected ESP family and Espressif conventions, so they remain editable.

## Distribution

Windows uses the multi-resolution icon embedded in the native runner.

The Linux build includes:

- application ID `com.ariosa.esp_loader`;
- GTK and desktop icons;
- `com.ariosa.esp_loader.desktop`.

The final Linux release will be distributed as an **AppImage**. AppImage
generation and portable `esptool` bundling are not implemented yet.

See [`PIANO_DI_LAVORO.md`](PIANO_DI_LAVORO.md) for the roadmap, detailed status,
and testing criteria.
