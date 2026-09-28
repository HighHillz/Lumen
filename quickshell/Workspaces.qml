pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell.Hyprland
import "Singletons"

/**
 * Numbered workspace circles for one monitor. Each in-use workspace is a small
 * circle with its number inside: dim grey when inactive (brightening on hover),
 * filled with the theme colour when active. Clicking a circle focuses that
 * workspace via the Hyprland-lua dispatcher. Active marker tracks the
 * monitor's live active workspace name from the Hyprland model.
 *
 * Only workspaces in use are shown: those on this monitor holding at least one
 * window, plus the active one (even if empty). Rule-assigned but empty
 * workspaces ([[Workspacerules]]) stay hidden until something lands on them.
 */
Item {
    id: workspaces

    property string screenName: ""
    property real s: 1
    property real dotW: 13 * s
    property real gap: 1 * s

    readonly property var range: {
        var out = [];
        var seen = ({});
        var wss = Hyprland.workspaces.values;
        for (var i = 0; i < wss.length; i++) {
            var w = wss[i];
            if (w.id >= 1 && w.monitor && w.monitor.name === screenName && !seen[w.id]
                    && w.toplevels.values.length > 0) {
                seen[w.id] = true;
                out.push(w.id);
            }
        }
        var a = parseInt(activeName);
        if (a >= 1 && !seen[a])
            out.push(a);
        out.sort(function (x, y) { return x - y; });
        return out;
    }

    readonly property string activeName: {
        var mons = Hyprland.monitors.values;
        for (var i = 0; i < mons.length; i++)
            if (mons[i].name === screenName)
                return mons[i].activeWorkspace ? mons[i].activeWorkspace.name : "";
        return "";
    }

    property int hoverIndex: -1

    readonly property int activeIndex: range.indexOf(parseInt(activeName))

    /** Centre x of a circle slot; every slot is the same width. */
    function slotCenterX(idx) {
        return idx * (dotW + gap) + dotW / 2;
    }

    readonly property point activeDotPoint: {
        void workspaces.activeName;
        void workspaces.width;
        return Qt.point(slotCenterX(Math.max(0, activeIndex)), height / 2);
    }

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    RowLayout {
        id: row
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: workspaces.gap

        Repeater {
            model: workspaces.range

            delegate: Item {
                id: slot

                required property var modelData
                required property int index

                readonly property string wsName: String(modelData)
                readonly property bool isActive: workspaces.activeName === wsName

                Layout.preferredWidth: workspaces.dotW
                Layout.preferredHeight: 22 * workspaces.s

                // Soft, even glow around the active circle (no offset).
                RectangularShadow {
                    anchors.centerIn: parent
                    width: workspaces.dotW
                    height: workspaces.dotW
                    radius: width / 2
                    blur: 6 * workspaces.s
                    spread: 0
                    color: Qt.alpha(Theme.vermLit, 0.7)
                    opacity: slot.isActive ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: workspaces.dotW
                    height: workspaces.dotW
                    radius: height / 2
                    color: slot.isActive ? Theme.vermLit
                         : Qt.alpha(Theme.cream, area.containsMouse ? 0.28 : 0.14)
                    Behavior on color { ColorAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

                    Text {
                        anchors.centerIn: parent
                        text: slot.wsName
                        font.family: Theme.font
                        font.pixelSize: 9 * workspaces.s
                        font.weight: Font.DemiBold
                        color: slot.isActive ? Theme.tileBg : Theme.cream
                        opacity: slot.isActive ? 1.0 : (area.containsMouse ? 0.95 : 0.7)
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                    }
                }

                MouseArea {
                    id: area
                    anchors.fill: parent
                    anchors.leftMargin: -workspaces.gap / 2
                    anchors.rightMargin: -workspaces.gap / 2
                    anchors.topMargin: -8 * workspaces.s
                    anchors.bottomMargin: -8 * workspaces.s
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Hyprland.dispatch('hl.dsp.focus({workspace="' + slot.wsName + '"})')
                    onContainsMouseChanged: {
                        if (containsMouse)
                            workspaces.hoverIndex = slot.index;
                        else if (workspaces.hoverIndex === slot.index)
                            workspaces.hoverIndex = -1;
                    }
                }
            }
        }
    }
}
