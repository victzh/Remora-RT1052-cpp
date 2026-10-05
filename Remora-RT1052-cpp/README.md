# Remora RT1052 for NVEM v5

This project builds Remora firmware for the NXP i.MX RT1052 used on the NVEM v5 controller.

## NVEM v5 hardware differences

The NVEM v5 uses a Winbond `W25Q16JVSSIQ` external serial NOR flash. It has a capacity of 16 Mbit, or 2 MiB. Earlier project settings assumed a 4 MiB external flash, so the boot configuration, runtime FlexSPI configuration, linker memory map, and JSON storage layout all had to be reduced accordingly.

The physical flash occupies `0x60000000` through `0x601FFFFF`. The final sixteen 4 KiB sectors are reserved as two 32 KiB regions for JSON upload and persistent configuration storage:

| Purpose | Flash offset | Absolute address | Size |
| --- | ---: | ---: | ---: |
| Firmware/XIP application | `0x000000-0x1EFFFF` | `0x60000000-0x601EFFFF` | 1,984 KiB |
| Temporary JSON upload | `0x1F0000-0x1F7FFF` | `0x601F0000-0x601F7FFF` | 32 KiB |
| Persistent JSON storage | `0x1F8000-0x1FFFFF` | `0x601F8000-0x601FFFFF` | 32 KiB |

The maximum uploaded JSON payload is 32,256 bytes. The remainder of the 32 KiB upload region is occupied by its 512-byte metadata header.

### Changes made for NVEM v5

- Tracked defaults are defined in `config/flash-layout.env`: 2 MiB of physical flash and 32 KiB per JSON region.
- The generated default `board/flash_layout.h` is tracked, so a fresh checkout can build directly in MCUXpresso IDE without first running a configuration script.
- `tools/configure-flash-layout.sh` validates the configured values, accepts environment overrides, regenerates `board/flash_layout.h`, and updates the MCUXpresso application length in `.cproject`.
- The ROM boot header, FlexSPI A1 configuration, and runtime FlexSPI controller all derive their capacity from `BOARD_FLASH_SIZE` in the generated header.
- The MCUXpresso application/linker region is limited to `0x1F0000` bytes, leaving the final 64 KiB outside the generated firmware image.
- JSON addresses in `source/configuration.h` are calculated from `BOARD_FLASH_SIZE`; changing that physical-size macro moves both reserved regions to the end of the device automatically.
- Compile-time checks enforce flash/sector alignment, JSON-region adjacency, metadata size, and the upper flash boundary.
- TFTP rejects uploads larger than the reserved 32 KiB region, and JSON lengths are checked before flash reads or writes.
- DMA descriptor addresses use an unsigned 32-bit address type, and volatile Ethernet receive data is copied explicitly. These changes allow the stricter Release configuration to compile without relying on Debug's `-fpermissive` option.
- The project metadata targets `MIMXRT1052xxxxB`, enables the external-flash XIP boot header, and uses DWARF-4 debug information for compatibility with the current MCU toolchain.

Do not edit `board/flash_layout.h` or the `.cproject` flash length directly. The checked-in versions contain the 2 MiB defaults needed for an IDE-only build. To change the layout, change the tracked defaults or provide the environment variables described below, then run the generator or build wrapper and commit the regenerated files when the new layout should become the project default.

## Headless MCUXpresso build

The following procedure was verified on macOS with MCUXpresso IDE 25.6.136. Adjust `MCUXPRESSO_IDE` for another installed version or platform. The project name used by the headless builder is `remora-rt1052-cpp`, not the older SDK example name embedded in some project metadata.

### Prerequisites

- MCUXpresso IDE with support for `MIMXRT1052xxxxB`.
- A writable Eclipse workspace directory separate from the project directory.
- The Eclipse project directory as the current directory—the directory directly containing `.project` and `.cproject`. Some checkouts have an outer and inner directory both named `Remora-RT1052-cpp`; in that case, enter the inner directory before building.

### Flash-layout configuration

The tracked defaults are:

```sh
NVEM_FLASH_SIZE_BYTES=0x200000
NVEM_JSON_REGION_SIZE_BYTES=0x8000
```

`NVEM_FLASH_SIZE_BYTES` is the physical external ROM capacity. `NVEM_JSON_REGION_SIZE_BYTES` is the size of each of the two reserved regions: one temporary upload region and one persistent storage region. Therefore, the application/linker capacity is:

```text
application size = ROM size - (2 * JSON region size)
```

The JSON region size includes the 512-byte upload metadata, so the maximum JSON document is `NVEM_JSON_REGION_SIZE_BYTES - 512` bytes. Both values may be supplied as hexadecimal or decimal byte counts and must meet the sector/alignment checks enforced by the generator.

#### Build examples

Build the tracked NVEM v5 default—2 MiB ROM with two 32 KiB JSON regions. This leaves `0x1F0000` bytes (1,984 KiB) for the application and supports JSON documents up to 32,256 bytes:

```sh
./tools/headless-build.sh Release
```

Build for a 4 MiB ROM while retaining the 32 KiB JSON regions. This leaves `0x3F0000` bytes (4,032 KiB) for the application and retains the 32,256-byte maximum JSON document size:

```sh
NVEM_FLASH_SIZE_BYTES=0x400000 \
./tools/headless-build.sh Release
```

Build for a 4 MiB ROM with two 64 KiB JSON regions. This leaves `0x3E0000` bytes (3,968 KiB) for the application and supports JSON documents up to 65,024 bytes:

```sh
NVEM_FLASH_SIZE_BYTES=0x400000 \
NVEM_JSON_REGION_SIZE_BYTES=0x10000 \
./tools/headless-build.sh Release
```

Decimal byte counts are also accepted. This example is equivalent to the tracked 2 MiB ROM and 32 KiB JSON layout:

```sh
NVEM_FLASH_SIZE_BYTES=2097152 \
NVEM_JSON_REGION_SIZE_BYTES=32768 \
./tools/headless-build.sh Debug
```

The ROM size must match the flash device actually installed on the board; increasing this value does not increase the capacity of a W25Q16 device. An override regenerates `board/flash_layout.h` and changes the `.cproject` linker region, so those generated values remain in the working tree after the build. Restore the tracked defaults with:

```sh
./tools/configure-flash-layout.sh
```

### Clean build

```sh
# If the current directory is the outer Remora-RT1052-cpp directory:
cd Remora-RT1052-cpp

# These files must exist here before invoking the wrapper:
test -f .project && test -f .cproject

./tools/headless-build.sh Debug
```

Use `./tools/headless-build.sh Release` for a Release build. The wrapper creates a fresh temporary Eclipse workspace by default, preventing stale imported project settings.

A successful build ends with `Build Finished. 0 errors`. The principal outputs are:

- `Debug/remora-rt1052-cpp.axf` — ELF firmware with symbols.
- `Debug/remora-rt1052-cpp.map` — linker map and memory usage.
- `Debug/remora-rt1052-cpp_Debug_memory.ld` — generated memory layout; with the defaults, `BOARD_FLASH` should have `LENGTH = 0x1f0000`.

Set `MCUXPRESSO_CLI` if the executable is not at the verified macOS location:

```sh
MCUXPRESSO_CLI="/path/to/mcuxpressoide" ./tools/headless-build.sh Debug
```

To reuse a workspace, set `MCUXPRESSO_WORKSPACE` to a writable directory outside the project. The wrapper imports the project only when it is not already present:

```sh
MCUXPRESSO_WORKSPACE=/tmp/remora-workspace ./tools/headless-build.sh Release
```

### Generate a raw binary

The current MCUXpresso post-build setting runs `size`, but its `objcopy` command is commented out. Generate the binary explicitly after a successful build:

```sh
MCUXPRESSO_IDE="/Applications/MCUXpressoIDE_25.6.136/ide"
OBJCOPY="$(find "$MCUXPRESSO_IDE/plugins" \
  -path '*/tools/bin/arm-none-eabi-objcopy' -type f -print -quit)"

test -x "$OBJCOPY"
"$OBJCOPY" -O binary \
  Debug/remora-rt1052-cpp.axf \
  Debug/remora-rt1052-cpp.bin
```

Before programming hardware, check the build log or generated map and confirm that the default `BOARD_FLASH` application region ends at `0x601F0000`. This ensures the firmware image cannot overlap the JSON regions.
