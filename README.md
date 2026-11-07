# DOOM — Garmin Instinct 3 Solar (Connect IQ watch app)

A Connect IQ watch app that brings a Doom-like experience to the Garmin
Instinct 3 Solar (black & white Memory-In-Pixel display, 176x176). It is
written entirely in Monkey C for the Connect IQ SDK.

## Important: what this is (and isn't)

Connect IQ apps run Monkey C bytecode on the watch — the SDK does not allow
compiling arbitrary C code, and apps have no general file-system access, so the
original id Tech 1 engine cannot be loaded with a real DOOM WAD on this
platform. This port is therefore a **Doom-inspired raycasting engine**
(Wolf3D/Doom style: tile map, player, hitscan shooting, doors, enemies)
written from scratch in Monkey C, targeted at the Instinct 3's 176x176
two-color display, with the exact control mapping you asked for.

## Controls

| Action | Button / gesture |
|--------|------------------|
| Move forwards | **UP** |
| Move backwards | **DOWN** (when no turn direction is selected) |
| Turn 10° | **BACK** to pick a direction (shown at top of screen: `TURN:<` / `TURN:>`), then **DOWN** turns 10° in that direction. With nothing selected, DOWN walks backwards. |
| Fire | **SELECT** (GPS button, `KEY_START`/`KEY_ENTER`) |
| Open door | **LIGHT** button. If your watch swallows the LIGHT button (firmware uses it for the backlight), **hold DOWN** instead — it opens the door too. |
| In-game menu | **MENU button** (toggles the pause menu: RESUME / QUIT). On devices that deliver press/release pairs a **long hold (~0.6s) of UP** also opens it. Choosing QUIT exits the app entirely. |
| Enemies | Black imps with white eyes (6 on the map). Distance-shaded walls/imps: solid up close, checkerboard dither for mid-range, sparse dots near the fog edge. Line of sight is wall-checked, so imps hide behind corners. |
| Quit the app | From the pause menu, choose **QUIT** |

HUD at the top shows the selected turn direction, HP and AMMO.

## Instinct 3 runtime findings (firmware 14.15 / CIQ 6.0.2)

These were established by pushing probe apps to the simulator and watching the
stack traces — all are why the first versions crashed on launch:

1. **Watchdog**: a callback that runs too long (e.g. naive 0.06-step ray
   marching over all 88 columns) is killed with
   `Watchdog Tripped Error - Code Executed Too Long`. The renderer therefore
   uses DDA grid traversal (max 32 grid crossings/ray) and 2px wall slices.
2. **`Dc.drawText` signature is `(x, y, font, text, justification)`** — the
   text draws in the current foreground color (`setColor`); there is no color
   parameter.
3. **Every built-in `Graphics.FONT_*` constant (bitmap `FONT_SMALL` etc. AND
   `FONT_SYSTEM_*`) throws an uncatchable `Invalid Font Specified` at runtime
   on Instinct 3.** `Graphics.getVectorFont` is also unavailable on this
   device (it is `@since 4.2.1` but absent from the Instinct 3 device API
   binding). The app therefore ships **custom bitmap fonts** as Connect IQ
   font resources (`resources/fonts`, BMText format): a 6x9 px mono font for
   the HUD and a 2x version for the menu. They load via
   `Ui.loadResource(Rez.Fonts.DoomSmall/DoomBig)` and are rejected nowhere —
   this is the only working text API found on the device.
   `tools/genfont.py` (PIL) regenerates the font resources.
4. **Key codes on Instinct 3** (runtime values):
   `KEY_UP=13, KEY_DOWN=8, KEY_ENTER=4, KEY_START=18, KEY_ESC=5,
   KEY_LIGHT=1, KEY_MENU=7`. Button taps arrive as a single
   `PRESS_TYPE_ACTION` event (`getType()==2`), not DOWN/UP pairs, so the
   hold timer is armed only on `PRESS_TYPE_DOWN` — arming it on ACTION
   popped the menu 600ms after every press. `mtMinApiLevel` is 4.2.1 in
   `manifest.xml` (3.2.0 downlevels symbols away and made `KeyCode`-typed
   params reject the constants).

## Project layout

```
manifest.xml        Connect IQ manifest (product id, min API level)
monkey.jungle       Jungle build config
build.settings      CIQ Studio project settings
source/
  DoomApp.mc        App.AppBase entry point
  DoomView.mc       View, render loop, input, in-game menu
  DoomDelegate.mc   InputDelegate: key handling + hold detection
  DoomEngine.mc     Raycasting engine: map, player, movement, shooting, doors
resources/
  drawables/        launcher icon
  strings/          app name
  fonts/            custom bitmap fonts (BMText) — the ONLY text API that
                    works on Instinct 3 (see "runtime findings" above)
tools/
  genfont.py        regenerates resources/fonts with PIL (embedded bitmap
                    font -> BMText fnt + atlas png, 1x and 2x)
store-art/
  cover_loom.png    Connect IQ Store cover (500x500, hell/blood theme)
  screen_idk.png    Connect IQ Store shot
bin/                build outputs (.prg/.iq) — gitignored
```

## Signing keys

`developer_key4096.der` / `.pem` are **not** in the repository — see
[BUILD.md](BUILD.md) ("Developer keys") to generate your own before building.

## Build & run

You need the Garmin Connect IQ SDK installed (`monkeyc`, `monkeydo`, and a
developer key `developer_key.der`). Device definitions must be installed at
`~/.Garmin/ConnectIQ/Devices/`.

```bash
cd /home/arturo/garmin/doom-instinct3
export PATH=/path/to/connectiq-sdk-9.2.0/bin:$PATH
export CONNECT_IQ_DEVICES_HOME=~/.Garmin/ConnectIQ/Devices

# 1. Build the PRG (sideload-ready, signed) — uses the 4096-bit key
monkeyc -d instinct3solar45mm -f monkey.jungle -o bin/Doom.prg -y developer_key4096.der -w

# 2. Run in the Connect IQ simulator
connectiq &                       # start the simulator (needs X11 display)
monkeydo bin/Doom.prg instinct3solar45mm
```

### Device id

The manifest declares product `instinct3solar45mm` — this SDK product id covers
both Instinct 3 Solar 45mm and 50mm (176×176 MIP, black & white, API level 5.1).

### Building the .iq for the Connect IQ Store

```bash
monkeyc -e -r -o bin/Doom.iq -f monkey.jungle -y developer_key4096.der -w
```

**Important:** The Connect IQ SDK's `.iq` export requires a **4096-bit RSA key**.
Generate it with:

```bash
openssl genrsa -out developer_key4096.pem 4096
openssl pkcs8 -topk8 -in developer_key4096.pem -outform DER -nocrypt -out developer_key4096.der
```

A 2048-bit key works for `.prg` sideloading but the `.iq` export will fail
with "Failed to extract developer signature for export" unless you use 4096-bit.

Steps for store submission:

1. Build `bin/Doom.iq` with the 4096-bit key (see above)
2. Register at https://developer.garmin.com/connect-iq/
3. Optionally replace `developer_key4096.der` with your Garmin-issued key
4. Upload `bin/Doom.iq` at https://developer.garmin.com/connect-iq/submit-an-app/

### Installing on a real watch

Sideload the produced `bin/Doom.prg` through the Connect IQ app on your phone
(or via Garmin Express), then launch "DOOM - Instinct 3" from the watch's app
list.

## Notes

- Monkey C is duck-typed; all locals and members use `var`, instance access via
  `me`/`self`. If your SDK enforces strict typing (`monkeyc -l`), add `as`
  type annotations where needed.
- Long-press detection uses `ButtonEventArgs.isLongPress` guarded by a
  try/catch fallback; on SDK builds without it, holds fall back to plain
  presses (DOWN-hold still opens doors via the timer-free path — actually it
  goes through `isLongPress` too; see `isLongPress()` in DoomView.mc).
- `Ui.popView(Ui.SLIDE_IMMEDIATE)` on the base view terminates the app on
-device ("backing out of the base page"); in the simulator use the simulator's
  stop/kill button.
