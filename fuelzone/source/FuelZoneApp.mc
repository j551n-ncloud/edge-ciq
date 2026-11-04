import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class FuelZoneApp extends Application.AppBase {
    hidden var _view as FuelZoneView?;

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        var v = new FuelZoneView();
        _view = v;
        return [v];
    }

    // Settings changed in the Garmin Connect app.
    function onSettingsChanged() as Void {
        var v = _view;
        if (v != null) {
            v.loadSettings();
        }
        WatchUi.requestUpdate();
    }
}
