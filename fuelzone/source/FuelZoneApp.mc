import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// (:background) because the live-ride sender (LiveService) runs in a
// background process that starts from this class too.
(:background)
class FuelZoneApp extends Application.AppBase {
    hidden var _view = null;

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        var v = new FuelZoneView();
        _view = v;
        return [v];
    }

    function getServiceDelegate() {
        return [new LiveService()];
    }

    // HTTP status of the last live-ride post, for the log.
    function onBackgroundData(data) as Void {
        System.println("live sent: " + data);
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
