import Toybox.Lang;
import Toybox.Test;

// Run with scripts/test.sh (needs the simulator).

const MIN = 60000;

// Feeds one sample per second from t0 to t1 (timer ms).
function ride(f as FuelState, t0 as Number, t1 as Number, est as Number, zone as Number) as Void {
    for (var t = t0; t <= t1; t += 1000) {
        f.update(t, est, zone);
    }
}

function fresh() as FuelState {
    var f = new FuelState();
    // 30 g gels, max 90 g/h, no planned gels / time, first gel after 60 min.
    f.configure(30, 90, 0, 0, 60);
    return f;
}

(:test)
function noRouteFirstGelAfterAnHour(logger as Logger) as Boolean {
    var f = fresh();
    ride(f, 0, 59 * MIN, -1, 2);
    Test.assert(f.beforeStart(59 * MIN));
    Test.assert(!f.shouldAlert(59 * MIN));
    Test.assertEqual(f.msUntilNext(59 * MIN), MIN);
    ride(f, 59 * MIN + 1000, 60 * MIN, -1, 2);
    Test.assert(f.shouldAlert(60 * MIN));
    // No second alert while counting down.
    Test.assert(!f.shouldAlert(60 * MIN + 1000));
    Test.assertEqual(f.countdownSec(60 * MIN), 5);
    Test.assertEqual(f.countdownSec(60 * MIN + 1500), 4);
    Test.assert(!f.tick(60 * MIN + 4999));
    Test.assert(f.tick(60 * MIN + 5000));
    Test.assertEqual(f.carbsTaken(), 30);
    return true;
}

(:test)
function noRouteThenEvery40MinAt45(logger as Logger) as Boolean {
    var f = fresh();
    ride(f, 0, 60 * MIN, -1, 2);
    f.shouldAlert(60 * MIN);
    f.tick(60 * MIN + 5000);
    Test.assertEqual(f.rate, 45);
    // 30 g at 45 g/h: 40 min.
    ride(f, 60 * MIN + 6000, 99 * MIN, -1, 2);
    Test.assert(!f.shouldAlert(99 * MIN));
    ride(f, 99 * MIN + 1000, 101 * MIN, -1, 2);
    Test.assert(f.shouldAlert(101 * MIN));
    return true;
}

(:test)
function hardZonesRaiseTheRate(logger as Logger) as Boolean {
    var f = fresh();
    var est = 150 * MIN;
    f.update(0, est, 2);
    Test.assertEqual(f.rate, 60);
    f.update(1000, est, 4);
    Test.assertEqual(f.rate, 90);
    f.update(2000, est, 5);
    Test.assertEqual(f.rate, 90);
    // Capped by the gut limit.
    f.configure(30, 70, 0, 0, 60);
    f.update(3000, est, 5);
    Test.assertEqual(f.rate, 70);
    return true;
}

(:test)
function routeLengthSetsTheBaseRate(logger as Logger) as Boolean {
    Test.assertEqual(FuelState.baseFor(50 * MIN), 0);
    Test.assertEqual(FuelState.baseFor(90 * MIN), 30);
    Test.assertEqual(FuelState.baseFor(150 * MIN), 60);
    Test.assertEqual(FuelState.baseFor(240 * MIN), 60);
    // 2.5 h route at 60 g/h: first 30 g gel after 30 min, no hour wait.
    var f = fresh();
    ride(f, 0, 29 * MIN, 150 * MIN, 2);
    Test.assert(!f.shouldAlert(29 * MIN));
    ride(f, 29 * MIN + 1000, 31 * MIN, 150 * MIN, 2);
    Test.assert(f.shouldAlert(31 * MIN));
    return true;
}

(:test)
function shortRouteHasNoGels(logger as Logger) as Boolean {
    var f = fresh();
    ride(f, 0, 70 * MIN, 45 * MIN, 4);
    Test.assert(!f.enabled);
    Test.assert(!f.shouldAlert(70 * MIN));
    Test.assertEqual(f.msUntilNext(70 * MIN), -1);
    return true;
}

(:test)
function plannedTimeActsLikeARoute(logger as Logger) as Boolean {
    var f = fresh();
    f.configure(30, 90, 0, 200, 60);
    f.update(0, -1, 2);
    Test.assert(!f.lengthUnknown);
    Test.assertEqual(f.rate, 60);
    // Long and hard: the zone takes it to 90.
    f.update(1000, -1, 4);
    Test.assertEqual(f.rate, 90);
    return true;
}

(:test)
function pausesAndJumpsAddNothing(logger as Logger) as Boolean {
    var f = fresh();
    f.update(0, 150 * MIN, 2);
    // Same timer (paused), then a 20 min jump (restart).
    f.update(0, 150 * MIN, 2);
    f.update(20 * MIN, 150 * MIN, 2);
    Test.assert(f.needG < 0.01);
    return true;
}

(:test)
function countdownSurvivesARestart(logger as Logger) as Boolean {
    var f = fresh();
    ride(f, 0, 60 * MIN, -1, 2);
    f.shouldAlert(60 * MIN);
    var g = fresh();
    g.restore(f.toArray());
    Test.assert(g.counting());
    Test.assert(g.tick(60 * MIN + 5000));
    Test.assertEqual(g.gelsTaken, 1);
    // Old saved shape [gels, lastGelMs, pending] keeps the gels.
    var h = fresh();
    h.restore([2, 4500000, -1]);
    Test.assertEqual(h.gelsTaken, 2);
    return true;
}

(:test)
function zonesFromCsv(logger as Logger) as Boolean {
    var z = new Zones();
    z.load("120,150,165,180");
    Test.assertEqual(z.zoneFor(110), 1);
    Test.assertEqual(z.zoneFor(150), 3);
    Test.assertEqual(z.zoneFor(164), 3);
    Test.assertEqual(z.zoneFor(200), 5);
    Test.assertEqual(z.rangeText(3), "150-165");
    return true;
}

(:test)
function durationFormat(logger as Logger) as Boolean {
    Test.assertEqual(fmtDuration(950000), "15:50");
    Test.assertEqual(fmtDuration(5050000), "1:24:10");
    return true;
}
