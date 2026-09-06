# ESP Loader

ESP Loader is a Flutter desktop application for preparing, programming, and
diagnosing Espressif devices on Windows and Linux.

The project is under development. Hardware detection, flash-image setup, and
flash programming are implemented and have passed physical-device testing. The
serial monitor has real Windows/Linux communication and coordinates with
programming and autoload; plotting still uses demonstration behavior.

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
- full-chip flash erasing with device-specific confirmation, log, Stop and timeout;
- real multi-image programming through esptool 4 or 5, with version-aware arguments;
- validation of readable, nonempty files, addresses, capacity, firmware target,
  and overlapping 4 KiB erase sectors before launching a write;
- command preview without writing, live output and per-image progress;
- Stop with process termination and a ten-minute programming timeout;
- real serial monitoring with configurable baud, data bits, stop bits and parity;
- UTF-8 line reconstruction, a bounded 10,000-line buffer, pause and timestamps;
- search, include/exclude filters, serial transmission, reset, copy and log saving;
- show/hide scrollable technical log panel retaining complete session output;
- native Windows and Linux application icons;
- Linux desktop assets prepared for a future AppImage release.

## Features still simulated

- autoload when a configured binary changes and remains stable across checks;
- automatic monitor suspension and reopening around programming;
- portable persistence of the last flash-image list in
  `esp_loader_profile.json`, stored beside the executable or AppImage;
- serial-data acquisition and plotting.

The **Test** button performs a real, non-destructive device query. It does not
write to or erase flash memory.

## Development requirements

- Flutter with Windows/Linux desktop support;
- `esptool` available in `PATH` (version 4 or newer for programming);
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
7. Press **Preview command** to validate the enabled images and inspect the
   canonical command in the technical log without accessing the device.
8. Press **Program** to write the enabled images. The actual command is logged
   after tool discovery; esptool 4 uses its legacy underscore command syntax.
9. **Stop** terminates the process; interrupted or timed-out programming can leave
   incomplete firmware, so repeat programming before using the device.

Image paths, addresses, and enabled states are restored from
`esp_loader_profile.json` at startup. The file is local to the executable folder,
so copies launched from different folders keep independent image lists. For an
AppImage, the profile is stored beside the original `.AppImage` file.

**Select project folder** accepts a project root and detects PlatformIO through
`platformio.ini`, ESP-IDF through `CMakeLists.txt` and `build/flasher_args.json`,
and Arduino through its `.ino` sketch and exported build binaries. PlatformIO
uses the most recently compiled environment when more than one build is present.
The detected build directory, chip, images, and offsets populate the flash table.
The selected project is stored in the portable profile. With Autoload enabled,
the project metadata is parsed again before every automatic programming cycle.

## Production packages

**Export for production** creates a ZIP from the enabled flash images. The ZIP
contains the binaries under `binaries/` and a versioned
`production_manifest.json` with project information, device and flash settings,
addresses, sizes, and SHA-256 hashes. After manually extracting the ZIP on
another PC, select the extracted directory with **Select project folder**. ESP
Loader recognizes it as a Production package and verifies every file before
populating the programming table. Source code and the original IDE are not
required on the production PC.

**Open production ZIP** accepts the archive directly. ESP Loader validates ZIP
paths, extracts it into an application-managed cache, verifies the manifest and
SHA-256 hashes, and opens the resulting Production package without requiring a
manual extraction step.

The progress bar describes the **current image** and can restart for each binary.
Success is shown only after esptool exits successfully. Configuration and image
editing are locked during programming. Leaving/disposal of the Programming page
cancels its operation. Output is retained in memory for the current app session.
With flash size **Detect**, capacity validation is delegated to esptool. The
selected chip is passed explicitly, preserving esptool's hardware compatibility
checks; no force or whole-chip erase option is added.

Automated tests cover validation, command syntax, process output, failed exits,
timeouts, cancellation, and UI transitions. Linux subprocess tests also exercise
stream draining and forced termination. Physical-device programming and erase
tests passed on September 6, 2026. Windows runtime verification remains pending.

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

## Erasing flash

Select the port and chip, then press **Erase flash** and confirm **Erase all**.
This removes all firmware and stored data from flash; no binary selection is
required. The activity indicator is indeterminate until esptool exits. Stop
terminates the host process but cannot undo an erase already sent to the chip.
The command uses `erase-flash` on esptool 5 and `erase_flash` on version 4,
without `--force`; esptool's device protection checks remain enabled.
See the [official erase command documentation](https://docs.espressif.com/projects/esptool/en/latest/esp32/esptool/basic-commands.html#erase-flash-erase-flash-erase-region).
Physical-device erase validation passed on September 6, 2026.

## Serial monitor

`GS240A` is the first reference target and emits raw UTF-8 text at 115200 baud.
Select its port, keep the default **115200 8N1**, and press **Connect**. Incoming
bytes are reconstructed into lines even when USB packets split a UTF-8 character.
Pause freezes the displayed snapshot while reception continues; Resume shows all
buffered lines. The oldest lines are discarded after 10,000 entries.

Search matches any text and Exclude removes lines containing its comma-separated
terms. The prefix field searches a master list learned from incoming `TAG: ...`
lines and standard ESP-IDF `ESP_LOGx` output such as `I (123) TAG: ...`. Selecting
a prefix checkbox creates its stable live tab. **All** always contains the complete
log, while each prefix tab receives only lines identified with that exact tag.
Copy visible uses the selected tab and its filters, while Save writes the complete buffer.
Reset pulses the ESP DTR/RTS control lines. If the monitor is connected when
programming starts, the application releases the serial port and reconnects it
after the operation when **Monitor after flashing** is enabled.
