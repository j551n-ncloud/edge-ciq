import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

// Spotify Web API straight from the Edge (through the phone's internet), no
// proxy. The refresh token and the app's Basic auth come from
// secrets-spotify/spotify.xml (scripts/spotify-login.py, never committed).
// The access token lives an hour and is kept in Storage; a rotated refresh
// token too. One request at a time: the view waits for the callback.
class Spotify {
    const API = "https://api.spotify.com/v1";

    hidden var _cb as Method? = null;
    // The call waiting for a fresh access token: [method, path, body].
    hidden var _pending as Array? = null;
    hidden var _retried as Boolean = false;

    function initialize() {
    }

    // cb(code as Number, data as Dictionary or String or Null)
    function call(httpMethod as Number, path as String, body as Dictionary?, cb as Method) as Void {
        _cb = cb;
        _retried = false;
        _pending = [httpMethod, path, body];
        if (token() == null) {
            refresh();
        } else {
            send();
        }
    }

    hidden function token() as String? {
        var t = Application.Storage.getValue("spAt");
        var exp = Application.Storage.getValue("spExp");
        if (t instanceof String && exp instanceof Number && exp > Time.now().value()) {
            return t;
        }
        return null;
    }

    hidden function send() as Void {
        var p = _pending as Array;
        var m = p[0] as Number;
        var headers = {"Authorization" => "Bearer " + token()};
        // Spotify wants a body (length) on PUT/POST, even an empty one.
        if (m == Communications.HTTP_REQUEST_METHOD_PUT || m == Communications.HTTP_REQUEST_METHOD_POST) {
            headers["Content-Type"] = Communications.REQUEST_CONTENT_TYPE_JSON;
        }
        Communications.makeWebRequest(API + (p[1] as String), p[2], {
            :method => m as Communications.HttpRequestMethod,
            :headers => headers,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        }, method(:onResp));
    }

    function onResp(code as Number, data as Dictionary or String or Null) as Void {
        if (code != 200 && code != 204) {
            System.println("spotify " + (_pending as Array)[1] + " " + code);
        }
        // Access token revoked or expired early: one fresh token, one retry.
        if (code == 401 && !_retried) {
            _retried = true;
            Application.Storage.deleteValue("spAt");
            refresh();
            return;
        }
        _pending = null;
        (_cb as Method).invoke(code, data);
    }

    // Token request, two ways: the app's id and secret as a Basic
    // Authorization header (works in the simulator), or as form fields
    // without that header. On the Edge through the iPhone the header way came
    // back as code 0, so code 0 switches to the other one, and the way that
    // worked is kept in Storage ("spForm").
    hidden var _form as Boolean = false;
    hidden var _triedOther as Boolean = false;

    hidden function refresh() as Void {
        _form = Application.Storage.getValue("spForm") == true;
        _triedOther = false;
        sendRefresh();
    }

    hidden function sendRefresh() as Void {
        var rt = Application.Storage.getValue("spRt");
        if (!(rt instanceof String)) {
            rt = Application.Properties.getValue("spotifyRefresh");
        }
        var body = {"grant_type" => "refresh_token", "refresh_token" => rt};
        var headers = {"Content-Type" => Communications.REQUEST_CONTENT_TYPE_URL_ENCODED};
        if (_form) {
            body["client_id"] = Application.Properties.getValue("spotifyId");
            body["client_secret"] = Application.Properties.getValue("spotifySecret");
        } else {
            headers["Authorization"] = "Basic " + Application.Properties.getValue("spotifyBasic");
        }
        Communications.makeWebRequest("https://accounts.spotify.com/api/token", body, {
            :method => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => headers,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        }, method(:onToken));
    }

    function onToken(code as Number, data as Dictionary or String or Null) as Void {
        System.println("spotify token " + (_form ? "form" : "basic") + " " + code
            + (code == 200 ? "" : ": " + data));
        if (code == 200 && data instanceof Dictionary && data["access_token"] instanceof String) {
            var ttl = data["expires_in"] instanceof Number ? data["expires_in"] as Number : 3600;
            Application.Storage.setValue("spAt", data["access_token"]);
            Application.Storage.setValue("spExp", Time.now().value() + ttl - 60);
            Application.Storage.setValue("spForm", _form);
            // Spotify may rotate the refresh token.
            if (data["refresh_token"] instanceof String) {
                Application.Storage.setValue("spRt", data["refresh_token"]);
            }
            send();
            return;
        }
        if (code == 0 && !_triedOther) {
            _triedOther = true;
            _form = !_form;
            sendRefresh();
            return;
        }
        _pending = null;
        // 400 from the token endpoint: the refresh token is dead (revoked or
        // the login was redone), so say that rather than "Error 400".
        (_cb as Method).invoke(code == 400 ? -9001 : code, data);
    }

    // Rider-readable text for a failed call.
    static function errorText(code as Number, data) as String {
        if (code == -9001) {
            return "Spotify login expired, redo it";
        }
        if (code == 401) {
            return "Spotify login rejected";
        }
        if (code == 403) {
            return "Spotify refused (Premium?)";
        }
        if (code == 404) {
            return "No active Spotify device";
        }
        if (code == 429) {
            return "Spotify: too many requests";
        }
        return Api.errorText(code, data);
    }
}
