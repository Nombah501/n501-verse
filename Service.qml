pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import "KaraokeModel.js" as KaraokeModel

Item {
    id: root

    property var shell: null
    property var mediaService: null
    property var fallbackMediaStatus: null
    property string state: "idle"
    property real position: 0
    property var document: null
    property string provider: ""
    property string timing: "none"
    property int activeLineIndex: -1
    property var currentLine: null
    property string projectionState: "unknown"
    property string errorCode: ""
    property int requestGeneration: 0
    property string generationTrackKey: ""
    property var pendingRequest: null
    property bool waitingForExit: false
    property real lastProjectionPosition: -1
    property int resolverTimeoutMs: 30000
    property int retryCooldownMs: 3000
    readonly property bool retryAvailable: !retryCooldownTimer.running
    property string networkMode: "Auto"
    property bool neteaseEnabled: true
    property bool lrclibEnabled: true
    property bool kugouEnabled: true
    property string showTranslations: "On"
    readonly property bool translationsVisible: root.showTranslations !== "Off"
    property int offsetMs: 0
    property var offsetKey: null
    property string offsetError: ""
    property var offsetRetry: null
    property int offsetSuccessSerial: 0
    readonly property bool offsetAvailable: root.offsetKey !== null && root.offsetKey !== undefined
    property var capabilities: null
    property string kotonohaVersion: ""
    property string capabilitiesError: ""
    property real capabilitiesProbedAtMs: 0
    property int capabilitiesFreshMs: 60000
    property string searchState: "idle"
    property var searchResults: []
    property string searchError: ""
    // Bounded failure token for the last forget/remove action. Failed removal
    // never discards the working document; the ready panel renders this.
    property string forgetError: ""
    property var searchQuery: null
    property string selectedProvider: ""
    property string selectedSongId: ""
    property string selectedCacheMode: ""
    property var savedAlias: null
    property var providerAttempts: []
    property var lastDiagnostic: null
    property string autoRetriedKey: ""
    property bool waitingForActionExit: false
    property int actionTimeoutMs: 30000
    property int searchCooldownMs: 5000
    property var searchCooldowns: ({})
    property int searchCooldownRevision: 0

    readonly property var mprisPlayers: Mpris.players ? Mpris.players.values : []
    readonly property bool mprisFallbackEnabled: !root.mediaService && root.shell
        && typeof root.shell.pluginShellForBarEntry === "function"
    readonly property var activePlayer: root.mediaService ? root.mediaService.activePlayer
        : (root.mprisFallbackEnabled ? root.fallbackActivePlayer() : null)
    readonly property string trackKey: root.currentTrackKey()
    readonly property var lines: document && Array.isArray(document.lines) ? document.lines : []
    readonly property string timingDetail: KaraokeModel.timingDetail(root.lines)
    readonly property string helperPath: String(Qt.resolvedUrl("bin/karaoke-lyrics")).replace(/^file:\/\//, "")
    function finite(value) {
        return typeof value === "number" && isFinite(value)
    }

    // Unicode-safe code-point length, consistent with the helper's Python
    // len()/slicing. String.length counts UTF-16 units and would let
    // astral characters bypass the 256-field bound.
    function codePointLength(value) {
        try {
            return Array.from(String(value)).length
        } catch (error) {
            return String(value).length
        }
    }

    function textValue(value) {
        return value === undefined || value === null ? "" : String(value)
    }
    function currentTrackKey() {
        var player = root.activePlayer
        if (!player) return ""
        var title = textValue(player.trackTitle)
        var artist = textValue(player.trackArtist)
        if (title === "" && artist === "") return ""
        var length = null
        if (player.lengthSupported === true) {
            var candidate = Number(player.length)
            if (root.finite(candidate) && candidate > 0) length = candidate
        }
        return JSON.stringify({
            dbusName: textValue(player.dbusName),
            uniqueId: textValue(player.uniqueId),
            trackTitle: title,
            trackArtist: artist,
            trackAlbum: textValue(player.trackAlbum),
            length: length,
            url: root.playerUrl()
        })
    }

    // Omarchy 4.0.3 gives third-party bar widgets a scoped shell facade that
    // deliberately withholds omarchy.media. Keep the normal shared-service
    // path, but bridge that one compatibility gap through the same selected
    // media service's status IPC and its already-published MPRIS player.
    function fallbackPlayerScore(player, status) {
        if (!player || !status || status.hasPlayer !== true || status.hasMedia !== true)
            return -1
        var title = root.textValue(player.trackTitle)
        var artist = root.textValue(player.trackArtist)
        if (title === "" && artist === "") return -1

        var identity = root.textValue(status.identity)
        var desktopEntry = root.textValue(status.desktopEntry)
        var playerIdentity = root.textValue(player.identity)
        var playerDesktopEntry = root.textValue(player.desktopEntry)
        var playerDbusName = root.textValue(player.dbusName)
        var score = 0
        if (identity !== "" && (identity === playerIdentity
                || identity === playerDesktopEntry || identity === playerDbusName))
            score += 100
        if (desktopEntry !== "" && (desktopEntry === playerIdentity
                || desktopEntry === playerDesktopEntry || desktopEntry === playerDbusName))
            score += 100

        var statusTitle = root.textValue(status.title)
        var statusArtist = root.textValue(status.artist)
        if (statusTitle !== "" && statusTitle === title) score += 40
        if (statusArtist !== "" && statusArtist === artist) score += 20

        var hasIdentity = identity !== "" || desktopEntry !== ""
        var hasTrack = statusTitle !== "" || statusArtist !== ""
        if (score === 0 || (hasIdentity && !hasTrack && score < 100)
                || (!hasIdentity && score < 60))
            return -1
        return score + (player.isPlaying === true ? 1 : 0)
    }

    function fallbackActivePlayer() {
        var players = root.mprisPlayers
        var status = root.fallbackMediaStatus
        if (status && typeof status === "object") {
            if (status.hasPlayer !== true || status.hasMedia !== true) return null
            var best = null
            var bestScore = -1
            for (var i = 0; i < players.length; i++) {
                var score = root.fallbackPlayerScore(players[i], status)
                if (score > bestScore) {
                    best = players[i]
                    bestScore = score
                }
            }
            return best
        }

        // Do not guess across several players before the status bridge
        // identifies Omarchy's selected one.
        var playing = []
        var metadata = []
        for (var j = 0; j < players.length; j++) {
            var player = players[j]
            if (!player) continue
            var hasMetadata = root.textValue(player.trackTitle) !== ""
                || root.textValue(player.trackArtist) !== ""
            if (!hasMetadata) continue
            metadata.push(player)
            if (player.isPlaying === true) playing.push(player)
        }
        if (playing.length === 1) return playing[0]
        return playing.length === 0 && metadata.length === 1 ? metadata[0] : null
    }

    function applyFallbackMediaStatus(raw) {
        var parsed = null
        try {
            var value = JSON.parse(String(raw || "").trim())
            if (value && typeof value === "object") parsed = value
        } catch (error) {
            parsed = null
        }
        var previous = root.fallbackMediaStatus
        if (previous && parsed && JSON.stringify(previous) === JSON.stringify(parsed)) return
        root.fallbackMediaStatus = parsed
        root.scheduleTrackSettle()
    }

    function refreshFallbackMediaStatus() {
        if (!root.mprisFallbackEnabled || fallbackMediaStatusProcess.running) return
        fallbackMediaStatusProcess.running = true
    }

    Process {
        id: fallbackMediaStatusProcess
        command: ["omarchy-shell", "media", "status"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.applyFallbackMediaStatus(text)
        }
    }

    Timer {
        id: fallbackMediaStatusTimer
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: root.mprisFallbackEnabled
        onTriggered: root.refreshFallbackMediaStatus()
    }

    Connections {
        target: Mpris.players
        ignoreUnknownSignals: true
        function onValuesChanged() {
            root.scheduleTrackSettle()
            root.refreshFallbackMediaStatus()
        }
    }

    function bindMediaService() {
        var candidate = null
        if (root.shell && typeof root.shell.firstPartyServiceFor === "function") {
            try {
                candidate = root.shell.firstPartyServiceFor("omarchy.media")
            } catch (error) {
                candidate = null
            }
        }
        if (candidate !== root.mediaService) {
            root.mediaService = candidate
            root.fallbackMediaStatus = null
            root.scheduleTrackSettle()
        }
        if (candidate) {
            mediaRetryTimer.stop()
            root.probeCapabilities(false)
        } else if (root.mprisFallbackEnabled) {
            root.refreshFallbackMediaStatus()
        } else mediaRetryTimer.restart()
    }

    function scheduleTrackSettle() {
        trackSettleTimer.restart()
    }

    function clearLyrics(nextState) {
        root.document = null
        root.provider = ""
        root.timing = "none"
        root.activeLineIndex = -1
        root.currentLine = null
        root.projectionState = "unknown"
        root.position = 0
        root.lastProjectionPosition = -1
        root.errorCode = ""
        root.offsetMs = 0
        root.offsetKey = null
        root.offsetError = ""
        root.selectedProvider = ""
        root.selectedSongId = ""
        root.selectedCacheMode = ""
        root.savedAlias = null
        root.providerAttempts = []
        root.forgetError = ""
        root.state = nextState || "idle"
        root.updateProjectionTimer()
    }

    function playerUrl() {
        var player = root.activePlayer
        if (!player || !player.metadata || typeof player.metadata !== "object") return null
        var url = player.metadata["xesam:url"]
        if (typeof url !== "string" || url.indexOf("file://") !== 0) return null
        return url
    }

    readonly property string trackArtUrl: {
        var player = root.activePlayer
        if (!player || !player.metadata || typeof player.metadata !== "object") return ""
        var art = player.metadata["mpris:artUrl"]
        return typeof art === "string" ? art : ""
    }

    function normalizeBool(value, fallback) {
        if (value === undefined || value === null) return fallback
        return value === true
    }

    function enabledProviders() {
        var list = []
        if (root.neteaseEnabled === true) list.push("netease")
        if (root.lrclibEnabled === true) list.push("lrclib")
        if (root.kugouEnabled === true) list.push("kugou")
        return list.join(",")
    }

    function configure(options) {
        var opts = options && typeof options === "object" ? options : {}
        var network = opts.networkMode === "Offline" ? "Offline" : "Auto"
        var netease = root.normalizeBool(opts.neteaseEnabled, true)
        var lrclib = root.normalizeBool(opts.lrclibEnabled, true)
        var kugou = root.normalizeBool(opts.kugouEnabled, true)
        var showT = opts.showTranslations === "Off" ? "Off" : "On"
        if (network === root.networkMode && netease === root.neteaseEnabled
                && lrclib === root.lrclibEnabled && kugou === root.kugouEnabled
                && showT === root.showTranslations) return
        var lookupChanged = network !== root.networkMode || netease !== root.neteaseEnabled
            || lrclib !== root.lrclibEnabled || kugou !== root.kugouEnabled
        root.networkMode = network
        root.neteaseEnabled = netease
        root.lrclibEnabled = lrclib
        root.kugouEnabled = kugou
        root.showTranslations = showT
        if (!lookupChanged) return
        root.clearSearchState()
        root.invalidateCurrentFetch()
    }

    function cancelFetchProcess() {
        if (lyricProcess.running) {
            lyricProcess.cancelled = true
            root.waitingForExit = true
            lyricProcess.running = false
        }
    }

    function cancelActionProcess() {
        if (actionProcess.running) {
            actionProcess.cancelled = true
            root.waitingForActionExit = true
            actionProcess.running = false
        }
    }

    function invalidateCurrentFetch() {
        var key = root.trackKey
        root.requestGeneration += 1
        root.generationTrackKey = key
        root.pendingRequest = root.makeRequest(key)
        root.cancelFetchProcess()
        root.cancelActionProcess()
        root.clearLyrics(key ? "loading" : "idle")
        if (!root.waitingForExit) root.startPending()
    }

    function makeRequest(key) {
        var player = root.activePlayer
        if (!player || !key) return null
        return {
            id: root.requestGeneration,
            key: key,
            title: root.textValue(player.trackTitle),
            artist: root.textValue(player.trackArtist),
            album: root.textValue(player.trackAlbum),
            duration: player.lengthSupported === true && root.finite(Number(player.length)) && Number(player.length) > 0
                ? Number(player.length) : null,
            url: root.playerUrl(),
            network: root.networkMode === "Offline" ? "off" : "auto",
            providers: root.enabledProviders(),
            refresh: false
        }
    }

    function settleTrack() {
        var key = root.trackKey
        if (key === root.generationTrackKey && key !== "") {
            root.performProjection(true)
            root.updateProjectionTimer()
            return
        }
        if (key !== root.generationTrackKey) {
            root.autoRetriedKey = ""
            autoRetryTimer.stop()
        }
        root.generationTrackKey = key
        root.requestGeneration += 1
        var request = root.makeRequest(key)
        root.pendingRequest = request
        root.cancelFetchProcess()
        root.cancelActionProcess()
        root.clearSearchState()
        root.selectedProvider = ""
        root.selectedSongId = ""
        root.selectedCacheMode = ""
        root.savedAlias = null
        root.clearLyrics(key ? "loading" : "idle")
        if (!root.waitingForExit) root.startPending()
    }

    function startPending() {
        var request = root.pendingRequest
        if (!request || root.waitingForExit || lyricProcess.running) return
        root.pendingRequest = null
        lyricProcess.runSerial += 1
        lyricProcess.completedRun = lyricProcess.runSerial - 1
        lyricProcess.timedOutRun = -1
        lyricProcess.outputReady = false
        lyricProcess.exitReady = false
        lyricProcess.exitCode = -1
        lyricProcess.exitStatus = ""
        lyricProcess.outputText = ""
        // Per-run stdout collection: the prior run is terminal here (no
        // running process, no pending exit wait), so retire its collector
        // first. The new collector carries the immutable originating serial;
        // a delayed old EOF has no live collector to complete through, and
        // even a misdelivered callback is rejected by acceptLyricOutput.
        if (lyricProcess.activeCollector) lyricProcess.activeCollector.destroy()
        lyricProcess.activeCollector = lyricCollectorFactory.createObject(lyricProcess,
            {expectedSerial: lyricProcess.runSerial})
        if (lyricProcess.activeCollector) lyricProcess.stdout = lyricProcess.activeCollector
        lyricProcess.streamSerial = -1
        lyricProcess.started = false
        lyricProcess.startedAtMs = 0
        lyricProcess.cancelled = false
        lyricProcess.timedOut = false
        lyricProcess.completed = false
        lyricProcess.runRequested = true
        lyricProcess.requestId = request.id
        lyricProcess.requestKey = request.key
        lyricProcess.command = [
            root.helperPath, "fetch", "--request-id", String(request.id),
            "--title", request.title, "--artist", request.artist,
            "--album", request.album,
            "--network", typeof request.network === "string" && request.network !== "" ? request.network : "auto",
            "--providers", typeof request.providers === "string" ? request.providers : "netease,lrclib,kugou"
        ]
        if (request.duration !== null && request.duration !== undefined)
            lyricProcess.command.push("--duration", String(request.duration))
        if (request.url !== null && request.url !== undefined && request.url !== "")
            lyricProcess.command.push("--url", String(request.url))
        if (request.refresh === true) lyricProcess.command.push("--refresh")
        lyricProcess.running = true
        resolverWatchdog.restart()
    }

    function retry() {
        var key = root.trackKey
        if (!key) {
            root.clearLyrics("idle")
            return
        }
        if (!root.retryAvailable) return
        root.requestGeneration += 1
        root.generationTrackKey = key
        root.pendingRequest = root.makeRequest(key)
        root.cancelFetchProcess()
        root.clearLyrics("loading")
        retryCooldownTimer.restart()
        if (!root.waitingForExit) root.startPending()
    }

    function refreshCurrent() {
        var key = root.trackKey
        if (!key) {
            root.clearLyrics("idle")
            return
        }
        if (!root.retryAvailable) return
        root.requestGeneration += 1
        root.generationTrackKey = key
        var request = root.makeRequest(key)
        if (request) request.refresh = true
        root.pendingRequest = request
        root.cancelFetchProcess()
        root.clearLyrics("loading")
        retryCooldownTimer.restart()
        if (!root.waitingForExit) root.startPending()
    }

    function maybeScheduleAutomaticRetry() {
        if (root.errorCode !== "providers_failed" && root.errorCode !== "resolver_timeout") return
        if (root.networkMode !== "Auto") return
        var player = root.activePlayer
        if (!player || player.isPlaying !== true) return
        var key = root.trackKey
        if (key === "" || key !== root.generationTrackKey) return
        if (root.autoRetriedKey === key) return
        autoRetryTimer.retryKey = key
        autoRetryTimer.retryGeneration = root.requestGeneration
        autoRetryTimer.restart()
    }

    function startAutomaticRetry(capturedKey, capturedGeneration) {
        if (capturedKey === "" || root.autoRetriedKey === capturedKey) return
        if (capturedKey !== root.trackKey || capturedKey !== root.generationTrackKey) return
        if (capturedGeneration !== root.requestGeneration) return
        if (root.networkMode !== "Auto") return
        var player = root.activePlayer
        if (!player || player.isPlaying !== true) return
        if (root.errorCode !== "providers_failed" && root.errorCode !== "resolver_timeout") return
        root.autoRetriedKey = capturedKey
        root.requestGeneration += 1
        root.generationTrackKey = capturedKey
        root.pendingRequest = root.makeRequest(capturedKey)
        root.cancelFetchProcess()
        root.clearLyrics("loading")
        if (!root.waitingForExit) root.startPending()
    }

    function exitStatusText(status) {
        return status === 0 ? "normal" : "crash"
    }

    function elapsedFor(process) {
        if (!process.startedAtMs) return 0
        return Math.max(0, Date.now() - process.startedAtMs)
    }

    function recordDiagnostic(kind, error, exitCode, exitStatus, elapsedMs, attempts) {
        var safeAttempts = root.validateAttempts(attempts) ? attempts : []
        root.lastDiagnostic = {
            kind: kind,
            error: root.validateErrorToken(error) ? String(error) : "",
            exitCode: typeof exitCode === "number" ? exitCode : -1,
            exitStatus: typeof exitStatus === "string" ? exitStatus : "",
            elapsedMs: typeof elapsedMs === "number" ? elapsedMs : 0,
            providerAttempts: safeAttempts,
            kotonohaVersion: typeof root.kotonohaVersion === "string" ? root.kotonohaVersion.slice(0, 64) : ""
        }
    }

    function finalizeLyricStartFailure() {
        if (lyricProcess.completed || lyricProcess.completedRun === lyricProcess.runSerial) return
        lyricProcess.completedRun = lyricProcess.runSerial
        lyricProcess.completed = true
        lyricProcess.runRequested = false
        var requestId = lyricProcess.requestId
        var requestKey = lyricProcess.requestKey
        var wasCancelled = lyricProcess.cancelled
        lyricProcess.cancelled = false
        lyricProcess.timedOutRun = -1
        root.waitingForExit = false
        resolverWatchdog.stop()
        if (wasCancelled) {
            if (root.pendingRequest) root.startPending()
            return
        }
        if (requestId !== root.requestGeneration || requestKey !== root.generationTrackKey
                || requestKey !== root.trackKey) {
            if (root.pendingRequest) root.startPending()
            return
        }
        root.recordDiagnostic("fetch", "helper_unavailable", -1, "", root.elapsedFor(lyricProcess), [])
        root.providerAttempts = []
        root.clearLyrics("provider_error")
        root.errorCode = "helper_unavailable"
        root.probeCapabilities(true)
        if (root.pendingRequest) root.startPending()
    }

    function finalizeActionStartFailure() {
        if (actionProcess.completed || actionProcess.completedAction === actionProcess.actionSerial) return
        actionProcess.completedAction = actionProcess.actionSerial
        actionProcess.completed = true
        actionProcess.runRequested = false
        var kind = actionProcess.commandKind
        var requestId = actionProcess.requestId
        var requestKey = actionProcess.requestKey
        var wasCancelled = actionProcess.cancelled
        actionProcess.cancelled = false
        actionProcess.timedOutAction = -1
        root.waitingForActionExit = false
        actionWatchdog.stop()
        if (wasCancelled) return
        // Capability probes are track-independent: a failed probe stays
        // retryable (freshness cleared, error set) even when the track
        // generation moved on. Only track-bound actions fence below.
        if (kind === "capabilities") {
            root.recordDiagnostic(kind || "action", "helper_unavailable", -1, "",
                root.elapsedFor(actionProcess), [])
            root.capabilitiesProbedAtMs = 0
            root.capabilities = null
            root.kotonohaVersion = ""
            root.capabilitiesError = "helper_unavailable"
            return
        }
        // Request/track fence: an old action whose failed-start lands after a
        // track change must not stamp the new track's state.
        if (requestId !== root.requestGeneration) return
        if (requestKey !== root.generationTrackKey || requestKey !== root.trackKey) return
        root.recordDiagnostic(kind || "action", "helper_unavailable", -1, "",
            root.elapsedFor(actionProcess), [])
        if (kind === "offset") {
            root.offsetError = "helper_unavailable"
            return
        }
        if (kind === "forget") {
            root.forgetError = "helper_unavailable"
            return
        }
        root.searchState = "provider_error"
        root.searchError = "helper_unavailable"
    }

    function checkLyricStartFailure(serial) {
        if (serial !== lyricProcess.runSerial) return
        if (lyricProcess.started || lyricProcess.exitReady || lyricProcess.completed) return
        if (!lyricProcess.runRequested || lyricProcess.running) return
        root.finalizeLyricStartFailure()
    }

    function checkActionStartFailure(serial) {
        if (serial !== actionProcess.actionSerial) return
        if (actionProcess.started || actionProcess.exitReady || actionProcess.completed) return
        if (!actionProcess.runRequested || actionProcess.running) return
        root.finalizeActionStartFailure()
    }

    function handleResolverTimeout() {
        if (!lyricProcess.running) return
        var expiredId = lyricProcess.requestId
        var expiredKey = lyricProcess.requestKey
        var expiredSerial = lyricProcess.runSerial
        lyricProcess.timedOutRun = expiredSerial
        lyricProcess.timedOut = true
        root.waitingForExit = true
        lyricProcess.running = false
        resolverWatchdog.stop()
        lyricKillTimer.killSerial = expiredSerial
        lyricKillTimer.restart()
        if (expiredId === root.requestGeneration && expiredKey === root.generationTrackKey
                && expiredKey === root.trackKey) {
            root.recordDiagnostic("fetch", "resolver_timeout", -1, "",
                root.elapsedFor(lyricProcess), [])
            root.clearLyrics("provider_error")
            root.errorCode = "resolver_timeout"
            root.maybeScheduleAutomaticRetry()
        }
    }

    function handleLyricKillTimeout() {
        if (lyricKillTimer.killSerial !== lyricProcess.runSerial) return
        if (lyricProcess.completed || lyricProcess.completedRun === lyricProcess.runSerial) return
        if (!lyricProcess.running) return
        try {
            lyricProcess.signal(9)
        } catch (error) {
        }
    }

    function handleActionKillTimeout() {
        if (actionKillTimer.killSerial !== actionProcess.actionSerial) return
        if (actionProcess.completed || actionProcess.completedAction === actionProcess.actionSerial) return
        if (!actionProcess.running) return
        try {
            actionProcess.signal(9)
        } catch (error) {
        }
    }

    function clearSearchState() {
        root.searchState = "idle"
        root.searchResults = []
        root.searchError = ""
        root.searchQuery = null
    }

    function noteQueryEdited() {
        if (root.searchState === "ready" || root.searchState === "provider_error"
                || root.searchState === "not_found") {
            root.searchState = "idle"
            root.searchResults = []
            root.searchError = ""
        }
    }

    function providerIds() {
        return ["netease", "lrclib", "kugou"]
    }

    function searchAvailable(provider) {
        var revision = root.searchCooldownRevision
        if (root.networkMode === "Offline") return false
        if (root.providerIds().indexOf(provider) < 0) return false
        if (root.enabledProviders().split(",").indexOf(provider) < 0) return false
        var last = root.searchCooldowns[provider] || 0
        if (Date.now() - last < root.searchCooldownMs) return false
        if (actionProcess.running || root.waitingForActionExit) return false
        return true
    }

    function scheduleSearchCooldownWake() {
        var now = Date.now()
        var wait = 0
        for (var key in root.searchCooldowns) {
            var elapsed = now - (root.searchCooldowns[key] || 0)
            var remaining = root.searchCooldownMs - elapsed
            if (remaining > 0 && (wait === 0 || remaining < wait)) wait = remaining
        }
        if (wait > 0) {
            searchCooldownTimer.interval = Math.min(Math.max(wait, 50), root.searchCooldownMs)
            searchCooldownTimer.restart()
        } else searchCooldownTimer.stop()
    }

    function actionTrackArgs() {
        var player = root.activePlayer
        if (!player || !root.trackKey) return null
        var args = ["--title", root.textValue(player.trackTitle),
            "--artist", root.textValue(player.trackArtist),
            "--album", root.textValue(player.trackAlbum)]
        if (player.lengthSupported === true && root.finite(Number(player.length)) && Number(player.length) > 0)
            args.push("--duration", String(Number(player.length)))
        return args
    }

    function queryArgs(queryTitle, queryArtist, queryAlbum) {
        var args = []
        // Preserve supplied empty strings (including --query-title "") so
        // the helper rejects an empty normalized title. Omitted/undefined
        // stays omitted; only a supplied string is forwarded.
        if (typeof queryTitle === "string")
            args.push("--query-title", queryTitle)
        if (typeof queryArtist === "string")
            args.push("--query-artist", queryArtist)
        if (typeof queryAlbum === "string")
            args.push("--query-album", queryAlbum)
        return args
    }

    function dispatchAction(kind, args) {
        if (actionProcess.running || root.waitingForActionExit) return false
        actionProcess.actionSerial += 1
        actionProcess.completedAction = actionProcess.actionSerial - 1
        actionProcess.timedOutAction = -1
        actionProcess.outputReady = false
        actionProcess.exitReady = false
        actionProcess.exitCode = -1
        actionProcess.exitStatus = ""
        actionProcess.outputText = ""
        // Per-run stdout collection, fenced exactly like the lyric channel:
        // retire the terminal run's collector, then stamp the new collector
        // with the immutable originating serial before running = true.
        if (actionProcess.activeCollector) actionProcess.activeCollector.destroy()
        actionProcess.activeCollector = actionCollectorFactory.createObject(actionProcess,
            {expectedSerial: actionProcess.actionSerial})
        if (actionProcess.activeCollector) actionProcess.stdout = actionProcess.activeCollector
        actionProcess.streamSerial = -1
        actionProcess.started = false
        actionProcess.startedAtMs = 0
        actionProcess.cancelled = false
        actionProcess.timedOut = false
        actionProcess.completed = false
        actionProcess.runRequested = true
        actionProcess.commandKind = kind
        actionProcess.requestId = root.requestGeneration
        actionProcess.requestKey = root.generationTrackKey
        actionProcess.command = [root.helperPath, kind, "--request-id", String(root.requestGeneration)].concat(args)
        actionProcess.running = true
        actionWatchdog.restart()
        return true
    }

    function capabilitiesFresh() {
        return root.capabilitiesProbedAtMs > 0
            && (Date.now() - root.capabilitiesProbedAtMs) < root.capabilitiesFreshMs
            && root.capabilities !== null
    }

    function probeCapabilities(force) {
        if (!force && root.capabilitiesFresh()) return
        if (actionProcess.running || root.waitingForActionExit) return
        root.dispatchAction("capabilities", [])
    }

    function validateErrorToken(value) {
        // Wire contract is a string: "" or a bounded [a-z0-9_]+ machine
        // token. Non-string scalars (true, 123, null) never validate, even
        // when their string form would match.
        if (typeof value !== "string") return false
        if (value === "") return true
        if (value.length > 64) return false
        return /^[a-z0-9_]+$/.test(value)
    }

    function validateAttempts(value) {
        if (value === undefined || value === null) return true
        if (!Array.isArray(value) || value.length > 3) return false
        var providers = root.providerIds()
        var outcomes = ["candidate", "not_found", "timeout", "error", "rejected"]
        for (var i = 0; i < value.length; i++) {
            var row = value[i]
            if (!row || typeof row !== "object") return false
            var keys = Object.keys(row)
            if (keys.length !== 2) return false
            if (providers.indexOf(row.provider) < 0) return false
            if (outcomes.indexOf(row.outcome) < 0) return false
        }
        return true
    }

    function validateSavedAlias(value) {
        if (value === undefined || value === null) return true
        if (!value || typeof value !== "object") return false
        var keys = ["queryTitle", "queryArtist", "queryAlbum", "provider", "songId",
            "matchedTitle", "matchedArtist", "matchedAlbum"]
        if (Object.keys(value).length !== keys.length) return false
        for (var i = 0; i < keys.length; i++) {
            var field = value[keys[i]]
            if (typeof field !== "string" || root.codePointLength(field) > 256) return false
        }
        if (root.providerIds().indexOf(value.provider) < 0) return false
        if (value.songId === "") return false
        return true
    }

    // Validated saved-alias object or null. Absent/undefined aliases stay
    // null so consumers never observe undefined.
    function savedAliasOrNull(value) {
        if (value === undefined || value === null) return null
        return root.validateSavedAlias(value) ? value : null
    }

    function validateCapabilities(payload) {
        if (!payload || typeof payload !== "object") return false
        if (payload.schemaVersion !== 1) return false
        if (payload.status !== "ready") return false
        if (!root.validateErrorToken(payload.error === undefined ? "" : payload.error)) return false
        if (typeof payload.kotonohaVersion !== "string") return false
        var caps = payload.capabilities
        if (!caps || typeof caps !== "object") return false
        if (typeof caps.local !== "boolean" || typeof caps.offset !== "boolean") return false
        if (typeof caps.matchEvidence !== "boolean") return false
        if (!Array.isArray(caps.search)) return false
        for (var i = 0; i < caps.search.length; i++) {
            if (typeof caps.search[i] !== "string"
                    || ["netease", "lrclib", "kugou"].indexOf(caps.search[i]) < 0) return false
        }
        return true
    }

    function validateSearch(payload, expectedId) {
        if (!payload || typeof payload !== "object") return false
        if (payload.schemaVersion !== 1 || payload.requestId !== expectedId) return false
        if (!root.validateErrorToken(payload.error === undefined ? "" : payload.error)) return false
        var statuses = ["ready", "not_found", "dependency_error", "provider_error"]
        if (statuses.indexOf(payload.status) < 0) return false
        if (typeof payload.query !== "object" || !payload.query) return false
        if (typeof payload.query.title !== "string" || typeof payload.query.artist !== "string") return false
        if (root.codePointLength(payload.query.title) > 256) return false
        if (root.codePointLength(payload.query.artist) > 256) return false
        if (payload.query.album !== undefined && typeof payload.query.album !== "string") return false
        if (payload.query.album !== undefined && root.codePointLength(payload.query.album) > 256) return false
        if (payload.status !== "ready") return true
        if (!Array.isArray(payload.results)) return false
        for (var i = 0; i < payload.results.length; i++) {
            var row = payload.results[i]
            if (!row || typeof row !== "object") return false
            if (typeof row.provider !== "string" || root.providerIds().indexOf(row.provider) < 0) return false
            if (typeof row.songId !== "string" || row.songId === "") return false
            if (root.codePointLength(row.songId) > 256) return false
            if (typeof row.title !== "string" || typeof row.artist !== "string") return false
            if (root.codePointLength(row.title) > 256) return false
            if (root.codePointLength(row.artist) > 256) return false
            if (row.album !== undefined && typeof row.album !== "string") return false
            if (row.album !== undefined && root.codePointLength(row.album) > 256) return false
            if (row.duration !== undefined && row.duration !== null
                    && (!root.finite(Number(row.duration)) || Number(row.duration) <= 0)) return false
            if (["high", "medium", "low"].indexOf(row.confidence) < 0) return false
            if (["word", "line", "none"].indexOf(row.timing) < 0) return false
            if (typeof row.hasTranslation !== "boolean") return false
            if ("lines" in row || "lyrics" in row || "payload" in row || "words" in row) return false
        }
        return true
    }

    function validateForget(payload, expectedId) {
        if (!payload || typeof payload !== "object") return false
        if (payload.schemaVersion !== 1 || payload.requestId !== expectedId) return false
        if (!root.validateErrorToken(payload.error === undefined ? "" : payload.error)) return false
        var statuses = ["ready", "not_found", "dependency_error", "provider_error"]
        if (statuses.indexOf(payload.status) < 0) return false
        if (payload.status !== "ready") return true
        if (!(payload.deleteStatus === "deleted" || payload.deleteStatus === "not-found")) return false
        return payload.aliasDeleteStatus === "deleted" || payload.aliasDeleteStatus === "not-found"
    }

    function search(provider, queryTitle, queryArtist, queryAlbum) {
        if (root.networkMode === "Offline") return
        if (!root.searchAvailable(provider)) return
        var trackArgs = root.actionTrackArgs()
        if (trackArgs === null) return
        if (actionProcess.running || root.waitingForActionExit) return
        root.searchCooldowns[provider] = Date.now()
        root.searchCooldownRevision += 1
        root.scheduleSearchCooldownWake()
        root.searchState = "loading"
        root.dispatchAction("search", ["--provider", provider, "--limit", "10"].concat(trackArgs)
            .concat(root.queryArgs(queryTitle, queryArtist, queryAlbum)))
    }

    function selectResult(provider, songId, queryTitle, queryArtist, queryAlbum) {
        if (root.networkMode === "Offline") return
        if (root.providerIds().indexOf(provider) < 0) return
        if (typeof songId !== "string" || songId === "") return
        if (actionProcess.running || root.waitingForActionExit) return
        var trackArgs = root.actionTrackArgs()
        if (trackArgs === null) return
        root.searchState = "loading"
        root.dispatchAction("select",
            ["--provider", provider, "--song-id", songId].concat(trackArgs)
                .concat(root.queryArgs(queryTitle, queryArtist, queryAlbum)))
    }

    function forgetCurrentMatch() {
        if (!root.selectedProvider || !root.selectedSongId) return
        if (actionProcess.running || root.waitingForActionExit) return
        var trackArgs = root.actionTrackArgs()
        if (trackArgs === null) return
        var provider = root.selectedProvider
        var songId = root.selectedSongId
        root.forgetError = ""
        root.dispatchAction("forget",
            ["--provider", provider, "--song-id", songId].concat(trackArgs))
    }

    function clearForgetError() {
        root.forgetError = ""
    }

    function writeOffset(deltaMs, setMs) {
        if (!root.offsetKey) {
            root.offsetError = "offset_unavailable"
            return
        }
        if (actionProcess.running || root.waitingForActionExit) return
        var args = ["--key-json", JSON.stringify(root.offsetKey)]
        if (setMs !== undefined && setMs !== null) args.push("--set-ms", String(setMs))
        else args.push("--delta-ms", String(deltaMs))
        root.offsetError = ""
        root.offsetRetry = {deltaMs: deltaMs, setMs: (setMs !== undefined && setMs !== null) ? setMs : null}
        root.dispatchAction("offset", args)
    }

    function nudgeOffset(deltaMs) {
        if (typeof deltaMs !== "number" || !root.finite(deltaMs)) return
        root.writeOffset(Math.trunc(deltaMs), null)
    }

    function resetOffset() {
        root.writeOffset(null, 0)
    }

    function retryOffset() {
        if (!root.offsetRetry || typeof root.offsetRetry !== "object") return
        if (root.offsetRetry.setMs !== undefined && root.offsetRetry.setMs !== null)
            root.writeOffset(null, root.offsetRetry.setMs)
        else if (typeof root.offsetRetry.deltaMs === "number")
            root.writeOffset(root.offsetRetry.deltaMs, null)
    }

    function seekToLine(index) {
        if (root.state !== "ready") return false
        if (typeof index !== "number" || Math.floor(index) !== index) return false
        if (!Array.isArray(root.lines) || index < 0 || index >= root.lines.length) return false
        var line = root.lines[index]
        if (!line || !root.finite(Number(line.start)) || Number(line.start) < 0) return false
        var player = root.activePlayer
        if (!player || player.canSeek !== true || player.positionSupported !== true) return false
        try {
            player.position = Number(line.start)
        } catch (error) {
            return false
        }
        root.performProjection(true)
        return true
    }

    function applySelectDocument(parsed) {
        root.document = parsed
        root.provider = parsed.provider
        root.timing = parsed.timing
        root.errorCode = ""
        root.state = "ready"
        root.selectedProvider = parsed.provider
        root.selectedSongId = typeof parsed.providerSongId === "string" ? parsed.providerSongId : ""
        root.selectedCacheMode = typeof parsed.cacheMode === "string" ? parsed.cacheMode : "manual"
        root.savedAlias = root.savedAliasOrNull(parsed.savedAlias)
        root.providerAttempts = root.validateAttempts(parsed.providerAttempts) ? parsed.providerAttempts : []
        root.syncOffsetFromDocument(parsed)
        root.clearSearchState()
        root.requestGeneration += 1
        root.performProjection(true)
        root.updateProjectionTimer()
    }

    function syncOffsetFromDocument(parsed) {
        if (parsed && typeof parsed.offsetMs === "number"
                && Math.floor(parsed.offsetMs) === parsed.offsetMs) root.offsetMs = parsed.offsetMs
        else root.offsetMs = 0
        if (parsed && parsed.offsetKey !== undefined && parsed.offsetKey !== null) root.offsetKey = parsed.offsetKey
        else root.offsetKey = null
        root.offsetError = ""
        root.offsetRetry = null
    }

    function mergeDocumentWarnings(extra) {
        if (!Array.isArray(extra) || extra.length === 0) return
        if (!root.document || typeof root.document !== "object") return
        var current = Array.isArray(root.document.warnings) ? root.document.warnings.slice(0) : []
        var changed = false
        for (var i = 0; i < extra.length; i++) {
            if (typeof extra[i] !== "string") continue
            if (current.indexOf(extra[i]) < 0 && current.length < 16) {
                current.push(extra[i])
                changed = true
            }
        }
        if (!changed) return
        var next = {}
        for (var key in root.document) next[key] = root.document[key]
        next.warnings = current
        root.document = next
    }

    function completeAction(output, exitCode, exitStatus, kind, requestId, requestKey) {
        var wasTimeout = actionProcess.timedOutAction === actionProcess.actionSerial || actionProcess.timedOut
        var wasCancelled = actionProcess.cancelled || root.waitingForActionExit
        actionProcess.timedOutAction = -1
        actionProcess.timedOut = false
        actionProcess.cancelled = false
        root.waitingForActionExit = false
        actionWatchdog.stop()
        if (wasTimeout || wasCancelled) {
            if (wasTimeout) {
                // Preserve the timeout cause while recording the eventual
                // numeric exit: the watchdog already published
                // resolver_timeout/capabilities_unavailable with exit -1, so
                // refresh the diagnostic with the observed exit without
                // overwriting the cause.
                var keepError = root.lastDiagnostic && typeof root.lastDiagnostic.error === "string"
                    && root.lastDiagnostic.error !== "" ? root.lastDiagnostic.error
                    : (kind === "capabilities" ? "capabilities_unavailable" : "resolver_timeout")
                var keepAttempts = root.lastDiagnostic && Array.isArray(root.lastDiagnostic.providerAttempts)
                    ? root.lastDiagnostic.providerAttempts : []
                root.recordDiagnostic(kind || "action", keepError, exitCode, exitStatus,
                    root.elapsedFor(actionProcess), keepAttempts)
            }
            if (kind === "capabilities") {
                root.capabilitiesProbedAtMs = 0
                if (wasTimeout) {
                    root.capabilities = null
                    root.kotonohaVersion = ""
                    root.capabilitiesError = "capabilities_unavailable"
                } else if (!root.capabilities) {
                    root.capabilitiesError = "capabilities_unavailable"
                }
            }
            return
        }
        // Capability results are track-independent: a late probe must still land.
        if (kind !== "capabilities"
                && (requestId !== root.requestGeneration || requestKey !== root.generationTrackKey
                    || requestKey !== root.trackKey)) return
        var parsed = null
        var text = String(output || "").trim()
        try {
            parsed = JSON.parse(text)
        } catch (error) {
            parsed = null
        }
        var nonzero = (typeof exitCode === "number" && exitCode !== 0) || exitStatus === "crash"
        if (kind === "capabilities") {
            if (parsed !== null && parsed.requestId === requestId && root.validateCapabilities(parsed)) {
                root.capabilities = parsed.capabilities
                root.kotonohaVersion = typeof parsed.kotonohaVersion === "string"
                    ? parsed.kotonohaVersion.slice(0, 64) : ""
                root.capabilitiesError = ""
                root.capabilitiesProbedAtMs = Date.now()
                root.recordDiagnostic(kind, "", exitCode, exitStatus,
                    root.elapsedFor(actionProcess), [])
            } else if (parsed === null && nonzero) {
                root.capabilitiesProbedAtMs = 0
                root.capabilities = null
                root.kotonohaVersion = ""
                root.capabilitiesError = "helper_unavailable"
                root.recordDiagnostic(kind, "helper_unavailable", exitCode, exitStatus,
                    root.elapsedFor(actionProcess), [])
            } else {
                root.capabilitiesProbedAtMs = 0
                root.capabilities = null
                root.kotonohaVersion = ""
                root.capabilitiesError = "capabilities_unavailable"
                root.recordDiagnostic(kind, "capabilities_unavailable", exitCode, exitStatus,
                    root.elapsedFor(actionProcess), [])
            }
            return
        }
        if (kind === "search") {
            if (parsed === null || !root.validateSearch(parsed, requestId)) {
                var searchFailed = parsed !== null && root.validateErrorToken(parsed.error) && parsed.error !== ""
                    ? parsed.error : "invalid_response"
                if (parsed === null && nonzero) searchFailed = "helper_unavailable"
                root.searchState = "provider_error"
                root.searchError = searchFailed
                root.recordDiagnostic(kind, searchFailed, exitCode, exitStatus,
                    root.elapsedFor(actionProcess), [])
                return
            }
            root.searchQuery = parsed.query
            root.recordDiagnostic(kind, parsed.error || "", exitCode, exitStatus,
                root.elapsedFor(actionProcess), [])
            if (parsed.status === "ready") {
                root.searchResults = parsed.results
                root.searchError = ""
                root.searchState = "ready"
            } else {
                root.searchState = parsed.status === "not_found" ? "not_found" : "provider_error"
                root.searchError = parsed.error || parsed.status
            }
            return
        }
        if (kind === "select") {
            if (parsed === null || !root.validateResponse(parsed, requestId) || parsed.status !== "ready"
                    || typeof parsed.providerSongId !== "string" || parsed.providerSongId === "") {
                var selectFailed = parsed !== null && root.validateErrorToken(parsed.error) && parsed.error !== ""
                    ? parsed.error : "invalid_response"
                if (parsed === null && nonzero) selectFailed = "helper_unavailable"
                root.searchState = "provider_error"
                root.searchError = selectFailed
                root.recordDiagnostic(kind, selectFailed, exitCode, exitStatus,
                    root.elapsedFor(actionProcess), [])
                return
            }
            root.recordDiagnostic(kind, "", exitCode, exitStatus,
                root.elapsedFor(actionProcess), parsed.providerAttempts)
            root.applySelectDocument(parsed)
            return
        }
        if (kind === "forget") {
            if (parsed === null || !root.validateForget(parsed, requestId) || parsed.status !== "ready") {
                var forgetFailed = parsed !== null && root.validateErrorToken(parsed.error) && parsed.error !== ""
                    ? parsed.error : "invalid_response"
                if (parsed === null && nonzero) forgetFailed = "helper_unavailable"
                // Failed removal keeps the working document, selection, and
                // search state; the bounded token surfaces in the ready panel.
                root.forgetError = forgetFailed
                root.recordDiagnostic(kind, forgetFailed, exitCode, exitStatus,
                    root.elapsedFor(actionProcess), [])
                return
            }
            root.recordDiagnostic(kind, "", exitCode, exitStatus,
                root.elapsedFor(actionProcess), [])
            root.selectedProvider = ""
            root.selectedSongId = ""
            root.selectedCacheMode = ""
            root.savedAlias = null
            root.clearSearchState()
            root.invalidateCurrentFetch()
            return
        }
        if (kind === "offset") {
            if (parsed === null || !root.validateOffset(parsed, requestId) || parsed.status !== "ready") {
                var offsetFailed = parsed !== null && root.validateErrorToken(parsed.error) && parsed.error !== ""
                    ? parsed.error : "invalid_response"
                if (parsed === null && nonzero) offsetFailed = "helper_unavailable"
                root.offsetError = offsetFailed
                root.recordDiagnostic(kind, offsetFailed, exitCode, exitStatus,
                    root.elapsedFor(actionProcess), [])
                return
            }
            if (JSON.stringify(parsed.offsetKey) !== JSON.stringify(root.offsetKey)) return
            root.offsetMs = parsed.offsetMs
            root.offsetKey = parsed.offsetKey
            root.offsetError = ""
            root.offsetSuccessSerial += 1
            root.mergeDocumentWarnings(parsed.warnings)
            root.recordDiagnostic(kind, "", exitCode, exitStatus,
                root.elapsedFor(actionProcess), [])
            root.performProjection(true)
            root.updateProjectionTimer()
            return
        }
    }

    function finalizeActionOutput() {
        if (actionProcess.completed || actionProcess.completedAction === actionProcess.actionSerial) return
        actionProcess.completedAction = actionProcess.actionSerial
        actionProcess.completed = true
        actionProcess.runRequested = false
        root.completeAction(actionProcess.outputText, actionProcess.exitCode, actionProcess.exitStatus,
            actionProcess.commandKind, actionProcess.requestId, actionProcess.requestKey)
    }

    function maybeCompleteAction() {
        if (!actionProcess.outputReady || !actionProcess.exitReady) return
        root.finalizeActionOutput()
    }
    // Origin-aware stdout publication for the action channel, fenced exactly
    // like the lyric channel.
    function acceptActionOutput(originSerial, collector, text) {
        if (!collector || typeof originSerial !== "number") return false
        if (originSerial !== actionProcess.actionSerial) return false
        if (actionProcess.stdout !== collector) return false
        if (actionProcess.completed || actionProcess.completedAction === originSerial) return false
        actionProcess.outputText = String(text || "")
        actionProcess.outputSerial = originSerial
        actionProcess.outputReady = true
        if (actionProcess.exitReady) root.maybeCompleteAction()
        return true
    }


    function handleActionTimeout() {
        if (!actionProcess.running) return
        var expiredId = actionProcess.requestId
        var expiredKey = actionProcess.requestKey
        var expiredSerial = actionProcess.actionSerial
        var expiredKind = actionProcess.commandKind
        actionProcess.timedOutAction = expiredSerial
        actionProcess.timedOut = true
        root.waitingForActionExit = true
        actionProcess.running = false
        actionWatchdog.stop()
        actionKillTimer.killSerial = expiredSerial
        actionKillTimer.restart()
        if (expiredKind === "capabilities") {
            root.capabilitiesProbedAtMs = 0
            root.capabilities = null
            root.kotonohaVersion = ""
            root.capabilitiesError = "capabilities_unavailable"
            root.recordDiagnostic("capabilities", "capabilities_unavailable", -1, "",
                root.elapsedFor(actionProcess), [])
            return
        }
        if (expiredId === root.requestGeneration && expiredKey === root.generationTrackKey
                && expiredKey === root.trackKey) {
            if (expiredKind === "offset") {
                root.offsetError = "resolver_timeout"
                root.recordDiagnostic("offset", "resolver_timeout", -1, "",
                    root.elapsedFor(actionProcess), [])
            } else if (expiredKind === "forget") {
                root.forgetError = "resolver_timeout"
                root.recordDiagnostic("forget", "resolver_timeout", -1, "",
                    root.elapsedFor(actionProcess), [])
            } else {
                root.searchState = "provider_error"
                root.searchError = "resolver_timeout"
                root.recordDiagnostic(expiredKind || "action", "resolver_timeout", -1, "",
                    root.elapsedFor(actionProcess), [])
            }
        }
    }

    function capabilityExplanation(feature) {
        if (!root.capabilities) return root.capabilitiesError || "capabilities_unavailable"
        if (feature === "local" && root.capabilities.local !== true) return "local_unavailable"
        if (feature === "offset" && root.capabilities.offset !== true) return "offset_unavailable"
        if (feature === "search"
                && (!Array.isArray(root.capabilities.search) || root.capabilities.search.length === 0))
            return "search_unavailable"
        return ""
    }

    function validateResponse(response, expectedId) {
        if (!response || typeof response !== "object") return false
        if (response.schemaVersion !== 1 || response.requestId !== expectedId) return false
        if (!root.validateErrorToken(response.error === undefined ? "" : response.error)) return false
        if (!root.validateAttempts(response.providerAttempts)) return false
        if (!root.validateSavedAlias(response.savedAlias)) return false
        var statuses = ["ready", "not_found", "dependency_error", "provider_error"]
        if (statuses.indexOf(response.status) < 0) return false
        if (response.warnings !== undefined) {
            if (!Array.isArray(response.warnings) || response.warnings.length > 16) return false
            for (var w = 0; w < response.warnings.length; w++) {
                if (typeof response.warnings[w] !== "string" || response.warnings[w].length > 128) return false
            }
        }
        if (response.status !== "ready") return true
        if (typeof response.provider !== "string" || response.provider === "") return false
        if (["word", "line"].indexOf(response.timing) < 0 || !Array.isArray(response.lines)) return false
        var previousStart = -Infinity
        var hasWords = false
        for (var i = 0; i < response.lines.length; i++) {
            var line = response.lines[i]
            if (!line || !root.finite(line.start) || !root.finite(line.end)
                    || line.start < 0 || line.end < line.start || line.start < previousStart
                    || typeof line.text !== "string" || typeof line.translation !== "string") return false
            previousStart = line.start
            if (!Array.isArray(line.words)) return false
            var previousWordStart = -Infinity
            var sawTimedWord = false
            var wordText = ""
            for (var j = 0; j < line.words.length; j++) {
                var word = line.words[j]
                if (!word || typeof word.text !== "string") return false
                var untimed = word.start === null && word.end === null
                if (untimed) {
                    if (sawTimedWord) return false
                    wordText += word.text
                    continue
                }
                if (!root.finite(word.start) || !root.finite(word.end)
                        || word.start < line.start || word.end < word.start
                        || word.end > line.end || word.start < previousWordStart) return false
                previousWordStart = word.start
                sawTimedWord = true
                hasWords = true
                wordText += word.text
            }
            if (sawTimedWord && wordText !== line.text) return false
        }
        if (response.lines.length === 0) return false
        if (response.timing !== (hasWords ? "word" : "line")) return false
        if (response.providerSongId !== undefined && response.providerSongId !== null
                && typeof response.providerSongId !== "string") return false
        if (typeof response.providerSongId === "string"
                && root.codePointLength(response.providerSongId) > 256) return false
        if (response.sourceKind !== undefined
                && ["local", "cache", "network"].indexOf(response.sourceKind) < 0) return false
        if (response.cacheMode !== undefined
                && ["manual", "auto", "none"].indexOf(response.cacheMode) < 0) return false
        if (response.searchTitle !== undefined && typeof response.searchTitle !== "string") return false
        if (response.searchTitle !== undefined && root.codePointLength(response.searchTitle) > 256) return false
        if (response.searchArtist !== undefined && typeof response.searchArtist !== "string") return false
        if (response.searchArtist !== undefined && root.codePointLength(response.searchArtist) > 256) return false
        if (response.searchAlbum !== undefined && typeof response.searchAlbum !== "string") return false
        if (response.searchAlbum !== undefined && root.codePointLength(response.searchAlbum) > 256) return false
        if (response.hasTranslation !== undefined && typeof response.hasTranslation !== "boolean") return false
        if (response.offsetMs !== undefined) {
            if (typeof response.offsetMs !== "number" || Math.floor(response.offsetMs) !== response.offsetMs
                    || response.offsetMs < -10000 || response.offsetMs > 10000) return false
        }
        if (response.offsetKey !== undefined && response.offsetKey !== null
                && !root.validateOffsetKey(response.offsetKey)) return false
        return true
    }

    function validateOffsetKey(key) {
        if (!key || typeof key !== "object") return false
        if (typeof key.trackTitle !== "string" || typeof key.trackArtist !== "string"
                || typeof key.trackAlbum !== "string") return false
        if (key.trackDurationS !== undefined && key.trackDurationS !== null
                && (!root.finite(Number(key.trackDurationS)))) return false
        if (typeof key.lyricsSourceId !== "string" || typeof key.lyricsDigest !== "string") return false
        if (key.lyricsSongId !== undefined && key.lyricsSongId !== null
                && typeof key.lyricsSongId !== "string") return false
        return true
    }

    function validateOffset(payload, expectedId) {
        if (!payload || typeof payload !== "object") return false
        if (payload.schemaVersion !== 1 || payload.requestId !== expectedId) return false
        if (!root.validateErrorToken(payload.error === undefined ? "" : payload.error)) return false
        var statuses = ["ready", "provider_error", "dependency_error"]
        if (statuses.indexOf(payload.status) < 0) return false
        if (payload.warnings !== undefined) {
            if (!Array.isArray(payload.warnings) || payload.warnings.length > 16) return false
            for (var i = 0; i < payload.warnings.length; i++) {
                if (typeof payload.warnings[i] !== "string" || payload.warnings[i].length > 128) return false
            }
        }
        if (payload.status !== "ready") return true
        if (typeof payload.offsetMs !== "number" || Math.floor(payload.offsetMs) !== payload.offsetMs
                || payload.offsetMs < -10000 || payload.offsetMs > 10000) return false
        if (payload.offsetKey === undefined || payload.offsetKey === null) return false
        return root.validateOffsetKey(payload.offsetKey)
    }

    function applyResponse(raw, requestId, requestKey, exitCode, exitStatus) {
        if (requestId !== root.requestGeneration || requestKey !== root.generationTrackKey
                || requestKey !== root.trackKey) return
        var parsed = null
        try {
            parsed = JSON.parse(String(raw || "").trim())
        } catch (error) {
            parsed = null
        }
        var nonzero = (typeof exitCode === "number" && exitCode !== 0) || exitStatus === "crash"
        if (parsed === null || !root.validateResponse(parsed, requestId)) {
            var failure = "invalid_response"
            if (parsed === null && nonzero) failure = "helper_unavailable"
            else if (parsed !== null && root.validateErrorToken(parsed.error) && parsed.error !== ""
                && parsed.status !== "ready") failure = parsed.error
            var failedAttempts = parsed !== null && root.validateAttempts(parsed.providerAttempts)
                ? parsed.providerAttempts : []
            var failedAlias = parsed !== null ? root.savedAliasOrNull(parsed.savedAlias) : null
            root.recordDiagnostic("fetch", failure, exitCode, exitStatus,
                root.elapsedFor(lyricProcess), failedAttempts)
            root.clearLyrics("provider_error")
            root.errorCode = failure
            root.providerAttempts = root.validateAttempts(failedAttempts) ? failedAttempts : []
            root.savedAlias = failedAlias
            if (failedAlias !== null && typeof failedAlias === "object") {
                root.selectedProvider = typeof failedAlias.provider === "string" ? failedAlias.provider : ""
                root.selectedSongId = typeof failedAlias.songId === "string" ? failedAlias.songId : ""
                root.selectedCacheMode = "manual"
            }
            if (failure === "helper_unavailable" || failure === "kotonoha_unavailable")
                root.probeCapabilities(true)
            else root.maybeScheduleAutomaticRetry()
            return
        }
        if (parsed.status === "ready") {
            root.recordDiagnostic("fetch", "", exitCode, exitStatus,
                root.elapsedFor(lyricProcess), parsed.providerAttempts)
            root.document = parsed
            root.provider = parsed.provider
            root.timing = parsed.timing
            root.errorCode = ""
            root.state = "ready"
            root.providerAttempts = root.validateAttempts(parsed.providerAttempts)
                ? parsed.providerAttempts : []
            // Durable correction state: a fresh manual-alias fetch restores the
            // saved query/match identity for consumers and the panel.
            root.savedAlias = root.savedAliasOrNull(parsed.savedAlias)
            if (parsed.cacheMode === "manual" && typeof parsed.providerSongId === "string"
                    && parsed.providerSongId !== "") {
                root.selectedProvider = parsed.provider
                root.selectedSongId = parsed.providerSongId
                root.selectedCacheMode = "manual"
            } else if (parsed.cacheMode === "auto" && typeof parsed.providerSongId === "string"
                    && parsed.providerSongId !== "") {
                root.selectedProvider = parsed.provider
                root.selectedSongId = parsed.providerSongId
                root.selectedCacheMode = "auto"
            } else {
                root.selectedProvider = ""
                root.selectedSongId = ""
                root.selectedCacheMode = ""
            }
            root.syncOffsetFromDocument(parsed)
            root.performProjection(true)
            root.updateProjectionTimer()
        } else {
            root.recordDiagnostic("fetch", parsed.error || parsed.status, exitCode, exitStatus,
                root.elapsedFor(lyricProcess), parsed.providerAttempts)
            var validAttempts = root.validateAttempts(parsed.providerAttempts)
                ? parsed.providerAttempts : []
            var validAlias = root.savedAliasOrNull(parsed.savedAlias)
            root.clearLyrics(parsed.status)
            root.errorCode = parsed.error || parsed.status
            root.providerAttempts = validAttempts
            root.savedAlias = validAlias
            if (validAlias !== null && typeof validAlias === "object") {
                root.selectedProvider = typeof validAlias.provider === "string" ? validAlias.provider : ""
                root.selectedSongId = typeof validAlias.songId === "string" ? validAlias.songId : ""
                root.selectedCacheMode = "manual"
            }
            if (root.errorCode === "kotonoha_unavailable" || root.errorCode === "helper_unavailable")
                root.probeCapabilities(true)
            else root.maybeScheduleAutomaticRetry()
        }
    }

    function completeProcess(output, exitCode, exitStatus, requestId, requestKey) {
        var wasTimeout = lyricProcess.timedOutRun === lyricProcess.runSerial || lyricProcess.timedOut
        var wasCancelled = lyricProcess.cancelled || root.waitingForExit
        lyricProcess.timedOutRun = -1
        lyricProcess.timedOut = false
        lyricProcess.cancelled = false
        root.waitingForExit = false
        resolverWatchdog.stop()
        if (!wasTimeout && !wasCancelled) root.applyResponse(output, requestId, requestKey, exitCode, exitStatus)
        else if (wasTimeout) root.recordDiagnostic("fetch", "resolver_timeout", exitCode, exitStatus,
            root.elapsedFor(lyricProcess), [])
        else if (wasCancelled) root.recordDiagnostic("fetch", "cancelled", exitCode, exitStatus,
            root.elapsedFor(lyricProcess), [])
        if (root.pendingRequest) root.startPending()
    }

    function finalizeLyricOutput() {
        if (lyricProcess.completed || lyricProcess.completedRun === lyricProcess.runSerial) return
        lyricProcess.completedRun = lyricProcess.runSerial
        lyricProcess.completed = true
        lyricProcess.runRequested = false
        root.completeProcess(lyricProcess.outputText, lyricProcess.exitCode, lyricProcess.exitStatus,
            lyricProcess.requestId, lyricProcess.requestKey)
    }

    function maybeCompleteProcess() {
        if (!lyricProcess.outputReady || !lyricProcess.exitReady) return
        root.finalizeLyricOutput()
    }
    // Origin-aware stdout publication for the lyric channel. Collectors pass
    // the immutable serial stamped at their creation; the callback never
    // reads the current serial, so a delayed EOF from a superseded run is
    // rejected and cannot set outputReady/outputText for the replacement.
    function acceptLyricOutput(originSerial, collector, text) {
        if (!collector || typeof originSerial !== "number") return false
        if (originSerial !== lyricProcess.runSerial) return false
        if (lyricProcess.stdout !== collector) return false
        if (lyricProcess.completed || lyricProcess.completedRun === originSerial) return false
        lyricProcess.outputText = String(text || "")
        lyricProcess.outputSerial = originSerial
        lyricProcess.outputReady = true
        if (lyricProcess.exitReady) root.maybeCompleteProcess()
        return true
    }


    function performProjection(force) {
        if (root.state !== "ready" || !Array.isArray(root.lines) || root.lines.length === 0 || !root.activePlayer) {
            root.activeLineIndex = -1
            root.currentLine = null
            root.projectionState = "unknown"
            return
        }
        var nextPosition = Number(root.activePlayer.position)
        if (!root.finite(nextPosition) || nextPosition < 0) {
            root.position = -1
            root.lastProjectionPosition = -1
            root.activeLineIndex = -1
            root.currentLine = null
            root.projectionState = "unknown"
            return
        }
        var displayPosition = nextPosition + root.offsetMs / 1000
        var state = KaraokeModel.projectState(root.lines, displayPosition)
        root.projectionState = state
        if (state === "line") {
            var hint = root.activeLineIndex
            if (force || root.lastProjectionPosition < 0 || displayPosition < root.lastProjectionPosition
                    || Math.abs(displayPosition - root.lastProjectionPosition) > 2) hint = -1
            var index = KaraokeModel.findLineIndex(root.lines, displayPosition, hint)
            root.position = displayPosition
            root.lastProjectionPosition = displayPosition
            root.activeLineIndex = index
            root.currentLine = index >= 0 ? root.lines[index] : null
        } else if (state === "before_first") {
            root.position = displayPosition
            root.lastProjectionPosition = displayPosition
            root.activeLineIndex = -1
            root.currentLine = root.lines[0]
        } else {
            root.position = displayPosition
            root.lastProjectionPosition = displayPosition
            root.activeLineIndex = -1
            root.currentLine = null
        }
    }

    function updateProjectionTimer() {
        var playing = root.activePlayer && root.activePlayer.isPlaying === true
        projectionTimer.interval = root.timing === "word" ? 33 : 200
        projectionTimer.running = root.state === "ready" && playing
        if (!playing) root.performProjection(true)
    }

    Timer {
        id: mediaRetryTimer
        interval: 500
        repeat: false
        onTriggered: root.bindMediaService()
    }

    Timer {
        id: trackSettleTimer
        interval: 120
        repeat: false
        onTriggered: root.settleTrack()
    }

    Timer {
        id: projectionTimer
        interval: 200
        repeat: true
        onTriggered: root.performProjection(false)
    }

    Timer {
        id: retryCooldownTimer
        interval: root.retryCooldownMs
        repeat: false
    }

    Timer {
        id: autoRetryTimer
        interval: 2000
        repeat: false
        property string retryKey: ""
        property int retryGeneration: 0
        onTriggered: root.startAutomaticRetry(retryKey, retryGeneration)
    }

    Timer {
        id: searchCooldownTimer
        interval: root.searchCooldownMs
        repeat: false
        onTriggered: {
            root.searchCooldownRevision += 1
            root.scheduleSearchCooldownWake()
        }
    }

    Timer {
        id: resolverWatchdog
        interval: root.resolverTimeoutMs
        repeat: false
        onTriggered: root.handleResolverTimeout()
    }

    Timer {
        id: actionWatchdog
        interval: root.actionTimeoutMs
        repeat: false
        onTriggered: root.handleActionTimeout()
    }

    Timer {
        id: lyricDrainTimer
        interval: 100
        repeat: false
        property int drainSerial: -1
        onTriggered: {
            if (drainSerial !== lyricProcess.runSerial) return
            if (lyricProcess.completed || lyricProcess.completedRun === lyricProcess.runSerial) return
            root.finalizeLyricOutput()
        }
    }

    Timer {
        id: actionDrainTimer
        interval: 100
        repeat: false
        property int drainSerial: -1
        onTriggered: {
            if (drainSerial !== actionProcess.actionSerial) return
            if (actionProcess.completed || actionProcess.completedAction === actionProcess.actionSerial) return
            root.finalizeActionOutput()
        }
    }

    Timer {
        id: lyricKillTimer
        interval: 1000
        repeat: false
        property int killSerial: -1
        onTriggered: root.handleLyricKillTimeout()
    }

    Timer {
        id: actionKillTimer
        interval: 1000
        repeat: false
        property int killSerial: -1
        onTriggered: root.handleActionKillTimeout()
    }

    // Per-run stdout collectors. Each run gets a fresh StdioCollector whose
    // expectedSerial is immutable: it is stamped at creation, before
    // running = true, and never read back from the (possibly already
    // replaced) current serial. A delayed EOF from a superseded run carries
    // the old serial and is rejected by acceptLyricOutput/acceptActionOutput,
    // so it can never set outputReady/outputText for the replacement.
    Component {
        id: lyricCollectorFactory
        StdioCollector {
            id: lyricCollector
            property int expectedSerial: -1
            waitForEnd: true
            onStreamFinished: root.acceptLyricOutput(lyricCollector.expectedSerial, lyricCollector,
                lyricCollector.text)
        }
    }

    Component {
        id: actionCollectorFactory
        StdioCollector {
            id: actionCollector
            property int expectedSerial: -1
            waitForEnd: true
            onStreamFinished: root.acceptActionOutput(actionCollector.expectedSerial, actionCollector,
                actionCollector.text)
        }
    }

    Process {
        id: lyricProcess
        property int requestId: 0
        property string requestKey: ""
        property int runSerial: 0
        property int completedRun: 0
        property int timedOutRun: -1
        property bool outputReady: false
        property bool exitReady: false
        property int exitCode: -1
        property string exitStatus: ""
        property string outputText: ""
        // Origin-aware stdout fencing: outputSerial owns the held bytes and
        // streamSerial stamps the started run, but the authoritative fence is
        // the per-run collector (activeCollector) reporting through
        // acceptLyricOutput with its immutable expectedSerial.
        property int streamSerial: -1
        property int outputSerial: -1
        property var activeCollector: null
        property bool started: false
        property real startedAtMs: 0
        property bool cancelled: false
        property bool timedOut: false
        property bool completed: false
        property bool runRequested: false
        command: []
        onStarted: {
            lyricProcess.started = true
            lyricProcess.startedAtMs = Date.now()
            lyricProcess.runRequested = false
            // Stdout collection for this run begins now: stamp the serial and
            // drop any bytes a superseded run delivered while pending start.
            lyricProcess.streamSerial = lyricProcess.runSerial
            lyricProcess.outputText = ""
            lyricProcess.outputSerial = -1
            lyricProcess.outputReady = false
        }
        onExited: function(code, status) {
            lyricProcess.exitCode = code
            lyricProcess.exitStatus = root.exitStatusText(status)
            lyricProcess.exitReady = true
            lyricProcess.runRequested = false
            if (lyricProcess.cancelled || lyricProcess.timedOut
                    || lyricProcess.completed || lyricProcess.completedRun === lyricProcess.runSerial) {
                root.finalizeLyricOutput()
                return
            }
            if (lyricProcess.outputReady) {
                root.maybeCompleteProcess()
            } else {
                lyricDrainTimer.drainSerial = lyricProcess.runSerial
                lyricDrainTimer.restart()
            }
        }
        onRunningChanged: {
            if (!lyricProcess.running && lyricProcess.runRequested
                    && !lyricProcess.started && !lyricProcess.exitReady && !lyricProcess.completed) {
                var serial = lyricProcess.runSerial
                Qt.callLater(function() { root.checkLyricStartFailure(serial) })
            }
        }
    }

    Process {
        id: actionProcess
        property string commandKind: ""
        property int requestId: 0
        property string requestKey: ""
        property int actionSerial: 0
        property int completedAction: 0
        property int timedOutAction: -1
        property bool outputReady: false
        property bool exitReady: false
        property int exitCode: -1
        property string exitStatus: ""
        property string outputText: ""
        // Fenced exactly like the lyric channel: the authoritative fence is
        // the per-run collector (activeCollector) reporting through
        // acceptActionOutput with its immutable expectedSerial.
        property int streamSerial: -1
        property int outputSerial: -1
        property var activeCollector: null
        property bool started: false
        property real startedAtMs: 0
        property bool cancelled: false
        property bool timedOut: false
        property bool completed: false
        property bool runRequested: false
        command: []
        onStarted: {
            actionProcess.started = true
            actionProcess.startedAtMs = Date.now()
            actionProcess.runRequested = false
            // Stdout collection for this action begins now: stamp the serial
            // and drop any bytes a superseded action delivered while pending.
            actionProcess.streamSerial = actionProcess.actionSerial
            actionProcess.outputText = ""
            actionProcess.outputSerial = -1
            actionProcess.outputReady = false
        }
        onExited: function(code, status) {
            actionProcess.exitCode = code
            actionProcess.exitStatus = root.exitStatusText(status)
            actionProcess.exitReady = true
            actionProcess.runRequested = false
            if (actionProcess.cancelled || actionProcess.timedOut
                    || actionProcess.completed || actionProcess.completedAction === actionProcess.actionSerial) {
                root.finalizeActionOutput()
                return
            }
            if (actionProcess.outputReady) {
                root.maybeCompleteAction()
            } else {
                actionDrainTimer.drainSerial = actionProcess.actionSerial
                actionDrainTimer.restart()
            }
        }
        onRunningChanged: {
            if (!actionProcess.running && actionProcess.runRequested
                    && !actionProcess.started && !actionProcess.exitReady && !actionProcess.completed) {
                var serial = actionProcess.actionSerial
                Qt.callLater(function() { root.checkActionStartFailure(serial) })
            }
        }
    }

    Connections {
        target: root.shell
        ignoreUnknownSignals: true
        function onChanged() { root.bindMediaService() }
    }

    Connections {
        target: root.mediaService
        ignoreUnknownSignals: true
        function onActivePlayerChanged() { root.scheduleTrackSettle() }
    }

    Connections {
        target: root.activePlayer
        ignoreUnknownSignals: true
        function onPostTrackChanged() { root.scheduleTrackSettle() }
        function onTrackChanged() { root.scheduleTrackSettle() }
        function onIsPlayingChanged() { root.performProjection(true); root.updateProjectionTimer() }
        function onPositionChanged() {
            root.performProjection(false)
            if (!root.activePlayer || root.activePlayer.isPlaying !== true) root.updateProjectionTimer()
        }
    }
    onMprisPlayersChanged: {
        root.scheduleTrackSettle()
        root.refreshFallbackMediaStatus()
    }
    onFallbackMediaStatusChanged: root.scheduleTrackSettle()

    onShellChanged: root.bindMediaService()
    onTrackKeyChanged: root.scheduleTrackSettle()
    onTimingChanged: root.updateProjectionTimer()
    onStateChanged: root.updateProjectionTimer()

    Component.onCompleted: root.bindMediaService()
}
