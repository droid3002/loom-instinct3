//
// DOOM for Garmin Connect IQ - Instinct 3 Solar
// Main view: render loop (timer driven) + input handling + in-game menu.
//
// CONTROLS (see README.md):
//   UP          : move forward
//   DOWN        : turn 10 deg in selected direction, else move back
//   BACK        : cycle selected turn direction (shown at top of screen)
//   SELECT/GPS  : fire
//   LIGHT       : open door (if the watch swallows the LIGHT button, hold DOWN)
//   hold UP     : in-game menu (RESUME / QUIT; QUIT exits the app)
//

using Toybox.Graphics as Gfx;
using Toybox.WatchUi as Ui;
using Toybox.Timer as Timer;
using Toybox.Lang as Lang;

const HUD_H = 34;       // top reserve: view starts below the status ring arc
const HUD_SAFE = 26;    // bottom reserve: HUD text strip above the bezel edge
// The firmware clamps tiny timer intervals (watchdog warns under ~100ms).
const TIMER_MS = 200;

class DoomView extends Ui.View {
    var mEngine;
    var mTimer;
    var mMenuOpen = false;
    var mMenuSel = 0;       // 0 = Resume, 1 = Quit
    var mHitFlash = 0;
    var mW = 0;
    var mH = 0;
    var mFontS = null;      // custom BMFont resource; the Instinct 3 firmware
    var mFontB = null;      // rejects every built-in FONT_* constant at runtime

    function initialize() {
        View.initialize();
        mEngine = new DoomEngine();
        mEngine.initialize();
        mTimer = new Timer.Timer();
        mFontS = Ui.loadResource(Rez.Fonts.DoomSmall);
        mFontB = Ui.loadResource(Rez.Fonts.DoomBig);
    }

    function drawTextS(dc, x, y, text) {
        if (mFontS != null) {
            dc.drawText(x, y, mFontS, text, Gfx.TEXT_JUSTIFY_LEFT);
        }
    }

    function drawTextB(dc, x, y, text) {
        if (mFontB != null) {
            dc.drawText(x, y, mFontB, text, Gfx.TEXT_JUSTIFY_LEFT);
        }
    }

    function onShow() {
        mTimer.start(method(:onTimer), TIMER_MS, true);
    }

    function onHide() {
        mTimer.stop();
    }

    function onTimer() {
        if (mHitFlash > 0) {
            mHitFlash = mHitFlash - 1;
        }
        Ui.requestUpdate();
    }

    // ---- Input entry points (called by DoomDelegate) ----

    function isMenuOpen() {
        return mMenuOpen;
    }

    // Key while the in-game menu is open. Returns true (event consumed),
    // so BACK cannot exit the app from inside the menu.
    function menuKey(key) {
        if (key == Ui.KEY_UP) {
            mMenuSel = 0;
        } else if (key == Ui.KEY_DOWN) {
            mMenuSel = 1;
        } else if (key == Ui.KEY_MENU) {
            // MENU (or its hold on older firmware) closes the menu = resume
            mMenuOpen = false;
        } else if (key == Ui.KEY_ENTER || key == Ui.KEY_START) {
            if (mMenuSel == 0) {
                mMenuOpen = false;
            } else {
                quitGame();
            }
        }
        Ui.requestUpdate();
        return true;
    }

    function openMenu() {
        mMenuOpen = true;
        mMenuSel = 0;
        Ui.requestUpdate();
    }

    function openDoor() {
        mEngine.toggleDoor();
        Ui.requestUpdate();
    }

    // One press of a game key (no hold distinction here).
    function keyAction(key) {
        if (key == Ui.KEY_UP) {
            mEngine.moveForward();
        } else if (key == Ui.KEY_DOWN) {
            if (mEngine.getTurn() != :none) {
                // Turn 10 deg in the selected direction
                if (mEngine.getTurn() == :left) {
                    mEngine.turn(-10);
                } else {
                    mEngine.turn(10);
                }
            } else {
                // No selection: move backwards
                mEngine.moveBack();
            }
        } else if (key == Ui.KEY_ESC) {
            // BACK: cycle selected turn direction, shown at top
            mEngine.cycleTurn();
        } else if (key == Ui.KEY_START || key == Ui.KEY_ENTER) {
            // Fire: GPS (START) / SELECT (ENTER) button
            mEngine.fire();
            mHitFlash = 4;
        } else if (key == Ui.KEY_LIGHT) {
            // Open door if the LIGHT button is delivered
            mEngine.toggleDoor();
        } else {
            return;
        }
        Ui.requestUpdate();
    }

    function quitGame() {
        // Pop the base view; backing out of the base page terminates the app.
        Ui.popView(Ui.SLIDE_IMMEDIATE);
    }

    function drawHud(dc) {
        // The ring covers the top arc and the bezel clips the screen corners,
        // so the HUD lives in a centered strip at the bottom.
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_WHITE);
        drawTextC(dc, mW / 2, mH - 22,
            "HP:" + mEngine.getHealth() + "  AMMO:" + mEngine.getAmmo());
        var turnText = "T:-";
        if (mEngine.getTurn() == :left) {
            turnText = "T:<";
        } else if (mEngine.getTurn() == :right) {
            turnText = "T:>";
        }
        drawTextC(dc, mW / 2, mH - 11, turnText);
    }

    // Centered text in the safe strip (mFontS guards against null loads).
    function drawTextC(dc, cx, y, text) {
        if (mFontS != null) {
            dc.drawText(cx, y, mFontS, text, Gfx.TEXT_JUSTIFY_CENTER);
        }
    }

    function drawMenu(dc) {
        var mw = 118;
        var mh = 76;
        var mx = Math.floor((mW - mw) / 2).toNumber();
        var my = Math.floor((mH - mh) / 2).toNumber();
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
        dc.fillRectangle(mx, my, mw, mh);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        drawTextB(dc, mx + 10, my + 6, "INGAME MENU");
        var items = ["RESUME", "QUIT"];
        var i;
        var item;
        for (i = 0; i < items.size(); i++) {
            item = items[i];
            if (i == mMenuSel) {
                item = "> " + item;
            }
            drawTextB(dc, mx + 10, my + 32 + i * 24, item);
        }
    }

    function onUpdate(dc) {
        View.onUpdate(dc);
        mW = dc.getWidth();
        mH = dc.getHeight();
        var viewH = mH - HUD_H - HUD_SAFE;

        // Clear screen (white paper)
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_WHITE);
        dc.clear();

        // Game world below the HUD
        mEngine.render(dc, 0, HUD_H, mW, viewH);
        mEngine.renderSprites(dc, 0, HUD_H, mW, viewH);

        // Crosshair at screen center
        var cx = Math.floor(mW / 2).toNumber();
        var cy = Math.floor(HUD_H + viewH / 2).toNumber();
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_WHITE);
        dc.drawLine(cx - 3, cy, cx + 3, cy);
        dc.drawLine(cx, cy - 3, cx, cy + 3);

        drawHud(dc);

        // Muzzle-flash style hit feedback (whole-screen inversion for a few frames)
        if (mHitFlash > 0) {
            dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
            dc.fillRectangle(0, 0, mW, mH);
        }

        // Pause menu overlay
        if (mMenuOpen) {
            drawMenu(dc);
        }
    }
}
