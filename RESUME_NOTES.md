# RESUME NOTES — Loom/DOOM on Instinct 3 Solar

## STATUS: WORKING in the simulator (Oct 28, 2026)

The app launches, renders the raycast world, and handles buttons, all verified
in the simulator with the 4096-key build. Both artifacts are built & signed:

- `bin/Doom.prg` (sideload, ~107 KB)
- `bin/Doom.iq` (Connect IQ Store export, ~27 KB)

## Debug pipeline (survives reboot if /tmp is recreated)

SDK 9.2.0 must live at `/tmp/opencode/ciq-sdk-9.2.0` (re-download:
https://developer.garmin.com/downloads/connect-iq/sdks/connectiq-sdk-lin-9.2.0-2026-06-09-92a1605b2.zip).
After unzip: `mv extract bin-path...`, then REPLACE `bin/shell` with a 2-line
wrapper calling `bin/shell.orig` (`exec .../shell.orig "$@"`) — otherwise
`monkeydo` hangs probing a fake sandbox port.

```bash
export PATH=/tmp/opencode/ciq-sdk-9.2.0/bin:$PATH
export CONNECT_IQ_DEVICES_HOME=~/.Garmin/ConnectIQ/Devices
# Xephyr must be nested on the real Xorg display :0 (user's desktop session):
DISPLAY=:0 Xephyr :99 -screen 400x400x16 &
setsid env DISPLAY=:99 /tmp/opencode/ciq-sdk-9.2.0/bin/connectiq >/tmp/opencode/ciq.log 2>&1 < /dev/null &
cd ~/garmin/doom-instinct3 && timeout 45 monkeydo bin/Doom.prg instinct3solar45mm
# crash stacks print on monkeydo stdout; also: /tmp/com.garmin.connectiq/GARMIN/APPS/LOGS/CIQ_LOG.YML
# screenshot: DISPLAY=:99 xwd -root -silent | convert xwd:- png:shot.png
# buttons: the Instinct 3 sim maps X keyboard: Escape=ESC, Return=ENTER, arrows
# are unreliable. Mouse-click the watch buttons on screen (input areas in
# Devices/instinct3solar45mm/simulator.json: up-area=(2..35,212..280) — click =
# KEY_UP tap, hold = KEY_MENU; down-area=(11..69,300..368)=KEY_DOWN; enter-rock-
# er area (right top)=onSelect→KEY_ENTER; esc=(right-middle)=KEY_ESC).
```

## Bugs fixed on the way to "launches cleanly"

1. **Watchdog kill** — 0.06-step ray marching x 88 cols exceeded the UI
   watchdog. Fix: DDA grid traversal (max 32 crossings/ray), radians (cos/sin
   were being handed degrees before), COLUMN_STEP=2 slices.
2. **drawText signature** is `(x, y, font, text, justification)` — text is
   drawn in the current foreground color; there is NO color parameter.
3. **ALL built-in fonts throw at runtime on Instinct 3** (bitmap FONT_* AND
   FONT_SYSTEM_*; `Invalid Font Specified`, uncatchable). getVectorFont is
   not in the Instinct 3 device API at all. Fix: custom BMText bitmap font
   resources loads via Ui.loadResource (see tools/genfont.py). Note for
   future font work: BMTexture cells must be width==xadvance, and texture
   png must be plain L or RGB (LA mode renders garbled).
4. **Input**: taps arrive as PRESS_TYPE_ACTION only (type=2); no DOWN/UP.
   Hold timer must be armed ONLY on PRESS_TYPE_DOWN (arming on ACTION pops
   the menu 600ms after every press). Runtime key values:
   UP=13 DOWN=8 ENTER=4 START=18 ESC=5 LIGHT=1 MENU=7 RESET=20.
   MENU button (hold or press) toggles the pause menu now.
5. **Map data**: player originally spawned INSIDE a wall ((2.5,2.5) is a wall
   tile) → solid black view; now (2.5,1.5). MAP_H was 16 but the map has 12
   rows; enemies were in walls — fixed.
7. **Sprites**: enemy sprites never showed because the FOV check was
   `(rel < 0 ? -rel : rel > fovRad/2)` — precedence made every enemy on the
   LEFT half of the view always skip. Now `(rel<0 ? -rel : rel) > halfFov`,
   plus wall occlusion via castRay and clamping to the viewport.
   Enemies render as black imps (solid silhouette, two white eye pixels,
   white "fade" stripes at distance — dithered imp bodies camouflage into
   dithered walls, so keep the outline solid).
8. **Ring/bezel safe area** (user report from real hardware): the Instinct 3
   status ring covers the top arc and the curved bezel clips the corners,
   so HUD text must sit in a centered strip at the BOTTOM. View layout:
   TOP_RES_Y=34 (DoomEngine) / HUD_H (DoomView) top reserve, BOT_RES_Y /
   HUD_SAFE=26 bottom text strip; HUD line 1 = HP+AMMO at h-22, line 2 =
   turn indicator T:/T</T> at h-11, both centered via TEXT_JUSTIFY_CENTER.
9. **Distance shading**: drawShadedColumn() renders wall columns by shade =
   1 - perp/FOG_DIST: >0.60 solid 2px, >0.25 checkerboard dither (2px bands
   every 6px, phase alternates per column), else sparse dots every 12px.
6. Manifest minApiLevel 3.2.0 downleveled symbols away (getVectorFont
   mystery); now 4.2.1.

## Store assets (in bin/)

- cover_loom.png 500x500 (hell/blood theme, <300KB)
- screen_idk.png (white bg, black "idk" text, <150KB)
- app id f60aa97406de642bea87e32d8e972c8a, name "Loom"

## If the app STILL crashes on real hardware

- The sim runtime ≈ firmware 14.15, so all above applies. Stack traces from
  the watch land in the Connect IQ log the user can pull (or set `.syslog`).
- Probe trick: temporarily add `Sys.println` breadcrumbs — they DO reach
  monkeydo stdout in the sim (and are no-ops on device).
