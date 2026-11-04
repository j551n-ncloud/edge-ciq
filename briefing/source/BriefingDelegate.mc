import Toybox.Lang;
import Toybox.WatchUi;

// A tap refreshes the brief.
class BriefingDelegate extends WatchUi.BehaviorDelegate {
    hidden var _view as BriefingView;

    function initialize(view as BriefingView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        _view.refresh();
        return true;
    }
}
