pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Default-printer state for the pill's printer indicator, polled from CUPS with
 * lpstat (CUPS has no cheap change feed a user process can watch). One poll
 * prints a single tab-separated line: queue name, state (idle / printing /
 * stopped), queued job count, the queue's alerts and whether a USB printer is
 * physically attached (its URI serial is matched against /sys). A network
 * printer is never reported attached, so its icon only shows while it has jobs
 * or a problem. A new problem raises one notification so a paper jam or an
 * empty tray isn't missed with the pill collapsed.
 */
Singleton {
    id: root

    property string name: ""
    property string state: "idle"
    property int jobs: 0
    property string alerts: ""
    property bool attached: false

    readonly property bool present: name.length > 0
    readonly property bool printing: state === "printing"
    /** Stopped queue or any error-level alert, e.g. media-empty-error, offline-report. */
    readonly property bool problem: present && (state === "stopped" || /error|offline|jam|empty/i.test(alerts))
    readonly property bool visible: present && (attached || jobs > 0 || problem)

    readonly property string label: name.replace(/_/g, " ")
    readonly property string statusText: !present ? ""
        : problem ? (state === "stopped" ? "Stopped" : alerts.replace(/-/g, " "))
        : printing ? "Printing · " + jobs + (jobs === 1 ? " job" : " jobs")
        : jobs > 0 ? jobs + (jobs === 1 ? " job queued" : " jobs queued")
        : "Ready"

    onProblemChanged: if (problem) {
        Quickshell.execDetached(["notify-send", "-a", "Printer", "-u", "critical",
            root.label + ": " + root.statusText, "Open localhost:631 for details"]);
    }

    /** CUPS web page for the queue, where jobs can be inspected, held or cancelled. */
    function openQueue() {
        Quickshell.execDetached(["xdg-open", "http://localhost:631/printers/" + root.name]);
    }

    /** Cancels every job this user has on the queue; other users' jobs are left alone. */
    function cancelMine() {
        if (!present || jobs === 0)
            return;
        Quickshell.execDetached(["cancel", "-u", Quickshell.env("USER"), root.name]);
        Qt.callLater(function () { if (!poll.running) poll.running = true; });
    }

    Process {
        id: poll
        command: ["sh", "-c",
            "export LC_ALL=C; "
            + "d=$(lpstat -d 2>/dev/null | sed -n 's/^system default destination: //p'); "
            + "[ -n \"$d\" ] || { echo; exit 0; }; "
            + "p=$(lpstat -l -p \"$d\" 2>/dev/null); "
            + "case \"$(printf '%s\\n' \"$p\" | head -n1)\" in "
            + "*'now printing'*) st=printing ;; *disabled*) st=stopped ;; *) st=idle ;; esac; "
            + "al=$(printf '%s\\n' \"$p\" | sed -n 's/^[[:space:]]*Alerts: //p' | head -n1); "
            + "[ \"$al\" = none ] && al=''; "
            + "n=$(lpstat -o \"$d\" 2>/dev/null | wc -l); "
            + "uri=$(lpstat -v \"$d\" 2>/dev/null | sed -n 's/^device for [^:]*: //p'); "
            + "at=0; case \"$uri\" in usb://*serial=*) s=${uri##*serial=}; s=${s%%&*}; "
            + "grep -qxF \"$s\" /sys/bus/usb/devices/*/serial 2>/dev/null && at=1 ;; esac; "
            + "printf '%s\\t%s\\t%s\\t%s\\t%s\\n' \"$d\" \"$st\" \"$n\" \"$al\" \"$at\""]
        stdout: StdioCollector {
            onStreamFinished: {
                var c = this.text.replace(/\n$/, "").split("\t");
                if (c.length < 5) {
                    root.name = "";
                    return;
                }
                root.name = c[0];
                root.state = c[1];
                root.jobs = parseInt(c[2], 10) || 0;
                root.alerts = c[3];
                root.attached = c[4] === "1";
            }
        }
    }

    /** Faster while something is printing so the count and state keep up. */
    Timer {
        interval: root.jobs > 0 ? 1500 : 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!poll.running) poll.running = true
    }
}
