import Toybox.Attention;
import Toybox.Lang;

// A "ding-ding" through the Edge speaker. Loud enough for a cyclist next to
// you, not a replacement for the mechanical bell German traffic law (StVZO
// §64a) requires. Silent if tones are turned off in the device settings.
module Bell {
    // Returns which path played, for the log.
    function ring() as String {
        if (!(Attention has :playTone)) {
            return "no playTone";
        }
        if (Attention has :ToneProfile) {
            try {
                var ding = [
                    new Attention.ToneProfile(3100, 90),
                    new Attention.ToneProfile(2500, 70),
                    new Attention.ToneProfile(3100, 90),
                    new Attention.ToneProfile(2500, 200)
                ] as Array<Attention.ToneProfile>;
                Attention.playTone({:toneProfile => ding, :repeatCount => 0});
                return "toneProfile";
            } catch (e) {
                Attention.playTone(Attention.TONE_LOUD_BEEP);
                return "toneProfile failed, loud beep";
            }
        }
        Attention.playTone(Attention.TONE_LOUD_BEEP);
        return "loud beep";
    }
}
