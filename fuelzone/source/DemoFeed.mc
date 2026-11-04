import Toybox.Lang;
import Toybox.Math;

// Fake ride for the simulator (setting demoMode, off by default). Plays at
// 10x, starting at 1:38:00 so a gel is due after ~12 s, then a 1.5 km climb
// at 6 %, then flat again; loops every 90 s.
// Returns [hr, speed m/s, cadence, timer ms, distance m, altitude m].
module DemoFeed {
    const SPEEDUP = 10;
    const FLAT_MPS = 7.8;
    const CLIMB_MPS = 3.9;

    function sample(realMs as Number) as Array<Numeric> {
        var r = (realMs % 90000) / 1000.0;
        var timer = 5880000 + (r * 1000 * SPEEDUP).toNumber();
        var flat1 = 30.0;
        var climbEnd = flat1 + 1500.0 / (CLIMB_MPS * SPEEDUP);
        var d0 = 37000.0;
        var alt0 = 120.0;
        var dist;
        var alt;
        var speed;
        var cad;
        if (r < flat1) {
            speed = FLAT_MPS;
            dist = d0 + FLAT_MPS * SPEEDUP * r;
            alt = alt0;
            cad = 88;
        } else if (r < climbEnd) {
            speed = CLIMB_MPS;
            var dc = CLIMB_MPS * SPEEDUP * (r - flat1);
            dist = d0 + FLAT_MPS * SPEEDUP * flat1 + dc;
            alt = alt0 + 0.06 * dc;
            cad = 74;
        } else {
            speed = FLAT_MPS;
            dist = d0 + FLAT_MPS * SPEEDUP * flat1 + 1500.0 + FLAT_MPS * SPEEDUP * (r - climbEnd);
            alt = alt0 + 90.0;
            cad = 90;
        }
        var hr = (r >= flat1 && r < climbEnd) ? 168 + (6 * Math.sin(r)).toNumber() : 150 + (5 * Math.sin(r)).toNumber();
        return [hr, speed, cad, timer, dist, alt];
    }
}
