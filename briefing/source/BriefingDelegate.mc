import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

// Single tap = refresh the brief, double tap anywhere = bell. A single tap
// waits Ui.DOUBLE_TAP_MS to make sure no second tap follows.
class BriefingDelegate extends WatchUi.BehaviorDelegate {
    hidden var _view as BriefingView;
    hidden var _pending as Array<Number>? = null;
    hidden var _timer as Timer.Timer = new Timer.Timer();

    function initialize(view as BriefingView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        if (_pending != null) {
            _timer.stop();
            _pending = null;
            _view.ringBell();
            return true;
        }
        _pending = evt.getCoordinates();
        _timer.start(method(:fireTap), Ui.DOUBLE_TAP_MS, false);
        return true;
    }

    function fireTap() as Void {
        var xy = _pending;
        _pending = null;
        if (xy != null) {
            _view.refresh();
        }
    }
}
