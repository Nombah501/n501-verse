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
    property color foreground: Color.accent
    property color muted: Color.muted
    property string fontFamily: Style.font.family
    property real fontSize: Style.font.body
    readonly property var projection: KaraokeModel.projectLine(line, position)
    readonly property string filledText: projection.filledText || ""
    readonly property string activeWordText: projection.activeWordText || ""
    readonly property string remainingText: projection.remainingText || ""
    readonly property real wordProgress: Number(projection.wordProgress) || 0
    readonly property bool hasWordTiming: wordTiming && projection.hasWordTiming === true

    implicitWidth: 1
    implicitHeight: Math.max(Style.font.body, fullText.implicitHeight)
    clip: true

    TextMetrics {
        id: fullMetrics
        font: fullText.font
        text: projection.text || ""
    }

    TextMetrics {
        id: untimedPrefixMetrics
        font: fullText.font
        text: projection.untimedPrefixText || ""
    }

    TextMetrics {
        id: timedPrefixMetrics
        font: fullText.font
        text: projection.timedPrefixText || ""
    }

    TextMetrics {
        id: prefixMetrics
        font: fullText.font
        text: projection.prefixText || ""
    }

    TextMetrics {
        id: currentWordMetrics
        font: fullText.font
        text: projection.activeWordText || ""
    }

    readonly property real fullWidth: Math.max(0, fullMetrics.advanceWidth)
    readonly property real fillStartWidth: Math.max(0, untimedPrefixMetrics.advanceWidth)
    readonly property real fillWidth: root.hasWordTiming
        ? Math.max(0, Math.min(root.fullWidth,
            root.fillStartWidth + timedPrefixMetrics.advanceWidth
                + currentWordMetrics.advanceWidth * root.wordProgress))
        : 0
    readonly property real panOffset: {
        if (root.fullWidth <= root.width || !root.hasWordTiming) return 0
        var center = prefixMetrics.advanceWidth + currentWordMetrics.advanceWidth * 0.5
        return Math.max(0, Math.min(root.fullWidth - root.width, center - root.width * 0.5))
    }

    Item {
        id: viewport
        anchors.fill: parent
        clip: true

        Item {
            id: content
            x: -root.panOffset
            width: Math.max(root.fullWidth, viewport.width)
            height: viewport.height

            Text {
                id: fullText
                anchors.verticalCenter: parent.verticalCenter
                width: root.hasWordTiming ? fullText.implicitWidth : viewport.width
                textFormat: Text.PlainText
                text: root.projection.text || ""
                color: root.hasWordTiming ? root.muted : root.foreground
                font.family: root.fontFamily
                font.pixelSize: root.fontSize
                elide: root.hasWordTiming ? Text.ElideNone : Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }

            Item {
                id: accentClip
                visible: root.hasWordTiming
                x: root.fillStartWidth
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Math.max(0, root.fillWidth - root.fillStartWidth)
                clip: true

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: root.projection.timedText || ""
                    color: root.foreground
                    opacity: root.playing ? 1.0 : 0.55
                    font.family: root.fontFamily
                    font.pixelSize: root.fontSize
                    elide: Text.ElideNone
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }
}
