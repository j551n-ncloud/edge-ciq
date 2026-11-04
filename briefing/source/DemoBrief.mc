import Toybox.Lang;

// Sample brief for the simulator (setting demoMode), same shape as glance's
// GET /garmin-api/edge-brief (ics-proxy/lib/edgeBrief.js).
module DemoBrief {
    function sample() as Dictionary {
        return {
            "at" => "07:12",
            "ready" => {
                "score" => 74,
                "rec" => "Good to go",
                "notes" => ["HRV 58 ms (avg 62)", "Sleep 6.2 h"]
            },
            "wx" => {
                "text" => "Partly cloudy",
                "tmin" => 7,
                "tmax" => 16,
                "wind" => 22,
                "rain" => 30,
                "sunset" => "17:04",
                "dark" => true
            },
            "pack" => ["Arm warmers", "Gilet", "Lights", "Rain jacket"],
            "plan" => {"min" => 150, "dest" => "Neckarsteinach", "km" => 75, "gels" => 5, "carbs" => 150},
            "fuel" => {"everyMin" => 30, "gelG" => 30, "perHour" => 60},
            "bike" => {"ok" => true, "note" => "Chain in 420 km"}
        };
    }
}
