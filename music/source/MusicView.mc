import Toybox.Application;
import Toybox.Communications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Spotify remote, straight to the Spotify Web API through the phone
// (Spotify.mc), laid out like the design canvas at 282x470:
//   header 34 | now playing 150 | prev / play-pause / next 120 |
//   like 84 | up next (the rest); status in the header
// No shuffle/repeat: Spotify disallows toggling them for this account
// (actions.disallows), so the buttons could only ever fail.
// Polls now-playing every 5 s while the widget is on screen.
class MusicView extends WatchUi.View {
    const POLL_MS = 5000;
    // Spotify applies commands asynchronously; read back after this.
    // First read-back after a command; while Spotify still reports the old
    // song after a skip, ask again every RETRY_MS, up to MAX_RETRIES times.
    const SETTLE_MS = 500;
    const RETRY_MS = 600;
    const MAX_RETRIES = 3;
    const GAP = 8;
    // market=from_token drops the per-track country lists, by far the
    // largest part of the answer.
    const PLAYER = "/me/player?market=from_token&additional_types=track";

    // Only what the screen shows, copied out of Spotify's answer:
    // active, playing, title, artist, posMs, lenMs, device, id.
    hidden var _now as Dictionary? = null;
    hidden var _status as String? = "Loading...";
    hidden var _busy as Boolean = false;
    // The play/pause path just sent, to flip it if Spotify says it's
    // already in that state (403); null for other commands.
    hidden var _lastToggle as String? = null;
    // A request is out over Bluetooth; don't stack another one on it (a slow
    // phone link plus the 5 s poll would otherwise queue requests until the
    // Edge rejects them).
    hidden var _inFlight as Boolean = false;
    // When the request in flight went out. A request the phone never
    // answers (Bluetooth link disturbed) would otherwise block every tap
    // with "Busy" until the widget is reopened.
    const STUCK_MS = 15000;
    hidden var _sentAt as Number = 0;
    hidden var _poll as Timer.Timer = new Timer.Timer();
    hidden var _settle as Timer.Timer = new Timer.Timer();
    hidden var _sp as Spotify = new Spotify();
    // Second connection for the liked check and the queue, so the large
    // queue answer never blocks the buttons or the poll.
    hidden var _bg as Spotify = new Spotify();
    hidden var _bgBusy as Boolean = false;
    // Liked state per track id, so it's only asked once per song.
    hidden var _likedId as String? = null;
    hidden var _liked as Boolean? = null;
    // Id of the song skipped away from, while waiting for Spotify to switch.
    hidden var _skipFrom as String? = null;
    hidden var _retries as Number = 0;
    // Up next comes from the playlist or album itself (small answers), not
    // from /me/player/queue: that's 35-50 KB and the Edge rejects it (-402).
    // AHEAD songs after the current one are kept ({title, artist, lenMs,
    // id}), so after a skip the new up next is already there; refilled in
    // the background when one is left.
    const AHEAD = 3;
    hidden var _ahead as Array<Dictionary> = [] as Array<Dictionary>;
    // Song id and context uri _ahead follows.
    hidden var _aheadFor as String? = null;
    hidden var _aheadCtx as String? = null;
    // Position of the current song in the playlist, -1 unknown; the song
    // list is fetched in pages of PL_PAGE ids, only to find it.
    const PL_PAGE = 100;
    const PL_MAX_PAGES = 10;
    hidden var _plIndex as Number = -1;
    hidden var _plPage as Number = 0;
    // Background work, one at a time on _bg, in this order: find the
    // position, fetch more songs ahead, the liked check.
    hidden var _needLookup as Boolean = false;
    hidden var _needMore as Boolean = false;
    hidden var _likedPending as Boolean = false;
    // A song about to end by itself: ask right after, not at the next poll.
    hidden var _endTimer as Timer.Timer = new Timer.Timer();
    // [x, y, w, h, cmd] per button, rebuilt on every draw.
    hidden var _buttons as Array<Array> = [] as Array<Array>;

    function initialize() {
        View.initialize();
        // Last known state, shown at once while the first answer is on its way.
        var c = Application.Storage.getValue("music");
        if (c instanceof Array && c.size() == 7) {
            _now = c[0] instanceof Dictionary ? c[0] as Dictionary : null;
            _likedId = c[1] instanceof String ? c[1] as String : null;
            _liked = c[2] instanceof Boolean ? c[2] as Boolean : null;
            _ahead = c[3] instanceof Array ? c[3] as Array<Dictionary> : [] as Array<Dictionary>;
            _aheadFor = c[4] instanceof String ? c[4] as String : null;
            _aheadCtx = c[5] instanceof String ? c[5] as String : null;
            _plIndex = c[6] instanceof Number ? c[6] as Number : -1;
        }
    }

    hidden function saveCache() as Void {
        Application.Storage.setValue("music", [_now, _likedId, _liked, _ahead, _aheadFor, _aheadCtx, _plIndex]);
    }

    function onShow() as Void {
        refresh();
        _poll.start(method(:refresh), POLL_MS, true);
    }

    function onHide() as Void {
        _poll.stop();
        _settle.stop();
        _endTimer.stop();
    }

    // --- Spotify -------------------------------------------------------------

    function refresh() as Void {
        unstick();
        if (!_busy && !_inFlight) {
            _inFlight = true;
            _sentAt = System.getTimer();
            _sp.call(Communications.HTTP_REQUEST_METHOD_GET, PLAYER, null, method(:onPlayer));
        }
    }

    function onPlayer(code as Number, data as Dictionary or String or Null) as Void {
        _busy = false;
        _inFlight = false;
        if (code == 200 && data instanceof Dictionary && data["item"] instanceof Dictionary) {
            var item = data["item"] as Dictionary;
            // Spotify hasn't switched yet: keep the song shown, ask again.
            var from = _skipFrom;
            if (from != null && from.equals(item["id"]) && _retries < MAX_RETRIES) {
                _retries++;
                _busy = true;
                _settle.start(method(:afterCmd), RETRY_MS, false);
                return;
            }
            _skipFrom = null;
            var was = _now;
            _now = compact(data);
            data = null;
            _status = null;
            var id = (_now as Dictionary)["id"];
            if (id instanceof String && !id.equals(_likedId)) {
                newSong(id);
            } else if (id instanceof String && !id.equals(_aheadFor) && !_needLookup) {
                // Same song, up next not for it (widget reopened): look up.
                _needLookup = true;
                bgNext();
            }
            // About to end by itself: ask right after it does.
            var n = _now as Dictionary;
            var left = (n["lenMs"] as Number) - (n["posMs"] as Number);
            _endTimer.stop();
            if (n["playing"] == true && left > 0 && left < POLL_MS) {
                _endTimer.start(method(:refresh), left + 400, false);
            }
            if (was == null || was["playing"] != (_now as Dictionary)["playing"]) {
                saveCache();
            }
        } else if (code == 200 || code == 204 || code == 0) {
            // Nothing playing on any device: Spotify answers 204 with an
            // empty body, which arrives as 0 through the iPhone (204 in the
            // simulator). Link problems have their own negative codes.
            _now = {"active" => false};
            _status = null;
        } else {
            _status = Spotify.errorText(code, data);
            System.println("music error " + code + ": " + _status);
        }
        WatchUi.requestUpdate();
    }

    hidden function compact(st as Dictionary) as Dictionary {
        var it = st["item"] as Dictionary;
        var artists = "";
        if (it["artists"] instanceof Array) {
            var a = it["artists"] as Array;
            for (var i = 0; i < a.size(); i++) {
                if (a[i] instanceof Dictionary && (a[i] as Dictionary)["name"] instanceof String) {
                    artists += (artists.length() > 0 ? ", " : "") + (a[i] as Dictionary)["name"];
                }
            }
        }
        var dev = st["device"];
        var ctx = st["context"];
        return {
            // For up next: playlist/album uri, shuffle, track number.
            "ctx" => (ctx instanceof Dictionary && ctx["uri"] instanceof String) ? ctx["uri"] : null,
            "shuffle" => st["shuffle_state"] == true,
            "trackNo" => it["track_number"] instanceof Number ? it["track_number"] : 0,
            "active" => true,
            "playing" => st["is_playing"] == true,
            "title" => it["name"] instanceof String ? it["name"] : "",
            "artist" => artists,
            "posMs" => st["progress_ms"] instanceof Number ? st["progress_ms"] : 0,
            "lenMs" => it["duration_ms"] instanceof Number ? it["duration_ms"] : 0,
            "device" => (dev instanceof Dictionary && dev["name"] instanceof String) ? dev["name"] : null,
            "id" => it["id"]
        };
    }

    // A different song is playing: up next from what's already ahead (no
    // request), then the liked check, in the background.
    hidden function newSong(id as String) as Void {
        _likedId = id;
        _liked = null;
        _likedPending = true;
        var now = _now;
        var ctx = now != null ? now["ctx"] : null;
        var k = -1;
        if (ctx instanceof String && ctx.equals(_aheadCtx)) {
            for (var i = 0; i < _ahead.size(); i++) {
                if (id.equals(_ahead[i]["id"])) {
                    k = i;
                    break;
                }
            }
        }
        if (k >= 0) {
            // Skipped or played on to a song we had ahead.
            _ahead = _ahead.slice(k + 1, null);
            if (_plIndex >= 0) {
                _plIndex += k + 1;
            }
            _aheadFor = id;
            _needLookup = false;
            _needMore = _ahead.size() < 2;
        } else {
            _ahead = [] as Array<Dictionary>;
            _aheadFor = null;
            _needLookup = true;
            _needMore = false;
        }
        saveCache();
        bgNext();
    }

    // Next piece of background work, if the second connection is free.
    hidden function bgNext() as Void {
        if (_bgBusy) {
            return;
        }
        if (_needLookup) {
            startLookup();
        } else if (_needMore) {
            fetchAhead(true);
        } else if (_likedPending && _likedId != null) {
            _likedPending = false;
            _bgBusy = true;
            _bg.call(Communications.HTTP_REQUEST_METHOD_GET,
                "/me/library/contains?uris=spotify%3Atrack%3A" + _likedId, null, method(:onLiked));
        }
    }

    // /me/library/contains answers a JSON array: [true] or [false].
    function onLiked(code as Number, data) as Void {
        _bgBusy = false;
        if (code == 200 && data instanceof Array && (data as Array).size() > 0) {
            _liked = (data as Array)[0] == true;
        } else {
            System.println("liked check " + code + ": " + data);
        }
        saveCache();
        WatchUi.requestUpdate();
        bgNext();
    }

    // Where the current song sits, then the songs after it.
    hidden function startLookup() as Void {
        _needLookup = false;
        var now = _now;
        var id = _likedId;
        var ctx = now != null ? now["ctx"] : null;
        _ahead = [] as Array<Dictionary>;
        _aheadFor = id;
        _aheadCtx = ctx instanceof String ? ctx : null;
        _plIndex = -1;
        // Shuffle (or radio, no context): only the full queue knows.
        if (now == null || id == null || now["shuffle"] == true || !(ctx instanceof String)) {
            doneAhead();
            return;
        }
        var kind = ctxKind();
        if (kind.equals("album")) {
            fetchAhead(false);
        } else if (kind.equals("playlist")) {
            _plPage = 0;
            fetchPlaylistIds();
        } else {
            doneAhead();
        }
    }

    hidden function ctxKind() as String {
        var parts = split(_aheadCtx as String, ":");
        return parts.size() >= 3 ? parts[parts.size() - 2] : "";
    }

    hidden function ctxId() as String {
        var parts = split(_aheadCtx as String, ":");
        return parts[parts.size() - 1];
    }

    // One page of the playlist's song ids (~4 KB per 100), to find the
    // current song's position.
    hidden function fetchPlaylistIds() as Void {
        _bgBusy = true;
        _bg.call(Communications.HTTP_REQUEST_METHOD_GET,
            "/playlists/" + ctxId() + "/items?fields=items(item(id))&limit=" + PL_PAGE + "&offset=" + (_plPage * PL_PAGE),
            null, method(:onPlaylistIds));
    }

    function onPlaylistIds(code as Number, data as Dictionary or String or Null) as Void {
        _bgBusy = false;
        var items = (code == 200 && data instanceof Dictionary && data["items"] instanceof Array)
            ? data["items"] as Array : null;
        data = null;
        if (items == null) {
            System.println("playlist ids " + code);
            doneAhead();
            return;
        }
        var id = _aheadFor;
        for (var i = 0; i < items.size(); i++) {
            var it = items[i];
            if (it instanceof Dictionary && it["item"] instanceof Dictionary
                    && id != null && id.equals((it["item"] as Dictionary)["id"])) {
                _plIndex = _plPage * PL_PAGE + i;
                fetchAhead(false);
                return;
            }
        }
        if (items.size() == PL_PAGE && _plPage + 1 < PL_MAX_PAGES) {
            _plPage += 1;
            fetchPlaylistIds();
            return;
        }
        // Not in the playlist (e.g. a song you queued yourself).
        doneAhead();
    }

    // The next AHEAD songs after the ones already known: name, id, length,
    // artist names (~120 bytes each).
    hidden function fetchAhead(append as Boolean) as Void {
        _needMore = false;
        if (_aheadCtx == null) {
            doneAhead();
            return;
        }
        var path;
        if (ctxKind().equals("album")) {
            var no = (_now != null && (_now as Dictionary)["trackNo"] instanceof Number)
                ? (_now as Dictionary)["trackNo"] as Number : 0;
            path = "/albums/" + ctxId() + "/tracks?limit=" + AHEAD + "&offset=" + (no + _ahead.size()) + "&market=from_token";
        } else if (_plIndex >= 0) {
            path = "/playlists/" + ctxId() + "/items?fields=items(item(name,id,duration_ms,artists(name)))&limit="
                + AHEAD + "&offset=" + (_plIndex + 1 + _ahead.size());
        } else {
            doneAhead();
            return;
        }
        _bgBusy = true;
        _bg.call(Communications.HTTP_REQUEST_METHOD_GET, path, null, method(:onAhead));
    }

    // Playlist answer {items: [{item: track}]}, album answer {items: [track]}.
    function onAhead(code as Number, data as Dictionary or String or Null) as Void {
        _bgBusy = false;
        if (code == 200 && data instanceof Dictionary && data["items"] instanceof Array) {
            var items = data["items"] as Array;
            for (var i = 0; i < items.size(); i++) {
                var t = items[i];
                if (t instanceof Dictionary && t["item"] instanceof Dictionary) {
                    t = t["item"] as Dictionary;
                }
                if (t instanceof Dictionary) {
                    _ahead.add(track(t));
                }
            }
            System.println("ahead ok: " + _ahead.size());
        } else {
            System.println("ahead " + code);
        }
        data = null;
        doneAhead();
    }

    hidden function track(t as Dictionary) as Dictionary {
        var artist = "";
        if (t["artists"] instanceof Array && (t["artists"] as Array).size() > 0
                && (t["artists"] as Array)[0] instanceof Dictionary) {
            var a = ((t["artists"] as Array)[0] as Dictionary)["name"];
            artist = a instanceof String ? a : "";
        }
        return {
            "title" => t["name"] instanceof String ? t["name"] : "",
            "artist" => artist,
            "lenMs" => t["duration_ms"] instanceof Number ? t["duration_ms"] : 0,
            "id" => t["id"]
        };
    }

    hidden function doneAhead() as Void {
        saveCache();
        WatchUi.requestUpdate();
        bgNext();
    }

    // The song after the current one, when known.
    hidden function nextTrack() as Dictionary? {
        var now = _now;
        if (now == null || _ahead.size() == 0 || _aheadFor == null || !_aheadFor.equals(now["id"])) {
            return null;
        }
        return _ahead[0];
    }

    hidden function split(s as String, sep as String) as Array<String> {
        var out = [] as Array<String>;
        var rest = s;
        var i = rest.find(sep);
        while (i != null) {
            out.add(rest.substring(0, i) as String);
            rest = rest.substring(i + sep.length(), rest.length()) as String;
            i = rest.find(sep);
        }
        out.add(rest);
        return out;
    }

    function command(cmd as String) as Void {
        unstick();
        if (_inFlight) {
            _status = "Busy, try again";
            WatchUi.requestUpdate();
            return;
        }
        var now = _now;
        var id = now != null ? now["id"] : null;
        var m = Communications.HTTP_REQUEST_METHOD_PUT;
        var path;
        if (cmd.equals("next") || cmd.equals("previous")) {
            m = Communications.HTTP_REQUEST_METHOD_POST;
            path = "/me/player/" + cmd;
            _skipFrom = id instanceof String ? id : null;
            _retries = 0;
            // Next: show the song ahead right away, and its up next too;
            // Spotify confirms after.
            var nt = nextTrack();
            if (cmd.equals("next") && nt != null && now != null) {
                _now = {
                    "ctx" => now["ctx"],
                    "shuffle" => now["shuffle"],
                    "trackNo" => (now["trackNo"] as Number) + 1,
                    "active" => true,
                    "playing" => true,
                    "title" => nt["title"],
                    "artist" => nt["artist"],
                    "posMs" => 0,
                    "lenMs" => nt["lenMs"],
                    "device" => now["device"],
                    "id" => nt["id"]
                };
                newSong(nt["id"] as String);
            }
        } else if (cmd.equals("like") || cmd.equals("unlike")) {
            if (!(id instanceof String)) {
                return;
            }
            if (cmd.equals("unlike")) {
                m = Communications.HTTP_REQUEST_METHOD_DELETE;
            }
            path = "/me/library?uris=spotify%3Atrack%3A" + id;
            _liked = cmd.equals("like");
        } else {
            var playing = now != null && now["playing"] == true;
            path = (cmd.equals("toggle") && playing) ? "/me/player/pause" : "/me/player/play";
            if (now != null && now["active"] == true) {
                now["playing"] = !playing;
            }
        }
        _busy = true;
        _inFlight = true;
        _sentAt = System.getTimer();
        _status = "...";
        WatchUi.requestUpdate();
        _lastToggle = path.equals("/me/player/pause") || path.equals("/me/player/play") ? path : null;
        _sp.call(m, path, m == Communications.HTTP_REQUEST_METHOD_DELETE ? null : {}, method(:onCmd));
    }

    function onCmd(code as Number, data as Dictionary or String or Null) as Void {
        _inFlight = false;
        // Pause on a paused player (or play on a playing one) is refused
        // with 403 when the shown state was behind: send the other one.
        var t = _lastToggle;
        if (code == 403 && t != null) {
            _lastToggle = null;
            var other = t.equals("/me/player/pause") ? "/me/player/play" : "/me/player/pause";
            var now = _now;
            if (now != null && now["active"] == true) {
                now["playing"] = other.equals("/me/player/play");
            }
            _inFlight = true;
            _sentAt = System.getTimer();
            _sp.call(Communications.HTTP_REQUEST_METHOD_PUT, other, {}, method(:onCmd));
            return;
        }
        _lastToggle = null;
        // Spotify confirms commands with an empty body, which the Edge
        // reports as -400 (body not JSON); its errors always carry JSON.
        if ((code >= 200 && code < 300) || code == -400) {
            _status = null;
            _settle.start(method(:afterCmd), SETTLE_MS, false);
        } else {
            _busy = false;
            _status = Spotify.errorText(code, data);
            System.println("music cmd " + code + ": " + _status);
            // The optimistic flip (or shown next song) was wrong; read the
            // real state.
            _likedId = null;
            _skipFrom = null;
        }
        WatchUi.requestUpdate();
    }

    // Gives up on a request that's been out longer than STUCK_MS.
    hidden function unstick() as Void {
        if (_inFlight && System.getTimer() - _sentAt > STUCK_MS) {
            System.println("music: no answer after " + STUCK_MS + " ms");
            _inFlight = false;
            _busy = false;
            _status = "No answer from phone";
        }
    }

    function afterCmd() as Void {
        _busy = false;
        refresh();
    }

    // --- Input (from MusicDelegate) ----------------------------------------------

    function tapAt(x as Number, y as Number) as Void {
        for (var i = 0; i < _buttons.size(); i++) {
            var b = _buttons[i];
            if (x >= b[0] && x < b[0] + b[2] && y >= b[1] && y < b[1] + b[3]) {
                command(b[4] as String);
                return;
            }
        }
    }


    // --- Drawing -----------------------------------------------------------------

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var s = h / 470.0;
        var pad = Ui.PAD;
        dc.setColor(Ui.INK, Ui.PAPER);
        dc.clear();
        _buttons = [] as Array<Array>;

        var now = _now;
        var active = now != null && now["active"] == true;

        // Header; a status (error, "...") takes the device's place.
        var hH = (34 * s).toNumber();
        dc.setColor(Ui.INK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(pad, hH / 2, Graphics.FONT_XTINY, "MUSIC", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        var st = _status;
        var right = st != null ? st
            : ((now != null && now["device"] instanceof String) ? "Spotify - " + now["device"] : "Spotify");
        dc.setColor(st != null ? Ui.WARN : Ui.INK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w - pad, hH / 2, Graphics.FONT_XTINY, Ui.fit(dc, right, Graphics.FONT_XTINY, w * 2 / 3),
            Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        Ui.hline(dc, hH - 1, w);

        // Now playing
        var y = hH;
        var hN = (150 * s).toNumber();
        var playing = active && now["playing"] == true;
        Ui.label(dc, pad, y + 10, !active ? "NOTHING PLAYING" : (playing ? "PLAYING" : "PAUSED"));
        if (active) {
            var title = now["title"] instanceof String ? now["title"] as String : "";
            var artist = now["artist"] instanceof String ? now["artist"] as String : "";
            var ty = y + 10 + dc.getFontHeight(Graphics.FONT_XTINY) + 4;
            dc.setColor(Ui.INK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(pad, ty, Graphics.FONT_MEDIUM, Ui.fit(dc, title, Graphics.FONT_MEDIUM, w - 2 * pad), Graphics.TEXT_JUSTIFY_LEFT);
            ty += dc.getFontHeight(Graphics.FONT_MEDIUM);
            dc.drawText(pad, ty, Graphics.FONT_SMALL, Ui.fit(dc, artist, Graphics.FONT_SMALL, w - 2 * pad), Graphics.TEXT_JUSTIFY_LEFT);

            var pos = now["posMs"] instanceof Number ? now["posMs"] as Number : 0;
            var len = now["lenMs"] instanceof Number ? now["lenMs"] as Number : 0;
            var barY = y + hN - 32;
            var barW = w - 2 * pad;
            dc.setColor(Ui.LINE, Ui.LINE);
            dc.fillRectangle(pad, barY, barW, 6);
            if (len > 0) {
                dc.setColor(Ui.INK, Ui.INK);
                dc.fillRectangle(pad, barY, (barW * pos.toFloat() / len).toNumber(), 6);
            }
            dc.setColor(Ui.MUTED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(pad, barY + 9, Graphics.FONT_XTINY, Ui.mmss(pos), Graphics.TEXT_JUSTIFY_LEFT);
            dc.drawText(w - pad, barY + 9, Graphics.FONT_XTINY, Ui.mmss(len), Graphics.TEXT_JUSTIFY_RIGHT);
        } else {
            dc.setColor(Ui.MUTED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(pad, y + hN / 2, Graphics.FONT_SMALL, "Start Spotify on the phone", Graphics.TEXT_JUSTIFY_LEFT);
        }
        Ui.hline(dc, y + hN - 1, w);

        // Previous / play-pause / next
        y += hN;
        var hC = (120 * s).toNumber();
        var bw = (w - 2 * pad - 2 * GAP) / 3;
        var bh = hC - 24;
        var by = y + 12;
        button(dc, pad, by, bw, bh, false, Ui.INK, "previous");
        iconSkip(dc, pad + bw / 2, by + bh / 2, false, Ui.INK);
        button(dc, pad + bw + GAP, by, bw, bh, true, Ui.INK, active ? "toggle" : "play");
        if (playing) {
            iconPause(dc, pad + bw + GAP + bw / 2, by + bh / 2, Ui.PAPER);
        } else {
            iconPlay(dc, pad + bw + GAP + bw / 2, by + bh / 2, Ui.PAPER);
        }
        button(dc, pad + 2 * (bw + GAP), by, bw, bh, false, Ui.INK, "next");
        iconSkip(dc, pad + 2 * (bw + GAP) + bw / 2, by + bh / 2, true, Ui.INK);

        // Like, full width
        y += hC;
        var hR = (84 * s).toNumber();
        var liked = active && _liked == true;
        textButton(dc, pad, y, w - 2 * pad, hR - 12, liked, Ui.FUEL, liked ? "unlike" : "like", liked ? "LIKED" : "LIKE");

        // Up next, in the space below
        y += hR;
        Ui.hline(dc, y, w);
        var nt = nextTrack();
        var nx = nt == null ? null
            : (nt["title"] as String) + ((nt["artist"] as String).length() > 0 ? " - " + nt["artist"] : "");
        if (active && nx != null) {
            var fh = dc.getFontHeight(Graphics.FONT_XTINY) + 2 + dc.getFontHeight(Graphics.FONT_SMALL);
            var ny = y + (h - y - fh) / 2;
            Ui.label(dc, pad, ny, "UP NEXT");
            dc.setColor(Ui.INK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(pad, ny + dc.getFontHeight(Graphics.FONT_XTINY) + 2, Graphics.FONT_SMALL,
                Ui.fit(dc, nx, Graphics.FONT_SMALL, w - 2 * pad), Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    hidden function button(dc as Dc, x as Number, y as Number, bw as Number, bh as Number,
                           filled as Boolean, color as Number, cmd as String) as Void {
        if (filled) {
            dc.setColor(color, color);
            dc.fillRectangle(x, y, bw, bh);
        } else {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(3);
            dc.drawRectangle(x + 1, y + 1, bw - 2, bh - 2);
            dc.setPenWidth(1);
        }
        _buttons.add([x, y, bw, bh, cmd]);
    }

    hidden function textButton(dc as Dc, x as Number, y as Number, bw as Number, bh as Number,
                               on as Boolean, onColor as Number, cmd as String, text as String) as Void {
        button(dc, x, y, bw, bh, on, on ? onColor : Ui.LINE, cmd);
        dc.setColor(on ? (onColor == Ui.INK ? Ui.PAPER : Ui.INK) : Ui.INK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + bw / 2, y + bh / 2, Graphics.FONT_SMALL, text,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Skip icon: triangle + bar, pointing right for next, left for previous.
    hidden function iconSkip(dc as Dc, cx as Number, cy as Number, forward as Boolean, color as Number) as Void {
        dc.setColor(color, color);
        if (forward) {
            dc.fillPolygon([[cx - 12, cy - 13], [cx - 12, cy + 13], [cx + 7, cy]]);
            dc.fillRectangle(cx + 8, cy - 13, 5, 26);
        } else {
            dc.fillPolygon([[cx + 12, cy - 13], [cx + 12, cy + 13], [cx - 7, cy]]);
            dc.fillRectangle(cx - 13, cy - 13, 5, 26);
        }
    }

    hidden function iconPlay(dc as Dc, cx as Number, cy as Number, color as Number) as Void {
        dc.setColor(color, color);
        dc.fillPolygon([[cx - 10, cy - 16], [cx - 10, cy + 16], [cx + 16, cy]]);
    }

    hidden function iconPause(dc as Dc, cx as Number, cy as Number, color as Number) as Void {
        dc.setColor(color, color);
        dc.fillRectangle(cx - 13, cy - 15, 9, 30);
        dc.fillRectangle(cx + 4, cy - 15, 9, 30);
    }
}
