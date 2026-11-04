import Toybox.BluetoothLowEnergy;
import Toybox.Lang;
import Toybox.System;

// Apple Media Service (AMS), the iPhone's built-in Bluetooth remote for the
// playing media app. Accessory side: write a command id to Remote Command.
// https://developer.apple.com/library/archive/documentation/CoreBluetooth/Reference/AppleMediaService_Reference/
module Ams {
    const SERVICE = "89D3502B-0F36-433A-8EF4-C502AD55F8DC";
    const REMOTE_COMMAND = "9B3C81D8-57B1-4A8A-B8DF-0E56F7CA51C2";
    const ENTITY_UPDATE = "2F7CABCE-808D-411F-9A0C-BB92BA96C102";
    const ENTITY_ATTRIBUTE = "C6B2F38C-23AB-46D8-A6AB-A3A870BBD5D7";
    // Remote command ids
    const CMD_TOGGLE = 2;
    const CMD_NEXT = 3;
    const CMD_PREVIOUS = 4;

    var device as BluetoothLowEnergy.Device? = null;

    function uuid(s as String) as BluetoothLowEnergy.Uuid {
        return BluetoothLowEnergy.stringToUuid(s);
    }

    // Has to happen before connecting: the Edge only discovers registered
    // services.
    function register() as Void {
        try {
            BluetoothLowEnergy.registerProfile({
                :uuid => uuid(SERVICE),
                :characteristics => [
                    {:uuid => uuid(REMOTE_COMMAND), :descriptors => [BluetoothLowEnergy.cccdUuid()]},
                    {:uuid => uuid(ENTITY_UPDATE), :descriptors => [BluetoothLowEnergy.cccdUuid()]},
                    {:uuid => uuid(ENTITY_ATTRIBUTE)}
                ]
            });
        } catch (e) {
            System.println("ams register failed: " + e.getErrorMessage());
        }
    }

    function remoteCommand() as BluetoothLowEnergy.Characteristic? {
        var d = device;
        if (d == null) {
            return null;
        }
        var svc = d.getService(uuid(SERVICE));
        return svc == null ? null : svc.getCharacteristic(uuid(REMOTE_COMMAND));
    }

    function send(cmd as Number) as String {
        var ch = remoteCommand();
        if (ch == null) {
            return "no AMS";
        }
        try {
            ch.requestWrite([cmd]b, {:writeType => BluetoothLowEnergy.WRITE_TYPE_WITH_RESPONSE});
            return "sent " + cmd;
        } catch (e) {
            return "write failed: " + e.getErrorMessage();
        }
    }

    function disconnect() as Void {
        var d = device;
        if (d != null) {
            try {
                BluetoothLowEnergy.unpairDevice(d);
            } catch (e) {
            }
            device = null;
        }
    }
}
