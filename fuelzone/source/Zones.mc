import Toybox.Lang;
import Toybox.UserProfile;

module ZoneStyle {
    // Z1..Z5, all from the device's 64-color palette (see the design spec).
    const COLORS = [0xAAAAAA, 0x00AAFF, 0x00AA00, 0xFFAA00, 0xFF0000];
    const NAMES = ["RECOVERY", "ENDURANCE", "TEMPO", "THRESHOLD", "MAX"];
}

// Heart-rate zones as four upper bounds (Z1..Z4); anything at or above the
// last one is Z5. From the device's cycling HR zones unless the hrZones
// setting overrides them. None known: no zone shown.
class Zones {
    var limits as Array<Number>? = null;

    function initialize() {
    }

    // csv like "120,150,165,180"; empty or invalid uses the device's
    // cycling HR zones.
    function load(csv as String) as Void {
        var parsed = parseCsv(csv);
        limits = parsed.size() == 4 ? parsed : profileLimits();
    }

    // 1..5, 0 when no zones are known.
    function zoneFor(hr as Number) as Number {
        var l = limits;
        if (l == null) {
            return 0;
        }
        for (var i = 0; i < 4; i++) {
            if (hr < l[i]) {
                return i + 1;
            }
        }
        return 5;
    }

    function rangeText(zone as Number) as String {
        var l = limits;
        if (l == null) {
            return "";
        }
        if (zone <= 1) {
            return "<" + l[0];
        }
        if (zone >= 5) {
            return l[3] + "+";
        }
        return l[zone - 2] + "-" + l[zone - 1];
    }

    hidden function profileLimits() as Array<Number>? {
        if (!(UserProfile has :getHeartRateZones)) {
            return null;
        }
        // [z1 min, z1 max, z2 max, z3 max, z4 max, z5 max]
        var z = UserProfile.getHeartRateZones(UserProfile.HR_ZONE_SPORT_BIKING);
        if (z == null || z.size() < 6) {
            return null;
        }
        return [z[1], z[2], z[3], z[4]];
    }
}

function parseCsv(s as String) as Array<Number> {
    var out = [] as Array<Number>;
    var rest = s;
    while (rest.length() > 0) {
        var i = rest.find(",");
        var part = (i == null) ? rest : rest.substring(0, i) as String;
        var n = part.toNumber();
        if (n != null) {
            out.add(n);
        }
        if (i == null) {
            break;
        }
        rest = rest.substring(i + 1, rest.length()) as String;
    }
    return out;
}
