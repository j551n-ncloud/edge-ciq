import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class MusicApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        var v = new MusicView();
        return [v, new MusicDelegate(v)];
    }
}
