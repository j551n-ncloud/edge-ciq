import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class BriefingApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        var v = new BriefingView();
        return [v, new BriefingDelegate(v)];
    }
}
