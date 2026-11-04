import Toybox.Application;
import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;

// Background sender for the live ride: every 5 min (Garmin's minimum) posts
// the latest snapshot the ride screen saved ("live" in Storage) to the glance
// proxy, through the phone. Runs in its own small background process, so it
// only uses Storage, Properties and Communications.
(:background)
class LiveService extends System.ServiceDelegate {
    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        var snap = Application.Storage.getValue("live");
        if (!(snap instanceof Dictionary)) {
            Background.exit(null);
            return;
        }
        var base = Application.Properties.getValue("baseUrl");
        var tok = Application.Properties.getValue("apiToken");
        Communications.makeWebRequest(
            (base instanceof String ? base : "https://dash.j551n.com") + "/garmin-api/live",
            snap as Dictionary<Object, Object>,
            {
                :method => Communications.HTTP_REQUEST_METHOD_POST,
                :headers => {
                    "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON,
                    "X-Api-Token" => (tok instanceof String ? tok : "")
                },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onSent));
    }

    function onSent(code as Number, data as Dictionary or String or Null) as Void {
        Background.exit(code);
    }
}
