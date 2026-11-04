import Toybox.Lang;
import Toybox.UserProfile;

module ZoneStyle {
    // Z1..Z5, all from the device's 64-color palette (see the design spec).
    const COLORS = [0xAAAAAA, 0x00AAFF, 0x00AA00, 0xFFAA00, 0xFF0000];
    const NAMES = ["RECOVERY", "ENDURANCE", "TEMPO", "THRESHOLD", "MAX"];
}

// Heart-rate zones as four upper bounds (Z1..Z4); anything at or above the
// last one is Z5. Same shape as the Strava custom zones (127/158/174/189).
class Zones {
    var limits as Array<Number> = [127, 158, 174, 189];

    function initialize() {
    }

    // csv like "127,158,174,189"; empty or invalid falls back to the
    // device's cycling HR zones.
    function load(csv as String) as Void {
        var parsed = parseCsv(csv);
        if (parsed.size() == 4) {
            limits = parsed;
            return;
        }
        var fromProfile = profileLimits();
        if (fromProfile != null) {
            limits = fromProfile;
        }
    }

    // 1..5
    function zoneFor(hr as Number) as Number {
        for (var i = 0; i < 4; i++) {
            if (hr < limits[i]) {
                return i + 1;
            }
        }
        return 5;
    }

    function rangeText(zone as Number) as String {
        if (zone <= 1) {
            return "<" + limits[0];
        }
        if (zone >= 5) {
            return limits[3] + "+";
        }
        return limits[zone - 2] + "-" + limits[zone - 1];
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
