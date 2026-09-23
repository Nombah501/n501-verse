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
    // Timing is claimed only for a ready document with real word/line timing.
    readonly property string syncLabel: {
        if (!root.ready || !karaokeService) return ""
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
            var line = karaokeService && karaokeService.currentLine
                && typeof karaokeService.currentLine.text === "string"
                ? karaokeService.currentLine.text : ""
            if (line !== "") text += "\n" + line
            text += "\nClick: panel · Right: refresh · Middle: search"
            if (root.offsetControlsAvailable) text += " · Wheel: timing"
        } else if (root.serviceState === "loading") {
            text += "\nLoading synchronized lyrics…"
        } else if (root.failureVisible) {
            text += "\n" + root.failureMessage
        }
        return text
    }
    // Native music glyph shared by the bar surface and the panel hero fallback.
    readonly property string musicGlyph: "󰎆"
    readonly property string verticalGlyph: {
        if (root.serviceState === "not_found") return "○"
        if (root.serviceState === "provider_error" || root.serviceState === "dependency_error") return "!"
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
    readonly property alias installCommandField: installCommand
    readonly property alias failureGlyphText: failureGlyph.text
    readonly property bool barGlyphVisible: glyphText.visible
    readonly property alias failurePrimaryButton: failurePrimaryButton
    readonly property alias failureDetailsButton: failureDetailsButton
    // The lyric clip keeps its size across line and progress states.
    readonly property alias lyricClipItem: lineItem
    // Public observable for popup sizing: the smoke asserts the panel
    // content width follows the configured bar mode.
    readonly property alias popupContentWidth: popup.contentWidth
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
        return parts.join(" · ")
    }
    readonly property color panelForeground: bar ? bar.barForeground : Color.foreground
    readonly property string panelFont: bar ? bar.fontFamily : Style.font.family
    readonly property string panelTiming: {
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
    // Fetch-level failure key: dependency_error normalizes before any error
    // code so the install guidance is never hidden by kotonoha_unavailable.
    readonly property string failureKey: {
        if (root.searchMode) return ""
        if (root.serviceState !== "not_found" && root.serviceState !== "dependency_error"
                && root.serviceState !== "provider_error") return ""
        if (root.serviceState === "dependency_error") return "dependency_error"
        if (karaokeService && karaokeService.errorCode) return String(karaokeService.errorCode)
        return root.serviceState
    }
    readonly property bool failureVisible: root.failureKey !== ""
    readonly property string failureMessage: root.failureCopy(root.failureKey).message
    readonly property string failureActionText: root.failureCopy(root.failureKey).action
    readonly property string offsetText: {
        var ms = karaokeService ? Math.trunc(Number(karaokeService.offsetMs) || 0) : 0
        if (ms === 0) return "Lyrics ±0 ms"
        return "Lyrics " + (ms > 0 ? "+" : "-") + Math.abs(ms) + " ms"
    }
    readonly property bool offsetControlsAvailable: !!karaokeService
        && karaokeService.offsetAvailable === true
    readonly property string offsetSupportHint: {
        if (!karaokeService || typeof karaokeService.capabilityExplanation !== "function") return ""
        if (karaokeService.capabilityExplanation("offset") === "") return ""
        if (!karaokeService.capabilities) return "Offset capabilities are unavailable"
        return "This Kotonoha version does not support offset"
    }
    readonly property string offsetDisabledHint: root.offsetSupportHint !== ""
        ? root.offsetSupportHint : "Timing offset needs a matched document"
    readonly property string searchSupportHint: {
        if (!karaokeService || typeof karaokeService.capabilityExplanation !== "function") return ""
        if (karaokeService.capabilityExplanation("search") === "") return ""
        if (!karaokeService.capabilities) return "Search capabilities are unavailable"
        return "This Kotonoha version does not support search"
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
    readonly property bool seekSupported: !!karaokeService && !!karaokeService.activePlayer
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
    property bool loadingLabelReady: false
    readonly property bool motionVisible: root.visible && !(root.bar && root.bar.barHidden === true)
    readonly property bool isPlaying: !!karaokeService && !!karaokeService.activePlayer
        && karaokeService.activePlayer.isPlaying === true
    readonly property string projectionState: root.karaokeService
        ? String(root.karaokeService.projectionState || "") : ""
    readonly property bool beforeFirstSceneVisible: root.projectionState === "before_first"
        && root.karaokeService
        && Number(root.karaokeService.leadInDuration || 0)
            - KaraokeModel.interludeThreshold() > 1e-9
    readonly property bool loadingHandoffVisible: root.serviceState === "loading"
        && root.loadingHandoffPending && !root.loadingMotionReady
    readonly property bool loadingSnapshotVisible: !root.vertical
        && root.loadingHandoffVisible && root.loadingSnapshotText !== ""
    readonly property bool timedGapVisible: root.ready
        && (root.beforeFirstSceneVisible || root.projectionState === "interlude")
    readonly property bool barTraceVisible: root.motionVisible && !root.vertical
        && ((root.serviceState === "loading" && root.loadingMotionReady)
            || root.timedGapVisible)
    readonly property bool finalFailure: ["not_found", "provider_error", "dependency_error"]
        .indexOf(root.serviceState) >= 0
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
        } else if (root.serviceState === "not_found" || root.serviceState === "dependency_error"
                || root.serviceState === "provider_error") {
            if (typeof svc.retry === "function") svc.retry()
        }
    }

    function followCurrent() {
        if (!root.karaokeService || !Array.isArray(root.karaokeService.lines)) return
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
        if (!svc || typeof svc.seekToLine !== "function") return false
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
        case "dependency_error":
            return {message: "Install Kotonoha 0.2.3 separately", action: "Select setup link"}
        case "kotonoha_unavailable":
            // Surfaces in the search/select/forget views, whose own state
            // (searchError/forgetError) is not normalized through
            // failureKey/dependency_error the way the main fetch view is.
            return {message: "Kotonoha provider library is unavailable", action: "Try again"}
        default:
            return {message: "No synchronized lyrics found", action: "Try again"}
        }
    }

    function failurePrimary() {
        var key = root.failureKey
        if (key === "dependency_error") {
            installCommand.selectAll()
            installCommand.forceActiveFocus()
            return
        }
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
        if (root.offsetControlsAvailable) ids.push("earlier", "later", "reset")
        if (!root.followEnabled) ids.push("follow")
        ids.push("details")
        ids.push("layoutMode")
        if (root.karaokeService && root.karaokeService.offsetError !== "") ids.push("retry_offset")
        if (root.forgetVisible) ids.push("forget")
        else if (root.removeVisible) ids.push("remove")
        return ids
    }
    function actionLabel(action) {
        switch (action) {
        case "refresh": return "Refresh"
        case "search": return root.searchMode ? "Search" : "Search"
        case "back": return "Back"
        case "earlier": return "Earlier"
        case "later": return "Later"
        case "reset": return "Reset"
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
        default: return action
        }
    }

    function actionEnabled(action) {
        var svc = root.karaokeService
        if (action === "refresh") return !!svc && svc.retryAvailable !== false
        if (action === "primary") {
            // Only retry-type primaries use the fetch retry cooldown. The
            // alias-unavailable Forget, Search-again, install-copy, and
            // offset-retry primaries must stay available during cooldown.
            var key = root.failureKey
            if (key === "alias_unavailable" || key === "selection_not_found"
                    || key === "dependency_error" || key === "offset_store_failed")
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
        case "details":
            root.showDiagnostics = !root.showDiagnostics
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
        if (typeof row.timing === "string" && row.timing !== "") parts.push(row.timing)
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
        if (typeof diag.kotonohaVersion === "string" && diag.kotonohaVersion !== "")
            parts.push("kotonoha: " + diag.kotonohaVersion)
        // Optional-evidence fallback: capabilities without matchEvidence rank
        // by confidence/word-timing/provider order instead of match evidence.
        var caps = root.karaokeService ? root.karaokeService.capabilities : null
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
        }

        Text {
            id: glyphText
            anchors.centerIn: parent
            visible: root.vertical || root.finalFailure
                || (root.ready && root.projectionState === "before_first"
                    && !root.beforeFirstSceneVisible)
                || (root.ready && root.projectionState === "after_last")
            textFormat: Text.PlainText
            text: root.verticalGlyph
            color: root.finalFailure ? Color.muted
                : (root.bar ? root.bar.barForeground : Color.bar.text)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
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

        KaraokeLine {
            id: lineItem
            visible: !root.vertical && root.ready && root.projectionState === "line"
                && root.karaokeService && !!root.karaokeService.currentLine
            anchors.fill: parent
            anchors.leftMargin: Style.spacing.md
            anchors.rightMargin: Style.spacing.md
            opacity: root.isPlaying ? 1 : 0.72
            line: root.karaokeService ? root.karaokeService.currentLine : null
            position: root.karaokeService && typeof root.karaokeService.position === "number"
                ? root.karaokeService.position : 0
            wordTiming: root.karaokeService ? root.karaokeService.timing === "word" : false
            playing: root.isPlaying
            foreground: root.bar ? root.bar.barForeground : Color.bar.text
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
        loadingLabelTimer.stop()
        root.loadingMotionReady = false
        root.loadingLabelReady = false
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
            loadingLabelTimer.restart()
            root.searchMode = false
            root.showDiagnostics = false
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
        id: loadingLabelTimer
        interval: 700
        repeat: false
        onTriggered: {
            if (root.serviceState === "loading") root.loadingLabelReady = true
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
            // Release every key to the query editors and the install-command
            // editor while one holds focus so typing and copy work.
            blocked: titleField.activeFocus || artistField.activeFocus
                || albumField.activeFocus || installCommand.activeFocus
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
                    fontFamily: root.panelFont
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

                Column {
                    width: parent.width
                    spacing: Style.space(2)
                    visible: root.serviceState === "ready" && !root.searchMode
                    Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: root.matchedText
                        visible: root.matchedText !== ""
                        color: Color.muted
                        font.family: root.panelFont
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: "Community lyrics · personal display only"
                        visible: root.sharedNoticeVisible
                        color: Color.muted
                        font.family: root.panelFont
                        font.pixelSize: Style.font.caption
                    }
                    Text {
                        textFormat: Text.PlainText
                        text: root.karaokeService
                            ? KaraokeModel.formatTime(root.karaokeService.position) + " / "
                                + KaraokeModel.formatTime(root.duration()) : "--:-- / --:--"
                        color: Color.muted
                        font.family: root.panelFont
                        font.pixelSize: Style.font.caption
                    }
                }

                Text {
                    id: statusText
                    width: parent.width
                    textFormat: Text.PlainText
                    color: Color.muted
                    font.family: root.panelFont
                    font.pixelSize: Style.font.body
                    visible: root.serviceState === "loading" && root.loadingLabelReady && !root.searchMode
                    horizontalAlignment: Text.AlignHCenter
                    text: "Loading synchronized lyrics…"
                }

                Column {
                    width: parent.width
                    spacing: Style.space(4)
                    visible: root.popupLoadingSnapshotVisible
                    opacity: loadingSnapshotItem.opacity
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
                        color: Color.muted
                        font.family: root.panelFont
                        font.pixelSize: Style.font.caption
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: root.loadingSnapshotText
                        color: Color.muted
                        font.family: root.panelFont
                        font.pixelSize: Style.font.body
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                }

                ProgressTrace {
                    id: popupTrace
                    width: Math.min(parent.width, 176)
                    x: (parent.width - width) / 2
                    visible: root.popupTraceVisible
                    busy: root.serviceState === "loading"
                    busyPhase: root.motionEnabled ? root.loadingPhase : 0.5
                    progress: root.traceProgress
                    accentColor: Color.accent
                    mutedColor: Color.muted
                }

                // One centered failure composition: glyph, literal message, and
                // the primary action. Never owns the document.
                Column {
                    id: failureBlock
                    width: parent.width
                    spacing: Style.space(8)
                    visible: root.failureVisible
                    opacity: visible ? 1 : 0
                    Text {
                        id: failureGlyph
                        width: parent.width
                        textFormat: Text.PlainText
                        text: root.musicGlyph
                        color: Color.muted
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
                            color: Color.muted
                            font.family: root.panelFont
                            font.pixelSize: Style.font.caption
                            wrapMode: Text.Wrap
                        }
                        Text {
                            width: parent.width
                            textFormat: Text.PlainText
                            text: root.providerAttemptsText
                            visible: root.providerAttemptsText !== ""
                            color: Color.muted
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
                    color: Color.muted
                    font.family: root.panelFont
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.Wrap
                }

                Column {
                    width: parent.width
                    spacing: Style.space(6)
                    visible: root.failureKey === "dependency_error"
                    TextEdit {
                        id: installCommand
                        width: parent.width
                        height: implicitHeight
                        textFormat: TextEdit.PlainText
                        text: "https://github.com/locez/kotonoha/releases/tag/v0.2.3"
                        color: Color.muted
                        font.family: root.panelFont
                        font.pixelSize: Style.font.caption
                        readOnly: true
                        selectByMouse: true
                        selectByKeyboard: true
                        wrapMode: TextEdit.WrapAnywhere
                        horizontalAlignment: TextEdit.AlignHCenter
                    }
                }

                // Visible actions sit before the long lyric list so the full
                // action area stays inside the panel height.
                Flow {
                    id: readyActions
                    width: parent.width
                    spacing: Style.space(6)
                    visible: root.serviceState === "ready" && !root.searchMode
                    Repeater {
                        model: root.serviceState === "ready" && !root.searchMode ? root.actionIds() : []
                        Button {
                            required property string modelData
                            required property int index
                            text: root.actionLabel(modelData)
                            enabled: root.actionEnabled(modelData)
                            hasCursor: root.cursorActive && root.focusSection === "actions"
                                && root.selectedIndex === index
                            visible: {
                                if (modelData === "follow") return !root.followEnabled
                                return true
                            }
                            onClicked: root.activateAction(modelData)
                            onHovered: function(isHovered) { if (isHovered) root.setCursor("actions", index) }
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
                        width: parent.width
                        textFormat: Text.PlainText
                        text: root.diagnosticText()
                        color: Color.muted
                        font.family: root.panelFont
                        font.pixelSize: Style.font.caption
                        wrapMode: Text.Wrap
                    }
                    Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: root.providerAttemptsText
                        visible: root.providerAttemptsText !== ""
                        color: Color.muted
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

                ListView {
                    id: lyricList
                    width: parent.width
                    height: Math.min(220, contentHeight)
                    visible: root.serviceState === "ready" && !root.searchMode
                    clip: true
                    model: root.karaokeService ? root.karaokeService.lines : []
                    spacing: Style.space(7)
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
                        width: lyricList.width
                        height: rowColumn.implicitHeight

                        CursorSurface {
                            id: rowCursor
                            anchors.fill: parent
                            hasCursor: root.seekSupported && root.cursorActive
                                && root.focusSection === "lyrics"
                                && root.selectedIndex === rowItem.index
                            current: root.karaokeService
                                && rowItem.index === root.karaokeService.activeLineIndex
                        }
                        Column {
                            id: rowColumn
                            width: parent.width
                            spacing: Style.space(2)

                            Text {
                                width: parent.width
                                visible: rowItem.index !== root.karaokeService.activeLineIndex
                                textFormat: Text.PlainText
                                text: rowItem.modelData.text || ""
                                color: Color.muted
                                font.family: root.panelFont
                                font.pixelSize: Style.font.body
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.Wrap
                            }

                            Item {
                                id: currentStage
                                width: parent.width
                                visible: rowItem.index === root.karaokeService.activeLineIndex
                                height: visible ? Math.max(24, currentRenderer.implicitHeight) : 0
                                KaraokeLine {
                                    id: currentRenderer
                                    anchors.fill: parent
                                    line: rowItem.modelData
                                    position: root.karaokeService
                                        && typeof root.karaokeService.position === "number"
                                        ? root.karaokeService.position : 0
                                    wordTiming: root.karaokeService.timing === "word"
                                    playing: root.isPlaying
                                    foreground: Color.accent
                                    muted: Color.muted
                                    fontFamily: root.panelFont
                                    fontSize: Style.font.body
                                }
                            }

                            Text {
                                width: parent.width
                                visible: root.translationsShown && rowItem.modelData
                                    && String(rowItem.modelData.translation || "") !== ""
                                textFormat: Text.PlainText
                                text: rowItem.modelData ? String(rowItem.modelData.translation || "") : ""
                                color: Color.muted
                                font.family: root.panelFont
                                font.pixelSize: Style.font.caption
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.Wrap
                            }

                            Text {
                                width: parent.width
                                textFormat: Text.PlainText
                                text: KaraokeModel.formatTime(Number(rowItem.modelData.start))
                                color: Color.muted
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
                    width: parent.width
                    textFormat: Text.PlainText
                    text: root.seekHint
                    visible: root.serviceState === "ready" && !root.searchMode && root.seekHint !== ""
                    color: Color.muted
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
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: Style.space(8)
                        Text {
                            textFormat: Text.PlainText
                            text: root.offsetText
                            color: root.panelForeground
                            font.family: root.panelFont
                            font.pixelSize: Style.font.body
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
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
                        color: Color.muted
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
                        color: Color.muted
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
                        color: Color.muted
                        font.family: root.panelFont
                        font.pixelSize: Style.font.caption
                        wrapMode: Text.Wrap
                    }
                    Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: root.searchOfflineHint
                        visible: root.searchOfflineHint !== ""
                        color: Color.muted
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
                        color: Color.muted
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
                                    color: Color.muted
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
    }

    Component.onCompleted: {
        root.pushSettings()
        Qt.callLater(root.followCurrent)
    }
}
