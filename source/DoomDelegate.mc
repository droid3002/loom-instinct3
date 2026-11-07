//
// DOOM for Garmin Connect IQ - Instinct 3 Solar
// Input delegate. Views never receive key events in Connect IQ; they go to
// the delegate returned with the view from AppBase.getInitialView().
//
// CONTROLS:
//   UP press          : move forward
//   UP hold (~0.6s)   : in-game menu (RESUME / QUIT)
//   DOWN press        : turn 10 deg in selected direction, else move back
//   DOWN hold         : open door (fallback when LIGHT is not delivered)
//   BACK press        : cycle selected turn direction (consumed, app stays)
//   GPS/START or ENTER: fire
//   LIGHT             : open door (if the firmware routes it to CIQ)
//

using Toybox.WatchUi as Ui;
using Toybox.Timer as Timer;

const HOLD_MS = 600;

class DoomDelegate extends Ui.InputDelegate {
    var mView;
    var mHoldTimer;
    var mHeldKey = 0;      // key currently pressed (0 = none)

    function initialize(view) {
        InputDelegate.initialize();
        mView = view;
        mHoldTimer = new Timer.Timer();
    }

    // Arm the hold detector for the key being pressed down.
    function startHold(key) {
        mHeldKey = key;
        mHoldTimer.start(method(:onHoldTimeout), HOLD_MS, false);
    }

    function stopHold() {
        mHeldKey = 0;
        mHoldTimer.stop();
    }

    // Fired while the key is still physically held (one-shot timer).
    function onHoldTimeout() {
        if (mHeldKey == Ui.KEY_UP) {
            mHeldKey = 0;
            mView.openMenu();
        } else if (mHeldKey == Ui.KEY_DOWN) {
            mHeldKey = 0;
            mView.openDoor();
        }
    }

    function onKey(keyEvent) {
        var key = keyEvent.getKey();
        var ptype = keyEvent.getType();

        // While the menu is open, consume everything: the menu never lets
        // BACK through, so it cannot quit the app by accident.
        if (mView.isMenuOpen()) {
            return mView.menuKey(key);
        }

        // Key released: end hold detection.
        if (ptype == Ui.PRESS_TYPE_UP) {
            stopHold();
            return true;
        }

        // PRESS_TYPE_DOWN (0) = press, PRESS_TYPE_UP (1) = release,
        // PRESS_TYPE_ACTION (2) = tap (some runtimes only send ACTION).
        // Hold detection needs a real DOWN/UP pair, so hold is armed only on
        // DOWN; ACTION always acts as a plain tap (a key held down also
        // produces repeated ACTION on some devices - but no UP - so arming
        // hold on ACTION would pop the menu after every press on those).
        if (ptype == Ui.PRESS_TYPE_DOWN || ptype == Ui.PRESS_TYPE_ACTION) {
            stopHold();
            if (key == Ui.KEY_UP) {
                mView.keyAction(key);
                if (ptype == Ui.PRESS_TYPE_DOWN) {
                    startHold(key);
                }
                return true;
            } else if (key == Ui.KEY_DOWN) {
                mView.keyAction(key);
                if (ptype == Ui.PRESS_TYPE_DOWN) {
                    startHold(key);
                }
                return true;
            } else if (key == Ui.KEY_ESC) {
                // Consumed on purpose: BACK must not exit the game.
                mView.keyAction(key);
                return true;
            } else if (key == Ui.KEY_START || key == Ui.KEY_ENTER) {
                mView.keyAction(key);
                return true;
            } else if (key == Ui.KEY_LIGHT) {
                mView.keyAction(key);
                return true;
            } else if (key == Ui.KEY_MENU) {
                // Instinct 3 has a physical MENU button: toggle the pause menu.
                stopHold();
                if (mView.isMenuOpen()) {
                    mView.menuKey(key);   // MENU closes the menu (resume)
                } else {
                    mView.openMenu();
                }
                return true;
            }
        }
        return false;
    }
}
