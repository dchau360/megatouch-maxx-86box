# Megatouch Maxx (Vic_VP Mod) — Mac & Linux Launcher

Run the **Vic_VP modded Megatouch Maxx** arcade touchscreen game on macOS and Linux using [86Box](https://86box.net/) PC emulation.

This repo contains only the launcher scripts and machine config. The game disk image, BIOS ROMs, and emulator binary are **not included** and must be obtained from the Vic_VP Megatouch Maxx distribution separately.

## What's in this repo

| File | Purpose |
|------|---------|
| `start_mac.sh` | macOS launcher — downloads 86Box, patches it, launches the game |
| `start_linux.sh` | Linux launcher — auto-detects or downloads 86Box, launches the game |
| `86box.cfg` | 86Box machine configuration (Pentium 166, S3 Trio64, 3M MicroTouch) |
| `nvr/tx97.nvr` | CMOS settings for the emulated ASUS TX97 motherboard |

## Required files (not included)

These files come from the **Vic_VP Megatouch Maxx distribution** and must be placed in the same directory as the scripts:

| File | Size | Description |
|------|------|-------------|
| `HardDisk.img` | ~3.7 GB | Game disk image — the Vic_VP modded Megatouch Maxx |
| `roms/` | ~7 MB | 86Box BIOS ROM files for the emulated hardware |
| `nvr/tx97.bin` | ~120 KB | ASUS TX97 motherboard BIOS ROM |

Once you have those, the directory should look like:

```
megatouch-maxx/
  start_mac.sh
  start_linux.sh
  86box.cfg
  HardDisk.img        ← from Vic_VP distribution
  nvr/
    tx97.bin          ← from Vic_VP distribution
    tx97.nvr          ← included in this repo
  roms/               ← from Vic_VP distribution
    ...
```

## Running on macOS

```bash
chmod +x start_mac.sh
./start_mac.sh
```

The script will:
1. Download the latest 86Box release if not already present
2. Patch the 86Box binary to fix two macOS-specific bugs (see below)
3. Lock the config read-only so 86Box can't overwrite settings on exit
4. Launch the game and bring it to the foreground

**Tested on**: macOS with Apple Silicon (M1/M2/M3)

## Running on Linux

> **Untested** — this script has not been verified on a real Linux system. It may work but could need adjustments. Reports and PRs welcome.

```bash
chmod +x start_linux.sh
./start_linux.sh
```

The script auto-detects 86Box via AppImage, system install, or Flatpak. If none is found it downloads the latest AppImage automatically.

## macOS patches applied

The `start_mac.sh` script applies two fixes to the downloaded 86Box binary:

### 1. HiDPI / NSHighResolutionCapable
Sets `NSHighResolutionCapable` to `false` in `Info.plist` so macOS uses a 1x NSView. Without this, coordinate scaling issues can occur on Retina displays.

### 2. Mouse button bug (ARM64 binary patch)
86Box 5.3 has a macOS-specific bug in `qt_rendererstack.cpp` where absolute mouse button events (required for the 3M MicroTouch touchscreen) are silently dropped on the primary monitor. The code checks `m_monitor_index >= 1` (always false on a single monitor) and `mouse_tablet_in_proximity` (always false without tablet hardware), so `mouse_set_buttons_ex()` is never called and clicks do nothing.

The script patches 4 ARM64 instructions in `mousePressEvent` and `mouseReleaseEvent` to NOP out these broken conditions. This fix has been submitted upstream: [86Box/86Box#7026](https://github.com/86Box/86Box/pull/7026).

Once that PR is merged, the binary patch step becomes a no-op.

## Emulated hardware

| Component | Emulated hardware |
|-----------|------------------|
| Motherboard | ASUS TX97 (Socket 7) |
| CPU | Intel Pentium P54C @ 166 MHz |
| RAM | 64 MB |
| Video | S3 Trio64V2/DX PCI |
| Sound | C-Media CMI8738 |
| Touchscreen | 3M MicroTouch Serial (COM1, 9600 baud) |

The guest OS is an embedded Linux 2.4 image with 3M's TWDrv kernel module and TWXinput X11 driver for touchscreen input.
