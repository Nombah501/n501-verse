.pragma library

function finite(value) {
    return typeof value === "number" && isFinite(value)
}

function validLine(line) {
    return !!line && finite(Number(line.start)) && finite(Number(line.end))
        && Number(line.start) >= 0 && Number(line.end) >= Number(line.start)
}

var validLinesCache = { lines: null, valid: false };

function validLines(lines) {
    // The service replaces document arrays rather than mutating them, so the
    // most recent validation result stays correct without re-scanning.
    if (lines === validLinesCache.lines) return validLinesCache.valid;
    var valid = Array.isArray(lines);
    var previous = -Infinity;
    for (var i = 0; valid && i < lines.length; i++) {
        if (!validLine(lines[i])) valid = false;
        else if (Number(lines[i].start) < previous) valid = false;
        else previous = Number(lines[i].start);
    }
    validLinesCache.lines = lines;
    validLinesCache.valid = valid;
    return valid;
}

function findLineIndex(lines, position, hintIndex) {
    if (!validLines(lines) || lines.length === 0 || !finite(Number(position))) return -1
    var pos = Number(position)
    if (pos < Number(lines[0].start)) return -1

    var hint = Number(hintIndex)
    if (isFinite(hint) && Math.floor(hint) === hint && hint >= 0 && hint < lines.length) {
        var index = hint
        if (pos >= Number(lines[index].start)) {
            while (index + 1 < lines.length && Number(lines[index + 1].start) <= pos) index++
            return index
        }
        while (index > 0 && Number(lines[index].start) > pos) index--
        return Number(lines[index].start) <= pos ? index : -1
    }

    var low = 0
    var high = lines.length - 1
    var result = -1
    while (low <= high) {
        var middle = Math.floor((low + high) / 2)
        if (Number(lines[middle].start) <= pos) {
            result = middle
            low = middle + 1
        } else {
            high = middle - 1
        }
    }
    return result
}

var INTERLUDE_GAP_S = 1.2
var LONG_INTERLUDE_GAP_S = 4.0
var INTERLUDE_CONVERGE_S = 3.0

function interludeThreshold() {
    return INTERLUDE_GAP_S
}

function longInterludeThreshold() {
    return LONG_INTERLUDE_GAP_S
}

function interludeConvergeWindow() {
    return INTERLUDE_CONVERGE_S
}

// Below this span, a word-timed line's trailing timestamp is treated as
// degenerate data (e.g. a zero-duration last word) rather than a genuine
// early finish, so lineEffectiveEnd falls back to the raw line end. This
// keeps callers that need room to work within the effective span --
// Service.qml's seekToLine epsilon in particular -- from being handed a
// span too thin (or zero) to use.
var MIN_WORD_SPAN_S = 0.05

function lineEffectiveEnd(line) {
    // Kotonoha's LRC parser sets line.end to the NEXT line's start, so a
    // word-timed line whose lyrics finish early (an explicit trailing word
    // timestamp) would otherwise report a zero gap and never show the
    // interlude marker. Sources with explicit line durations (YRC/KRC) are
    // unaffected because their last word end equals line.end.
    var end = Number(line.end)
    var projection = projectLine(line, line.start)
    if (!projection.hasWordTiming) return end
    var wordEnd = Number(projection.lastWordEnd)
    if (!finite(wordEnd)) return end
    if (wordEnd - Number(line.start) < MIN_WORD_SPAN_S) return end
    return Math.min(end, wordEnd)
}

function projectStateFromAnchor(lines, position, index, effectiveEnd) {
    var pos = Number(position)
    if (index < 0) return "before_first"
    if (pos <= effectiveEnd) return "line"
    if (index + 1 >= lines.length) return "after_last"
    return Number(lines[index + 1].start) - effectiveEnd - INTERLUDE_GAP_S > 1e-9
        ? "interlude" : "line"
}

function projectState(lines, position) {
    if (!validLines(lines) || lines.length === 0) return "unknown"
    if (!finite(Number(position))) return "unknown"
    var pos = Number(position)
    if (pos < Number(lines[0].start)) return "before_first"
    // Nearest started line chooses the anchor; the state decides painting.
    var index = findLineIndex(lines, pos, -1)
    var effectiveEnd = index >= 0 ? lineEffectiveEnd(lines[index]) : -1
    return projectStateFromAnchor(lines, pos, index, effectiveEnd)
}

function lineHasWordTiming(line) {
    // Same complete-span bar as the renderer so labels agree with paint.
    if (!validLine(line)) return false
    return projectLine(line, 0).hasWordTiming === true
}

function timingDetail(lines) {
    if (!Array.isArray(lines) || lines.length === 0) return "line"
    var complete = 0
    for (var i = 0; i < lines.length; i++) {
        if (lineHasWordTiming(lines[i])) complete++
    }
    if (complete === 0) return "line"
    if (complete === lines.length) return "word"
    return "mixed"
}

function projectLine(line, position) {
    var empty = {
        text: "",
        filledText: "",
        activeWordText: "",
        remainingText: "",
        wordProgress: 0,
        hasWordTiming: false,
        prefixText: "",
        suffixText: "",
        untimedPrefixText: "",
        timedPrefixText: "",
        timedText: "",
        lastWordEnd: NaN
    }
    if (!validLine(line)) return empty

    var text = typeof line.text === "string" ? line.text : String(line.text || "")
    var words = Array.isArray(line.words) ? line.words : []
    var timedWords = []
    var untimedPrefix = ""
    var sawTimed = false
    var completeSpans = true
    for (var i = 0; i < words.length; i++) {
        var word = words[i]
        if (!word || typeof word.text !== "string") continue
        var hasStart = finite(Number(word.start))
        var hasEnd = finite(Number(word.end))
        if (word.start === null && word.end === null) {
            if (sawTimed) {
                completeSpans = false
                break
            }
            untimedPrefix += word.text
            continue
        }
        if (word.start === null || word.end === null
                || !hasStart || !hasEnd || Number(word.start) < 0
                || Number(word.end) < Number(word.start)) {
            completeSpans = false
            break
        }
        sawTimed = true
        var timed = {
            timed: true,
            start: Number(word.start),
            end: Number(word.end),
            text: word.text
        }
        timedWords.push(timed)
    }
    if (completeSpans && timedWords.length > 0
            && untimedPrefix + timedWords.map(function(word) { return word.text }).join("") !== text) {
        completeSpans = false
    }
    if (!completeSpans || timedWords.length === 0) {
        empty.text = text
        empty.remainingText = text
        empty.suffixText = text
        return empty
    }

    var pos = finite(Number(position)) ? Number(position) : Number(line.start)
    var active = 0
    var progress = 0
    if (pos < timedWords[0].start) {
        active = 0
    } else {
        active = timedWords.length - 1
        progress = 1
        for (var j = 0; j < timedWords.length; j++) {
            var current = timedWords[j]
            var next = j + 1 < timedWords.length ? timedWords[j + 1] : null
            if (pos < current.start) {
                active = j
                progress = 0
                break
            }
            if (pos <= current.end) {
                active = j
                var span = current.end - current.start
                progress = span > 0 ? (pos - current.start) / span : (pos >= current.end ? 1 : 0)
                break
            }
            if (next && pos < next.start) {
                active = j + 1
                progress = 0
                break
            }
        }
    }
    progress = Math.max(0, Math.min(1, progress))

    var timedPrefix = ""
    for (var before = 0; before < active; before++) timedPrefix += timedWords[before].text
    var currentText = timedWords[active].text
    var suffix = ""
    for (var after = active + 1; after < timedWords.length; after++) suffix += timedWords[after].text

    return {
        text: text,
        filledText: untimedPrefix + timedPrefix + (progress >= 1 ? currentText : ""),
        activeWordText: currentText,
        remainingText: suffix,
        wordProgress: progress,
        hasWordTiming: true,
        prefixText: untimedPrefix + timedPrefix,
        suffixText: suffix,
        untimedPrefixText: untimedPrefix,
        timedPrefixText: timedPrefix,
        timedText: timedWords.map(function(word) { return word.text }).join(""),
        lastWordEnd: timedWords.reduce(function(max, word) {
            return word.end > max ? word.end : max
        }, timedWords[0].end)
    }
}

function formatTime(seconds) {
    if (!finite(Number(seconds)) || Number(seconds) < 0) return "--:--"
    var whole = Math.floor(Number(seconds))
    var minutes = Math.floor(whole / 60)
    var remainder = whole % 60
    return minutes + ":" + (remainder < 10 ? "0" : "") + remainder
}
if (typeof module !== "undefined" && module.exports) {
    module.exports = { findLineIndex: findLineIndex, projectLine: projectLine, formatTime: formatTime,
        projectState: projectState, projectStateFromAnchor: projectStateFromAnchor,
        lineHasWordTiming: lineHasWordTiming, timingDetail: timingDetail,
        validLines: validLines, interludeGapS: INTERLUDE_GAP_S, interludeThreshold: interludeThreshold,
        longInterludeGapS: LONG_INTERLUDE_GAP_S, interludeConvergeS: INTERLUDE_CONVERGE_S,
        lineEffectiveEnd: lineEffectiveEnd,
        minWordSpanS: MIN_WORD_SPAN_S }
}
