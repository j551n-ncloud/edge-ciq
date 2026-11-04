import Toybox.Lang;

// Fueling logic with no device APIs, so the unit tests can drive it directly.
// All times are activity timer time in milliseconds.
//
// The next gel is due one interval after the last one (or after the start),
// so eating late pushes the schedule instead of stacking gels.
//
// No confirmation needed: when a gel is due the alert counts down
// CONFIRM_MS and then logs it by itself. The countdown runs on timer time,
// so it waits while the ride is paused.
class FuelState {
    const CONFIRM_MS = 3000;

    var intervalMs as Number = 1500000;
    var gelGrams as Number = 25;
    var carbsPerHour as Number = 60;
    var plannedGels as Number = 0;
    // Off for rides planned under 60 min (no fueling needed).
    var enabled as Boolean = true;

    var gelsTaken as Number = 0;
    var lastGelMs as Number = 0;
    // Timer time at which the counting-down gel gets logged, -1 = none.
    var pendingAtMs as Number = -1;

    function initialize() {
    }

    function configure(intervalMin as Number, grams as Number, perHour as Number,
                       planned as Number, plannedMinutes as Number) as Void {
        intervalMs = intervalMin * 60000;
        gelGrams = grams;
        carbsPerHour = perHour;
        plannedGels = planned;
        enabled = plannedMinutes == 0 || plannedMinutes >= 60;
    }

    function dueAt() as Number {
        return lastGelMs + intervalMs;
    }

    // Negative once overdue.
    function msUntilNext(t as Number) as Number {
        return dueAt() - t;
    }

    // True once per gel, when it falls due: show the alert and start the
    // countdown.
    function shouldAlert(t as Number) as Boolean {
        if (!enabled || pendingAtMs >= 0 || t < dueAt()) {
            return false;
        }
        pendingAtMs = t + CONFIRM_MS;
        return true;
    }

    // Logs the gel once its countdown has run out. True when it did.
    function tick(t as Number) as Boolean {
        if (pendingAtMs < 0 || t < pendingAtMs) {
            return false;
        }
        logGel(t);
        return true;
    }

    function counting() as Boolean {
        return pendingAtMs >= 0;
    }

    // Whole seconds left on the countdown (3, 2, 1), 0 when none.
    function countdownSec(t as Number) as Number {
        if (pendingAtMs < 0) {
            return 0;
        }
        var left = pendingAtMs - t;
        return left <= 0 ? 0 : (left + 999) / 1000;
    }

    function logGel(t as Number) as Void {
        gelsTaken += 1;
        lastGelMs = t;
        pendingAtMs = -1;
    }

    function carbsTaken() as Number {
        return gelsTaken * gelGrams;
    }

    function carbsTarget(t as Number) as Number {
        return (t.toLong() * carbsPerHour / 3600000l).toNumber();
    }

    // Share of the interval elapsed since the last gel, 0.0..1.0.
    function sinceLastFraction(t as Number) as Float {
        var f = (t - lastGelMs).toFloat() / intervalMs;
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
        lastGelMs = 0;
        pendingAtMs = -1;
    }

    function toArray() as Array<Number> {
        return [gelsTaken, lastGelMs, pendingAtMs];
    }

    function restore(a as Array) as Void {
        if (a.size() == 3 && a[0] instanceof Number && a[1] instanceof Number && a[2] instanceof Number) {
            gelsTaken = a[0] as Number;
            lastGelMs = a[1] as Number;
            pendingAtMs = a[2] as Number;
        }
    }
}
