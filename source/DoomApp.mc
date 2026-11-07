//
// DOOM for Garmin Connect IQ - Instinct 3 Solar (black & white, 176x176)
//
// Application entry point. Connect IQ watch apps are driven by
// App.AppBase.getInitialView(), which returns the view stack to push on launch.
//

using Toybox.Application as App;
using Toybox.WatchUi as Ui;

class DoomApp extends App.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    // Return the initial view of the application. The second element is the
    // input delegate — without it the app would render but receive no buttons.
    function getInitialView() {
        var view = new DoomView();
        return [view, new DoomDelegate(view)];
    }
}
