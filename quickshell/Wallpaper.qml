pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "Singletons"

/**
 * Wallpaper surface: a filmstrip over the wallpaper directory, rendered as one
 * of the pill's surfaces. Thumbs come from the Walls singleton snapshot, newest
 * first. An album dropdown in the header narrows the strip to one subfolder
 * (or All) and holds the automatic shuffle interval; both persist in Flags. The focused thumb is large and fully lit; neighbours shrink, dim and
 * desaturate as they slide under it, so the strip reads as depth. Arrow keys
 * and wheel move focus, clicking a neighbour glides to it, Enter or a tap on
 * the focused thumb applies it via wallpaper.sh (strip stays open so you can
 * keep trying picks). Hold the focused thumb for the heat duration to trash the
 * file (press-and-hold confirm, same as the clipboard wipe); progress sweeps
 * along the thumb's lower edge and drains on early release.
 */
PillSurface {
    id: root

    property int focusIndex: 0

    /** Selected album (subfolder), "" for every wallpaper. Persisted in Flags. */
    readonly property string album: Flags.wallpaperAlbum

    /** True while the album dropdown panel is open. */
    property bool albumOpen: false

    /** Shuffle intervals offered in the dropdown, in minutes; 0 is off. */
    readonly property var shuffleSteps: [0, 5, 15, 30, 60]

    function shuffleLabel(min) {
        return min === 0 ? "off" : (min >= 60 ? (min / 60) + "h" : min + "m");
    }

    /**
     * Miniature of the physical monitor arrangement, shown on the focused tile
     * when more than one screen is connected. Logical rects are fitted into a
     * small box, keeping their real positions; clicking one sends the pick to
     * that output only, while a tap on the tile itself keeps meaning all.
     */
    readonly property var monMap: {
        var scr = Quickshell.screens;
        if (scr.length < 2)
            return { w: 0, h: 0, tiles: [] };
        var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
        for (var i = 0; i < scr.length; i++) {
            minX = Math.min(minX, scr[i].x);
            minY = Math.min(minY, scr[i].y);
            maxX = Math.max(maxX, scr[i].x + scr[i].width);
            maxY = Math.max(maxY, scr[i].y + scr[i].height);
        }
        var k = Math.min(Math.min(26 * scr.length, 120) * s / (maxX - minX), (22 * s) / (maxY - minY));
        var tiles = [];
        for (i = 0; i < scr.length; i++)
            tiles.push({
                name: scr[i].name,
                x: (scr[i].x - minX) * k,
                y: (scr[i].y - minY) * k,
                w: scr[i].width * k,
                h: scr[i].height * k
            });
        return { w: (maxX - minX) * k, h: (maxY - minY) * k, tiles: tiles };
    }

    readonly property var localItems: {
        if (album.length === 0)
            return Walls.entries;
        var out = [];
        for (var i = 0; i < Walls.entries.length; i++)
            if (Walls.entries[i].album === album)
                out.push(Walls.entries[i]);
        return out;
    }

    /**
     * Re-centre after a filter switch. Deferred with callLater because this
     * handler fires before dependent bindings refresh, so a direct call would
     * still see the previous filter's list and park the strip on an index the
     * new list does not have.
     */
    onAlbumChanged: Qt.callLater(centerOnCurrent)

    readonly property var items: localItems
    readonly property int itemCount: items.length

    /**
     * Gesture hint visibility. Hidden while the focus is moving so paging
     * through wallpapers stays clean; the dwell timer reveals it only once the
     * pick has been held still, so it reads as a quiet caption, not a nag.
     */
    property bool hintShown: false

    /** Output name under the pointer in the focused tile's screen picker, "" when none. */
    property string monHover: ""

    /**
     * Preview arming: playback and the dimension probe only start once the
     * focus has rested for a beat, so wheeling through the strip never churns
     * decoders or process spawns per step.
     */
    property bool previewArmed: true

    onFocusIndexChanged: {
        hintShown = false;
        hintDwell.restart();
        previewArmed = false;
        previewArm.restart();
    }

    Timer {
        id: previewArm
        interval: 300
        onTriggered: root.previewArmed = true
    }

    onItemsChanged: if (focusIndex >= itemCount) focusIndex = Math.max(0, itemCount - 1);

    Timer {
        id: hintDwell
        interval: 600
        onTriggered: root.hintShown = true
    }

    /**
     * Continuous view position chasing focusIndex. The strip renders from this
     * single value, so any input rate (40Hz key autorepeat, wheel bursts) stays
     * coherent: lag is bounded by the chase time constant, not piled up across
     * per-tile retargeting animations.
     */
    property real pos: 0

    clip: true

    readonly property var slotW:      [196, 126, 104, 88, 74]
    readonly property var slotH:      [110, 71, 59, 50, 42]
    readonly property var slotCX:     [0, 143, 244, 326, 393]
    readonly property var slotBright: [1, 0.56, 0.42, 0.30, 0.22]
    readonly property var slotSat:    [1, 0.65, 0.55, 0.45, 0.40]

    function slotLerp(arr, ao) {
        if (ao >= 4)
            return arr[4];
        var i = Math.floor(ao);
        var f = ao - i;
        return arr[i] + (arr[i + 1] - arr[i]) * f;
    }

    function offsetX(off) {
        var ao = Math.abs(off);
        var cx = ao <= 4 ? slotLerp(slotCX, ao) : slotCX[4] + (ao - 4) * 60;
        return (off < 0 ? -cx : cx) * s;
    }

    function move(delta) {
        if (itemCount === 0)
            return;
        focusIndex = Math.max(0, Math.min(itemCount - 1, focusIndex + delta));
    }

    FrameAnimation {
        running: root.active && root.pos !== root.focusIndex
        onTriggered: {
            var k = 1 - Math.exp(-frameTime / 0.07);
            var next = root.pos + (root.focusIndex - root.pos) * k;
            root.pos = Math.abs(next - root.focusIndex) < 0.001 ? root.focusIndex : next;
        }
    }

    function activate() {
        if (focusIndex < 0 || focusIndex >= itemCount)
            return;
        Walls.apply(items[focusIndex].path);
    }

    function centerOnCurrent() {
        var idx = 0;
        for (var i = 0; i < localItems.length; i++)
            if (localItems[i].path === Walls.current) {
                idx = i;
                break;
            }
        focusIndex = idx;
        pos = idx;
    }

    onActiveChanged: if (active) {
        albumOpen = false;
        Walls.refresh();
        centerOnCurrent();
        hintShown = false;
        hintDwell.restart();
    }

    Connections {
        target: Walls
        function onEntriesChanged() {
            if (root.focusIndex >= Walls.count)
                root.focusIndex = Math.max(0, Walls.count - 1);
        }
    }

    /**
     * Local resolution badge. Dimensions are probed lazily for the focused
     * tile only (ffprobe reads images and videos alike) and cached per path,
     * so browsing stays cheap and revisits are instant.
     */
    property var dimsCache: ({})

    readonly property string focusedLocalPath: {
        if (focusIndex < 0 || focusIndex >= itemCount)
            return "";
        var e = items[focusIndex];
        return (e && e.path !== undefined) ? e.path : "";
    }

    onFocusedLocalPathChanged: dimsDebounce.restart()

    Timer {
        id: dimsDebounce
        interval: 320
        onTriggered: {
            var p = root.focusedLocalPath;
            if (p === "" || root.dimsCache[p] !== undefined)
                return;
            dimsProc.running = false;
            dimsProc.path = p;
            dimsProc.command = ["sh", "-c",
                "ffprobe -v quiet -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 \"$1\" | head -1",
                "_", p];
            dimsProc.running = true;
        }
    }

    Process {
        id: dimsProc
        property string path: ""
        stdout: StdioCollector {
            onStreamFinished: {
                var t = this.text.trim();
                if (t.length && dimsProc.path.length) {
                    var c = Object.assign({}, root.dimsCache);
                    c[dimsProc.path] = t;
                    root.dimsCache = c;
                }
            }
        }
    }

    /**
     * Album dropdown: a capsule naming the album on screen (plus the shuffle
     * interval when one runs) that folds open a panel listing All and every
     * album with its count, and a shuffle row underneath. Picking an album
     * narrows the strip and the random pool; picking an interval starts or
     * stops the automatic shuffle in Walls.
     */
    Rectangle {
        id: albumBtn
        anchors.top: parent.top
        anchors.topMargin: 9 * root.s
        anchors.right: parent.right
        anchors.rightMargin: 14 * root.s
        z: 40
        width: albumBtnRow.implicitWidth + 20 * root.s
        height: 22 * root.s
        radius: height / 2
        color: root.albumOpen ? Qt.alpha(Theme.onGlow, 0.18) : Theme.frameBg
        border.width: 1
        border.color: root.albumOpen ? Qt.alpha(Theme.onGlow, 0.45) : (albumBtnHover.hovered ? Theme.border : Theme.hairSoft)
        Behavior on color { ColorAnimation { duration: Motion.fast } }

        Row {
            id: albumBtnRow
            anchors.centerIn: parent
            spacing: 5 * root.s

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.album.length > 0 ? root.album : "All"
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 9.5 * root.s
                font.weight: Font.DemiBold
                font.letterSpacing: 0.4 * root.s
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: Flags.wallpaperShuffleMin > 0
                text: "· " + root.shuffleLabel(Flags.wallpaperShuffleMin)
                color: Theme.vermLit
                font.family: Theme.font
                font.pixelSize: 9.5 * root.s
                font.weight: Font.DemiBold
            }

            GlyphIcon {
                anchors.verticalCenter: parent.verticalCenter
                width: 10 * root.s
                height: 10 * root.s
                name: root.albumOpen ? "chevron-up" : "chevron-down"
                color: Theme.subtle
                stroke: 2
            }
        }

        HoverHandler {
            id: albumBtnHover
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.albumOpen = !root.albumOpen
        }
    }

    /** Click-away catcher: any click outside the open panel closes it. */
    MouseArea {
        anchors.fill: parent
        z: 45
        visible: root.albumOpen
        onClicked: root.albumOpen = false
    }

    component AlbumRow: Rectangle {
        id: arow

        property string value: ""
        property string label: ""
        property int count: 0
        readonly property bool selected: root.album === value

        width: albumList.cellWidth - 2 * root.s
        height: albumList.cellHeight - 2 * root.s
        radius: 6 * root.s
        color: selected ? Qt.alpha(Theme.onGlow, 0.16) : (arowHover.hovered ? Theme.frameBg : "transparent")

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 9 * root.s
            anchors.right: arowCount.left
            anchors.rightMargin: 8 * root.s
            anchors.verticalCenter: parent.verticalCenter
            text: arow.label
            elide: Text.ElideRight
            color: arow.selected ? Theme.cream : Theme.subtle
            font.family: Theme.font
            font.pixelSize: 10 * root.s
            font.weight: arow.selected ? Font.DemiBold : Font.Medium
        }

        Text {
            id: arowCount
            anchors.right: parent.right
            anchors.rightMargin: 9 * root.s
            anchors.verticalCenter: parent.verticalCenter
            text: arow.count
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 9 * root.s
            font.features: { "tnum": 1 }
        }

        HoverHandler {
            id: arowHover
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                Flags.wallpaperAlbum = arow.value;
                root.albumOpen = false;
            }
        }
    }

    Rectangle {
        id: albumPanel
        anchors.top: albumBtn.bottom
        anchors.topMargin: 5 * root.s
        anchors.right: albumBtn.right
        z: 50
        visible: root.albumOpen
        width: 250 * root.s
        height: Math.min(albumList.contentHeight, root.height - y - shuffleBox.height - 22 * root.s) + shuffleBox.height + 14 * root.s
        radius: 10 * root.s
        color: Theme.tileBg
        border.width: 1
        border.color: Theme.border

        // Swallow clicks on the panel's own padding so they don't close it.
        MouseArea {
            anchors.fill: parent
        }

        GridView {
            id: albumList
            anchors.top: parent.top
            anchors.topMargin: 5 * root.s
            anchors.left: parent.left
            anchors.leftMargin: 5 * root.s
            anchors.right: parent.right
            anchors.rightMargin: 5 * root.s
            height: parent.height - shuffleBox.height - 14 * root.s
            clip: true
            cellWidth: width / 2
            cellHeight: 22 * root.s
            boundsBehavior: Flickable.StopAtBounds
            model: [{ name: "", label: "All", count: Walls.count }].concat(Walls.albums.map(function (a) {
                return { name: a.name, label: a.name, count: a.count };
            }))
            delegate: AlbumRow {
                required property var modelData
                value: modelData.name
                label: modelData.label
                count: modelData.count
            }
        }

        Rectangle {
            anchors.bottom: shuffleBox.top
            anchors.left: parent.left
            anchors.leftMargin: 9 * root.s
            anchors.right: parent.right
            anchors.rightMargin: 9 * root.s
            height: 1
            color: Theme.hairSoft
        }

        Item {
            id: shuffleBox
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 4 * root.s
            anchors.left: parent.left
            anchors.leftMargin: 9 * root.s
            anchors.right: parent.right
            anchors.rightMargin: 6 * root.s
            height: 26 * root.s

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Shuffle"
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 10 * root.s
                font.weight: Font.Medium
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1 * root.s

                Repeater {
                    model: root.shuffleSteps

                    delegate: Rectangle {
                        id: step

                        required property int modelData
                        readonly property bool on: Flags.wallpaperShuffleMin === modelData

                        width: stepText.implicitWidth + 9 * root.s
                        height: 18 * root.s
                        radius: height / 2
                        color: on ? Qt.alpha(Theme.onGlow, 0.18) : (stepHover.hovered ? Theme.frameBg : "transparent")
                        border.width: on ? 1 : 0
                        border.color: Qt.alpha(Theme.onGlow, 0.45)

                        Text {
                            id: stepText
                            anchors.centerIn: parent
                            text: root.shuffleLabel(step.modelData)
                            color: step.on ? Theme.cream : Theme.faint
                            font.family: Theme.font
                            font.pixelSize: 9 * root.s
                            font.weight: Font.DemiBold
                        }

                        HoverHandler {
                            id: stepHover
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Flags.wallpaperShuffleMin = step.modelData
                        }
                    }
                }
            }
        }
    }

    Repeater {
        model: root.items

        delegate: Item {
            id: tile

            required property int index
            required property var modelData

            readonly property string thumbSource: "file://" + modelData.thumb

            /**
             * Live preview gating: only the focused tile plays, and only once
             * the strip has settled on it, so paging never spins up decoders.
             * Gifs play in place, videos
             * loop muted through the ffmpeg backend; everything else keeps the
             * static thumb, which also stays underneath as the loading frame.
             */
            readonly property bool isGif: /\.gif$/i.test(modelData.path)
            readonly property string videoSource: /\.(mp4|webm|mkv|mov)$/i.test(modelData.path) ? "file://" + modelData.path : ""
            readonly property bool showPreview: focused && root.previewArmed && ao < 0.5
            readonly property string resLabel: root.dimsCache[modelData.path] !== undefined ? root.dimsCache[modelData.path] : ""
            readonly property bool motion: /\.(gif|mp4|webm|mkv|mov)$/i.test(modelData.path)

            readonly property real off: index - root.pos
            readonly property real ao: Math.abs(off)
            readonly property bool focused: index === root.focusIndex
            readonly property real bright: root.slotLerp(root.slotBright, ao)
            readonly property real sat: root.slotLerp(root.slotSat, ao)
            readonly property real corner: (8 + 2 * Math.max(0, 1 - ao)) * root.s

            readonly property real hold: trashHeat.hold
            readonly property bool committing: trashHeat.hold >= trashHeat.tapThreshold
            readonly property real commitProgress: Math.max(0, (trashHeat.hold - trashHeat.tapThreshold) / (1 - trashHeat.tapThreshold))

            /**
             * Fade a tile out as its outer edge nears the clipped strip
             * boundary, so the strip ends soften instead of getting hard-cut by
             * the pill's clip.
             */
            readonly property real edgeFade: {
                var soft = 70 * root.s;
                var gap = Math.min(x, root.width - (x + width));
                return Math.max(0, Math.min(1, gap / soft));
            }

            width: root.slotLerp(root.slotW, ao) * root.s
            height: root.slotLerp(root.slotH, ao) * root.s
            x: root.width / 2 + root.offsetX(off) - width / 2
            y: (root.height - height) / 2
            z: 10 - ao
            visible: ao <= 5
            opacity: edgeFade * (ao <= 4 ? 1 : Math.max(0, 5 - ao))

            onFocusedChanged: if (!focused) trashHeat.cancel()

            ClippingRectangle {
                id: card
                anchors.fill: parent
                radius: tile.corner
                color: Theme.tileBg

                layer.enabled: true
                layer.effect: MultiEffect {
                    saturation: tile.sat - 1
                    shadowEnabled: tile.focused
                    shadowColor: Qt.rgba(0, 0, 0, Theme.shadowOpacity)
                    shadowBlur: 0.7
                    shadowVerticalOffset: 4 * root.s
                }

                Image {
                    id: thumbImage
                    anchors.fill: parent
                    source: tile.ao <= 6 ? tile.thumbSource : ""
                    sourceSize.width: 512
                    sourceSize.height: 220
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                }

                Rectangle {
                    anchors.fill: parent
                    color: Theme.tileBg
                    visible: thumbImage.status === Image.Error
                }

                AnimatedImage {
                    anchors.fill: parent
                    source: tile.showPreview && tile.isGif ? "file://" + tile.modelData.path : ""
                    playing: source != ""
                    visible: status === AnimatedImage.Ready
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                }

                Loader {
                    anchors.fill: parent
                    active: tile.showPreview && tile.videoSource !== ""

                    sourceComponent: Item {
                        VideoOutput {
                            id: videoPreview
                            anchors.fill: parent
                            fillMode: VideoOutput.PreserveAspectCrop
                            visible: vidPlayer.playbackState === MediaPlayer.PlayingState
                        }

                        MediaPlayer {
                            id: vidPlayer
                            videoOutput: videoPreview
                            loops: MediaPlayer.Infinite
                            source: tile.videoSource
                            onMediaStatusChanged: if (mediaStatus === MediaPlayer.LoadedMedia) play()
                        }
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(0, 0, 0, 1)
                    opacity: 1 - tile.bright
                }

                Rectangle {
                    id: consume
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: card.height * tile.commitProgress
                    visible: tile.committing
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.alpha(Theme.vermBurn, 0.66) }
                        GradientStop { position: 0.74; color: Qt.alpha(Theme.vermLit, 0.30) }
                        GradientStop { position: 1.0; color: Qt.alpha(Theme.flameGlow, 0.0) }
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: 2 * root.s
                        opacity: Math.min(1, tile.commitProgress * 3)
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: Qt.alpha(Theme.flameGlow, 0.0) }
                            GradientStop { position: 0.5; color: Theme.flameGlow }
                            GradientStop { position: 1.0; color: Qt.alpha(Theme.flameGlow, 0.0) }
                        }
                    }
                }

                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.margins: 5 * root.s
                    visible: tile.motion
                    width: motionText.implicitWidth + 9 * root.s
                    height: motionText.implicitHeight + 4 * root.s
                    radius: height / 2
                    color: Qt.rgba(0, 0, 0, 0.55)

                    Text {
                        id: motionText
                        anchors.centerIn: parent
                        text: "▶"
                        color: Theme.cream
                        font.family: Theme.font
                        font.pixelSize: 7.5 * root.s
                    }
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottomMargin: 6 * root.s
                    visible: tile.focused && tile.resLabel.length > 0
                    width: resText.implicitWidth + 12 * root.s
                    height: resText.implicitHeight + 5 * root.s
                    radius: height / 2
                    color: Qt.rgba(0, 0, 0, 0.55)
                    Text {
                        id: resText
                        anchors.centerIn: parent
                        text: tile.resLabel.replace("x", "×")
                        color: Theme.bright
                        font.family: Theme.font
                        font.pixelSize: 9.5 * root.s
                        font.features: { "tnum": 1 }
                    }
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: tile.corner
                color: "transparent"
                border.width: 1
                border.color: tile.committing ? Theme.vermLit : Theme.border
                Behavior on border.color { ColorAnimation { duration: Motion.fast } }
            }

            HeatHold {
                id: trashHeat
                tapThreshold: 0.25
                onConfirmed: Walls.trash(tile.modelData.path)
                onTapped: root.activate()
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPressed: {
                    if (tile.focused)
                        trashHeat.press();
                }
                onReleased: if (tile.focused) trashHeat.release()
                onExited: trashHeat.cancel()
                onClicked: if (!tile.focused) root.focusIndex = tile.index
            }

            /**
             * Per-screen picker riding the focused tile's upper right corner.
             * Hovering a screen rect names it in the backing pill and lights
             * it, so the miniature reads as "send this pick to that monitor"
             * without a legend. Sits above the tile's press area, so a click
             * here never reaches the trash HeatHold underneath.
             */
            Rectangle {
                id: monPick

                property string hoverOut: ""

                onHoverOutChanged: if (tile.focused) root.monHover = hoverOut

                visible: tile.focused && root.monMap.tiles.length > 0
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 5 * root.s
                width: hoverLabel.width + screenRects.width + 12 * root.s
                height: screenRects.height + 8 * root.s
                radius: 6 * root.s
                color: Qt.rgba(0, 0, 0, 0.62)

                Behavior on width { NumberAnimation { duration: Motion.fast } }

                Text {
                    id: hoverLabel
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: screenRects.left
                    anchors.rightMargin: monPick.hoverOut.length > 0 ? 6 * root.s : 0
                    width: monPick.hoverOut.length > 0 ? implicitWidth : 0
                    clip: true
                    text: monPick.hoverOut
                    color: Theme.cream
                    font.family: Theme.font
                    font.pixelSize: 9 * root.s
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.3 * root.s
                }

                Item {
                    id: screenRects
                    anchors.right: parent.right
                    anchors.rightMargin: 5 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.monMap.w
                    height: root.monMap.h

                    Repeater {
                        model: root.monMap.tiles

                        delegate: Rectangle {
                            id: mrect
                            required property var modelData

                            x: mrect.modelData.x + 0.75 * root.s
                            y: mrect.modelData.y + 0.75 * root.s
                            width: Math.max(2, mrect.modelData.w - 1.5 * root.s)
                            height: Math.max(2, mrect.modelData.h - 1.5 * root.s)
                            radius: 3 * root.s
                            color: monHover.hovered ? Qt.alpha(Theme.vermLit, 0.45) : Qt.rgba(1, 1, 1, 0.10)
                            border.width: 1
                            border.color: monHover.hovered ? Theme.vermLit : Qt.rgba(1, 1, 1, 0.35)

                            Behavior on color { ColorAnimation { duration: Motion.fast } }
                            Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                            HoverHandler {
                                id: monHover
                                onHoveredChanged: monPick.hoverOut = hovered ? mrect.modelData.name : (monPick.hoverOut === mrect.modelData.name ? "" : monPick.hoverOut)
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Walls.apply(tile.modelData.path, mrect.modelData.name)
                            }
                        }
                    }
                }
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: root.itemCount === 0
        text: root.album.length > 0 ? "No wallpapers in " + root.album : "No wallpapers in " + Walls.wpDir
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 10.5 * root.s
    }

    component HintKey: Row {
        id: hk

        property string key: ""
        property string caption: ""

        spacing: 5 * root.s

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: keyText.implicitWidth + 11 * root.s
            height: keyText.implicitHeight + 6 * root.s
            radius: 5 * root.s
            color: Theme.frameBg
            border.width: 1
            border.color: Theme.hairSoft

            Text {
                id: keyText
                anchors.centerIn: parent
                text: hk.key
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 8.5 * root.s
                font.weight: Font.DemiBold
                font.letterSpacing: 0.5 * root.s
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: hk.caption
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 9.5 * root.s
            font.weight: Font.Medium
            font.letterSpacing: 0.3 * root.s
        }
    }

    /**
     * Gesture legend: keycap chips for tap / corner / hold instead of one grey
     * text line. Hovering a screen rect swaps the whole legend for a single
     * "set on <output> only" caption, so the corner action explains itself the
     * moment it is about to happen.
     */
    Item {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 9 * root.s
        width: hintLegend.width
        height: hintLegend.height
        visible: root.itemCount > 0
        opacity: (root.hintShown || root.monHover.length > 0) ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.standard } }

        Row {
            id: hintLegend
            spacing: 14 * root.s
            visible: root.monHover.length === 0

            HintKey { key: "tap"; caption: root.monMap.tiles.length > 0 ? "set all" : "set" }
            HintKey { visible: root.monMap.tiles.length > 0; key: "corner"; caption: "one screen" }
            HintKey { key: "hold"; caption: "delete" }
        }

        Text {
            anchors.centerIn: parent
            visible: root.monHover.length > 0
            text: "set on " + root.monHover + " only"
            color: Theme.cream
            font.family: Theme.font
            font.pixelSize: 10 * root.s
            font.weight: Font.DemiBold
            font.letterSpacing: 0.4 * root.s
        }
    }

    MouseArea {
        id: wheelArea
        anchors.fill: parent
        z: 20
        acceptedButtons: Qt.NoButton
        property real acc: 0
        onWheel: (event) => {
            acc += event.angleDelta.y / 120;
            const notches = Math.trunc(acc);
            if (notches !== 0) {
                root.move(-notches);
                acc -= notches;
            }
            event.accepted = true;
        }
    }
}
