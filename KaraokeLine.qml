pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "KaraokeModel.js" as KaraokeModel

Item {
    id: root

    property var line: null
    property real position: 0
    property bool wordTiming: false
    property bool playing: true
    property bool segmentEnabled: true
    property bool wrapEnabled: false
    property color accent: Color.accent
    property color foreground: Color.accent
    property color muted: Color.muted
    property string fontFamily: Style.font.family
    property real fontSize: Style.font.body
    readonly property color upcoming: Qt.rgba(root.foreground.r, root.foreground.g,
        root.foreground.b, 0.62)
    readonly property var paintedText: currentLayer.paintText

    FontMetrics {
        id: segmentMetrics
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
    }

    readonly property var segments: {
        var family = root.fontFamily
        var size = root.fontSize
        if (!root.line) return []
        return root.segmentEnabled
            ? KaraokeModel.segmentLine(root.line, function(text) {
                return segmentMetrics.advanceWidth(text)
            }, root.width)
            : [root.line]
    }
    readonly property int segmentIndex: root.segmentEnabled
        ? KaraokeModel.activeSegmentIndex(root.line, root.segments, root.position) : 0
    readonly property var currentSegment: root.segments[root.segmentIndex] || null
    property var displayedSegment: null
    readonly property real fullWidth: root.currentSegment
        ? Math.min(root.width, currentLayer.fullWidth) : 0

    implicitWidth: 1
    implicitHeight: Math.max(Style.font.body, currentLayer.implicitHeight)
    clip: true

    onCurrentSegmentChanged: {
        if (root.displayedSegment === root.currentSegment) return
        fadeOut.stop()
        fadeIn.stop()
        if (root.playing && root.displayedSegment && root.currentSegment) {
            previousLayer.segment = root.displayedSegment
            previousLayer.playbackPosition = root.position
            previousLayer.opacity = 1
            fadeOut.restart()
            currentLayer.opacity = 0
            fadeIn.restart()
        } else {
            previousLayer.opacity = 0
            currentLayer.opacity = 1
        }
        root.displayedSegment = root.currentSegment
    }
    onPlayingChanged: {
        if (!root.playing) {
            fadeOut.stop()
            fadeIn.stop()
            previousLayer.opacity = 0
            currentLayer.opacity = 1
        }
    }

    component LyricLayer: Item {
        id: layer
        property var segment: null
        property real playbackPosition: 0
        readonly property var projection: KaraokeModel.projectLine(segment, playbackPosition)
        readonly property bool hasWordTiming: root.wordTiming && projection.hasWordTiming === true
        readonly property real fullWidth: Math.max(0, fullMetrics.advanceWidth)
        readonly property real fillStartWidth: Math.max(0, untimedPrefixMetrics.advanceWidth)
        readonly property real sungWidth: layer.fillStartWidth + timedPrefixMetrics.advanceWidth
        readonly property real activeWidth: currentWordMetrics.advanceWidth
            * (Number(projection.wordProgress) || 0)
        readonly property var paintText: fullText
        implicitHeight: fullText.implicitHeight
        clip: true

        TextMetrics {
            id: fullMetrics
            font: fullText.font
            text: layer.projection.text || ""
        }
        TextMetrics {
            id: untimedPrefixMetrics
            font: fullText.font
            text: layer.projection.untimedPrefixText || ""
        }
        TextMetrics {
            id: timedPrefixMetrics
            font: fullText.font
            text: layer.projection.timedPrefixText || ""
        }
        TextMetrics {
            id: currentWordMetrics
            font: fullText.font
            text: layer.projection.activeWordText || ""
        }

        Text {
            id: fullText
            anchors.verticalCenter: parent.verticalCenter
            width: root.wrapEnabled ? layer.width
                : layer.hasWordTiming && !(layer.segment && layer.segment.elide)
                    ? implicitWidth : layer.width
            textFormat: root.wrapEnabled && layer.hasWordTiming ? Text.StyledText : Text.PlainText
            text: root.wrapEnabled && layer.hasWordTiming
                ? KaraokeModel.styledWordLine(layer.segment, layer.playbackPosition,
                    root.foreground.toString(), root.accent.toString(), root.upcoming.toString())
                : layer.projection.text || ""
            color: root.foreground
            opacity: layer.hasWordTiming && !root.wrapEnabled ? 0.62 : 1
            font.family: root.fontFamily
            font.pixelSize: root.fontSize
            wrapMode: root.wrapEnabled ? Text.Wrap : Text.NoWrap
            horizontalAlignment: root.wrapEnabled ? Text.AlignHCenter : Text.AlignLeft
            elide: layer.segment && layer.segment.elide ? Text.ElideRight : Text.ElideNone
            verticalAlignment: Text.AlignVCenter
        }

        Item {
            visible: layer.hasWordTiming && !root.wrapEnabled
            width: layer.sungWidth
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            clip: true
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: layer.segment && layer.segment.elide ? layer.width : layer.fullWidth
                textFormat: Text.PlainText
                text: layer.projection.text || ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: root.fontSize
                elide: layer.segment && layer.segment.elide ? Text.ElideRight : Text.ElideNone
            }
        }
        Item {
            visible: layer.hasWordTiming && !root.wrapEnabled
            x: layer.sungWidth
            width: Math.max(0, Math.min(layer.activeWidth, layer.width - x))
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            clip: true
            Text {
                x: -layer.sungWidth
                anchors.verticalCenter: parent.verticalCenter
                width: layer.segment && layer.segment.elide ? layer.width : layer.fullWidth
                textFormat: Text.PlainText
                text: layer.projection.text || ""
                color: root.accent
                opacity: root.playing ? 1 : 0.55
                font.family: root.fontFamily
                font.pixelSize: root.fontSize
                elide: layer.segment && layer.segment.elide ? Text.ElideRight : Text.ElideNone
            }
        }

    }

    LyricLayer {
        id: previousLayer
        anchors.fill: parent
        opacity: 0
    }
    LyricLayer {
        id: currentLayer
        anchors.fill: parent
        segment: root.currentSegment
        playbackPosition: root.position
    }
    NumberAnimation {
        id: fadeOut
        target: previousLayer
        property: "opacity"
        to: 0
        duration: 120
        easing.type: Easing.OutCubic
    }
    NumberAnimation {
        id: fadeIn
        target: currentLayer
        property: "opacity"
        to: 1
        duration: 210
        easing.type: Easing.OutCubic
    }
}
