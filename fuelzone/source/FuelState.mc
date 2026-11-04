import Toybox.Lang;

// Fueling logic with no device APIs, so the unit tests can drive it directly.
// All times are activity timer time in milliseconds, so nothing counts while
// the ride is paused.
//
// Carbs are a running need: every second adds the current rate (g/h), and a
// gel is due once the need since the last gel reaches one gel. The rate is
// the higher of
//   - the base rate for the ride length (Jeukendrup 2014 guideline):
//     under 1 h no gels, 1-2 h 30 g/h, 2 h+ 60 g/h (90 only when riding
//     hard, through the zones);
//     ride length unknown (no route, no planned time): 45 g/h, first gel
//     only after noRouteStart (60 min),
//   - the rate for the current HR zone: Z3 60, Z4 and Z5 90 g/h,
// capped at maxPerHour (what the gut is trained for).
//
// No confirmation needed: when a gel is due the alert counts down
// confirmMs and then logs it by itself.
// Seconds the gel alert counts down before the gel is logged.
const CONFIRM_SEC = 5;

class FuelState {
    // Countdown before a due gel is logged, shown in steps of a second on a
    // real ride (confirmMs is longer in the 10x demo, the steps stay 5).
    var confirmMs as Number = 5000;
    const HOUR_MS = 3600000;
    // Longest sample gap that still counts (a restart or a jump in the timer
    // adds nothing).
    const MAX_STEP_MS = 10000;
    const UNKNOWN_BASE = 45;

    var gelGrams as Number = 30;
    var maxPerHour as Number = 90;
    var plannedGels as Number = 0;
    // Planned ride time in min, used like a route estimate. 0 = not set.
    var plannedMinutes as Number = 0;
    var noRouteStartMs as Number = 3600000;

    // False on a ride (or route) shorter than an hour.
    var enabled as Boolean = true;
    // Ride length unknown: first gel at noRouteStartMs.
    var lengthUnknown as Boolean = true;
    // Current rate in g/h.
    var rate as Number = 0;

    var gelsTaken as Number = 0;
    // Grams needed since the last gel.
    var needG as Float = 0.0;
    // Timer time at which the counting-down gel gets logged, -1 = none.
    var pendingAtMs as Number = -1;
    hidden var _lastT as Number = -1;

    function initialize() {
    }

    function configure(grams as Number, perHourMax as Number, planned as Number,
                       plannedMin as Number, noRouteStartMin as Number) as Void {
        gelGrams = grams > 0 ? grams : 30;
        maxPerHour = perHourMax;
        plannedGels = planned;
        plannedMinutes = plannedMin;
        noRouteStartMs = noRouteStartMin * 60000;
    }

    // Base rate in g/h for a ride of this length.
    static function baseFor(totalMs as Number) as Number {
        if (totalMs < 60 * 60000) {
            return 0;
        }
        if (totalMs < 120 * 60000) {
            return 30;
        }
        return 60;
    }

    static function zoneRate(zone as Number) as Number {
        if (zone >= 4) {
            return 90;
        }
        if (zone == 3) {
            return 60;
        }
        return 0;
    }

    // Once per sample. estTotalMs: expected ride length from the route, -1
    // when there is no route. zone: current HR zone, 0 when unknown.
    function update(t as Number, estTotalMs as Number, zone as Number) as Void {
        var est = estTotalMs;
        if (est < 0 && plannedMinutes > 0) {
            est = plannedMinutes * 60000;
        }
        lengthUnknown = est < 0;
        var base;
        if (lengthUnknown) {
            enabled = true;
            base = t < noRouteStartMs ? 0 : UNKNOWN_BASE;
        } else {
            base = baseFor(est);
            enabled = base > 0;
        }
        var r = base;
        // The zone only raises the rate once fueling is on at all.
        if (base > 0 && zoneRate(zone) > r) {
            r = zoneRate(zone);
        }
        if (r > maxPerHour) {
            r = maxPerHour;
        }
        rate = enabled ? r : 0;

        var dt = t - _lastT;
        if (_lastT >= 0 && dt > 0 && dt <= MAX_STEP_MS) {
            needG += rate * dt / HOUR_MS.toFloat();
        }
        _lastT = t;
    }

    // Ride length unknown and still in the first hour.
    function beforeStart(t as Number) as Boolean {
        return lengthUnknown && gelsTaken == 0 && t < noRouteStartMs;
    }

    hidden function due(t as Number) as Boolean {
        if (lengthUnknown && gelsTaken == 0) {
            return t >= noRouteStartMs;
        }
        return needG >= gelGrams;
    }

    // True once per gel, when it falls due: show the alert and start the
    // countdown.
    function shouldAlert(t as Number) as Boolean {
        if (!enabled || pendingAtMs >= 0 || !due(t)) {
            return false;
        }
        pendingAtMs = t + confirmMs;
        return true;
    }

    // Logs the gel once its countdown has run out. True when it did.
    function tick(t as Number) as Boolean {
        if (pendingAtMs < 0 || t < pendingAtMs) {
            return false;
        }
        logGel();
        return true;
    }

    function logGel() as Void {
        gelsTaken += 1;
        needG = needG > gelGrams ? needG - gelGrams : 0.0;
        pendingAtMs = -1;
    }

    // Time until the next gel at the current rate, -1 when it can't be said
    // (fueling off, rate 0).
    function msUntilNext(t as Number) as Number {
        if (!enabled) {
            return -1;
        }
        if (pendingAtMs >= 0) {
            return 0;
        }
        if (beforeStart(t)) {
            return noRouteStartMs - t;
        }
        if (rate <= 0) {
            return -1;
        }
        var left = gelGrams - needG;
        return left <= 0 ? 0 : (left * HOUR_MS / rate).toNumber();
    }

    function counting() as Boolean {
        return pendingAtMs >= 0;
    }

    // Countdown left, 5 4 3 2 1, 0 when none.
    function countdownSec(t as Number) as Number {
        if (pendingAtMs < 0) {
            return 0;
        }
        var left = pendingAtMs - t;
        return left <= 0 ? 0 : (left * CONFIRM_SEC + confirmMs - 1) / confirmMs;
    }

    function carbsTaken() as Number {
        return gelsTaken * gelGrams;
    }

    // Progress towards the next gel, 0.0..1.0.
    function progress(t as Number) as Float {
        var f = beforeStart(t) ? t.toFloat() / noRouteStartMs : needG / gelGrams;
        if (f < 0.0) {
            return 0.0;
        }
        if (f > 1.0) {
            return 1.0;
        }
        return f;
    }

    function reset() as Void {
        gelsTaken = 0;
        needG = 0.0;
        pendingAtMs = -1;
        _lastT = -1;
    }

    function toArray() as Array<Numeric> {
        return [gelsTaken, needG, pendingAtMs] as Array<Numeric>;
    }

    // Saved state; the old [gels, lastGelMs, pending] shape keeps the gels.
    function restore(a as Array) as Void {
        if (a.size() != 3 || !(a[0] instanceof Number) || !(a[2] instanceof Number)) {
            return;
        }
        gelsTaken = a[0] as Number;
        needG = (a[1] instanceof Float) ? a[1] as Float : 0.0;
        pendingAtMs = a[2] as Number;
    }
}
