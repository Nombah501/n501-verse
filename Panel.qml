pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "KaraokeModel.js" as KaraokeModel

Panel {
    id: root
    moduleName: "n501.karaoke"
    ipcTarget: "n501.karaoke"
    manageIpc: false
    // Single resolved service interface shared by every child view.
    readonly property var karaokeService: bar && bar.shell && typeof bar.shell.serviceFor === "function"
        ? bar.shell.serviceFor("n501.karaoke") : null

    readonly property string serviceState: karaokeService ? String(karaokeService.state || "idle") : "idle"
    readonly property bool ready: serviceState === "ready"
    readonly property bool vertical: bar ? bar.vertical : false
    readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal
    readonly property string layoutMode: {
        var mode = String(setting("layoutMode", "") || "").toLowerCase()
        if (["compact", "standard", "expanded"].indexOf(mode) >= 0) return mode
        var legacyWidth = Number(setting("width", 520))
        if (isFinite(legacyWidth) && legacyWidth <= 400) return "compact"
        if (isFinite(legacyWidth) && legacyWidth >= 650) return "expanded"
        return "standard"
    }
    readonly property bool motionEnabled: setting("motionEnabled", true) !== false
    readonly property real lyricScale: setting("lyricsSize", "Normal") === "Small" ? 0.85
        : setting("lyricsSize", "Normal") === "Large" ? 1.2 : 1
    readonly property int configuredWidth: root.layoutMode === "compact" ? 320
        : (root.layoutMode === "expanded" ? 720 : 520)
    readonly property int slotWidth: vertical ? barSize : configuredWidth
    // The slot stays visible for loading and error glyphs; only idle collapses it.
    visible: serviceState !== "idle"
    // Collapse the slot when hidden so the host does not reserve space.
    implicitWidth: !visible ? 0 : button.implicitWidth
    implicitHeight: button.implicitHeight
    readonly property string artistName: karaokeService && karaokeService.activePlayer
        ? String(karaokeService.activePlayer.trackArtist || "") : ""
    readonly property string titleName: karaokeService && karaokeService.activePlayer
        ? String(karaokeService.activePlayer.trackTitle || "") : ""
    readonly property string syncLabel: {
        if (!root.ready || !karaokeService) return ""
        if (karaokeService.timing === "none") return "Unsynced"
        if (karaokeService.timing === "instrumental") return "Instrumental"
        if (karaokeService.timing === "word")
            return karaokeService.timingDetail === "mixed" ? "Word + line" : "Word sync"
        return karaokeService.timing === "line" ? "Line sync" : ""
    }
    // The tooltip is the only text on a vertical bar: every state says what it is.
    readonly property string tooltipText: {
        var label = root.artistName + (root.artistName && root.titleName ? " — " : "") + root.titleName
        if (label === "") return ""
        var text = root.syncLabel !== "" ? label + " (" + root.syncLabel + ")" : label
        if (root.ready) {
            var line = karaokeService && karaokeService.timing !== "none"
                && karaokeService.currentLine && typeof karaokeService.currentLine.text === "string"
                ? karaokeService.currentLine.text : ""
            if (line !== "") text += "\n" + line
            text += "\nClick: panel · Right: refresh · Middle: search"
            if (root.offsetControlsAvailable) text += " · Wheel: timing"
        } else if (root.serviceState === "loading" && karaokeService
                && karaokeService.resolutionVisible) {
            text += "\n" + String(karaokeService.resolutionPhrase || "Resolving lyrics…")
        } else if (root.serviceState === "loading") {
            text += "\nResolving lyrics…"
        } else if (root.resolutionStatusVisible) {
            text += "\n" + root.resolutionPhrase
        } else if (root.failureVisible) {
            text += "\n" + root.failureMessage
        }
        return text
    }
    // Native music glyph shared by the bar surface and the panel hero fallback.
    readonly property string musicGlyph: "󰎆"
    readonly property string verticalGlyph: {
        if (root.serviceState === "not_found") return "○"
        if (root.serviceState === "provider_error") return "!"
        return root.musicGlyph
    }
    readonly property string shownKey: root.serviceState + "|"
        + (karaokeService ? String(karaokeService.projectionState || "") : "") + "|"
        + (karaokeService && karaokeService.currentLine
            ? String(karaokeService.currentLine.text || "") + String(karaokeService.currentLine.start) : "")
    // Indicator extent from actual visible lyric/glyph content, never a slot fraction.
    readonly property real openPanelIndicatorWidth: {
        if (!visible) return 0
        if (vertical) return barSize
        if (lineItem.visible)
            return Math.max(1, Math.min(configuredWidth, lineItem.fullWidth))
        if (loadingSnapshotItem.visible)
            return Math.max(1, Math.min(configuredWidth, loadingSnapshotItem.implicitWidth))
        if (root.barTraceVisible) return Math.min(configuredWidth, 104)
        if (glyphText.visible) return Math.max(1, glyphText.implicitWidth)
        return configuredWidth
    }
    // Vertical bars read this extent: track the painted glyph, never the slot.
    readonly property real openPanelIndicatorHeight: {
        if (!visible) return 0
        if (vertical && glyphText.visible) return Math.max(1, Math.min(barSize, glyphText.implicitHeight))
        return barSize
    }
    readonly property alias button: barButton
    readonly property alias catcher: keyCatcher
    readonly property alias failureGlyphText: failureGlyph.text
    readonly property bool barGlyphVisible: glyphText.visible
    readonly property alias failurePrimaryButton: failurePrimaryButton
    readonly property alias failureDetailsButton: failureDetailsButton
    readonly property alias resolutionHeadingVisible: statusText.visible
    readonly property alias failureSummaryVisible: failureSummary.visible
    // The lyric clip keeps its size across line and progress states.
    readonly property alias lyricClipItem: lineItem
    readonly property alias barDisplayText: unsyncedBarText.text
    readonly property alias unsyncedBadgeVisible: unsyncedBadge.visible
    readonly property alias unsyncedBarVisible: unsyncedBarText.visible
    readonly property alias renderedSeekHint: seekHintText.text
    function renderedRowTime(index) {
        var row = lyricList.itemAtIndex(index)
        return row && row.timeText ? row.timeText.text : ""
    }
    readonly property alias instrumentalStateVisible: instrumentalState.visible
    readonly property alias offsetBlockVisible: offsetBlock.visible
    function staticLyricText() {
        var row = lyricList.itemAtIndex(0)
        return row && row.staticPaintText && row.staticPaintText.visible
            ? row.staticPaintText.text : ""
    }
    readonly property bool wordSyncGlyphVisible: wordSyncGlyph.visible && wordSyncGlyph.opacity > 0
    readonly property string wordSyncTrackKey: karaokeService ? String(karaokeService.trackKey || "") : ""
    property string confirmedWordSyncTrackKey: ""
    readonly property bool firstWordLineDue: {
        var svc = root.karaokeService
        if (!root.ready || !svc || !svc.currentLine || svc.projectionState !== "line"
                || svc.timing !== "word" || !Array.isArray(svc.lines)) return false
        for (var i = 0; i < svc.lines.length; i++) {
            if (KaraokeModel.lineHasWordTiming(svc.lines[i]))
                return svc.currentLine === svc.lines[i] && svc.position >= svc.lines[i].start
        }
        return false
    }
    function showWordSyncGlyph() {
        if (!root.firstWordLineDue || !root.wordSyncTrackKey
                || root.confirmedWordSyncTrackKey === root.wordSyncTrackKey) return
        root.confirmedWordSyncTrackKey = root.wordSyncTrackKey
        wordSyncFade.stop()
        wordSyncGlyph.opacity = 1
        wordSyncTimer.restart()
    }
    onFirstWordLineDueChanged: root.showWordSyncGlyph()
    onWordSyncTrackKeyChanged: {
        wordSyncTimer.stop()
        wordSyncFade.stop()
        wordSyncGlyph.opacity = 0
        root.confirmedWordSyncTrackKey = ""
        Qt.callLater(root.showWordSyncGlyph)
    }
    Timer {
        id: wordSyncTimer
        interval: 1200
        onTriggered: {
            if (root.motionEnabled) wordSyncFade.restart()
            else wordSyncGlyph.opacity = 0
        }
    }
    NumberAnimation {
        id: wordSyncFade
        target: wordSyncGlyph
        property: "opacity"
        to: 0
        duration: 180
        easing.type: Easing.OutCubic
    }
    function activePanelRowHeight() {
        var svc = root.karaokeService
        var row = svc ? lyricList.itemAtIndex(svc.activeLineIndex) : null
        return row ? row.height : 0
    }
    function activePanelPaintText() {
        var svc = root.karaokeService
        var row = svc ? lyricList.itemAtIndex(svc.activeLineIndex) : null
        return row ? row.activePaintText : null
    }
    function activePanelTranslationText() {
        var svc = root.karaokeService
        var row = svc ? lyricList.itemAtIndex(svc.activeLineIndex) : null
        return row ? row.translationText : null
    }
    // Public observable for popup sizing: the smoke asserts the panel
    // content width follows the configured bar mode.
    readonly property alias popupContentWidth: popup.contentWidth
    readonly property real readyActionsY: readyActions.y
    readonly property real lyricListY: lyricList.y
    readonly property bool barMarksClearOfLyric: wordSyncGlyph.x + wordSyncGlyph.implicitWidth <= lineItem.x
        && pauseMark.x + pauseMark.implicitWidth <= lineItem.x
    readonly property bool menuCardVisible: menuCard.visible
    readonly property real menuCardTop: menuAnchor.y + menuCard.y
    readonly property real readyActionsBottom: readyActions.y + readyActions.height
    readonly property bool matchedDetailVisible: matchedDetail.visible
    // Public observable for the deferred search-title focus path: smoke and
    // keybindings assert this instead of reaching into private field ids.
    readonly property alias searchTitleField: titleField
    readonly property alias searchArtistField: artistField
    readonly property alias searchAlbumField: albumField
    readonly property bool searchTitleFocused: titleField.activeFocus
    // Set by middle click or the `/` key; the search view never owns the document.
    property bool searchMode: false
    // Section/index cursor shared by keyboard and mouse. Sections depend on
    // the current view: ready → actions + lyrics; search → query + provider
    // + results + actions; failure → actions. Visuals derive from
    // hasCursor via Button/CursorSurface, never from containsMouse, so
    // exactly one highlight exists across keyboard and mouse.
    property string focusSection: "actions"
    property int selectedIndex: 0
    property bool cursorActive: false
    // Provider selected for manual search; empty means "first available".
    property string searchProvider: ""
    // Editable correction drafts, seeded once per search-view entry.
    property string queryDraftTitle: ""
    property string queryDraftArtist: ""
    property string queryDraftAlbum: ""
    property string searchSeedKey: ""
    // Set around an offset write so the 1.2s success flash only fires when the
    // write actually lands without an error.
    property bool offsetWritePending: false
    property bool offsetFlashVisible: false
    property bool showDiagnostics: false
    property bool menuOpen: false
    property real wheelRemainder: 0
    readonly property var lyricDocument: karaokeService && karaokeService.document ? karaokeService.document : null
    readonly property string provenanceLabel: {
        if (!root.lyricDocument) return ""
        var source = String(root.lyricDocument.sourceKind || "")
        var mode = String(root.lyricDocument.cacheMode || "")
        if (source === "local") return "Local"
        if (source === "cache" && mode === "manual") return "Manual cache"
        if (source === "cache") return "Auto cache"
        if (source === "network") return "Network"
        return ""
    }
    readonly property string privacyWarning: {
        if (!root.lyricDocument || !Array.isArray(root.lyricDocument.warnings)) return ""
        var parts = []
        if (root.lyricDocument.warnings.indexOf("cache_permissions") >= 0)
            parts.push("Lyrics cache permissions could not be tightened")
        if (root.lyricDocument.warnings.indexOf("offset_store_permissions") >= 0)
            parts.push("Timing-offset storage permissions could not be tightened")
        if (root.lyricDocument.warnings.indexOf("alias_store_failed") >= 0)
            parts.push("Lyrics were selected but the edited query was not saved")
        else if (root.lyricDocument.warnings.indexOf("alias_store_permissions") >= 0)
            parts.push("Lyrics were selected but the edited query was not saved")
        if (root.lyricDocument.warnings.indexOf("kotonoha_import_failed") >= 0)
            parts.push("Earlier Kotonoha selections could not be imported")
        return parts.join(" · ")
    }
    // The popup surface is Color.popups.background regardless of the bar: a
    // transparent bar recolours bar.barForeground for the wallpaper, which
    // would make popup text unreadable on the popup's own background.
    readonly property color panelForeground: Color.popups.text
    readonly property color secondaryForeground: Qt.rgba(panelForeground.r, panelForeground.g,
        panelForeground.b, 0.62)
    readonly property color barTextColor: bar ? bar.barForeground : Color.bar.text
    readonly property color barSecondaryForeground: Qt.rgba(barTextColor.r, barTextColor.g,
        barTextColor.b, 0.62)
    readonly property string panelFont: bar ? bar.fontFamily : Style.font.family
    readonly property string panelTiming: {
        if (karaokeService && karaokeService.timing === "none") return "Unsynced"
        if (karaokeService && karaokeService.timing === "instrumental") return "Instrumental"
        if (karaokeService && karaokeService.timing === "word" && karaokeService.timingDetail === "mixed")
            return "Word + line"
        return karaokeService && karaokeService.timing === "word" ? "Word sync" : "Line sync"
    }
    readonly property bool translationsShown: karaokeService ? karaokeService.translationsVisible !== false : true
    // Local file artwork only; anything remote falls back to the music glyph so
    // the panel never triggers a network image fetch.
    readonly property bool heroArtLocal: karaokeService
        && typeof karaokeService.trackArtUrl === "string"
        && (karaokeService.trackArtUrl.indexOf("file:///") === 0
            || karaokeService.trackArtUrl.indexOf("file://localhost/") === 0)
    readonly property string provenanceShort: {
        if (!root.lyricDocument) return ""
        var source = String(root.lyricDocument.sourceKind || "")
        var mode = String(root.lyricDocument.cacheMode || "")
        if (source === "local") return "local"
        if (source === "cache" && mode === "manual") return "manual cache"
        if (source === "cache") return "auto cache"
        if (source === "network") return "network"
        return ""
    }
    readonly property string matchedText: {
        if (!root.lyricDocument) return ""
        var title = String(root.lyricDocument.title || "")
        var artist = String(root.lyricDocument.artist || "")
        var head = title + (title !== "" && artist !== "" ? " — " : "") + artist
        var provider = karaokeService ? String(karaokeService.provider || "") : ""
        var confidence = String(root.lyricDocument.confidence || "")
        var parts = []
        if (head !== "") parts.push(head)
        if (provider !== "") parts.push(provider)
        if (confidence !== "") parts.push(confidence)
        if (root.provenanceShort !== "") parts.push(root.provenanceShort)
        if (parts.length === 0) return ""
        return "Matched: " + parts.join(" · ")
    }
    // Shared sources carry the personal-display notice; local files do not.
    readonly property bool sharedNoticeVisible: root.lyricDocument
        && (String(root.lyricDocument.sourceKind || "") === "network"
            || String(root.lyricDocument.sourceKind || "") === "cache")
    // Fetch-level failure key uses the helper error token when one is available.
    readonly property string failureKey: {
        if (root.searchMode) return ""
        if (root.serviceState !== "not_found" && root.serviceState !== "provider_error") return ""
        if (karaokeService && karaokeService.errorCode) return String(karaokeService.errorCode)
        return root.serviceState
    }
    readonly property bool failureVisible: root.failureKey !== ""
    readonly property bool resolutionStatusVisible: !root.searchMode
        && root.serviceState === "loading" && !!root.karaokeService
        && root.karaokeService.resolutionVisible === true
    readonly property string resolutionPhrase: root.resolutionStatusVisible
        ? String(root.karaokeService.resolutionPhrase || "") : ""
    readonly property var resolutionTimeline: {
        var steps = root.karaokeService && Array.isArray(root.karaokeService.resolutionSteps)
            ? root.karaokeService.resolutionSteps : []
        var rows = []
        var indices = ({})
        for (var i = 0; i < steps.length; i++) {
            var step = steps[i]
            if (step.stage === "ranking" && ["found", "unsynced", "instrumental"].indexOf(step.outcome) < 0)
                continue
            var key = step.stage === "provider" ? step.stage + ":" + step.provider : step.stage
            if (indices[key] === undefined) {
                indices[key] = rows.length
                rows.push(step)
            } else rows[indices[key]] = step
        }
        return rows
    }
    readonly property string failureProviderSummary: {
        var parts = []
        for (var i = 0; i < root.resolutionTimeline.length; i++) {
            var step = root.resolutionTimeline[i]
            if (step.stage === "provider" && step.outcome !== "query")
                parts.push(root.resolutionStepText(step))
        }
        return parts.join(", ")
    }
    function resolutionStepText(step) {
        var label = ({local: "Local lyrics", alias: "Saved correction",
            cache: "Lyrics Cache", ranking: "Ranking", retry: "Retry"})[step.stage]
            || (root.karaokeService && root.karaokeService.providerLabel
                ? root.karaokeService.providerLabel(step.provider) : step.provider)
        return label + " · " + (step.outcome === "query" || step.outcome === "checking"
            ? "…" : step.outcome)
    }
    readonly property string failureMessage: root.failureCopy(root.failureKey).message
    readonly property string failureActionText: root.failureCopy(root.failureKey).action
    readonly property string offsetText: {
        var ms = karaokeService ? Math.trunc(Number(karaokeService.offsetMs) || 0) : 0
        return (ms < 0 ? "−" : "+") + Math.abs(ms) + " ms"
    }
    readonly property bool offsetControlsAvailable: !!karaokeService
        && karaokeService.timing !== "none" && karaokeService.timing !== "instrumental"
        && karaokeService.offsetAvailable === true
    readonly property string offsetSupportHint: {
        if (!karaokeService || typeof karaokeService.capabilityExplanation !== "function") return ""
        if (karaokeService.capabilityExplanation("offset") === "") return ""
        if (!karaokeService.capabilities) return "Offset capabilities are unavailable"
        return "Timing offset is unavailable in this build"
    }
    readonly property string offsetDisabledHint: root.offsetSupportHint !== ""
        ? root.offsetSupportHint : "Timing offset needs a matched document"
    readonly property string searchSupportHint: {
        if (!karaokeService || typeof karaokeService.capabilityExplanation !== "function") return ""
        if (karaokeService.capabilityExplanation("search") === "") return ""
        if (!karaokeService.capabilities) return "Search capabilities are unavailable"
        return "Search is unavailable in this build"
    }
    readonly property bool searchOffline: !!karaokeService
        && karaokeService.networkMode === "Offline"
    readonly property string searchOfflineHint: root.searchOffline
        ? "Manual search is unavailable offline" : ""
    readonly property var searchRows: {
        if (!karaokeService || !Array.isArray(karaokeService.searchResults)) return []
        return karaokeService.searchResults.slice(0, 10)
    }
    readonly property var savedSelection: karaokeService ? karaokeService.savedAlias : null
    readonly property bool forgetVisible: {
        if (root.lyricDocument && String(root.lyricDocument.cacheMode || "") === "manual") return true
        if (!root.lyricDocument && root.savedSelection) return true
        return false
    }
    readonly property bool removeVisible: {
        if (!root.lyricDocument) return false
        if (String(root.lyricDocument.cacheMode || "") === "manual") return false
        return String(root.lyricDocument.sourceKind || "") === "cache"
    }
    readonly property string forgetLabel: "Forget saved correction"
    readonly property string removeLabel: "Remove cached match"
    // Two clicks: count automatic entries first, then confirm with the number.
    readonly property string clearCacheLabel: {
        var svc = root.karaokeService
        switch (svc ? svc.cacheClearState : "") {
        case "counting": return "Clear cache…"
        case "confirm":
            return svc.cacheClearEntries === 0 ? "Cache is empty"
                : "Confirm (" + svc.cacheClearEntries + (svc.cacheClearEntries === 1 ? " entry)" : " entries)")
        case "clearing": return "Clearing…"
        case "done": return "Cleared " + svc.cacheClearRemoved + (svc.cacheClearRemoved === 1 ? " entry" : " entries")
        case "error": return "Clear cache failed · retry"
        default: return "Clear cache"
        }
    }
    onShowDiagnosticsChanged: {
        if (!root.showDiagnostics && root.karaokeService
                && typeof root.karaokeService.dismissCacheClear === "function")
            root.karaokeService.dismissCacheClear()
    }
    // Failed forget/remove while ready: bounded token, actionable copy, and
    // visibility for the ready failure banner. The document is preserved.
    readonly property string forgetFailureMessage: {
        if (!root.karaokeService || typeof root.karaokeService.forgetError !== "string") return ""
        if (root.karaokeService.forgetError === "") return ""
        return root.failureCopy(root.karaokeService.forgetError).message
    }
    readonly property bool forgetFailureVisible: root.serviceState === "ready" && !root.searchMode
        && root.forgetFailureMessage !== ""
    function dismissForgetError() {
        if (root.karaokeService && typeof root.karaokeService.clearForgetError === "function")
            root.karaokeService.clearForgetError()
    }
    readonly property bool seekSupported: !!karaokeService && karaokeService.timing !== "none"
        && karaokeService.timing !== "instrumental"
        && !!karaokeService.activePlayer
        && karaokeService.activePlayer.canSeek === true
        && karaokeService.activePlayer.positionSupported === true
    readonly property string seekHint: root.seekSupported ? "" : "Seeking is unavailable for this player"
    // Lyrics own the motion. A small trace reports timing only when no line is
    // due; loading is the sole indeterminate state.
    property real loadingPhase: 0
    property string lastVisibleLineText: ""
    property string loadingSnapshotText: ""
    property string lastVisibleTitle: ""
    property string lastVisibleArtist: ""
    property string loadingSnapshotTitle: ""
    property string loadingSnapshotArtist: ""
    property bool loadingHandoffPending: false
    property bool loadingMotionReady: false
    readonly property bool motionVisible: root.visible && !(root.bar && root.bar.barHidden === true)
    readonly property bool isPlaying: !!karaokeService && !!karaokeService.activePlayer
        && karaokeService.activePlayer.isPlaying === true
    readonly property string projectionState: root.karaokeService
        ? String(root.karaokeService.projectionState || "") : ""
    readonly property bool beforeFirstSceneVisible: root.projectionState === "before_first"
        && root.karaokeService
        && Number(root.karaokeService.leadInDuration || 0) >= KaraokeModel.interludeThreshold()
    readonly property bool loadingHandoffVisible: root.serviceState === "loading"
        && root.loadingHandoffPending && !root.loadingMotionReady
    readonly property bool loadingSnapshotVisible: !root.vertical
        && root.loadingHandoffVisible && root.loadingSnapshotText !== ""
    readonly property bool timedGapVisible: root.ready
        && (root.beforeFirstSceneVisible || root.projectionState === "interlude")
    readonly property int countdownStep: root.timedGapVisible && root.karaokeService
        ? Number(root.karaokeService.countdownStep || 0) : 0
    readonly property bool countdownVisible: root.motionVisible && !root.vertical
        && root.timedGapVisible && root.countdownStep > 0
    readonly property string countdownDots: root.countdownStep === 3 ? "● ● ●"
        : root.countdownStep === 2 ? "● ● ○" : "● ○ ○"
    readonly property bool pauseSceneVisible: root.motionVisible && !root.vertical
        && root.ready && !root.isPlaying
    readonly property bool resolutionShimmerRunning: root.motionEnabled && root.motionVisible
        && root.isPlaying && root.resolutionStatusVisible && root.resolutionPhrase !== ""
        && !root.vertical
    readonly property string previewSegmentText: root.countdownVisible && previewLine.currentSegment
        ? String(previewLine.currentSegment.text || "") : ""
    readonly property bool countdownDotsVisible: countdownRow.visible
    readonly property bool introBreathingAnimationRunning: introBreath.running
    readonly property real barTraceOpacity: barTrace.opacity
    readonly property bool resolutionShimmerAnimationRunning: shimmerSweep.running
    readonly property bool barTraceVisible: root.motionVisible && !root.vertical
        && ((root.serviceState === "loading" && root.loadingMotionReady
                && !root.resolutionStatusVisible) || (root.timedGapVisible && !root.countdownVisible))
    readonly property bool finalFailure: ["not_found", "provider_error"].indexOf(root.serviceState) >= 0
    property real failureOpacity: 1
    onIsPlayingChanged: {
        if (!root.isPlaying) {
            wordSyncTimer.stop()
            wordSyncFade.stop()
            wordSyncGlyph.opacity = 0
            failureDissolve.stop()
            root.failureOpacity = 1
            loadingSnapshotFade.stop()
        }
    }
    onFinalFailureChanged: {
        failureDissolve.stop()
        if (root.finalFailure && root.motionEnabled && root.isPlaying) {
            root.failureOpacity = 0
            failureDissolve.start()
        } else root.failureOpacity = 1
    }
    NumberAnimation {
        id: failureDissolve
        target: root
        property: "failureOpacity"
        to: 1
        duration: 200
        easing.type: Easing.OutCubic
    }
    readonly property bool popupTraceVisible: root.opened && !root.searchMode
        && ((root.serviceState === "loading" && root.loadingMotionReady)
            || root.timedGapVisible)
    readonly property bool popupLoadingSnapshotVisible: root.opened
        && root.loadingHandoffVisible && !root.searchMode
    readonly property bool loadingTraceRunning: root.motionEnabled && root.motionVisible
        && root.isPlaying && root.serviceState === "loading" && root.loadingMotionReady
    readonly property real traceProgress: {
        if (!root.karaokeService) return 0
        if (root.projectionState === "before_first")
            return root.clamp01(Number(root.karaokeService.leadInProgress || 0))
        if (root.projectionState === "interlude")
            return root.clamp01(Number(root.karaokeService.interludeProgress || 0))
        return 0
    }
    readonly property bool introBreathingRunning: root.motionEnabled && root.motionVisible
        && root.isPlaying && root.ready && root.beforeFirstSceneVisible && !root.countdownVisible
    function clamp01(value) {
        var number = Number(value)
        if (!isFinite(number) || number <= 0) return 0
        return number >= 1 ? 1 : number
    }

    property bool followEnabled: true
    property bool autoFollowing: false

    // Pushes the CURRENT settings to the service right now. Called directly
    // (synchronously) whenever `settings` itself just changed -- including
    // construction -- since at that point `settings` already holds the
    // caller's deliberate value.
    function pushSettings() {
        if (karaokeService && typeof karaokeService.configure === "function") karaokeService.configure(settings)
    }
    // The host (Bar.qml injectProps) sets `bar` before `settings`, so the
    // instant `bar` changes (and karaokeService resolves) `settings` may
    // still be Ui/Panel.qml's `({})` placeholder default -- including for a
    // second (or later) panel instance bound after the service already has
    // real settings applied, e.g. monitor hotplug or the widget moved/
    // re-added. Pushing that placeholder straight through configure() would
    // toggle an already-settled service (e.g. Offline) back to the Auto/
    // all-providers default and immediately start a lookup, which the real
    // settings assignment that follows in the same synchronous injectProps()
    // turn then cancels -- wiping and refetching a document that never
    // needed it. Deferring via Qt.callLater means this reads `settings`
    // again only once that follow-up assignment has landed, so it always
    // pushes the turn's real value rather than the placeholder; an ordinary
    // settings-only change (no `bar` change alongside it, e.g. an edited
    // shell.json entry or cycleLayoutMode) never goes through this deferred
    // path at all and keeps pushing synchronously via pushSettings() above.
    function deferredPushSettings() {
        Qt.callLater(root.pushSettings)
    }
    // Direct bar-size control: the next enum in fixed Compact → Standard →
    // Expanded → Compact order, title-cased for the manifest enum. The copy
    // is applied locally first for immediate width/popup reflow, then
    // persisted inline; other settings are preserved verbatim. Existing
    // settings propagation (onSettingsChanged → configure) applies it.
    function nextLayoutMode() {
        var order = ["Compact", "Standard", "Expanded"]
        var current = String(root.layoutMode || "standard").toLowerCase()
        var at = 0
        for (var i = 0; i < order.length; i++) {
            if (order[i].toLowerCase() === current) at = i
        }
        return order[(at + 1) % order.length]
    }

    function cycleLayoutMode() {
        var next = root.nextLayoutMode()
        var copy = {}
        if (root.settings && typeof root.settings === "object") {
            for (var key in root.settings) copy[key] = root.settings[key]
        }
        copy["layoutMode"] = next
        root.settings = copy
        if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
            root.bar.shell.updateEntryInline(root.moduleName, copy)
    }

    function secondaryAction() {
        var svc = root.karaokeService
        if (!svc) return
        if (root.serviceState === "ready") {
            if (typeof svc.refreshCurrent === "function") svc.refreshCurrent()
        } else if (root.serviceState === "not_found" || root.serviceState === "provider_error") {
            if (typeof svc.retry === "function") svc.retry()
        }
    }

    function followCurrent() {
        if (!root.karaokeService || root.karaokeService.timing === "none"
                || root.karaokeService.timing === "instrumental"
                || !Array.isArray(root.karaokeService.lines)) return
        var index = Number(root.karaokeService.activeLineIndex)
        if (index < 0 || index >= root.karaokeService.lines.length) return
        root.autoFollowing = true
        Qt.callLater(function() {
            if (root.followEnabled && lyricList.count > index) lyricList.positionViewAtIndex(index, ListView.Center)
            root.autoFollowing = false
        })
    }

    function seekLyricRow(index) {
        var svc = root.karaokeService
        if (!root.seekSupported || !svc || typeof svc.seekToLine !== "function") return false
        if (svc.seekToLine(index) !== true) return false
        root.followEnabled = true
        if (lyricList.count > index) lyricList.positionViewAtIndex(index, ListView.Center)
        return true
    }
    // Losing seek support while focused on lyrics would orphan the cursor on
    // a section that no longer exists; fall back to the first enabled action
    // so exactly one highlight remains.
    onSeekSupportedChanged: {
        if (!root.seekSupported && root.focusSection === "lyrics") {
            root.focusSection = "actions"
            root.selectedIndex = root.firstEnabledActionIndex()
        }
    }


    function duration() {
        if (!root.karaokeService || !root.karaokeService.activePlayer) return -1
        var player = root.karaokeService.activePlayer
        if (player.lengthSupported !== true) return -1
        var length = Number(player.length)
        return isFinite(length) && length > 0 ? length : -1
    }
    // Exact literal failure copy shared by the lyrics, search, and offset views.
    function failureCopy(code) {
        switch (String(code || "")) {
        case "network_disabled":
            return {message: "Network lyrics are disabled", action: "Try again"}
        case "resolver_timeout":
            return {message: "Lyrics lookup timed out", action: "Try again"}
        case "providers_failed":
            return {message: "Lyrics providers are unavailable", action: "Try again"}
        case "helper_unavailable":
            return {message: "Lyrics helper could not run", action: "Try again"}
        case "alias_unavailable":
            return {message: "Saved lyrics correction is unavailable", action: "Forget saved correction"}
        case "invalid_response":
            return {message: "Lyrics provider returned unusable data", action: "Try again"}
        case "invalid_payload":
            return {message: "Lyrics provider returned unusable data", action: "Try again"}
        case "invalid_request":
            return {message: "Lyrics request was invalid", action: "Try again"}
        case "payload_too_large":
            return {message: "Lyrics response is too large", action: "Try again"}
        case "selection_not_found":
            return {message: "That lyrics version is no longer available", action: "Search again"}
        case "offset_store_failed":
            return {message: "Could not save timing offset", action: "Retry offset"}
        case "offset_unavailable":
            return {message: "Timing offset is unavailable", action: "Try again"}
        case "search_failed":
            return {message: "Lyrics search failed", action: "Try again"}
        case "search_unavailable":
            return {message: "Search is unavailable for this provider", action: "Try again"}
        case "cache_delete_failed":
            return {message: "Could not remove cached lyrics", action: "Try again"}
        case "cache_store_failed":
            return {message: "Could not save the lyrics correction", action: "Try again"}
        case "alias_store_failed":
            return {message: "Saved correction could not be removed", action: "Try again"}
        case "alias_store_permissions":
            return {message: "Correction storage permissions blocked removal", action: "Try again"}
        default:
            return {message: "No synchronized lyrics found", action: "Try again"}
        }
    }

    function failurePrimary() {
        var key = root.failureKey
        if (key === "selection_not_found") {
            root.openSearch()
            return
        }
        if (key === "alias_unavailable") {
            root.forgetCurrentMatch()
            return
        }
        if (key === "offset_store_failed") {
            if (root.karaokeService && typeof root.karaokeService.retryOffset === "function")
                root.karaokeService.retryOffset()
            return
        }
        if (root.karaokeService && typeof root.karaokeService.retry === "function")
            root.karaokeService.retry()
    }

    function forgetCurrentMatch() {
        if (root.karaokeService && typeof root.karaokeService.forgetCurrentMatch === "function")
            root.karaokeService.forgetCurrentMatch()
    }

    function deleteSelected() {
        var svc = root.karaokeService
        if (!svc) return
        if ((root.forgetVisible || root.removeVisible) && svc.selectedProvider && svc.selectedSongId)
            root.forgetCurrentMatch()
    }

    function availableSearchProviders() {
        var enabled = []
        var svc = root.karaokeService
        if (svc && typeof svc.enabledProviders === "function") {
            var parts = String(svc.enabledProviders() || "").split(",")
            for (var i = 0; i < parts.length; i++) {
                if (parts[i] !== "") enabled.push(parts[i])
            }
        } else enabled = ["netease", "lrclib", "kugou"]
        if (svc && svc.capabilities && Array.isArray(svc.capabilities.search)) {
            var supported = []
            for (var j = 0; j < enabled.length; j++) {
                if (svc.capabilities.search.indexOf(enabled[j]) >= 0) supported.push(enabled[j])
            }
            return supported
        }
        return enabled
    }

    readonly property string activeSearchProvider: {
        var list = root.availableSearchProviders()
        if (root.searchProvider !== "" && list.indexOf(root.searchProvider) >= 0) return root.searchProvider
        return list.length > 0 ? list[0] : ""
    }

    function seedQueryDrafts() {
        var svc = root.karaokeService
        var title = "", artist = "", album = ""
        var inView = svc ? svc.searchQuery : null
        var alias = svc ? svc.savedAlias : null
        var doc = root.lyricDocument
        if (inView && typeof inView.title === "string" && inView.title !== "") {
            title = inView.title
            artist = typeof inView.artist === "string" ? inView.artist : ""
            album = typeof inView.album === "string" ? inView.album : ""
        } else if (alias && typeof alias.queryTitle === "string" && alias.queryTitle !== "") {
            title = alias.queryTitle
            artist = typeof alias.queryArtist === "string" ? alias.queryArtist : ""
            album = typeof alias.queryAlbum === "string" ? alias.queryAlbum : ""
        } else if (doc && typeof doc.searchTitle === "string" && doc.searchTitle !== "") {
            title = doc.searchTitle
            artist = typeof doc.searchArtist === "string" ? doc.searchArtist : ""
            album = typeof doc.searchAlbum === "string" ? doc.searchAlbum : ""
        } else {
            title = root.titleName
            artist = root.artistName
            album = svc && svc.activePlayer ? String(svc.activePlayer.trackAlbum || "") : ""
        }
        root.queryDraftTitle = title
        root.queryDraftArtist = artist
        root.queryDraftAlbum = album
        root.searchSeedKey = root.trackSeedKey()
    }

    function trackSeedKey() {
        var svc = root.karaokeService
        if (!svc) return "no-service"
        return String(svc.trackKey || "") + "|" + String(svc.state || "")
    }

    function focusSearchTitle() {
        // Deterministic deferred focus that wins the host KeyboardPanel
        // focus: the host claims keyCatcher through a single Qt.callLater on
        // open, so the title claim is double-deferred to run strictly after
        // it. Guarded by searchMode so a late turn never steals focus after
        // the user exited search.
        searchFocusTimer.restart()
        Qt.callLater(function() {
            Qt.callLater(function() {
                if (root.searchMode) {
                    titleField.forceActiveFocus()
                    searchFocusTimer.restart()
                }
            })
        })
    }

    // Tab/Backtab while a query field holds focus: the key catcher is
    // `blocked` for the whole field-editing duration (see keyCatcher below),
    // so it never sees these keys itself. Each field forwards them here
    // instead of letting them fall on the floor. Within the three fields,
    // Tab/Backtab simply move to the next/previous field. At either edge
    // (Backtab from title, Tab from album) focus hands back to the key
    // catcher, the same way Escape already does, so a further Tab/Backtab
    // reaches the catcher unblocked and calls switchPanel, which opens the
    // neighbouring bar widget's panel (host Bar.qml switchPanelFrom) --
    // not a section within this panel.
    function focusAdjacentQueryField(direction) {
        var fields = [titleField, artistField, albumField]
        var current = 0
        for (var i = 0; i < fields.length; i++) {
            if (fields[i].activeFocus) { current = i; break }
        }
        var next = current + direction
        if (next < 0 || next >= fields.length) {
            keyCatcher.forceActiveFocus()
            return
        }
        root.setCursor("query", next)
        fields[next].forceActiveFocus()
    }

    function openSearch() {
        // Seed once per search-view entry: repeated entry while already
        // searching (e.g. pressing `/` again) must not overwrite unsent
        // edits. A new track still reseeds via the seed-key comparison.
        var entering = !root.searchMode
        root.searchMode = true
        if (entering || root.searchSeedKey !== root.trackSeedKey()) root.seedQueryDrafts()
        root.focusSection = "query"
        root.selectedIndex = 0
        root.cursorActive = true
        var svc = root.karaokeService
        if (svc && typeof svc.probeCapabilities === "function") {
            var fresh = svc.capabilitiesFresh && typeof svc.capabilitiesFresh === "function"
                ? svc.capabilitiesFresh() : !!svc.capabilities
            svc.probeCapabilities(!fresh)
        }
        root.focusSearchTitle()
    }

    function closeSearch() {
        root.searchMode = false
        root.resetPanelCursor()
    }

    // Public harness operation for scripted query fencing: routes through
    // the same TextField edit path as typed input so stale results are
    // invalidated via noteQueryEdited. Prefer this over private field ids.
    function setQueryDraftTitle(text) {
        titleField.text = String(text)
    }
    function setQueryDraftArtist(text) {
        artistField.text = String(text)
    }
    function setQueryDraftAlbum(text) {
        albumField.text = String(text)
    }

    function doSearch() {
        var svc = root.karaokeService
        if (!svc || typeof svc.search !== "function") return
        if (root.searchOffline) return
        var provider = root.activeSearchProvider
        if (provider === "") return
        keyCatcher.forceActiveFocus()
        svc.search(provider, root.queryDraftTitle, root.queryDraftArtist, root.queryDraftAlbum)
    }

    function selectSearchRow(pick) {
        var svc = root.karaokeService
        if (!svc || typeof svc.selectResult !== "function") return
        if (root.searchOffline) return
        var results = root.searchRows
        var row = results[pick]
        if (!row || typeof row.provider !== "string" || typeof row.songId !== "string"
                || row.provider === "" || row.songId === "") return
        var query = svc.searchQuery
        var qTitle = query && typeof query.title === "string" ? query.title : root.queryDraftTitle
        var qArtist = query && typeof query.artist === "string" ? query.artist : root.queryDraftArtist
        var qAlbum = query && typeof query.album === "string" ? query.album : root.queryDraftAlbum
        svc.selectResult(row.provider, row.songId, qTitle, qArtist, qAlbum)
    }

    function cycleSearchProvider(direction) {
        var list = root.availableSearchProviders()
        if (list.length === 0) return
        var current = list.indexOf(root.activeSearchProvider)
        var step = direction < 0 ? -1 : 1
        var next = current < 0 ? 0 : (current + step + list.length) % list.length
        root.searchProvider = list[next]
    }

    // Pending is set before the call (a synchronous result may land inside
    // it) and restored when the service reports it dispatched nothing, so a
    // refused write never strands the controls; an in-flight write stays pending.
    function requestOffsetDelta(deltaMs) {
        var svc = root.karaokeService
        if (!svc || typeof svc.nudgeOffset !== "function") return
        if (!root.offsetControlsAvailable) return
        var wasPending = root.offsetWritePending
        root.offsetWritePending = true
        if (svc.nudgeOffset(deltaMs) === false) root.offsetWritePending = wasPending
    }

    function requestOffsetReset() {
        var svc = root.karaokeService
        if (!svc || typeof svc.resetOffset !== "function") return
        if (!root.offsetControlsAvailable) return
        var wasPending = root.offsetWritePending
        root.offsetWritePending = true
        if (svc.resetOffset() === false) root.offsetWritePending = wasPending
    }

    function showOffsetFlash() {
        root.offsetFlashVisible = true
        offsetFlashTimer.restart()
    }

    function handleWheel(delta) {
        if (!root.offsetControlsAvailable) return
        var outcome = Util.wheelSteps(root.wheelRemainder, Number(delta) || 0)
        root.wheelRemainder = outcome.remainder
        var steps = Math.trunc(outcome.steps)
        for (var i = 0; i < Math.abs(steps); i++) {
            if (steps > 0) root.requestOffsetDelta(100)
            else root.requestOffsetDelta(-100)
        }
    }

    // First enabled action for initial focus: a disabled Refresh during retry
    // cooldown must not steal the cursor.
    function firstEnabledActionIndex() {
        var ids = root.actionIds()
        for (var i = 0; i < ids.length; i++) {
            if (root.actionEnabled(ids[i])) return i
        }
        return 0
    }

    // Ordered action ids for the current view. The actions row always sits
    // before the long lyric/result list so it stays inside the panel height.
    function actionIds() {
        if (root.searchMode) {
            var searchActions = ["search", "back", "layoutMode"]
            if (root.forgetVisible) searchActions.push("forget")
            else if (root.removeVisible) searchActions.push("remove")
            return searchActions
        }
        if (root.failureVisible) return ["primary", "details", "layoutMode"]
        if (root.serviceState !== "ready" || !root.karaokeService) return []
        var ids = ["refresh", "search"]
        if (root.offsetControlsAvailable) ids.push("earlier", "reset", "later")
        ids.push("menu")
        if (root.menuOpen) {
            ids.push("details", "layoutMode", "clearCache")
            if (!root.followEnabled) ids.push("follow")
            if (root.karaokeService.offsetError !== "") ids.push("retry_offset")
            if (root.forgetVisible) ids.push("forget")
            else if (root.removeVisible) ids.push("remove")
        }
        return ids
    }
    function actionLabel(action) {
        switch (action) {
        case "refresh": return "Refresh"
        case "search": return root.searchMode ? "Search" : "Search"
        case "back": return "Back"
        case "earlier": return "−"
        case "later": return "+"
        case "reset": return root.offsetText
        case "menu": return "⋯"
        case "follow": return "Follow"
        case "details": return root.showDiagnostics ? "Hide details" : "Details"
        case "layoutMode":
            if (root.layoutMode === "compact") return "Bar size: Compact"
            if (root.layoutMode === "expanded") return "Bar size: Expanded"
            return "Bar size: Standard"
        case "forget": return root.forgetLabel
        case "remove": return root.removeLabel
        case "primary": return root.failureActionText
        case "retry_offset": return "Retry offset"
        case "clearCache": return root.clearCacheLabel
        default: return action
        }
    }

    function actionEnabled(action) {
        var svc = root.karaokeService
        if (action === "refresh") return !!svc && svc.retryAvailable !== false
        if (action === "primary") {
            // Only retry-type primaries use the fetch retry cooldown. Forget,
            // Search-again, and offset-retry primaries stay available.
            var key = root.failureKey
            if (key === "alias_unavailable" || key === "selection_not_found"
                    || key === "offset_store_failed")
                return true
            return !!svc ? svc.retryAvailable !== false : true
        }
        if (action === "search") {
            if (root.searchMode)
                return root.searchOfflineHint === "" && root.activeSearchProvider !== ""
                    && root.searchSupportHint === "" && !!svc
                    && svc.searchAvailable(root.activeSearchProvider) === true
            return true
        }
        if (action === "earlier" || action === "later" || action === "reset")
            return root.offsetControlsAvailable && !root.offsetWritePending
        if (action === "retry_offset") return true
        if (action === "clearCache") {
            var clearState = svc ? svc.cacheClearState : ""
            if (clearState === "counting" || clearState === "clearing" || clearState === "done") return false
            return !(clearState === "confirm" && svc.cacheClearEntries === 0)
        }
        if (action === "layoutMode") return true
        if (action === "forget" || action === "remove")
            return !!svc && !!svc.selectedProvider && !!svc.selectedSongId
        return true
    }

    function activateAction(action) {
        var svc = root.karaokeService
        switch (action) {
        case "refresh":
            if (svc && typeof svc.refreshCurrent === "function") svc.refreshCurrent()
            return
        case "search":
            if (root.searchMode) root.doSearch()
            else root.openSearch()
            return
        case "back":
            root.closeSearch()
            return
        case "earlier":
            root.requestOffsetDelta(100)
            return
        case "later":
            root.requestOffsetDelta(-100)
            return
        case "reset":
            root.requestOffsetReset()
            return
        case "follow":
            root.followEnabled = true
            root.followCurrent()
            return
        case "menu":
            root.menuOpen = !root.menuOpen
            return
        case "details":
            root.showDiagnostics = !root.showDiagnostics
            return
        case "clearCache":
            if (!svc) return
            if (svc.cacheClearState === "confirm") svc.confirmCacheClear()
            else svc.requestCacheClear()
            return
        case "layoutMode":
            root.cycleLayoutMode()
            return
        case "forget":
        case "remove":
            root.forgetCurrentMatch()
            return
        case "primary":
            root.failurePrimary()
            return
        case "retry_offset":
            if (svc && typeof svc.retryOffset === "function") svc.retryOffset()
            return
        }
    }

    // Visible sections for the current view, in navigation order.
    readonly property var visibleSections: {
        if (root.searchMode) {
            var sections = ["query", "provider"]
            if (root.searchRows.length > 0) sections.push("results")
            sections.push("actions")
            return sections
        }
        if (root.failureVisible) return ["actions"]
        // Players without seeking expose no lyric cursor section: rows stay
        // readable, but there is nothing seekable to highlight or activate.
        if (root.ready) return root.seekSupported ? ["actions", "lyrics"] : ["actions"]
        // Loading, idle, and any other non-interactive state expose no cursor
        // section: movement keys must find a concrete empty array, never
        // undefined, so they cannot throw or consume a dead action.
        return []
    }

    function sectionCount(section) {
        if (section === "actions") return root.actionIds().length
        if (section === "lyrics") return root.karaokeService && Array.isArray(root.karaokeService.lines)
            ? root.karaokeService.lines.length : 0
        if (section === "query") return 3
        if (section === "provider") return 1
        if (section === "results") return root.searchRows.length
        return 0
    }
    function setCursor(section, index) {
        // Without seek support there is no lyric cursor to enter.
        if (section === "lyrics" && !root.seekSupported) return
        // Reject sections the current view does not expose (notably every
        // section while loading): hovering or forcing a hidden section must
        // not light a dead highlight.
        var sections = root.visibleSections
        if (!sections || sections.indexOf(section) < 0) return
        var count = root.sectionCount(section)
        if (count <= 0) return
        root.focusSection = section
        root.selectedIndex = Math.max(0, Math.min(count - 1, index))
        root.cursorActive = true
    }

    function clampSelectedIndex() {
        var count = root.sectionCount(root.focusSection)
        if (count <= 0) {
            var visible = root.visibleSections
            if (visible && visible.length > 0 && visible.indexOf(root.focusSection) < 0) {
                root.focusSection = visible[0]
                root.selectedIndex = 0
            } else root.selectedIndex = 0
            return
        }
        if (root.selectedIndex < 0) root.selectedIndex = 0
        else if (root.selectedIndex >= count) root.selectedIndex = count - 1
    }

    // Up/Down wraps within the current section; Left/Right moves to the
    // adjacent visible section without changing the selected item. This
    // deliberate behavior differs from the audio panel's vertical
    // fall-through and keeps lyric rows addressable by index.
    function moveCursor(dx, dy) {
        var sections = root.visibleSections
        if (!sections || sections.length === 0) {
            root.cursorActive = false
            return
        }
        if (sections.indexOf(root.focusSection) < 0) {
            root.focusSection = sections[0]
            root.selectedIndex = 0
            root.cursorActive = true
            root.ensureCursorVisible()
            return
        }
        if (dx !== 0) {
            root.moveSection(dx)
            return
        }
        if (dy !== 0) {
            var count = root.sectionCount(root.focusSection)
            if (count <= 0) return
            var next = (root.selectedIndex + (dy > 0 ? 1 : -1) + count) % count
            root.selectedIndex = next
            root.cursorActive = true
            root.ensureCursorVisible()
        }
    }

    function moveSection(delta) {
        var sections = root.visibleSections
        if (!sections || sections.length === 0) {
            root.cursorActive = false
            return
        }
        var current = sections.indexOf(root.focusSection)
        if (current < 0) current = delta > 0 ? -1 : 0
        var next = (current + (delta > 0 ? 1 : -1) + sections.length) % sections.length
        root.focusSection = sections[next]
        root.clampSelectedIndex()
        root.cursorActive = true
        root.ensureCursorVisible()
    }

    function activateCursor() {
        // No exposed section (loading/idle): Enter/Space must not light a
        // dead highlight or dispatch a hidden action.
        var sections = root.visibleSections
        if (!sections || sections.length === 0) {
            root.cursorActive = false
            return
        }
        root.cursorActive = true
        root.clampSelectedIndex()
        var section = root.focusSection
        var index = root.selectedIndex
        if (section === "actions") {
            var ids = root.actionIds()
            if (index >= 0 && index < ids.length && root.actionEnabled(ids[index]))
                root.activateAction(ids[index])
            return
        }
        if (section === "lyrics") {
            // Unreachable while unsupported: the section is omitted from
            // visibleSections and setCursor rejects it, so activation never
            // routes to a consumed no-op. Guarded for defense in depth.
            if (root.seekSupported) root.seekLyricRow(index)
            return
        }
        if (section === "query") {
            if (index === 0) titleField.forceActiveFocus()
            else if (index === 1) artistField.forceActiveFocus()
            else albumField.forceActiveFocus()
            return
        }
        if (section === "provider") {
            root.cycleSearchProvider(1)
            return
        }
        if (section === "results") {
            root.selectSearchRow(index)
            return
        }
    }

    function ensureCursorVisible() {
        if (!root.cursorActive) return
        if (root.focusSection === "lyrics") {
            if (lyricList.count > root.selectedIndex)
                lyricList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
        } else if (root.focusSection === "results") {
            if (resultsList.count > root.selectedIndex)
                resultsList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
        }
    }

    function resetPanelCursor() {
        if (root.searchMode) {
            root.focusSection = "query"
            root.selectedIndex = 0
            root.cursorActive = true
            return
        }
        if (root.failureVisible) {
            root.focusSection = "actions"
            root.selectedIndex = 0
            root.cursorActive = true
            return
        }
        if (root.serviceState === "ready" && root.karaokeService) {
            var active = Number(root.karaokeService.activeLineIndex)
            var count = Array.isArray(root.karaokeService.lines) ? root.karaokeService.lines.length : 0
            if (root.seekSupported && active >= 0 && active < count) {
                root.focusSection = "lyrics"
                root.selectedIndex = active
                root.cursorActive = true
                if (lyricList.count > active) lyricList.positionViewAtIndex(active, ListView.Center)
            } else {
                root.focusSection = "actions"
                root.selectedIndex = root.firstEnabledActionIndex()
                root.cursorActive = true
            }
            return
        }
        root.cursorActive = false
    }

    // Exact panel key map: Escape closes, Tab hands panels off, Up/Down/j/k move
    // the cursor, Enter/Space activates, f follows, [ ] nudge, r retries or
    // refreshes, / searches, b returns to lyrics, x forgets the saved match.
    function handlePanelTextKey(text) {
        var key = String(text || "").toLowerCase()
        if (key === "f") {
            if (root.serviceState !== "ready") return
            root.followEnabled = !root.followEnabled
            if (root.followEnabled) root.followCurrent()
            return
        }
        if (text === "[") {
            root.requestOffsetDelta(100)
            return
        }
        if (text === "]") {
            root.requestOffsetDelta(-100)
            return
        }
        if (key === "r") {
            root.secondaryAction()
            return
        }
        if (text === "/") {
            root.openSearch()
            return
        }
        if (key === "b") {
            if (root.searchMode) root.closeSearch()
        }
    }
    // One metadata line per search row: duration, provider, confidence, timing,
    // and translation availability. Rows never carry lyric bodies.
    function resultMetaText(row) {
        if (!row || typeof row !== "object") return ""
        var parts = []
        if (row.duration !== undefined && row.duration !== null
                && isFinite(Number(row.duration)) && Number(row.duration) > 0)
            parts.push(KaraokeModel.formatTime(Number(row.duration)))
        if (typeof row.provider === "string" && row.provider !== "") parts.push(row.provider)
        if (typeof row.confidence === "string" && row.confidence !== "") parts.push(row.confidence)
        if (typeof row.timing === "string" && row.timing !== "")
            parts.push(row.timing === "none" ? "unsynced" : row.timing)
        parts.push(row.hasTranslation === true ? "translation" : "no translation")
        return parts.join(" · ")
    }

    function diagnosticText() {
        var diag = root.karaokeService ? root.karaokeService.lastDiagnostic : null
        if (!diag || typeof diag !== "object") return "No diagnostics yet"
        var parts = []
        parts.push("command: " + String(diag.kind || ""))
        parts.push("error: " + String(diag.error || ""))
        if (typeof diag.exitCode === "number" && diag.exitCode !== -1)
            parts.push("exit: " + diag.exitCode)
        if (typeof diag.exitStatus === "string" && diag.exitStatus !== "")
            parts.push("status: " + diag.exitStatus)
        if (typeof diag.elapsedMs === "number") parts.push("elapsed: " + diag.elapsedMs + " ms")
        if (typeof diag.coreVersion === "string" && diag.coreVersion !== "")
            parts.push("core: " + diag.coreVersion)
        // Optional-evidence fallback: capabilities without matchEvidence rank
        // by confidence/word-timing/provider order instead of match evidence.
        var caps = root.karaokeService ? root.karaokeService.capabilities : null
        if (caps && caps.embedded === false)
            parts.push("embedded tags: unavailable (needs python-mutagen)")
        if (!caps || caps.matchEvidence !== true)
            parts.push("match evidence: fallback ranking")
        return parts.join("\n")
    }

    readonly property string providerAttemptsText: {
        var attempts = root.karaokeService && Array.isArray(root.karaokeService.providerAttempts)
            ? root.karaokeService.providerAttempts : []
        var diag = root.karaokeService ? root.karaokeService.lastDiagnostic : null
        var fromDiag = diag && Array.isArray(diag.providerAttempts) ? diag.providerAttempts : []
        var rows = attempts.length > 0 ? attempts : fromDiag
        if (rows.length === 0) return ""
        var parts = []
        for (var i = 0; i < rows.length; i++) {
            if (rows[i] && typeof rows[i].provider === "string")
                parts.push(rows[i].provider + "/" + String(rows[i].outcome || ""))
        }
        return parts.length > 0 ? "Providers: " + parts.join(" · ") : ""
    }

    // True only when capabilities are actually unavailable (no capabilities
    // object, or a reported capabilitiesError) -- never merely because the
    // 60 s capabilitiesFresh() window lapsed. That freshness window still
    // governs background re-probe decisions (e.g. openSearch()'s force
    // probe) through svc.capabilitiesFresh() directly; it is unrelated to
    // whether "Retry capabilities" should be offered.
    readonly property bool capabilitiesUnavailable: {
        var svc = root.karaokeService
        if (!svc || !svc.capabilities) return true
        return typeof svc.capabilitiesError === "string" && svc.capabilitiesError !== ""
    }

    function retryCapabilities() {
        if (root.karaokeService && typeof root.karaokeService.probeCapabilities === "function")
            root.karaokeService.probeCapabilities(true)
    }

    component ProgressTrace: Item {
        id: trace
        property color accentColor: Color.accent
        property color mutedColor: Color.muted
        property real progress: 0
        property bool busy: false
        property real busyPhase: 0
        readonly property real busyStart: -20 + trace.busyPhase * (trace.width + 20)
        readonly property real head: trace.busy
            ? trace.busyStart + 20
            : trace.width * trace.progress
        enabled: false
        height: 10
        clip: true
        Rectangle {
            id: rail
            anchors.centerIn: parent
            width: parent.width
            height: 3
            radius: 1.5
            color: trace.mutedColor
            opacity: 0.5
        }
        Rectangle {
            x: trace.busy ? trace.busyStart : 0
            anchors.verticalCenter: rail.verticalCenter
            width: trace.busy ? 20 : trace.head
            height: rail.height
            radius: rail.radius
            color: trace.accentColor
            opacity: 0.9
        }
        Rectangle {
            x: trace.busy ? trace.head - width / 2
                : Math.max(0, Math.min(trace.width - width, trace.head - width / 2))
            anchors.verticalCenter: rail.verticalCenter
            width: 5
            height: 5
            radius: 2.5
            color: trace.accentColor
            visible: trace.busy || trace.progress > 0
        }
    }

    WidgetButton {
        id: barButton
        anchors.fill: parent
        bar: root.bar
        fixedWidth: root.slotWidth
        fixedHeight: root.barSize
        keepSpace: true
        text: ""
        // The full-slot button is a hit area with separately painted content.
        hasVisualContent: true
        tooltipText: root.tooltipText
        onPressed: function(code) {
            if (code === Qt.RightButton) root.secondaryAction()
            else if (code === Qt.MiddleButton) {
                root.openSearch()
                root.open()
            } else root.toggle()
        }
        onWheelMoved: function(delta) { root.handleWheel(delta) }
    }

    Item {
        id: content
        anchors.fill: parent
        clip: true

        ProgressTrace {
            id: barTrace
            anchors.centerIn: parent
            width: 104
            visible: root.barTraceVisible
            busy: root.serviceState === "loading"
            busyPhase: root.motionEnabled ? root.loadingPhase : 0.5
            progress: root.traceProgress
            accentColor: Color.accent
            mutedColor: root.bar ? root.bar.barForeground : Color.bar.text
            property real breathOpacity: 1
            opacity: root.pauseSceneVisible ? 0.5 : root.introBreathingRunning ? breathOpacity : 1
            SequentialAnimation on breathOpacity {
                id: introBreath
                running: root.introBreathingRunning
                loops: Animation.Infinite
                NumberAnimation { from: 0.4; to: 0.9; duration: 1400; easing.type: Easing.InOutSine }
                NumberAnimation { from: 0.9; to: 0.4; duration: 1400; easing.type: Easing.InOutSine }
            }
        }
        Row {
            id: countdownRow
            anchors.centerIn: parent
            width: Math.min(root.configuredWidth - Style.spacing.md * 2, 360)
            spacing: Style.spacing.sm
            visible: root.countdownVisible
            opacity: root.pauseSceneVisible ? 0.5 : 1
            Text {
                id: countdownText
                text: root.countdownDots
                textFormat: Text.PlainText
                color: Color.accent
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.body
                anchors.verticalCenter: parent.verticalCenter
            }
            KaraokeLine {
                id: previewLine
                width: Math.max(0, countdownRow.width - countdownText.implicitWidth - countdownRow.spacing)
                height: root.barSize
                line: root.countdownVisible && root.karaokeService ? root.karaokeService.nextLine : null
                position: line ? line.start : 0
                playing: false
                wordTiming: false
                foreground: Color.muted
                accent: Color.accent
                fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                fontSize: Style.font.body
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Text {
            id: pauseMark
            anchors.left: parent.left
            anchors.leftMargin: 2
            anchors.verticalCenter: parent.verticalCenter
            visible: root.pauseSceneVisible
            text: "⏸"
            textFormat: Text.PlainText
            color: root.bar ? root.bar.barForeground : Color.bar.text
            opacity: 0.5
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
        }

        Text {
            anchors.centerIn: parent
            visible: root.ready && !root.vertical && root.projectionState === "after_last"
                && root.karaokeService && root.karaokeService.afterLastElapsed < 0.25
            opacity: !root.karaokeService ? 0 : root.pauseSceneVisible ? 0.5
                : 1 - Math.min(1, root.karaokeService.afterLastElapsed / 0.25)
            text: root.lastVisibleLineText
            textFormat: Text.PlainText
            color: root.bar ? root.bar.barForeground : Color.bar.text
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
            width: Math.max(0, root.configuredWidth - Style.spacing.md * 2)
            horizontalAlignment: Text.AlignHCenter
        }
        Rectangle {
            anchors.centerIn: parent
            width: 22
            height: 22
            radius: 11
            color: Color.accent
            visible: root.ready && !root.vertical && root.projectionState === "after_last"
                && root.karaokeService && root.karaokeService.afterLastElapsed < 2.5
            opacity: !root.karaokeService ? 0 : root.pauseSceneVisible ? 0.25
                : 0.4 * (1 - Math.min(1, root.karaokeService.afterLastElapsed / 2.5))
        }

        Text {
            id: glyphText
            anchors.centerIn: parent
            visible: root.vertical
                || (root.finalFailure && !root.resolutionStatusVisible)
                || (root.ready && root.projectionState === "before_first"
                    && !root.beforeFirstSceneVisible)
                || (root.ready && root.projectionState === "after_last"
                    && root.karaokeService && root.karaokeService.afterLastElapsed >= 2.5)
            textFormat: Text.PlainText
            text: root.verticalGlyph
            color: root.finalFailure ? root.barSecondaryForeground
                : (root.bar ? root.bar.barForeground : Color.bar.text)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            opacity: root.finalFailure ? root.failureOpacity
                : (root.pauseSceneVisible ? 0.5 : 1)
        }
        Text {
            id: unsyncedBarText
            anchors.centerIn: parent
            width: Math.max(0, root.configuredWidth - Style.spacing.md * 2)
            visible: root.ready && !root.vertical && root.karaokeService
                && (root.karaokeService.timing === "none"
                    || root.karaokeService.timing === "instrumental")
            textFormat: Text.PlainText
            text: root.titleName + (root.karaokeService
                && root.karaokeService.timing === "instrumental" ? " · Instrumental" : "")
            color: root.bar ? root.bar.barForeground : Color.bar.text
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
        Text {
            anchors.left: glyphText.right
            anchors.leftMargin: Style.spacing.sm
            anchors.verticalCenter: glyphText.verticalCenter
            visible: root.finalFailure && !root.resolutionStatusVisible && !root.vertical
            text: root.karaokeService && root.karaokeService.resolutionPhrase !== ""
                ? root.karaokeService.resolutionPhrase : root.failureMessage
            textFormat: Text.PlainText
            color: root.barSecondaryForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            width: Math.max(0, root.configuredWidth - glyphText.width - Style.spacing.md * 2)
            opacity: root.failureOpacity
        }

        Text {
            id: resolutionBarText
            anchors.centerIn: parent
            width: Math.max(0, root.configuredWidth - Style.spacing.md * 2)
            visible: root.resolutionStatusVisible && !root.vertical
            textFormat: Text.PlainText
            text: root.resolutionPhrase
            color: root.bar ? root.bar.barForeground : Color.bar.text
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
        Item {
            anchors.fill: resolutionBarText
            visible: root.resolutionShimmerRunning
            clip: true
            Item {
                id: shimmerWindow
                width: 48
                height: parent.height
                clip: true
                Text {
                    x: -shimmerWindow.x
                    width: resolutionBarText.width
                    height: resolutionBarText.height
                    textFormat: Text.PlainText
                    text: resolutionBarText.text
                    color: Color.accent
                    opacity: 0.5
                    font: resolutionBarText.font
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
                SequentialAnimation on x {
                    id: shimmerSweep
                    running: root.resolutionShimmerRunning
                    loops: Animation.Infinite
                    NumberAnimation {
                        from: -48
                        to: resolutionBarText.width
                        duration: 2200
                        easing.type: Easing.InOutSine
                    }
                    PauseAnimation { duration: 550 }
                }
            }
        }

        Text {
            id: loadingSnapshotItem
            anchors.centerIn: parent
            visible: root.loadingSnapshotVisible && opacity > 0
            textFormat: Text.PlainText
            text: root.loadingSnapshotText
            color: root.bar ? root.bar.barForeground : Color.bar.text
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
            width: Math.max(0, root.configuredWidth - Style.spacing.md * 2)
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            id: wordSyncGlyph
            anchors.left: parent.left
            anchors.leftMargin: 2
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "◆"
            color: Color.accent
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            opacity: 0
            visible: lineItem.visible && root.karaokeService
                && root.karaokeService.timing === "word" && opacity > 0
        }

        KaraokeLine {
            id: lineItem
            visible: !root.vertical && root.ready && root.projectionState === "line"
                && root.karaokeService && !!root.karaokeService.currentLine
            anchors.fill: parent
            // The pause and Word Sync marks live in this left gutter, so
            // they never paint over the first letter.
            anchors.leftMargin: Math.max(Style.spacing.md,
                2 + Math.max(pauseMark.implicitWidth, wordSyncGlyph.implicitWidth) + Style.space(3))
            anchors.rightMargin: Style.spacing.md
            opacity: root.isPlaying ? 1 : 0.5
            line: root.karaokeService ? root.karaokeService.currentLine : null
            position: root.karaokeService && typeof root.karaokeService.position === "number"
                ? root.karaokeService.position : 0
            wordTiming: root.karaokeService ? root.karaokeService.timing === "word" : false
            playing: root.isPlaying
            foreground: root.bar ? root.bar.barForeground : Color.bar.text
            accent: Color.accent
            muted: Color.muted
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            fontSize: Style.font.body
        }

        NumberAnimation {
            id: loadingSnapshotFade
            target: loadingSnapshotItem
            property: "opacity"
            from: 1
            to: 0
            duration: 250
            easing.type: Easing.OutCubic
            running: false
            onFinished: {
                loadingSnapshotItem.opacity = 0
                root.loadingSnapshotText = ""
                root.loadingSnapshotTitle = ""
                root.loadingSnapshotArtist = ""
            }
        }
    }

    onShownKeyChanged: {
        var line = root.ready && root.projectionState === "line" && root.karaokeService
            ? root.karaokeService.currentLine : null
        var nextText = line ? String(line.text || "") : ""
        if (nextText !== "") {
            root.lastVisibleLineText = nextText
            root.lastVisibleTitle = root.titleName
            root.lastVisibleArtist = root.artistName
        }
    }
    onServiceStateChanged: {
        button.hideOwnTooltip()
        loadingRevealTimer.stop()
        root.loadingMotionReady = false
        if (serviceState === "idle") root.close()
        if (serviceState === "loading") {
            // Keep the outgoing lyric briefly while loading starts. A quick
            // result draws its due lyric at full opacity immediately.
            loadingSnapshotFade.stop()
            var hasOutgoingComposition = root.lastVisibleLineText !== ""
                || root.lastVisibleTitle !== "" || root.lastVisibleArtist !== ""
            root.loadingSnapshotText = root.lastVisibleLineText
            root.loadingSnapshotTitle = hasOutgoingComposition && root.lastVisibleTitle !== ""
                ? root.lastVisibleTitle : root.titleName
            root.loadingSnapshotArtist = hasOutgoingComposition && root.lastVisibleArtist !== ""
                ? root.lastVisibleArtist : root.artistName
            root.loadingHandoffPending = true
            root.loadingPhase = 0
            loadingSnapshotItem.opacity = root.loadingSnapshotText !== "" ? 1 : 0
            if (root.loadingSnapshotText !== "") loadingSnapshotFade.start()
            loadingRevealTimer.restart()
            root.searchMode = false
            root.showDiagnostics = false
            root.menuOpen = false
            root.cursorActive = false
            root.offsetWritePending = false
            root.offsetFlashVisible = false
        } else {
            if (root.ready) {
                root.lastVisibleTitle = root.titleName
                root.lastVisibleArtist = root.artistName
            }
            root.resetPanelCursor()
            if (root.ready && root.loadingHandoffPending && !root.vertical) {
                handoffReleaseTimer.restart()
            }
            if (!root.ready) root.loadingHandoffPending = false
        }
    }
    onKaraokeServiceChanged: root.deferredPushSettings()
    onSettingsChanged: root.pushSettings()
    onSearchModeChanged: {
        root.menuOpen = false
        if (root.searchMode) {
            if (root.searchSeedKey !== root.trackSeedKey()) root.seedQueryDrafts()
            root.focusSection = "query"
            root.selectedIndex = 0
            root.cursorActive = true
            if (root.opened) root.focusSearchTitle()
        } else root.resetPanelCursor()
    }
    // Host hide lifecycle: hiding the bar closes the native popout.
    Connections {
        target: root.bar
        ignoreUnknownSignals: true
        function onBarHiddenChanged() {
            if (root.bar && root.bar.barHidden === true) root.close()
        }
    }

    Timer {
        id: loadingRevealTimer
        interval: 250
        repeat: false
        onTriggered: {
            if (root.serviceState !== "loading") return
            root.loadingMotionReady = true
            if (root.loadingSnapshotText === "") {
                root.loadingSnapshotTitle = ""
                root.loadingSnapshotArtist = ""
            }
        }
    }


    Timer {
        id: handoffReleaseTimer
        interval: 1
        repeat: false
        onTriggered: root.loadingHandoffPending = false
    }

    Timer {
        id: loadingTraceTick
        interval: 20
        repeat: true
        running: root.loadingTraceRunning
        onTriggered: {
            if (root.loadingTraceRunning)
                root.loadingPhase = (root.loadingPhase + 0.014) % 1
        }
    }

    // Brief success feedback after an offset write lands.
    Timer {
        id: offsetFlashTimer
        interval: 1200
        repeat: false
        onTriggered: root.offsetFlashVisible = false
    }

    Timer {
        id: searchFocusTimer
        interval: 50
        repeat: false
        onTriggered: {
            if (!root.searchMode || !root.opened) return
            titleField.forceActiveFocus()
            if (!titleField.activeFocus) restart()
        }
    }
    onOpenedChanged: {
        if (opened) {
            root.resetPanelCursor()
            if (root.searchMode) root.focusSearchTitle()
            else Qt.callLater(function() { keyCatcher.forceActiveFocus() })
        }
    }

    component PanelAction: Item {
        id: actionItem
        required property string action
        readonly property int actionIndex: root.actionIds().indexOf(action)
        readonly property bool selected: root.cursorActive && root.focusSection === "actions"
            && root.selectedIndex === actionIndex
        implicitWidth: action === "refresh" ? 64 : action === "search" ? 58
            : action === "earlier" || action === "later" ? 28
            : action === "reset" ? 76 : action === "menu" ? 32
            : actionButton.implicitWidth + Style.space(8)
        implicitHeight: actionButton.implicitHeight
        width: implicitWidth
        height: implicitHeight
        Rectangle {
            anchors.fill: parent
            radius: Style.space(4)
            color: Qt.rgba(root.panelForeground.r, root.panelForeground.g,
                root.panelForeground.b, actionItem.selected ? 0.16 : 0.06)
            border.color: actionItem.selected ? Color.accent
                : Qt.rgba(root.panelForeground.r, root.panelForeground.g,
                    root.panelForeground.b, 0.34)
            border.width: 1
        }
        Button {
            id: actionButton
            anchors.fill: parent
            text: root.actionLabel(actionItem.action)
            enabled: root.actionEnabled(actionItem.action)
            hasCursor: actionItem.selected
            onClicked: root.activateAction(actionItem.action)
            onHovered: function(isHovered) {
                if (isHovered) root.setCursor("actions", actionItem.actionIndex)
            }
        }
    }

    KeyboardPanel {
        id: popup
        anchorItem: button
        owner: root
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher
        contentWidth: popup.fittedContentWidth(root.configuredWidth, root.configuredWidth)
        contentHeight: popup.fittedContentHeight(contentColumn.implicitHeight, 460)

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            // Release every key to the query editors while one holds focus
            // so typing and copy work.
            blocked: titleField.activeFocus || artistField.activeFocus
                || albumField.activeFocus
            onCloseRequested: root.close()
            onTabRequested: function(direction) { root.switchPanel(direction) }
            onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
            onActivateRequested: root.activateCursor()
            onDeleteRequested: root.deleteSelected()
            onTextKey: function(text) { root.handlePanelTextKey(text) }
            Column {
                id: contentColumn
                width: parent.width
                spacing: Style.space(8)
                Connections {
                    target: root.karaokeService
                    ignoreUnknownSignals: true
                    function onActiveLineIndexChanged() {
                        if (root.followEnabled) root.followCurrent()
                    }
                    function onDocumentChanged() {
                        // A new document ends manual search: the saved result
                        // is now the working lyrics.
                        root.searchMode = false
                        root.showDiagnostics = false
                        root.menuOpen = false
                        if (root.followEnabled && root.serviceState === "ready") root.resetPanelCursor()
                        else root.clampSelectedIndex()
                    }
                    function onStateChanged() {
                        if (root.followEnabled && root.serviceState === "ready") root.followCurrent()
                    }
                    function onOffsetMsChanged() {
                        // Flash only for a write this panel issued that landed
                        // cleanly; document syncs never set the pending flag.
                        if (root.offsetWritePending && root.karaokeService
                                && root.karaokeService.offsetError === "") {
                            root.offsetWritePending = false
                            root.showOffsetFlash()
                        }
                    }
                    function onOffsetSuccessSerialChanged() {
                        // Unchanged writes (reset at zero, clamped nudge) never
                        // move offsetMs, so the service serial is the feedback.
                        if (root.offsetWritePending && root.karaokeService
                                && root.karaokeService.offsetError === "") {
                            root.offsetWritePending = false
                            root.showOffsetFlash()
                        }
                    }
                    function onOffsetErrorChanged() {
                        if (root.karaokeService && root.karaokeService.offsetError !== "")
                            root.offsetWritePending = false
                    }
                }

                PanelHero {
                    width: parent.width
                    visible: root.serviceState === "ready" && !root.searchMode
                    title: root.titleName
                    meta: root.artistName
                    detail: root.panelTiming
                    foreground: root.panelForeground
                    fontFamily: Style.font.family
                    iconComponent: Component {
                        Item {
                            width: Style.font.display
                            height: Style.font.display
                            Image {
                                anchors.fill: parent
                                visible: root.heroArtLocal
                                source: root.heroArtLocal && root.karaokeService
                                    ? root.karaokeService.trackArtUrl : ""
                                fillMode: Image.PreserveAspectCrop
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: !root.heroArtLocal
                                textFormat: Text.PlainText
                                text: root.musicGlyph
                                font.family: root.panelFont
                                font.pixelSize: Style.font.display
                            }
                        }
                    }
                }

                // Keep metadata out of the hero; the provenance lives in Details.
                Item {
                    width: parent.width
                    height: 26
                    visible: root.serviceState === "ready" && !root.searchMode
                        && root.karaokeService.timing !== "instrumental"
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 3
                        radius: 2
                        color: root.secondaryForeground
                        opacity: 0.35
                    }
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width * Math.max(0, Math.min(1,
                            root.duration() > 0 && root.karaokeService
                                ? root.karaokeService.position / root.duration() : 0))
                        height: 3
                        radius: 2
                        color: Color.accent
                    }
                    Text {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        textFormat: Text.PlainText
                        text: root.karaokeService
                            ? KaraokeModel.formatTime(root.karaokeService.position) : "--:--"
                        color: root.secondaryForeground
                        font.family: root.panelFont
                        font.pixelSize: Style.font.caption
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        textFormat: Text.PlainText
                        text: KaraokeModel.formatTime(root.duration())
                        color: root.secondaryForeground
                        font.family: root.panelFont
                        font.pixelSize: Style.font.caption
                    }
                }

                Text {
                    id: statusText
                    width: parent.width
                    textFormat: Text.PlainText
                    color: root.secondaryForeground
                    font.family: root.panelFont
                    font.pixelSize: Style.font.body
                    visible: root.serviceState === "loading" && root.resolutionStatusVisible
                    horizontalAlignment: Text.AlignHCenter
                    text: root.resolutionPhrase
                }

                Column {
                    width: parent.width
                    spacing: Style.space(4)
                    visible: root.serviceState === "loading" && root.resolutionStatusVisible
                        && root.resolutionTimeline.length > 0
                    Repeater {
                        model: root.resolutionTimeline
                        delegate: Text {
                            required property var modelData
                            width: parent.width
                            textFormat: Text.PlainText
                            text: root.resolutionStepText(modelData)
                            color: modelData.outcome === "found" || modelData.outcome === "instrumental"
                                ? root.panelForeground : root.secondaryForeground
                            font.family: root.panelFont
                            font.pixelSize: Style.font.caption
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: Style.space(4)
                    visible: root.popupLoadingSnapshotVisible
                    Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: root.loadingSnapshotTitle
                        visible: text !== ""
                        color: root.panelForeground
                        font.family: root.panelFont
                        font.pixelSize: Style.font.body
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: root.loadingSnapshotArtist
                        visible: text !== ""
                        color: root.secondaryForeground
                        font.family: root.panelFont
                        font.pixelSize: Style.font.caption
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: root.loadingSnapshotText
                        color: root.secondaryForeground
                        font.family: root.panelFont
                        font.pixelSize: Style.font.body
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                }

                Item {
                    id: traceSlot
                    width: parent.width
                    height: 10
                    visible: root.serviceState !== "idle" && !root.searchMode
                    ProgressTrace {
                        id: popupTrace
                        width: Math.min(parent.width, 176)
                        x: (parent.width - width) / 2
                        visible: root.popupTraceVisible
                        busy: root.serviceState === "loading"
                        busyPhase: root.motionEnabled ? root.loadingPhase : 0.5
                        progress: root.traceProgress
                        accentColor: Color.accent
                        mutedColor: root.secondaryForeground
                    }
                }
                Text {
                    width: parent.width
                    visible: root.opened && root.countdownStep > 0 && !root.searchMode
                    textFormat: Text.PlainText
                    text: root.countdownDots
                    color: Color.accent
                    font.family: root.panelFont
                    font.pixelSize: Style.font.caption
                    horizontalAlignment: Text.AlignHCenter
                }

                // One centered failure composition: glyph, literal message, and
                // the primary action. Never owns the document.
                Column {
                    id: failureBlock
                    width: parent.width
                    spacing: Style.space(8)
                    visible: root.failureVisible && !(root.karaokeService
                        && root.karaokeService.autoRetryPending)
                    opacity: visible ? 1 : 0
                    Text {
                        id: failureGlyph
                        width: parent.width
                        textFormat: Text.PlainText
                        text: root.musicGlyph
                        color: root.secondaryForeground
                        font.family: root.panelFont
                        font.pixelSize: Style.font.display
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: root.failureMessage
                        color: root.panelForeground
                        font.family: root.panelFont
                        font.pixelSize: Style.font.body
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                    }
                    Text {
                        id: failureSummary
                        width: parent.width
                        visible: root.failureProviderSummary !== ""
                        textFormat: Text.PlainText
                        text: root.failureProviderSummary
                        color: root.secondaryForeground
                        font.family: root.panelFont
                        font.pixelSize: Style.font.caption
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                    }
                    Button {
                        id: failurePrimaryButton
                        text: root.failureActionText
                        anchors.horizontalCenter: parent.horizontalCenter
                        enabled: root.actionEnabled("primary")
                        hasCursor: root.cursorActive && root.focusSection === "actions"
                            && root.actionIds()[root.selectedIndex] === "primary"
                        onClicked: root.activateAction("primary")
                        onHovered: function(isHovered) { if (isHovered) root.setCursor("actions",
                            root.actionIds().indexOf("primary")) }
                    }
                    Button {
                        id: failureDetailsButton
                        text: root.showDiagnostics ? "Hide details" : "Details"
                        anchors.horizontalCenter: parent.horizontalCenter
                        hasCursor: root.cursorActive && root.focusSection === "actions"
                            && root.actionIds()[root.selectedIndex] === "details"
                        onClicked: root.showDiagnostics = !root.showDiagnostics
                        onHovered: function(isHovered) { if (isHovered) root.setCursor("actions",
                            root.actionIds().indexOf("details")) }
                    }
                    Button {
                        text: root.actionLabel("layoutMode")
                        anchors.horizontalCenter: parent.horizontalCenter
                        enabled: root.actionEnabled("layoutMode")
                        hasCursor: root.cursorActive && root.focusSection === "actions"
                            && root.actionIds()[root.selectedIndex] === "layoutMode"
                        onClicked: root.activateAction("layoutMode")
                        onHovered: function(isHovered) { if (isHovered) root.setCursor("actions",
                            root.actionIds().indexOf("layoutMode")) }
                    }
                    Column {
                        id: failureDiagnostics
                        width: parent.width
                        spacing: Style.space(4)
                        visible: root.showDiagnostics
                        Text {
                            width: parent.width
                            textFormat: Text.PlainText
                            text: root.diagnosticText()
                            color: root.secondaryForeground
                            font.family: root.panelFont
                            font.pixelSize: Style.font.caption
                            wrapMode: Text.Wrap
                        }
                        Text {
                            width: parent.width
                            textFormat: Text.PlainText
                            text: root.providerAttemptsText
                            visible: root.providerAttemptsText !== ""
                            color: root.secondaryForeground
                            font.family: root.panelFont
                            font.pixelSize: Style.font.caption
                            wrapMode: Text.Wrap
                        }
                        Button {
                            text: "Retry capabilities"
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: root.capabilitiesUnavailable
                            onClicked: root.retryCapabilities()
                        }
                    }
                }

                Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: root.privacyWarning
                    visible: root.privacyWarning !== ""
                    color: root.secondaryForeground
                    font.family: root.panelFont
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.Wrap
                }

                // Three compact groups remain on one row even at the 320px bar size.
                Row {
                    id: readyActions
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Style.space(4)
                    visible: root.serviceState === "ready" && !root.searchMode
                    PanelAction { action: "refresh" }
                    PanelAction { action: "search" }
                    Item { width: Style.space(2); height: 1 }
                    PanelAction { action: "earlier"; visible: root.offsetControlsAvailable; width: visible ? implicitWidth : 0 }
                    PanelAction { action: "reset"; visible: root.offsetControlsAvailable; width: visible ? implicitWidth : 0 }
                    PanelAction { action: "later"; visible: root.offsetControlsAvailable; width: visible ? implicitWidth : 0 }
                    Item { width: Style.space(2); height: 1 }
                    PanelAction { action: "menu" }
                }
                // The ⋯ menu floats over the lyric list under its button, so
                // opening it never moves the list. A fixed 1 px anchor keeps
                // the column layout identical whether it is open or closed
                // (Column does not lay out or show zero-height children).
                Item {
                    id: menuAnchor
                    width: parent.width
                    height: 1
                    z: 2
                    visible: root.serviceState === "ready" && !root.searchMode
                    Rectangle {
                        id: menuCard
                        visible: root.menuOpen
                        x: Math.max(0, readyActions.x + readyActions.width - width)
                        y: -Style.space(2) - 1
                        width: Math.min(parent.width, Math.max(menuColumn.implicitWidth, 160) + Style.space(12))
                        height: menuColumn.implicitHeight + Style.space(12)
                        radius: Style.space(6)
                        color: Qt.rgba(Color.popups.background.r, Color.popups.background.g,
                            Color.popups.background.b, 1)
                        border.width: 1
                        border.color: Qt.rgba(root.panelForeground.r, root.panelForeground.g,
                            root.panelForeground.b, 0.34)
                        Column {
                            id: menuColumn
                            anchors.centerIn: parent
                            spacing: Style.space(4)
                            Repeater {
                                model: root.serviceState === "ready" && root.menuOpen && !root.searchMode
                                    ? root.actionIds().slice(root.actionIds().indexOf("menu") + 1) : []
                                PanelAction {
                                    required property string modelData
                                    action: modelData
                                    width: menuCard.width - Style.space(12)
                                }
                            }
                        }
                    }
                }

                // Failed forget/remove while ready: actionable copy above the
                // diagnostics block. The working lyrics stay in place and the
                // forget/remove action remains enabled for retry.
                Column {
                    width: parent.width
                    spacing: Style.space(4)
                    visible: root.forgetFailureVisible
                    Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: root.forgetFailureMessage
                        color: root.panelForeground
                        font.family: root.panelFont
                        font.pixelSize: Style.font.body
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                    }
                    Button {
                        text: "Dismiss"
                        anchors.horizontalCenter: parent.horizontalCenter
                        onClicked: root.dismissForgetError()
                    }
                }

                Column {
                    width: parent.width
                    spacing: Style.space(4)
                    visible: root.showDiagnostics && root.serviceState === "ready" && !root.searchMode
                    Text {
                        id: matchedDetail
                        width: parent.width
                        visible: root.matchedText !== ""
                        textFormat: Text.PlainText
                        text: root.matchedText
                        color: root.secondaryForeground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        wrapMode: Text.Wrap
                    }
                    Text {
                        width: parent.width
                        visible: root.sharedNoticeVisible
                        textFormat: Text.PlainText
                        text: "Community lyrics · personal display only"
                        color: root.secondaryForeground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                    }
                    Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: root.diagnosticText()
                        color: root.secondaryForeground
                        font.family: root.panelFont
                        font.pixelSize: Style.font.caption
                        wrapMode: Text.Wrap
                    }
                    Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: root.providerAttemptsText
                        visible: root.providerAttemptsText !== ""
                        color: root.secondaryForeground
                        font.family: root.panelFont
                        font.pixelSize: Style.font.caption
                        wrapMode: Text.Wrap
                    }
                    Button {
                        text: "Retry capabilities"
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: root.capabilitiesUnavailable
                        onClicked: root.retryCapabilities()
                    }
                }

                Text {
                    id: unsyncedBadge
                    width: parent.width
                    visible: root.ready && !root.searchMode && root.karaokeService
                        && root.karaokeService.timing === "none"
                    text: "Unsynced"
                    textFormat: Text.PlainText
                    color: Color.accent
                    font.family: root.panelFont
                    font.pixelSize: Style.font.caption
                    horizontalAlignment: Text.AlignHCenter
                }
                Column {
                    id: instrumentalState
                    width: parent.width
                    spacing: Style.space(4)
                    visible: root.ready && !root.searchMode && root.karaokeService
                        && root.karaokeService.timing === "instrumental"
                    Text {
                        width: parent.width
                        text: "Instrumental Track"
                        textFormat: Text.PlainText
                        color: root.panelForeground
                        font.family: root.panelFont
                        font.pixelSize: Style.font.body
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Text {
                        width: parent.width
                        text: "LRCLIB identifies this track as instrumental."
                        textFormat: Text.PlainText
                        color: root.secondaryForeground
                        font.family: root.panelFont
                        font.pixelSize: Style.font.caption
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                    }
                }


                ListView {
                    id: lyricList
                    width: parent.width
                    height: Math.max(Math.min(220, contentHeight), root.menuOpen ? menuCard.height : 0)
                    visible: root.serviceState === "ready" && !root.searchMode
                        && root.karaokeService.timing !== "instrumental"
                    clip: true
                    model: root.karaokeService ? root.karaokeService.lines : []
                    spacing: Style.space(7)
                    // Edge fades: a row cut by the list edge (e.g. the
                    // previous line's timestamp under the actions) fades out
                    // instead of showing as a stray fragment.
                    Rectangle {
                        parent: lyricList
                        z: 1
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        height: Style.space(18)
                        visible: !lyricList.atYBeginning
                        gradient: Gradient {
                            GradientStop { position: 0; color: Color.popups.background }
                            GradientStop { position: 1; color: Qt.rgba(Color.popups.background.r,
                                Color.popups.background.g, Color.popups.background.b, 0) }
                        }
                    }
                    Rectangle {
                        parent: lyricList
                        z: 1
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: Style.space(18)
                        visible: !lyricList.atYEnd
                        gradient: Gradient {
                            GradientStop { position: 0; color: Qt.rgba(Color.popups.background.r,
                                Color.popups.background.g, Color.popups.background.b, 0) }
                            GradientStop { position: 1; color: Color.popups.background }
                        }
                    }
                    boundsBehavior: Flickable.StopAtBounds
                    onMovementStarted: {
                        if (!root.autoFollowing) root.followEnabled = false
                    }
                    onMovementEnded: {
                        if (!root.autoFollowing) root.followEnabled = false
                    }
                    delegate: Item {
                        id: rowItem
                        required property var modelData
                        required property int index
                        readonly property var activePaintText: currentRenderer.paintedText
                        readonly property var staticPaintText: staticLine
                        readonly property var translationText: rowTranslation
                        readonly property alias timeText: rowTime
                        width: lyricList.width
                        height: rowColumn.implicitHeight

                        CursorSurface {
                            id: rowCursor
                            anchors.fill: parent
                            hasCursor: root.seekSupported && root.cursorActive
                                && root.focusSection === "lyrics"
                                && root.selectedIndex === rowItem.index
                            current: root.karaokeService && root.karaokeService.timing !== "none"
                                && rowItem.index === root.karaokeService.activeLineIndex
                        }
                        Column {
                            id: rowColumn
                            width: parent.width
                            spacing: Style.space(2)

                            Text {
                                id: staticLine
                                width: parent.width
                                visible: root.karaokeService.timing === "none"
                                    || rowItem.index !== root.karaokeService.activeLineIndex
                                textFormat: Text.PlainText
                                text: rowItem.modelData.text || ""
                                color: root.secondaryForeground
                                font.family: Style.font.family
                                font.pixelSize: Math.round(Style.font.body * root.lyricScale)
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.Wrap
                            }

                            Item {
                                id: currentStage
                                width: parent.width
                                visible: root.karaokeService.timing !== "none"
                                    && rowItem.index === root.karaokeService.activeLineIndex
                                height: visible ? Math.max(24, currentRenderer.implicitHeight) : 0
                                KaraokeLine {
                                    id: currentRenderer
                                    anchors.fill: parent
                                    segmentEnabled: false
                                    wrapEnabled: true
                                    line: root.karaokeService && root.karaokeService.lines
                                        ? root.karaokeService.lines[rowItem.index] : rowItem.modelData
                                    position: root.karaokeService
                                        && typeof root.karaokeService.position === "number"
                                        ? root.karaokeService.position : 0
                                    wordTiming: root.karaokeService.timing === "word"
                                    playing: root.isPlaying
                                    foreground: root.panelForeground
                                    muted: root.secondaryForeground
                                    fontFamily: Style.font.family
                                    fontSize: Math.round(Style.font.body * root.lyricScale)
                                }
                            }

                            Text {
                                id: rowTranslation
                                width: parent.width
                                visible: root.translationsShown && rowItem.modelData
                                    && String(rowItem.modelData.translation || "") !== ""
                                textFormat: Text.PlainText
                                text: rowItem.modelData ? String(rowItem.modelData.translation || "") : ""
                                color: root.secondaryForeground
                                font.family: Style.font.family
                                font.pixelSize: Math.round(Style.font.caption * root.lyricScale)
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.Wrap
                            }

                            Text {
                                id: rowTime
                                width: parent.width
                                textFormat: Text.PlainText
                                visible: root.karaokeService.timing !== "none"
                                text: KaraokeModel.formatTime(Number(rowItem.modelData.start))
                                color: root.secondaryForeground
                                font.family: root.panelFont
                                font.pixelSize: Style.font.caption
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: root.seekSupported
                            hoverEnabled: true
                            onEntered: root.setCursor("lyrics", rowItem.index)
                            onClicked: root.seekLyricRow(rowItem.index)
                        }
                    }
                }

                Text {
                    id: seekHintText
                    width: parent.width
                    textFormat: Text.PlainText
                    visible: root.serviceState === "ready" && !root.searchMode
                        && root.karaokeService.timing !== "none"
                        && root.karaokeService.timing !== "instrumental" && root.seekHint !== ""
                    text: root.seekHint
                    color: root.secondaryForeground
                    font.family: root.panelFont
                    font.pixelSize: Style.font.caption
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }

                // Timing calibration: service-owned values only, never derived here.
                Column {
                    id: offsetBlock
                    width: parent.width
                    spacing: Style.space(4)
                    visible: root.serviceState === "ready" && !root.searchMode
                        && root.karaokeService.timing !== "none"
                        && root.karaokeService.timing !== "instrumental"
                    // The offset value is the reset button in the action stepper.
                    Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: "Timing offset saved"
                        visible: root.offsetFlashVisible
                        color: Color.accent
                        font.family: root.panelFont
                        font.pixelSize: Style.font.caption
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: root.karaokeService ? root.failureCopy(root.karaokeService.offsetError).message : ""
                        visible: root.karaokeService && root.karaokeService.offsetError !== ""
                        color: root.secondaryForeground
                        font.family: root.panelFont
                        font.pixelSize: Style.font.caption
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                    }
                    Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: root.offsetDisabledHint
                        visible: !root.offsetControlsAvailable
                        color: root.secondaryForeground
                        font.family: root.panelFont
                        font.pixelSize: Style.font.caption
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                    }
                }
                // Manual search: editable query, one provider at a time,
                // metadata rows. The displayed document is never touched here.
                Column {
                    id: searchView
                    width: parent.width
                    spacing: Style.space(6)
                    visible: root.searchMode
                    Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: "Manual search"
                        color: root.panelForeground
                        font.family: root.panelFont
                        font.pixelSize: Style.font.body
                        font.bold: true
                    }
                    TextField {
                        id: titleField
                        width: parent.width
                        placeholderText: "Title"
                        text: root.queryDraftTitle
                        hasCursor: root.cursorActive && root.focusSection === "query"
                            && root.selectedIndex === 0
                        onTextChanged: {
                            if (root.queryDraftTitle !== text) {
                                root.queryDraftTitle = text
                                if (root.karaokeService
                                        && typeof root.karaokeService.noteQueryEdited === "function")
                                    root.karaokeService.noteQueryEdited()
                            }
                        }
                        onHoveredChanged: if (hovered) root.setCursor("query", 0)
                        onAccepted: root.doSearch()
                        Keys.onEscapePressed: keyCatcher.forceActiveFocus()
                        Keys.onTabPressed: function(event) {
                            event.accepted = true
                            root.focusAdjacentQueryField(1)
                        }
                        Keys.onBacktabPressed: function(event) {
                            event.accepted = true
                            root.focusAdjacentQueryField(-1)
                        }
                    }
                    TextField {
                        id: artistField
                        width: parent.width
                        placeholderText: "Artist"
                        text: root.queryDraftArtist
                        hasCursor: root.cursorActive && root.focusSection === "query"
                            && root.selectedIndex === 1
                        onTextChanged: {
                            if (root.queryDraftArtist !== text) {
                                root.queryDraftArtist = text
                                if (root.karaokeService
                                        && typeof root.karaokeService.noteQueryEdited === "function")
                                    root.karaokeService.noteQueryEdited()
                            }
                        }
                        onHoveredChanged: if (hovered) root.setCursor("query", 1)
                        onAccepted: root.doSearch()
                        Keys.onEscapePressed: keyCatcher.forceActiveFocus()
                        Keys.onTabPressed: function(event) {
                            event.accepted = true
                            root.focusAdjacentQueryField(1)
                        }
                        Keys.onBacktabPressed: function(event) {
                            event.accepted = true
                            root.focusAdjacentQueryField(-1)
                        }
                    }
                    TextField {
                        id: albumField
                        width: parent.width
                        placeholderText: "Album (optional)"
                        text: root.queryDraftAlbum
                        hasCursor: root.cursorActive && root.focusSection === "query"
                            && root.selectedIndex === 2
                        onTextChanged: {
                            if (root.queryDraftAlbum !== text) {
                                root.queryDraftAlbum = text
                                if (root.karaokeService
                                        && typeof root.karaokeService.noteQueryEdited === "function")
                                    root.karaokeService.noteQueryEdited()
                            }
                        }
                        onHoveredChanged: if (hovered) root.setCursor("query", 2)
                        onAccepted: root.doSearch()
                        Keys.onEscapePressed: keyCatcher.forceActiveFocus()
                        Keys.onTabPressed: function(event) {
                            event.accepted = true
                            root.focusAdjacentQueryField(1)
                        }
                        Keys.onBacktabPressed: function(event) {
                            event.accepted = true
                            root.focusAdjacentQueryField(-1)
                        }
                    }
                    Row {
                        width: parent.width
                        spacing: Style.space(8)
                        Text {
                            textFormat: Text.PlainText
                            text: "Provider: " + root.activeSearchProvider
                            color: root.panelForeground
                            font.family: root.panelFont
                            font.pixelSize: Style.font.body
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Button {
                            text: "Change"
                            anchors.verticalCenter: parent.verticalCenter
                            enabled: root.availableSearchProviders().length > 1
                            hasCursor: root.cursorActive && root.focusSection === "provider"
                                && root.selectedIndex === 0
                            onClicked: root.cycleSearchProvider(1)
                            onHovered: function(isHovered) { if (isHovered) root.setCursor("provider", 0) }
                        }
                    }
                    Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: root.searchSupportHint
                        visible: root.searchSupportHint !== ""
                        color: root.secondaryForeground
                        font.family: root.panelFont
                        font.pixelSize: Style.font.caption
                        wrapMode: Text.Wrap
                    }
                    Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: root.searchOfflineHint
                        visible: root.searchOfflineHint !== ""
                        color: root.secondaryForeground
                        font.family: root.panelFont
                        font.pixelSize: Style.font.caption
                        wrapMode: Text.Wrap
                    }
                    Flow {
                        id: searchActions
                        width: parent.width
                        spacing: Style.space(6)
                        Repeater {
                            model: root.searchMode ? root.actionIds() : []
                            Button {
                                required property string modelData
                                required property int index
                                text: root.actionLabel(modelData)
                                enabled: root.actionEnabled(modelData)
                                hasCursor: root.cursorActive && root.focusSection === "actions"
                                    && root.selectedIndex === index
                                onClicked: root.activateAction(modelData)
                                onHovered: function(isHovered) { if (isHovered) root.setCursor("actions", index) }
                            }
                        }
                    }
                    Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: "Searching…"
                        visible: root.karaokeService && root.karaokeService.searchState === "loading"
                        color: root.secondaryForeground
                        font.family: root.panelFont
                        font.pixelSize: Style.font.body
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Column {
                        width: parent.width
                        spacing: Style.space(6)
                        visible: root.karaokeService
                            && (root.karaokeService.searchState === "not_found"
                                || root.karaokeService.searchState === "provider_error")
                        Text {
                            width: parent.width
                            textFormat: Text.PlainText
                            text: root.karaokeService
                                ? root.failureCopy(root.karaokeService.searchError).message : ""
                            color: root.panelForeground
                            font.family: root.panelFont
                            font.pixelSize: Style.font.body
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                        }
                        Button {
                            text: "Search again"
                            anchors.horizontalCenter: parent.horizontalCenter
                            onClicked: root.doSearch()
                        }
                    }
                    ListView {
                        id: resultsList
                        width: parent.width
                        height: Math.min(220, contentHeight)
                        clip: true
                        model: root.searchRows
                        spacing: Style.space(4)
                        boundsBehavior: Flickable.StopAtBounds
                        delegate: Item {
                            id: resultItem
                            required property var modelData
                            required property int index
                            width: resultsList.width
                            height: resultColumn.implicitHeight + Style.space(8)
                            CursorSurface {
                                anchors.fill: parent
                                hasCursor: root.cursorActive && root.focusSection === "results"
                                    && root.selectedIndex === resultItem.index
                            }
                            Column {
                                id: resultColumn
                                width: parent.width
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Style.space(2)
                                Text {
                                    width: parent.width
                                    textFormat: Text.PlainText
                                    text: String(resultItem.modelData.title || "")
                                        + (String(resultItem.modelData.artist || "") !== ""
                                            ? " — " + resultItem.modelData.artist : "")
                                    color: root.panelForeground
                                    font.family: root.panelFont
                                    font.pixelSize: Style.font.body
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: parent.width
                                    textFormat: Text.PlainText
                                    text: root.resultMetaText(resultItem.modelData)
                                    color: root.secondaryForeground
                                    font.family: root.panelFont
                                    font.pixelSize: Style.font.caption
                                    elide: Text.ElideRight
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onEntered: root.setCursor("results", resultItem.index)
                                onClicked: root.selectSearchRow(resultItem.index)
                            }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: root.ipcTarget
        function open(): void { root.open() }
        function close(): void { root.close() }
        function show(): void { root.open() }
        function hide(): void { root.close() }
        function toggle(): void { root.toggle() }
        function search(): void { root.openSearch(); root.open() }
    }

    Component.onCompleted: {
        root.pushSettings()
        Qt.callLater(root.followCurrent)
    }
}
