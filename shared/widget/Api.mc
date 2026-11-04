import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;

// Calls to the glance proxy through the phone (Garmin Connect app over
// Bluetooth). Base URL and the narrow EDGE_API_TOKEN come from
// secrets/edge.xml, written by scripts/secrets.sh from glance's .env at build
// time and never committed.
module Api {
    function url(path as String) as String {
        var base = Application.Properties.getValue("baseUrl");
        return (base instanceof String ? base : "https://dash.j551n.com") + path;
    }

    function headers(json as Boolean) as Dictionary {
        var t = Application.Properties.getValue("apiToken");
        var h = {"X-Api-Token" => (t instanceof String ? t : "")};
        if (json) {
            h["Content-Type"] = Communications.REQUEST_CONTENT_TYPE_JSON;
        }
        return h;
    }

    function get(path as String, cb as Method) as Void {
        Communications.makeWebRequest(url(path), null, {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :headers => headers(false),
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        }, cb);
    }

    function post(path as String, body as Dictionary, cb as Method) as Void {
        Communications.makeWebRequest(url(path), body, {
            :method => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => headers(true),
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        }, cb);
    }

    // Short, rider-readable text for a failed request.
    function errorText(code as Number, data) as String {
        if (code == -104 || code == -2 || code == -300) {
            return "Phone not connected";
        }
        if (code == 401 || code == 403) {
            return "Token rejected";
        }
        if (code == 404) {
            return "Not deployed yet";
        }
        if (code == 409 && data instanceof Dictionary && data["error"] instanceof String) {
            return data["error"] as String;
        }
        if (code == 503) {
            return "Not set up on the proxy";
        }
        return "Error " + code;
    }
}
