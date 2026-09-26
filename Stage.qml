import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import "KaraokeModel.js" as KaraokeModel

Item {
    id: root
    property var shell: null
    property var service: null
    property var manifest: null
    property bool opened: false
    property var focusedScreen: null
    readonly property alias surface: window
    readonly property alias backdrop: dim
    readonly property alias lyric: currentLyric
    readonly property alias lyricSlot: lyricSlot
    readonly property alias nextLyric: upcomingLyric
    readonly property alias translation: translatedText
    readonly property alias countdown: countdownText
    readonly property alias trace: progressTrace
    readonly property alias card: statusCard
    readonly property alias cardTitle: cardTitleText
    readonly property alias cardArtist: cardArtistText
    readonly property alias cardState: cardStateText
    readonly property string cardMessage: {
        if (!root.service) return ""
        if (root.service.state === "not_found") return "No lyrics"
        if (root.service.state === "loading") return "Searching…"
        if (root.service.state !== "ready") return ""
        if (root.service.timing === "instrumental") return "Instrumental"
        if (root.service.timing === "none")
            return root.service.lines && root.service.lines.length > 0
                ? "Unsynced — lyrics in the panel" : "No lyrics"
        return ""
    }
    readonly property bool singing: root.service && root.service.state === "ready"
        && root.service.timing !== "none" && root.service.timing !== "instrumental"
    readonly property bool gap: root.singing && (root.service.projectionState === "interlude"
        || (root.service.projectionState === "before_first"
            && root.service.leadInDuration >= KaraokeModel.interludeThreshold()))
    // Sweep (non-wrap) mode keeps the bar's per-word clipped fill; wrap only
    // takes over when the line is wider than the slot, where a sweep could
    // not be shown at all.
    readonly property bool lyricWrap: !!currentLyric.line
        && lyricMetrics.advanceWidth(String(currentLyric.line.text || "")) > lyricSlot.width

    function open() {
        var focused = Hyprland.focusedMonitor
        for (var i = 0; i < Quickshell.screens.length; i++) {
            if (focused && Quickshell.screens[i].name === focused.name) {
                root.focusedScreen = Quickshell.screens[i]
                break
            }
        }
        if (!root.focusedScreen) root.focusedScreen = Quickshell.screens[0]
        root.opened = true
        if (root.service && typeof root.service.requestStageCloseCheck === "function")
            root.service.requestStageCloseCheck()
    }
    function close() { root.opened = false }
    Connections {
        target: root.service
        ignoreUnknownSignals: true
        function onStageCloseRequested() {
            if (root.shell) root.shell.hide("n501.karaoke")
        }
    }

    PanelWindow {
        id: window
        visible: root.opened
        screen: root.focusedScreen
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Normal
        WlrLayershell.namespace: "n501-karaoke-stage"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region {}

        Rectangle {
            id: dim
            anchors.fill: parent
            color: Color.background
            opacity: 0.8
        }

        FontMetrics {
            id: lyricMetrics
            font.family: Style.font.family
            font.pixelSize: 64
        }

        Item {
            id: lyricSlot
            width: parent.width * 0.8
            height: Math.max(currentLyric.implicitHeight, 80)
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.70 - height / 2
            KaraokeLine {
                id: currentLyric
                visible: root.singing && root.service.projectionState === "line"
                    && !!root.service.currentLine
                width: root.lyricWrap ? parent.width
                    : Math.min(parent.width, lyricMetrics.advanceWidth(
                        String(root.service && root.service.currentLine
                            ? root.service.currentLine.text || "" : "")) + 2)
                height: parent.height
                anchors.horizontalCenter: parent.horizontalCenter
                line: root.service ? root.service.currentLine : null
                position: root.service ? root.service.position : 0
                wordTiming: root.service ? root.service.timing === "word" : false
                playing: root.service && root.service.activePlayer
                    ? root.service.activePlayer.isPlaying : true
                motionEnabled: root.service ? root.service.motionEnabled !== false : true
                trackKey: root.service ? String(root.service.trackKey || "") : ""
                segmentEnabled: false
                wrapEnabled: root.lyricWrap
                foreground: Color.popups.text
                accent: Color.accent
                fontSize: 64
            }
        }
        Text {
            id: translatedText
            visible: currentLyric.visible && root.service.translationsVisible !== false
                && text !== ""
            width: lyricSlot.width
            anchors.horizontalCenter: lyricSlot.horizontalCenter
            anchors.top: lyricSlot.bottom
            anchors.topMargin: 12
            textFormat: Text.PlainText
            text: currentLyric.visible ? String(root.service.currentLine.translation || "") : ""
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: 28
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
        }

        KaraokeLine {
            id: upcomingLyric
            readonly property var following: root.service && root.service.lines
                ? root.service.lines[root.service.activeLineIndex + 1] : null
            visible: currentLyric.visible && !!following
            width: lyricSlot.width
            height: Math.max(implicitHeight, 48)
            anchors.horizontalCenter: lyricSlot.horizontalCenter
            anchors.top: translatedText.visible ? translatedText.bottom : lyricSlot.bottom
            anchors.topMargin: 24
            line: visible ? following : null
            position: line ? line.start : 0
            playing: false
            motionEnabled: false
            wordTiming: false
            segmentEnabled: false
            wrapEnabled: true
            foreground: Color.muted
            fontSize: 36
        }

        Item {
            id: progressTrace
            visible: root.gap && root.service.countdownStep > 0
            width: Math.min(parent.width * 0.4, 360)
            height: 10
            x: (parent.width - width) / 2
            y: parent.height * 0.70 - 45
            readonly property real progress: root.service
                ? root.service.projectionState === "before_first"
                    ? root.service.leadInProgress : root.service.interludeProgress : 0
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 3
                radius: 1.5
                color: Color.muted
                opacity: 0.5
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * Math.max(0, Math.min(1, progressTrace.progress))
                height: 3
                radius: 1.5
                color: Color.accent
            }
        }
        Text {
            id: countdownText
            visible: progressTrace.visible
            anchors.horizontalCenter: progressTrace.horizontalCenter
            anchors.top: progressTrace.bottom
            text: root.service ? root.service.countdownStep === 3 ? "● ● ●"
                : root.service.countdownStep === 2 ? "● ● ○" : "● ○ ○" : ""
            color: Color.accent
            font.family: Style.font.family
            font.pixelSize: 32
        }
        Rectangle {
            id: statusCard
            visible: root.cardMessage !== ""
            width: Math.min(parent.width * 0.8, 640)
            height: statusContent.implicitHeight + 64
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.70 - height / 2
            radius: 16
            color: Color.background
            border.color: Color.muted
            border.width: 1

            Column {
                id: statusContent
                width: parent.width - 64
                anchors.centerIn: parent
                spacing: 12
                Text {
                    id: cardTitleText
                    width: parent.width
                    textFormat: Text.PlainText
                    text: root.service && root.service.activePlayer
                        ? String(root.service.activePlayer.trackTitle || "") : ""
                    color: Color.popups.text
                    font.family: Style.font.family
                    font.pixelSize: 36
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }
                Text {
                    id: cardArtistText
                    width: parent.width
                    textFormat: Text.PlainText
                    text: root.service && root.service.activePlayer
                        ? String(root.service.activePlayer.trackArtist || "") : ""
                    color: Color.muted
                    font.family: Style.font.family
                    font.pixelSize: 24
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }
                Text {
                    id: cardStateText
                    width: parent.width
                    textFormat: Text.PlainText
                    text: root.cardMessage
                    color: Color.accent
                    font.family: Style.font.family
                    font.pixelSize: 24
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }
            }
        }
    }
}
