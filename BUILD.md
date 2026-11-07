# Build instructions for DOOM — Instinct 3 (Connect IQ)

## Prerequisites

Garmin Connect IQ SDK 9.2.0 (or later) installed and on your PATH:
`monkeyc`, `monkeydo`, `connectiq`.

Device definitions must be installed at `~/.Garmin/ConnectIQ/Devices/`.
The SDK zip no longer bundles them — download the `devices.tar.gz` bundle
(e.g. from https://github.com/DuckSoft/setup-connectiq-actions) and extract:

```bash
mkdir -p ~/.Garmin/ConnectIQ/Devices
tar -xzf devices.tar.gz -C ~/.Garmin/ConnectIQ/Devices
```

## Developer keys

A developer key (`developer_key.der`) is required for signing. Generate one:

```bash
# For .prg builds (sideload/testing) — 2048-bit RSA is fine:
openssl genrsa -out developer_key.pem 2048
openssl pkcs8 -topk8 -in developer_key.pem -outform DER -nocrypt -out developer_key.der

# For .iq export (Connect IQ Store) — REQUIRES 4096-bit RSA:
openssl genrsa -out developer_key4096.pem 4096
openssl pkcs8 -topk8 -in developer_key4096.pem -outform DER -nocrypt -out developer_key4096.der
```

**Critical finding:** The Connect IQ SDK's `.iq` export (`-e` flag) requires a
**4096-bit RSA key**. With a 2048-bit key, the export fails with
"Failed to extract developer signature for export." This is an SDK requirement
for the `rsa-4096` signature format used in the IQ package manifest.

## Build the .prg (sideload / test on watch)

```bash
cd /home/arturo/garmin/doom-instinct3
export PATH=/path/to/connectiq-sdk-9.2.0/bin:$PATH
export CONNECT_IQ_DEVICES_HOME=~/.Garmin/ConnectIQ/Devices

monkeyc -d instinct3solar45mm -f monkey.jungle -o bin/Doom.prg -y developer_key4096.der -w
```

**BUILD SUCCESSFUL** → `bin/Doom.prg` (signed, ready to sideload to the watch)

## Build the .iq (for Connect IQ Store upload)

```bash
monkeyc -e -r -o bin/Doom.iq -f monkey.jungle -y developer_key4096.der -w
```

Produces `bin/Doom.iq` (7-zip archive format, ~20KB), ready to upload at
https://developer.garmin.com/connect-iq/submit-an-app/

**Note:** Even with a self-generated 4096-bit key, the `.iq` file builds
successfully. When you register with the Garmin developer portal, replace
`developer_key4096.der` with your Garmin-issued key and re-run the export.

## Run in the simulator

```bash
connectiq &              # start Connect IQ simulator (once, needs X11 display)
monkeydo bin/Doom.prg instinct3solar45mm
```

If running headless, start a virtual display first (e.g. `Xephyr :99 -screen 400x400x16 &
` then `DISPLAY=:99 connectiq &`).

## Project files

```
manifest.xml                  Connect IQ manifest (watch-app, Instinct 3 Solar)
monkey.jungle                 Jungle build config
source/
  DoomApp.mc                  App.AppBase entry point
  DoomView.mc                 View, render loop, input, in-game menu
  DoomEngine.mc               Raycasting engine (map, player, shooting, doors)
resources/
  drawables/icon.png          62x62 launcher icon
  drawables/drawables.xml     Bitmap resource definition
  strings/strings.xml         App name string
bin/Doom.prg                  Compiled, signed PRG (sideload-ready)
developer_key.der             Your signing key
README.md / BUILD.md          Documentation
```

## Notes

- `minApiLevel="4.2.1"` — confirmed working with SDK 9.2.0 on `instinct3solar45mm` (was 3.2.0, but that downlevels away symbols since 4.2.1 such as the KeyCode/font bindings the app needs)
- The SDK's `instinct3solar45mm` product id covers both Instinct 3 Solar 45mm
  and 50mm (176×176 MIP, black & white)
- Physical button constants used: `KEY_UP`, `KEY_DOWN`, `KEY_ESC`, `KEY_ENTER`,
  `KEY_LIGHT` (Instinct 3 Solar has no separate LIGHT key in CIQ — firmware
  consumes it for the backlight; hold-DOWN is the door fallback)
- Hold-UP detection uses `args.isLongPress` with a try/catch fallback
