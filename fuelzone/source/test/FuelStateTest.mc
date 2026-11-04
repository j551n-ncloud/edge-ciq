import Toybox.Lang;
import Toybox.Test;

// Run with scripts/test.sh (needs the simulator).

const MIN = 60000;

(:test)
function alertsOnceAtDueThenLogsAfterThreeSeconds(logger as Logger) as Boolean {
    var f = new FuelState();
    f.configure(25, 25, 60, 5, 130);
    var due = 25 * MIN;
    Test.assert(!f.shouldAlert(due - 1000));
    Test.assert(f.shouldAlert(due));
    // No second alert while counting down.
    Test.assert(!f.shouldAlert(due + 1000));
    Test.assertEqual(f.countdownSec(due), 3);
    Test.assertEqual(f.countdownSec(due + 1500), 2);
    Test.assert(!f.tick(due + 2999));
    Test.assertEqual(f.gelsTaken, 0);
    Test.assert(f.tick(due + 3000));
    Test.assertEqual(f.gelsTaken, 1);
    Test.assert(!f.counting());
    Test.assert(!f.tick(due + 4000));
    return true;
}

(:test)
function nextGelCountsFromTheLoggedOne(logger as Logger) as Boolean {
    var f = new FuelState();
    f.configure(25, 25, 60, 5, 130);
    f.shouldAlert(25 * MIN);
    f.tick(25 * MIN + 3000);
    Test.assertEqual(f.dueAt(), 50 * MIN + 3000);
    Test.assertEqual(f.carbsTaken(), 25);
    Test.assert(!f.shouldAlert(50 * MIN));
    Test.assert(f.shouldAlert(50 * MIN + 3000));
    return true;
}

(:test)
function countdownSurvivesARestart(logger as Logger) as Boolean {
    var f = new FuelState();
    f.configure(25, 25, 60, 5, 130);
    f.shouldAlert(25 * MIN);
    var g = new FuelState();
    g.configure(25, 25, 60, 5, 130);
    g.restore(f.toArray());
    Test.assert(g.counting());
    Test.assert(g.tick(25 * MIN + 3000));
    Test.assertEqual(g.gelsTaken, 1);
    return true;
}

(:test)
function shortRideHasNoAlerts(logger as Logger) as Boolean {
    var f = new FuelState();
    f.configure(25, 25, 60, 0, 45);
    Test.assert(!f.shouldAlert(40 * MIN));
    return true;
}

(:test)
function carbTargetFollowsTime(logger as Logger) as Boolean {
    var f = new FuelState();
    f.configure(25, 25, 60, 5, 130);
    Test.assertEqual(f.carbsTarget(84 * MIN), 84);
    return true;
}

(:test)
function zonesFromCsv(logger as Logger) as Boolean {
    var z = new Zones();
    z.load("127,158,174,189");
    Test.assertEqual(z.zoneFor(120), 1);
    Test.assertEqual(z.zoneFor(158), 3);
    Test.assertEqual(z.zoneFor(164), 3);
    Test.assertEqual(z.zoneFor(200), 5);
    Test.assertEqual(z.rangeText(3), "158-174");
    return true;
}

(:test)
function durationFormat(logger as Logger) as Boolean {
    Test.assertEqual(fmtDuration(950000), "15:50");
    Test.assertEqual(fmtDuration(5050000), "1:24:10");
    return true;
}
