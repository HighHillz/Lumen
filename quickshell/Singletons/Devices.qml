pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * Single owner of screen vibrance (a Hyprland screen shader) and
 * external-monitor brightness (ddcutil) for the mixer. The persisted vibrance
 * percent is the source of truth: loaded and re-applied once at startup so the
 * tint survives a reboot, and every later set both pushes the shader and writes
 * back the state file.
 * DDC monitors come from `ddcutil detect` (one brightness fader each); the
 * setvcp/getvcp wire format lives here so every caller speaks it the same.
 * The internal laptop backlight (eDP, no DDC/CI) is driven separately via
 * brightnessctl and gated on /sys/class/backlight being present, so a desktop
 * exposes nothing.
 */
Singleton {
    id: root

    readonly property string stateFile: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ricelin/nvibrant-value"

    property int vibrance: 40

    /**
     * DDC-capable monitors from `ddcutil detect`: [{ bus, label }] with label
     * taken from the DRM connector, falling back to the I2C bus number.
     */
    property var ddcMonitors: []

    /** True once an internal backlight has been found under /sys/class/backlight. */
    property bool backlightPresent: false

    /** Current internal-backlight level, 0..100. */
    property int backlightPct: 75

    /**
     * Loads the persisted vibrance percent and applies it once, so the saved
     * tint is restored on boot. Singletons init lazily, so a startup caller
     * must reference this for the restore to fire.
     */
    function restore() {
        var raw = vibState.text();
        var v = parseInt((raw || "40").trim());
        root.vibrance = isNaN(v) ? 40 : v;
        if (raw && raw.trim().length)
            applyVibrance(root.vibrance);
    }

    /**
     * Sets the screen vibrance to `pct` percent: pushes it to nvibrant and
     * persists it to the state file. `vibrance` mirrors the last set value.
     */
    function setVibrance(pct) {
        root.vibrance = Math.round(pct);
        applyVibrance(pct);
        saveVibrance(pct);
    }

    readonly property string shaderDir: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/lumen"

    /** Flips between two shader files, since Hyprland skips a reload when the path is unchanged. */
    property bool shaderFlip: false

    /**
     * Fragment shader that boosts saturation, weighted toward dull colours so
     * already-vivid ones don't clip, which is the same idea as NVIDIA's digital
     * vibrance. The strength is baked in because screen shaders take no uniforms.
     */
    function vibranceShader(strength) {
        return "#version 300 es\n"
            + "precision highp float;\n"
            + "in vec2 v_texcoord;\n"
            + "uniform sampler2D tex;\n"
            + "out vec4 fragColor;\n"
            + "const float STRENGTH = " + strength.toFixed(3) + ";\n"
            + "void main() {\n"
            + "    vec4 c = texture(tex, v_texcoord);\n"
            + "    float luma = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));\n"
            + "    float sat = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));\n"
            + "    c.rgb = mix(vec3(luma), c.rgb, 1.0 + STRENGTH * (1.0 - sat));\n"
            + "    fragColor = vec4(clamp(c.rgb, 0.0, 1.0), c.a);\n"
            + "}\n";
    }

    /**
     * Applies vibrance as a Hyprland screen shader, which works on every
     * output whichever GPU drives it (nvibrant only reached NVIDIA outputs, so
     * it never touched an iGPU-driven laptop panel). 0% drops the shader
     * entirely, so neutral costs nothing.
     */
    function applyVibrance(pct) {
        var strength = Math.max(0, Math.min(100, pct)) / 100;
        if (strength <= 0) {
            Quickshell.execDetached(["hyprctl", "eval", 'hl.config({decoration={screen_shader=""}})']);
            return;
        }
        root.shaderFlip = !root.shaderFlip;
        var path = root.shaderDir + "/vibrance-" + (root.shaderFlip ? "a" : "b") + ".frag";
        Quickshell.execDetached(["sh", "-c",
            'mkdir -p "$(dirname "$1")" && printf "%s" "$2" > "$1" && hyprctl eval "hl.config({decoration={screen_shader=\\"$1\\"}})"',
            "_", path, root.vibranceShader(strength)]);
    }

    function saveVibrance(pct) {
        Quickshell.execDetached(["sh", "-c",
            'mkdir -p "$(dirname "$1")" && printf "%s\n" "$2" > "$1"',
            "_", root.stateFile, String(Math.round(pct))]);
    }

    function detect() {
        ddcDetect.running = true;
        blDetect.running = true;
    }

    function setBrightness(bus, pct) {
        Quickshell.execDetached(["timeout", "3", "ddcutil", "setvcp", "10",
            String(pct), "--bus", bus, "--noverify"]);
    }

    /**
     * Sets the internal laptop backlight to `pct` percent via brightnessctl.
     * No-op effect on machines without /sys/class/backlight (brightnessctl
     * simply finds no device), and inert when brightnessctl is absent.
     */
    function setBacklight(pct) {
        root.backlightPct = Math.round(Math.max(1, Math.min(100, pct)));
        Quickshell.execDetached(["brightnessctl", "set", root.backlightPct + "%"]);
    }

    /**
     * Parses a `ddcutil getvcp --brief` line, returning the current brightness
     * percent or -1 when no value is present.
     */
    function parseBrightness(text) {
        var m = text.match(/C\s+(\d+)\s+/);
        return m ? parseInt(m[1], 10) : -1;
    }

    Process {
        id: ddcDetect
        command: ["ddcutil", "detect", "--brief"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var mons = [];
                var blocks = this.text.split(/\bDisplay \d+/);
                for (var i = 0; i < blocks.length; i++) {
                    var bus = /I2C bus:\s+\/dev\/i2c-(\d+)/.exec(blocks[i]);
                    var conn = /DRM connector:\s+card\d+-(\S+)/.exec(blocks[i]);
                    if (bus)
                        mons.push({ bus: bus[1], label: conn ? conn[1] : "BUS " + bus[1] });
                }
                root.ddcMonitors = mons;
            }
        }
    }

    Process {
        id: blDetect
        command: ["sh", "-c", "dev=$(ls /sys/class/backlight 2>/dev/null | head -n1); [ -n \"$dev\" ] || exit 0; max=$(cat /sys/class/backlight/$dev/max_brightness); cur=$(cat /sys/class/backlight/$dev/brightness); echo \"$(( cur * 100 / max ))\""]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var v = parseInt(this.text.trim(), 10);
                if (!isNaN(v)) {
                    root.backlightPct = Math.max(1, Math.min(100, v));
                    root.backlightPresent = true;
                }
            }
        }
    }

    /** A config reload resets screen_shader, so the saved vibrance goes back on after it. */
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded" && root.vibrance > 0)
                root.applyVibrance(root.vibrance);
        }
    }

    /** Keeps the mixer's fader in step when the brightness keys move the backlight. */
    Connections {
        target: Backlight
        function onBrightnessChanged() {
            if (Backlight.present)
                root.backlightPct = Math.max(1, Math.round(Backlight.brightness * 100));
        }
    }

    FileView {
        id: vibState
        path: root.stateFile
        blockLoading: true
        printErrors: false
    }
}