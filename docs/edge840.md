# Fuel + Zone on the Edge 840

A full-screen ride page with heart rate and zone, ascent or power, speed,
cadence, ride time, and a gel timer that reminds you to eat.

You need the file `fuelzone-edge840.prg` (you get it from Johannes) and a USB
cable for the Edge.

## 1. Copy the file onto the Edge

1. Connect the Edge 840 to your computer with the USB cable.
2. Open the Edge's storage:
   - **Windows:** File Explorer, then "Edge 840", then "Internal Storage".
   - **Mac:** the Edge doesn't show up in Finder. Install
     [OpenMTP](https://openmtp.ganeshrvel.com) (free) and open the Edge in it.
3. Open the `Garmin` folder, then `Apps`. If there is no `Apps` folder, create it.
4. Copy `fuelzone-edge840.prg` into `Garmin/Apps`.
5. Eject the Edge and unplug it. It can take a minute to load the app.

## 2. Add it as a data page

1. On the Edge: **Menu**, then **Activity Profiles**, then the profile you
   ride with (for example Road).
2. **Data Screens**, then add a new screen (or pick one you don't need).
3. Set the **Layout** to **1 field**.
4. Tap the field, then **Connect IQ**, then **Fuel + Zone**.
5. Back out of the menu. Swipe to that page during a ride.

Use it on a 1-field page. On a smaller field it only shows the gel countdown.

## 3. Before your first ride

- **Heart rate zones** come from your cycling HR zones on the Edge (set them
  in the Garmin Connect app under your heart rate zones, cycling).
- **Tones** must be on for the gel beep: Menu, System, Tones.

## What it does during the ride

- **When gels come** (30 g each):
  - **Riding a route:** the Edge works out how long the ride will take.
    Under 1 hour: no gels. 1 to 2 hours: 30 g per hour. Longer: 60 g
    per hour. The first gel comes as soon as 30 g are due, so 30 minutes
    in on a 2.5 hour route.
  - **No route:** the first gel comes after 1 hour, then 45 g per hour.
  - **Riding hard:** in zone 3 at least 60 g per hour, in zone 4 or 5
    90 g per hour, so gels come sooner. Never more than 90 g per hour.
- **Next gel in:** the countdown at the current pace. It only runs while the
  ride timer runs.
- **Gel alert:** when a gel is due, the screen turns orange and beeps. You
  don't need to press anything. After 5 seconds it logs the gel by itself
  and beeps again.
- **Carbs:** grams eaten so far, and next to "CARBS" the current rate in g/h.
- **Ascent / Power:** shows total ascent until a power meter sends data, then
  3 second power.
- The Lap button works as normal, this page doesn't use it.
- After the ride, Garmin Connect shows **carbs** and **gels** on the activity
  (in the Connect IQ section of the ride).

90 g per hour is a lot if you're not used to it, your stomach needs
training for that. If you want a lower limit or other gel sizes, tell
Johannes and he'll build you a new file.

## Remove it

Connect the Edge again and delete `fuelzone-edge840.prg` from `Garmin/Apps`.
