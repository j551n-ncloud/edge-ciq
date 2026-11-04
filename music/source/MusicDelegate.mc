import Toybox.Lang;
import Toybox.WatchUi;

// A tap hits the button under the finger.
class MusicDelegate extends WatchUi.BehaviorDelegate {
    hidden var _view as MusicView;

    function initialize(view as MusicView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        var xy = evt.getCoordinates();
        _view.tapAt(xy[0], xy[1]);
        return true;
    }
}
