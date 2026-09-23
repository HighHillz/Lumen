pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Announces keyboard lock and touchpad toggles so the pill can flash a short
 * "<Feature> enabled / disabled" notice. Caps and Num Lock are read from the
 * keyboard's LED class devices; sysfs can't be watched with inotify, so a timer
 * re-reads the two files, which costs a file read and no process per tick. The
 * first reading only seeds the state, so login doesn't flash. The touchpad has
 * no LED, so binds.lua reports its toggles over IPC through `report()`.
 *
 * Fn Lock can't be shown: on ASUS laptops the kernel consumes Fn+Esc itself and
 * exposes no state for it.
 */
Singleton {
    id: root

    signal toggled(string name, bool on)

    property string capsPath: ""
    property string numPath: ""
    property int caps: -1
    property int num: -1

    function report(name, on) {
        root.toggled(name, on);
    }

    /** Folds one LED reading in, announcing only a real change after the first read. */
    function update(which, text) {
        var v = parseInt((text || "").trim(), 10);
        if (isNaN(v))
            return;
        var on = v > 0 ? 1 : 0;
        if (which === "caps") {
            if (root.caps >= 0 && on !== root.caps)
                root.toggled("Caps Lock", on === 1);
            root.caps = on;
        } else {
            if (root.num >= 0 && on !== root.num)
                root.toggled("Num Lock", on === 1);
            root.num = on;
        }
    }

    /** First LED of each kind; the laptop keyboard enumerates before any external one. */
    Process {
        running: true
        command: ["sh", "-c", "for k in capslock numlock; do d=$(ls -d /sys/class/leds/*::$k 2>/dev/null | head -n1); echo \"$k $d\"; done"]
        stdout: SplitParser {
            onRead: (line) => {
                var parts = line.trim().split(" ");
                if (parts.length < 2 || parts[1].length === 0)
                    return;
                if (parts[0] === "capslock")
                    root.capsPath = parts[1] + "/brightness";
                else if (parts[0] === "numlock")
                    root.numPath = parts[1] + "/brightness";
            }
        }
    }

    FileView {
        id: capsFile
        path: root.capsPath
        blockLoading: true
        printErrors: false
    }

    FileView {
        id: numFile
        path: root.numPath
        blockLoading: true
        printErrors: false
    }

    Timer {
        interval: 150
        repeat: true
        running: root.capsPath.length > 0 || root.numPath.length > 0
        onTriggered: {
            if (root.capsPath.length > 0) {
                capsFile.reload();
                root.update("caps", capsFile.text());
            }
            if (root.numPath.length > 0) {
                numFile.reload();
                root.update("num", numFile.text());
            }
        }
    }
}
