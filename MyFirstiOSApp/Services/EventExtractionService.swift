/// EventExtractionService.swift
/// ============================
/// Extracts structured date/time events from unstructured text sources using regex.
///
/// ## Approach
/// Pure regex-based extraction (Experiment A). The pipeline:
/// 1. Early exit / past-event filtering
/// 2. Structured caption fast path (for well-formatted event lists)
/// 3. Date anchor detection across all input sources
/// 4. Time extraction near each date anchor (scoped to same + next line)
/// 5. Description extraction (preceding lines for title-block OCR, same/next line for flyers)
/// 6. Cross-source merging (date from OCR + time from caption)
/// 7. Multi-source deduplication
/// 8. Year inference, formatting, and chronological sorting

import Foundation

// MARK: - Private Types

private enum InputSource: Int, Comparable {
    case caption = 0
    case ocr = 1
    case altText = 2
    static func < (lhs: InputSource, rhs: InputSource) -> Bool { lhs.rawValue < rhs.rawValue }
}

private struct DateAnchor {
    let month: Int
    let day: Int
    let year: Int?
    let endDay: Int?
    let endMonth: Int?
    let range: Range<String.Index>
    let lineIndex: Int          // which line of the text this appears on
}

private struct TimeInfo {
    let startHour: Int
    let startMinute: Int
    let endHour: Int?
    let endMinute: Int
    let isMidnightEnd: Bool
}

private struct RawEvent {
    var month: Int
    var day: Int
    var year: Int?
    var endMonth: Int?
    var endDay: Int?
    var startHour: Int?
    var startMinute: Int
    var endHour: Int?
    var endMinute: Int
    var isMidnightEnd: Bool
    var descriptionText: String
    var source: InputSource
    var dateOnly: Bool
}

// MARK: - Public API

enum EventExtractionService {

    static func extractEvents(
        ocrTexts: [String],
        altTexts: [String],
        caption: String,
        currentDate: Date
    ) -> [ExtractedEvent] {
        let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let allOCR = ocrTexts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let allAlt = altTexts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if allOCR.isEmpty && allAlt.isEmpty && trimmedCaption.isEmpty { return [] }

        // Past-event filter
        if isPastEventPost(caption: trimmedCaption, ocrTexts: allOCR, altTexts: allAlt, currentDate: currentDate) {
            return []
        }

        // Structured caption fast path (e.g. Yu and Me 17-event list)
        if let structured = parseStructuredCaption(trimmedCaption, currentDate: currentDate) {
            return structured
        }

        // Typo correction from caption
        let typoTime = findTypoCorrection(in: trimmedCaption)

        // Build source list; strip alt-text metadata dates
        var sources: [(text: String, source: InputSource)] = []
        for ocr in allOCR { sources.append((ocr, .ocr)) }
        sources.append((trimmedCaption, .caption))
        for alt in allAlt { sources.append((stripAltTextMetaDates(alt), .altText)) }

        // Extract raw events from all sources
        var rawEvents: [RawEvent] = []
        var orphanDates: [DateAnchor] = []  // dates with no time found

        for (text, source) in sources {
            let (events, orphans) = extractRawEvents(from: text, source: source, currentDate: currentDate, typoTime: typoTime)
            rawEvents.append(contentsOf: events)
            if source == .ocr { orphanDates.append(contentsOf: orphans) }
        }

        // Cross-source merging: orphan dates from OCR + time from caption
        if !orphanDates.isEmpty && !trimmedCaption.isEmpty {
            let crossSourceEvents = mergeOrphanDatesWithCaption(
                orphanDates: orphanDates, caption: trimmedCaption, ocrTexts: allOCR, currentDate: currentDate
            )
            rawEvents.append(contentsOf: crossSourceEvents)
        }

        // Deduplicate
        let deduped = deduplicateEvents(rawEvents)

        // Format and sort
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: currentDate)
        let results = deduped.compactMap { raw -> ExtractedEvent? in
            formatEvent(raw, currentYear: currentYear, currentDate: currentDate)
        }
        return results.sorted { $0.datetimeStart < $1.datetimeStart }
    }
}

// MARK: - Month Name Resolution

private let englishMonthsFull: [String: Int] = [
    "january": 1, "february": 2, "march": 3, "april": 4,
    "may": 5, "june": 6, "july": 7, "august": 8,
    "september": 9, "october": 10, "november": 11, "december": 12,
]
private let englishMonthsAbbr: [String: Int] = [
    "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
    "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
]
private let spanishMonths: [String: Int] = [
    "enero": 1, "febrero": 2, "marzo": 3, "abril": 4,
    "mayo": 5, "junio": 6, "julio": 7, "agosto": 8,
    "septiembre": 9, "octubre": 10, "noviembre": 11, "diciembre": 12,
]

private func monthNumber(from name: String) -> Int? {
    let lower = name.lowercased()
    return englishMonthsFull[lower] ?? englishMonthsAbbr[lower] ?? spanishMonths[lower]
}

// MARK: - Time Parsing Helpers

private func to24Hour(_ hour: Int, _ minute: Int, _ ampm: String) -> (Int, Int) {
    let ap = ampm.lowercased().replacingOccurrences(of: ".", with: "").trimmingCharacters(in: .whitespaces)
    let isPM = ap.hasPrefix("p")
    var h = hour
    if isPM { if h != 12 { h += 12 } }
    else { if h == 12 { h = 0 } }
    return (h, minute)
}

private func parseHourMinute(_ s: String) -> (Int, Int)? {
    let trimmed = s.trimmingCharacters(in: .whitespaces)
    if trimmed.contains(":") {
        let parts = trimmed.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return (h, m)
    }
    guard let h = Int(trimmed) else { return nil }
    return (h, 0)
}

// MARK: - Regex Helpers

private func firstMatch(_ pattern: String, in text: String) -> NSTextCheckingResult? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
    return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
}

private func allMatches(_ pattern: String, in text: String) -> [NSTextCheckingResult] {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
    return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
}

private func cap(_ result: NSTextCheckingResult, _ index: Int, in text: String) -> String? {
    guard index < result.numberOfRanges else { return nil }
    let nsRange = result.range(at: index)
    guard nsRange.location != NSNotFound, let range = Range(nsRange, in: text) else { return nil }
    return String(text[range])
}

// MARK: - Past-Event Detection

private func isPastEventPost(caption: String, ocrTexts: [String], altTexts: [String], currentDate: Date) -> Bool {
    let pastPatterns = [
        "\\b(?:last\\s+night|last\\s+evening|yesterday)\\b",
        "\\bthank\\s+you\\b.*\\bcame\\s+out\\b",
        "\\bwho\\s+came\\s+out\\b",
    ]
    var hasPastIndicator = false
    for pattern in pastPatterns {
        if firstMatch(pattern, in: caption) != nil { hasPastIndicator = true; break }
    }
    if !hasPastIndicator { return false }

    let allText = ([caption] + ocrTexts + altTexts).joined(separator: " ")
    let anchors = findDateAnchors(in: allText)
    let calendar = Calendar.current
    let currentYear = calendar.component(.year, from: currentDate)
    for anchor in anchors {
        let year = anchor.year ?? currentYear
        if let date = makeDate(year: year, month: anchor.month, day: anchor.day), date > currentDate {
            return false
        }
    }
    return true
}

private func makeDate(year: Int, month: Int, day: Int) -> Date? {
    var c = DateComponents(); c.year = year; c.month = month; c.day = day
    return Calendar.current.date(from: c)
}

// MARK: - Alt-Text Metadata Stripping

private func stripAltTextMetaDates(_ text: String) -> String {
    let pattern = "(?:Photo|Video)\\s+by\\s+.+?\\s+on\\s+(?:January|February|March|April|May|June|July|August|September|October|November|December)\\s+\\d{1,2},\\s+\\d{4}\\.?"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
    return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
}

// MARK: - Structured Caption Parsing (Fast Path)

private func parseStructuredCaption(_ caption: String, currentDate: Date) -> [ExtractedEvent]? {
    // Detect: 3+ lines matching "MonthAbbr. Day, Time..."
    let detectPattern = "(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\\.?\\s+\\d{1,2},\\s+\\d{1,2}"
    let matches = allMatches(detectPattern, in: caption)
    guard matches.count >= 3 else { return nil }

    // Split into entries: each starts with a month abbreviation pattern
    let entryStartPattern = "(?i)(?:^|\\n)\\s*((?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\\.?\\s+\\d)"
    let entryStarts = allMatches(entryStartPattern, in: caption)
    guard entryStarts.count >= 3 else { return nil }

    let calendar = Calendar.current
    let currentYear = calendar.component(.year, from: currentDate)
    var events: [ExtractedEvent] = []

    // Extract each entry as a substring from one entry start to the next
    for i in 0..<entryStarts.count {
        let matchRange = entryStarts[i].range(at: 1)
        guard matchRange.location != NSNotFound, let startRange = Range(matchRange, in: caption) else { continue }
        let entryStart = startRange.lowerBound

        let entryEnd: String.Index
        if i + 1 < entryStarts.count {
            let nextRange = entryStarts[i + 1].range(at: 1)
            if nextRange.location != NSNotFound, let nr = Range(nextRange, in: caption) {
                entryEnd = nr.lowerBound
            } else {
                entryEnd = caption.endIndex
            }
        } else {
            entryEnd = caption.endIndex
        }

        let entryText = String(caption[entryStart..<entryEnd]).trimmingCharacters(in: .whitespacesAndNewlines)

        // Parse: "Apr. 2, 7-8PM: Description..."
        let fullPattern = "(?i)(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\\.?\\s+(\\d{1,2}),\\s+(.+?):\\s+(.*)"
        guard let m = firstMatch(fullPattern, in: entryText),
              let monthStr = cap(m, 1, in: entryText),
              let dayStr = cap(m, 2, in: entryText),
              let timeStr = cap(m, 3, in: entryText),
              let descStr = cap(m, 4, in: entryText),
              let month = monthNumber(from: monthStr),
              let day = Int(dayStr) else { continue }

        let year = inferYear(month: month, day: day, currentYear: currentYear, currentDate: currentDate)
        guard let ti = parseTimeString(timeStr) else { continue }

        let desc = cleanStructuredDescription(descStr)
        let startStr = fmtDatetime(year: year, month: month, day: day, hour: ti.startHour, minute: ti.startMinute)
        var endStr: String? = nil
        if let eh = ti.endHour {
            if ti.isMidnightEnd {
                if let nd = nextDay(year: year, month: month, day: day) {
                    endStr = fmtDatetime(year: nd.0, month: nd.1, day: nd.2, hour: 0, minute: 0)
                }
            } else {
                endStr = fmtDatetime(year: year, month: month, day: day, hour: eh, minute: ti.endMinute)
            }
        }
        events.append(ExtractedEvent(datetimeStart: startStr, datetimeEnd: endStr, description: desc))
    }

    guard !events.isEmpty else { return nil }
    return events.sorted { $0.datetimeStart < $1.datetimeStart }
}

private func parseTimeString(_ s: String) -> TimeInfo? {
    let t = s.trimmingCharacters(in: .whitespaces)
    // Time range: "7-8PM", "11:30AM-12:30PM", "8-10PM"
    let rangeP = "(?i)(\\d{1,2}(?::\\d{2})?)\\s*(AM|PM|a\\.?m\\.?|p\\.?m\\.?)?\\s*[-–]\\s*(\\d{1,2}(?::\\d{2})?)\\s*(AM|PM|a\\.?m\\.?|p\\.?m\\.?)"
    if let m = firstMatch(rangeP, in: t),
       let startS = cap(m, 1, in: t), let endS = cap(m, 3, in: t), let endAP = cap(m, 4, in: t),
       let (sh, sm) = parseHourMinute(startS), let (eh, em) = parseHourMinute(endS) {
        let startAP = cap(m, 2, in: t) ?? endAP
        let (sH, sM) = to24Hour(sh, sm, startAP)
        let (eH, eM) = to24Hour(eh, em, endAP)
        return TimeInfo(startHour: sH, startMinute: sM, endHour: eH, endMinute: eM, isMidnightEnd: eH == 0 && eM == 0)
    }
    // Single time: "7:30PM", "7PM"
    let singleP = "(?i)(\\d{1,2}(?::\\d{2})?)\\s*(a\\.?m\\.?|p\\.?m\\.?|AM|PM)"
    if let m = firstMatch(singleP, in: t),
       let ts = cap(m, 1, in: t), let ap = cap(m, 2, in: t),
       let (h, mn) = parseHourMinute(ts) {
        let (hh, mm) = to24Hour(h, mn, ap)
        return TimeInfo(startHour: hh, startMinute: mm, endHour: nil, endMinute: 0, isMidnightEnd: false)
    }
    return nil
}

private func cleanStructuredDescription(_ s: String) -> String {
    var d = s.trimmingCharacters(in: .whitespacesAndNewlines)
    // Remove trailing RSVP/signup/ticket text
    if let r = try? NSRegularExpression(pattern: "(?i)\\s*(?:RSVP|Sign-?ups?\\s+start|Tickets?\\s+include|Fans\\s+will).*$", options: []) {
        d = r.stringByReplacingMatches(in: d, range: NSRange(d.startIndex..., in: d), withTemplate: "")
    }
    // Remove trailing @mentions
    if let r = try? NSRegularExpression(pattern: "\\s*@\\S+\\s*$", options: []) {
        d = r.stringByReplacingMatches(in: d, range: NSRange(d.startIndex..., in: d), withTemplate: "")
    }
    d = d.trimmingCharacters(in: .whitespacesAndNewlines)
    while d.hasSuffix(".") || d.hasSuffix("!") || d.hasSuffix(",") {
        d = String(d.dropLast()).trimmingCharacters(in: .whitespaces)
    }
    return d
}

// MARK: - Typo Correction

private func findTypoCorrection(in caption: String) -> TimeInfo? {
    let pattern = "\\*+\\s*TYPO\\s*[-–]?\\s*(.+?)\\s*\\*+"
    guard let m = firstMatch(pattern, in: caption), let cs = cap(m, 1, in: caption) else { return nil }
    return parseTimeString(cs)
}

// MARK: - Date Anchor Detection

private let monthNamesRE = "(?:January|February|March|April|May|June|July|August|September|October|November|December)"
private let monthAbbrRE = "(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)"

private func findDateAnchors(in text: String) -> [DateAnchor] {
    let lines = text.components(separatedBy: .newlines)
    var anchors: [DateAnchor] = []
    // Track ranges to avoid duplicates
    var usedRanges: [Range<String.Index>] = []

    func addAnchor(_ a: DateAnchor) {
        if usedRanges.contains(where: { $0.overlaps(a.range) }) { return }
        usedRanges.append(a.range)
        anchors.append(a)
    }

    // Find which line each character offset belongs to
    func lineIndex(for range: Range<String.Index>) -> Int {
        var pos = text.startIndex
        for (idx, line) in lines.enumerated() {
            let lineEnd = text.index(pos, offsetBy: line.count, limitedBy: text.endIndex) ?? text.endIndex
            if range.lowerBound >= pos && range.lowerBound <= lineEnd { return idx }
            pos = text.index(lineEnd, offsetBy: 1, limitedBy: text.endIndex) ?? text.endIndex
        }
        return lines.count - 1
    }

    // B5: Date range "May 14–17, 2026"
    let drP = "(?i)(\(monthNamesRE)|\(monthAbbrRE))\\.?\\s+(\\d{1,2})\\s*[–\\-]\\s*(\\d{1,2})\\s*,?\\s*(\\d{4})?"
    for m in allMatches(drP, in: text) {
        guard let ms = cap(m, 1, in: text), let ds = cap(m, 2, in: text), let es = cap(m, 3, in: text),
              let mo = monthNumber(from: ms), let d = Int(ds), let ed = Int(es),
              let r = Range(m.range, in: text), ed > d, d <= 31, ed <= 31,
              (ed > 12 || d > 12) else { continue }
        let yr = cap(m, 4, in: text).flatMap { Int($0) }
        addAnchor(DateAnchor(month: mo, day: d, year: yr, endDay: ed, endMonth: nil, range: r, lineIndex: lineIndex(for: r)))
    }

    // B3: DOW + Month + Day: "Wed - March 4th"
    let dowP = "(?i)(?:Mon(?:day)?|Tues?(?:day)?|Wed(?:nesday)?|Thur?s?(?:day)?|Fri(?:day)?|Sat(?:urday)?|Sun(?:day)?)\\s*[-–,]?\\s*(\(monthNamesRE))\\s+(\\d{1,2})(?:st|nd|rd|th)?\"?"
    for m in allMatches(dowP, in: text) {
        guard let ms = cap(m, 1, in: text), let ds = cap(m, 2, in: text),
              let mo = monthNumber(from: ms), let d = Int(ds), let r = Range(m.range, in: text) else { continue }
        addAnchor(DateAnchor(month: mo, day: d, year: nil, endDay: nil, endMonth: nil, range: r, lineIndex: lineIndex(for: r)))
    }

    // B1: Full month + day: "March 4th", "April 4, 2026"
    let fmP = "(?i)(\(monthNamesRE))\\s+(\\d{1,2})(?:st|nd|rd|th)?\"?\\s*,?\\s*(\\d{4})?"
    for m in allMatches(fmP, in: text) {
        guard let ms = cap(m, 1, in: text), let ds = cap(m, 2, in: text),
              let mo = monthNumber(from: ms), let d = Int(ds), let r = Range(m.range, in: text) else { continue }
        let yr = cap(m, 3, in: text).flatMap { Int($0) }
        addAnchor(DateAnchor(month: mo, day: d, year: yr, endDay: nil, endMonth: nil, range: r, lineIndex: lineIndex(for: r)))
    }

    // B4: Spanish date: "7 de abril de 2026"
    let spP = "(?i)(\\d{1,2})\\s+de\\s+(enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|octubre|noviembre|diciembre)(?:\\s+de\\s+(\\d{4}))?"
    for m in allMatches(spP, in: text) {
        guard let ds = cap(m, 1, in: text), let ms = cap(m, 2, in: text),
              let mo = monthNumber(from: ms), let d = Int(ds), let r = Range(m.range, in: text) else { continue }
        let yr = cap(m, 3, in: text).flatMap { Int($0) }
        addAnchor(DateAnchor(month: mo, day: d, year: yr, endDay: nil, endMonth: nil, range: r, lineIndex: lineIndex(for: r)))
    }

    return anchors
}

// MARK: - Time Extraction (scoped to anchor line + next line)

/// Find time in the anchor's line and the next 1-2 lines.
private func findTimeScopedToLines(anchor: DateAnchor, lines: [String]) -> TimeInfo? {
    // Build search text from anchor line + next 2 lines
    let startLine = anchor.lineIndex
    let endLine = min(startLine + 2, lines.count - 1)
    let searchText = lines[startLine...endLine].joined(separator: " ")

    // Dual timezone: "4 PM PT / 7 ET"
    let dtzP = "(?i)(\\d{1,2}(?::\\d{2})?)\\s*(AM|PM)\\s*(?:PT|PST)\\s*/\\s*(\\d{1,2}(?::\\d{2})?)\\s*(AM|PM)?\\s*(?:ET|EST)"
    if let m = firstMatch(dtzP, in: searchText),
       let etStr = cap(m, 3, in: searchText) {
        let etAP = cap(m, 4, in: searchText) ?? cap(m, 2, in: searchText) ?? "PM"
        if let (h, mn) = parseHourMinute(etStr) {
            let (hh, mm) = to24Hour(h, mn, etAP)
            return TimeInfo(startHour: hh, startMinute: mm, endHour: nil, endMinute: 0, isMidnightEnd: false)
        }
    }

    // Doors/Puertas: "Puertas: 6:30 p.m."
    let doorsP = "(?i)(?:Puertas|Doors)\\s*:?\\s*(\\d{1,2}(?::\\d{2})?)\\s*(a\\.?m\\.?|p\\.?m\\.?|AM|PM)"
    if let m = firstMatch(doorsP, in: searchText),
       let ts = cap(m, 1, in: searchText), let ap = cap(m, 2, in: searchText),
       let (h, mn) = parseHourMinute(ts) {
        let (hh, mm) = to24Hour(h, mn, ap)
        return TimeInfo(startHour: hh, startMinute: mm, endHour: nil, endMinute: 0, isMidnightEnd: false)
    }

    // Time range with midnight: "7-Midnite"
    let midP = "(?i)(\\d{1,2}(?::\\d{2})?)\\s*(AM|PM|a\\.?m\\.?|p\\.?m\\.?)?\\s*[-–]\\s*(?:Midnite|Midnight)"
    if let m = firstMatch(midP, in: searchText),
       let ss = cap(m, 1, in: searchText) {
        let sAP = cap(m, 2, in: searchText) ?? "PM"
        if let (h, mn) = parseHourMinute(ss) {
            let (hh, mm) = to24Hour(h, mn, sAP)
            return TimeInfo(startHour: hh, startMinute: mm, endHour: 0, endMinute: 0, isMidnightEnd: true)
        }
    }

    // Time range: "7-11pm", "8PM - 12AM"
    let trP = "(?i)(\\d{1,2}(?::\\d{2})?)\\s*(AM|PM|a\\.?m\\.?|p\\.?m\\.?)?\\s*[-–]\\s*(\\d{1,2}(?::\\d{2})?)\\s*(AM|PM|a\\.?m\\.?|p\\.?m\\.?)"
    if let m = firstMatch(trP, in: searchText),
       let ss = cap(m, 1, in: searchText), let es = cap(m, 3, in: searchText), let eAP = cap(m, 4, in: searchText),
       let (sh, sm) = parseHourMinute(ss), let (eh, em) = parseHourMinute(es) {
        let sAP = cap(m, 2, in: searchText) ?? eAP
        let (sH, sM) = to24Hour(sh, sm, sAP)
        let (eH, eM) = to24Hour(eh, em, eAP)
        return TimeInfo(startHour: sH, startMinute: sM, endHour: eH, endMinute: eM, isMidnightEnd: eH == 0 && eM == 0)
    }

    // "When: ... Time: 6:00 PM" or "at 7pm"
    let whenP = "(?i)(?:Time|at)\\s*:?\\s*(\\d{1,2}(?::\\d{2})?)\\s*(a\\.?m\\.?|p\\.?m\\.?|AM|PM)"
    if let m = firstMatch(whenP, in: searchText),
       let ts = cap(m, 1, in: searchText), let ap = cap(m, 2, in: searchText),
       let (h, mn) = parseHourMinute(ts) {
        let (hh, mm) = to24Hour(h, mn, ap)
        return TimeInfo(startHour: hh, startMinute: mm, endHour: nil, endMinute: 0, isMidnightEnd: false)
    }

    // Single time: "8 PM EST", with pricing context filter
    let stP = "(?i)(\\d{1,2}(?::\\d{2})?)\\s*(a\\.?m\\.?|p\\.?m\\.?|AM|PM)\\s*(?:EST|ET|CST|CT|MST|MT|PST|PT)?"
    for m in allMatches(stP, in: searchText) {
        guard let ts = cap(m, 1, in: searchText), let ap = cap(m, 2, in: searchText) else { continue }
        // Skip pricing context
        if let r = Range(m.range, in: searchText) {
            let before = String(searchText[searchText.startIndex..<r.lowerBound]).lowercased()
            if before.contains("$") || before.contains("b4") || before.hasSuffix("before ") || before.hasSuffix("entry ") { continue }
        }
        if let (h, mn) = parseHourMinute(ts) {
            let (hh, mm) = to24Hour(h, mn, ap)
            return TimeInfo(startHour: hh, startMinute: mm, endHour: nil, endMinute: 0, isMidnightEnd: false)
        }
    }

    return nil
}

// MARK: - Description Extraction

/// Extract description for a date anchor. Strategy:
/// 1. For flyer-style (DOW prefix on multi-event text): text after date on same line + next line
/// 2. Always try preceding lines if flyer-style yields poor results
/// 3. Fallback: text after date on same line
private func extractDescription(anchor: DateAnchor, lines: [String], text: String, source: InputSource, allLines: Bool = false) -> String {
    let li = anchor.lineIndex
    let anchorLine = lines[li]

    // Check if this is flyer-style: line starts with DOW AND has event text after the date
    let dowStart = "(?i)^\\s*(?:Mon|Tues?|Wed|Thur?s?|Fri|Sat|Sun)"
    if firstMatch(dowStart, in: anchorLine) != nil {
        let flyerDesc = extractFlyerDescription(lines: lines, anchorLineIndex: li)
        // If flyer extraction yielded a reasonable description, use it
        if flyerDesc.count > 5 && !flyerDesc.contains("PM PT") && !flyerDesc.contains("PM EST") && !flyerDesc.hasPrefix("|") {
            return flyerDesc
        }
    }

    // For caption source: use the full line containing the date (includes text before date)
    if source == .caption {
        let captionDesc = extractCaptionDescription(lines: lines, anchorLineIndex: li)
        if captionDesc.count > 10 { return captionDesc }
    }

    // Look at non-empty lines BEFORE the date for the description (title-block style)
    let precedingDesc = extractPrecedingDescription(lines: lines, anchorLineIndex: li)
    if !precedingDesc.isEmpty { return precedingDesc }

    // Fallback: text after date on same line, stripped of time
    return extractAfterDateOnLine(anchorLine: anchorLine, anchor: anchor)
}

/// For caption source: use the first meaningful sentence of the caption.
/// This is better than line-level extraction because caption sentences often
/// span the date mention (e.g., "FRUITFLIES returns, April 4 at @venue").
private func extractCaptionDescription(lines: [String], anchorLineIndex: Int) -> String {
    // Use the first substantial line of the caption as description
    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 10 { continue }
        if trimmed.hasPrefix("****") { continue }  // typo lines
        // Clean: remove date, time, @mentions from the line
        var cleaned = trimmed
        // Remove date patterns (with surrounding punctuation/spaces)
        let datePatterns = [
            "(?i),?\\s*\(monthNamesRE)\\s+\\d{1,2}(?:st|nd|rd|th)?\\s*,?\\s*(?:\\d{4})?",
            "(?i),?\\s*\(monthAbbrRE)\\.?\\s+\\d{1,2}(?:st|nd|rd|th)?\\s*,?\\s*(?:\\d{4})?",
        ]
        for dp in datePatterns {
            if let r = try? NSRegularExpression(pattern: dp, options: []) {
                cleaned = r.stringByReplacingMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: " ")
            }
        }
        // Remove time patterns
        let timePatterns = [
            "(?i)\\d{1,2}(?::\\d{2})?\\s*(?:AM|PM|a\\.?m\\.?|p\\.?m\\.?)?\\s*[-–]\\s*\\d{1,2}(?::\\d{2})?\\s*(?:AM|PM|a\\.?m\\.?|p\\.?m\\.?)",
            "(?i)\\d{1,2}(?::\\d{2})?\\s*(?:AM|PM|a\\.?m\\.?|p\\.?m\\.?)\\s*(?:EST|ET|PT|PST)?",
        ]
        for tp in timePatterns {
            if let r = try? NSRegularExpression(pattern: tp, options: []) {
                cleaned = r.stringByReplacingMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: " ")
            }
        }
        // Remove "at @venue" patterns
        if let r = try? NSRegularExpression(pattern: "\\s+at\\s+@\\S+", options: [.caseInsensitive]) {
            cleaned = r.stringByReplacingMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: "")
        }
        // Remove remaining @mentions
        if let r = try? NSRegularExpression(pattern: "\\s*@\\S+", options: []) {
            cleaned = r.stringByReplacingMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: "")
        }
        // Remove "* on Saturday" type noise
        if let r = try? NSRegularExpression(pattern: "\\s*\\*\\s*on\\s+\\w+day\\b.*$", options: [.caseInsensitive]) {
            cleaned = r.stringByReplacingMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: "")
        }
        // Collapse whitespace
        cleaned = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip leading emoji/special chars
        while let first = cleaned.unicodeScalars.first,
              !CharacterSet.letters.contains(first) && !CharacterSet.decimalDigits.contains(first) {
            cleaned = String(cleaned.dropFirst())
        }
        // Strip trailing punctuation
        while cleaned.hasSuffix(",") || cleaned.hasSuffix("*") || cleaned.hasSuffix("!") || cleaned.hasSuffix(".") {
            cleaned = String(cleaned.dropLast())
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count > 5 { return cleaned }
    }
    return ""
}

/// Extract description from lines preceding the date anchor.
private func extractPrecedingDescription(lines: [String], anchorLineIndex: Int) -> String {
    var descParts: [String] = []
    let skipWords = ["drink specials", "good times", "test kitchen", "join us", "register:"]
    for i in stride(from: anchorLineIndex - 1, through: 0, by: -1) {
        let line = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty { continue }
        let lower = line.lowercased()
        if skipWords.contains(where: { lower.contains($0) }) { continue }
        if lower.hasPrefix("****") { continue }
        if line.count < 3 { continue }
        descParts.insert(line, at: 0)
        if descParts.count >= 4 { break }
    }
    return descParts.joined(separator: " ")
}

private func extractFlyerDescription(lines: [String], anchorLineIndex: Int) -> String {
    var parts: [String] = []
    let anchorLine = lines[anchorLineIndex]

    // Remove DOW + date prefix
    let dowDateP = "(?i)(?:Mon(?:day)?|Tues?(?:day)?|Wed(?:nesday)?|Thur?s?(?:day)?|Fri(?:day)?|Sat(?:urday)?|Sun(?:day)?)\\s*[-–,]?\\s*\(monthNamesRE)\\s+\\d{1,2}(?:st|nd|rd|th)?\"?\\s*"
    if let m = firstMatch(dowDateP, in: anchorLine), let r = Range(m.range, in: anchorLine) {
        let after = String(anchorLine[r.upperBound...]).trimmingCharacters(in: .whitespaces)
        let cleaned = stripTrailingTime(after)
        if !cleaned.isEmpty { parts.append(cleaned) }
    }

    // Next line: continuation before time
    if anchorLineIndex + 1 < lines.count {
        let next = lines[anchorLineIndex + 1].trimmingCharacters(in: .whitespaces)
        if !next.isEmpty && firstMatch("(?i)^\\s*(?:Mon|Tues?|Wed|Thur?s?|Fri|Sat|Sun)", in: next) == nil {
            let cleaned = stripTrailingTime(next)
            if !cleaned.isEmpty { parts.append(cleaned) }
        }
    }

    return parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
}

private func extractAfterDateOnLine(anchorLine: String, anchor: DateAnchor) -> String {
    // Remove the date portion and strip time
    let datePatterns = [
        "(?i)\(monthNamesRE)\\s+\\d{1,2}(?:st|nd|rd|th)?\\s*,?\\s*(?:\\d{4})?\\s*",
        "(?i)\\d{1,2}\\s+de\\s+(?:enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|octubre|noviembre|diciembre)(?:\\s+de\\s+\\d{4})?\\s*",
    ]
    for dp in datePatterns {
        if let m = firstMatch(dp, in: anchorLine), let r = Range(m.range, in: anchorLine) {
            let after = String(anchorLine[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            let cleaned = stripTrailingTime(after)
            if cleaned.count > 3 { return cleaned }
        }
    }
    return ""
}

private func stripTrailingTime(_ s: String) -> String {
    var result = s
    let patterns = [
        "(?i)\\s*\\d{1,2}(?::\\d{2})?\\s*(?:AM|PM|a\\.?m\\.?|p\\.?m\\.?)?\\s*[-–]\\s*(?:\\d{1,2}(?::\\d{2})?\\s*(?:AM|PM|a\\.?m\\.?|p\\.?m\\.?)|(?:Midnite|Midnight))\\s*$",
        "(?i)\\s*\\d{1,2}(?::\\d{2})?\\s*(?:AM|PM|a\\.?m\\.?|p\\.?m\\.?)\\s*(?:EST|ET|PT|PST)?\\s*$",
        "(?i)\\s*\\|\\s*\\d{1,2}(?::\\d{2})?\\s*(?:AM|PM)\\s*(?:EST|ET)?\\s*$",
        "(?i)\\s*[-–]\\s*(?:Puertas|Doors).*$",
        "(?i)\\s*[-–]\\s*Show.*$",
    ]
    for p in patterns {
        if let r = try? NSRegularExpression(pattern: p, options: []) {
            result = r.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
    }
    // Strip trailing "+ ShortName"
    if let r = try? NSRegularExpression(pattern: "\\s*\\+\\s*\\S{1,10}\\s*$", options: []) {
        result = r.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
    }
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - Deadline Context Detection

private func isDeadlineContext(_ anchor: DateAnchor, lines: [String]) -> Bool {
    let line = lines[anchor.lineIndex].lowercased()
    let deadlineWords = ["deadline", "due", "expires", "registration closes", "registration ends", "early bird"]
    return deadlineWords.contains { line.contains($0) }
}

// MARK: - Raw Event Extraction

private func extractRawEvents(from text: String, source: InputSource, currentDate: Date, typoTime: TimeInfo?) -> ([RawEvent], [DateAnchor]) {
    let anchors = findDateAnchors(in: text)
    if anchors.isEmpty { return ([], []) }

    let lines = text.components(separatedBy: .newlines)
    let calendar = Calendar.current
    let currentYear = calendar.component(.year, from: currentDate)
    var events: [RawEvent] = []
    var orphans: [DateAnchor] = []

    for anchor in anchors {
        if isDeadlineContext(anchor, lines: lines) { continue }

        // Date range without time = date-only event
        if let endDay = anchor.endDay {
            let time = findTimeScopedToLines(anchor: anchor, lines: lines)
            if time == nil {
                let year = anchor.year ?? inferYear(month: anchor.month, day: anchor.day, currentYear: currentYear, currentDate: currentDate)
                let desc = extractDescription(anchor: anchor, lines: lines, text: text, source: source)
                events.append(RawEvent(
                    month: anchor.month, day: anchor.day, year: year,
                    endMonth: anchor.endMonth ?? anchor.month, endDay: endDay,
                    startHour: nil, startMinute: 0, endHour: nil, endMinute: 0,
                    isMidnightEnd: false, descriptionText: desc, source: source, dateOnly: true
                ))
                continue
            }
        }

        // Find time, apply typo correction if present
        var time = findTimeScopedToLines(anchor: anchor, lines: lines)
        if let typo = typoTime { time = typo }

        guard let resolvedTime = time else {
            orphans.append(anchor)
            continue
        }

        let desc = extractDescription(anchor: anchor, lines: lines, text: text, source: source)
        let year = anchor.year ?? inferYear(month: anchor.month, day: anchor.day, currentYear: currentYear, currentDate: currentDate)

        events.append(RawEvent(
            month: anchor.month, day: anchor.day, year: year,
            endMonth: nil, endDay: nil,
            startHour: resolvedTime.startHour, startMinute: resolvedTime.startMinute,
            endHour: resolvedTime.endHour, endMinute: resolvedTime.endMinute,
            isMidnightEnd: resolvedTime.isMidnightEnd,
            descriptionText: desc, source: source, dateOnly: false
        ))
    }

    return (events, orphans)
}

// MARK: - Cross-Source Merging (orphan dates + caption times)

private func mergeOrphanDatesWithCaption(orphanDates: [DateAnchor], caption: String, ocrTexts: [String], currentDate: Date) -> [RawEvent] {
    let calendar = Calendar.current
    let currentYear = calendar.component(.year, from: currentDate)
    var events: [RawEvent] = []

    // Find times in caption (standalone, not associated with a date)
    let captionAnchors = findDateAnchors(in: caption)

    for orphan in orphanDates {
        // Skip if caption has a date anchor for this same date (will be handled by normal extraction)
        if captionAnchors.contains(where: { $0.month == orphan.month && $0.day == orphan.day }) { continue }

        // Search caption for a standalone time
        let captionLines = caption.components(separatedBy: .newlines)
        var bestTime: TimeInfo?
        for line in captionLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            // Try to find a time, skipping pricing contexts
            let stP = "(?i)(\\d{1,2}(?::\\d{2})?)\\s*(a\\.?m\\.?|p\\.?m\\.?|AM|PM)"
            for m in allMatches(stP, in: trimmed) {
                guard let ts = cap(m, 1, in: trimmed), let ap = cap(m, 2, in: trimmed) else { continue }
                if let r = Range(m.range, in: trimmed) {
                    let before = String(trimmed[trimmed.startIndex..<r.lowerBound]).lowercased()
                    if before.contains("$") || before.contains("b4") || before.hasSuffix("before ") { continue }
                }
                if let (h, mn) = parseHourMinute(ts) {
                    let (hh, mm) = to24Hour(h, mn, ap)
                    bestTime = TimeInfo(startHour: hh, startMinute: mm, endHour: nil, endMinute: 0, isMidnightEnd: false)
                    break  // take first valid time
                }
            }
            if bestTime != nil { break }
        }

        guard let time = bestTime else { continue }

        // Description from first sentence of caption
        let desc = firstSentenceOfCaption(caption)
        let year = orphan.year ?? inferYear(month: orphan.month, day: orphan.day, currentYear: currentYear, currentDate: currentDate)

        events.append(RawEvent(
            month: orphan.month, day: orphan.day, year: year,
            endMonth: nil, endDay: nil,
            startHour: time.startHour, startMinute: time.startMinute,
            endHour: time.endHour, endMinute: time.endMinute,
            isMidnightEnd: time.isMidnightEnd,
            descriptionText: desc, source: .caption, dateOnly: false
        ))
    }

    return events
}

private func firstSentenceOfCaption(_ caption: String) -> String {
    // First line or first sentence (up to period/exclamation/newline)
    let lines = caption.components(separatedBy: .newlines)
    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 10 {
            // Strip trailing punctuation
            var result = trimmed
            while result.hasSuffix(".") || result.hasSuffix("!") {
                result = String(result.dropLast())
            }
            return result
        }
    }
    return caption.prefix(100).trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - Description Quality Scoring

/// Score a description for dedup ranking. Higher = better.
private func descQuality(_ desc: String) -> Int {
    let d = desc.trimmingCharacters(in: .whitespacesAndNewlines)
    if d.isEmpty { return 0 }
    var score = d.count
    let lower = d.lowercased()
    // Penalize descriptions that start with time/noise
    if firstMatch("^\\d{1,2}[:-]\\d", in: d) != nil { score -= 60 }  // starts with "8-12PM", "7:00"
    if lower.hasPrefix("at @") || lower.hasPrefix("register") { score -= 50 }
    if lower.contains("bit.ly") { score -= 30 }
    // Penalize very short descriptions
    if d.count < 10 { score -= 20 }
    return score
}

/// Clean a description for merge comparison: strip leading time, trailing punctuation.
private func cleanDescForMerge(_ desc: String) -> String {
    var d = desc.trimmingCharacters(in: .whitespacesAndNewlines)
    // Strip leading time patterns
    if let r = try? NSRegularExpression(pattern: "^(?i)\\d{1,2}[:-]\\d+\\s*(?:AM|PM)?\\s*", options: []),
       let m = r.firstMatch(in: d, range: NSRange(d.startIndex..., in: d)),
       let mr = Range(m.range, in: d) {
        d = String(d[mr.upperBound...])
    }
    // Strip trailing punctuation
    while d.hasSuffix("'.") || d.hasSuffix("'.") || d.hasSuffix(".") || d.hasSuffix("'") {
        d = String(d.dropLast())
    }
    return d.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Compute word overlap fraction between two descriptions.
private func descOverlap(_ a: String, _ b: String) -> Double {
    let aWords = Set(a.lowercased().split(whereSeparator: \.isWhitespace).map(String.init))
    let bWords = Set(b.lowercased().split(whereSeparator: \.isWhitespace).map(String.init))
    let allWords = aWords.union(bWords)
    guard !allWords.isEmpty else { return 1.0 }
    let common = aWords.intersection(bWords).count
    return Double(common) / Double(allWords.count)
}

// MARK: - Deduplication

private func deduplicateEvents(_ events: [RawEvent]) -> [RawEvent] {
    guard !events.isEmpty else { return [] }

    var groups: [String: [RawEvent]] = [:]
    for event in events {
        let key = "\(event.month)-\(event.day)"
        groups[key, default: []].append(event)
    }

    var result: [RawEvent] = []
    for (_, group) in groups {
        if group.count == 1 { result.append(group[0]); continue }

        var merged: [RawEvent] = []
        var used = Set<Int>()

        for i in 0..<group.count {
            if used.contains(i) { continue }
            var best = group[i]
            for j in (i + 1)..<group.count {
                if used.contains(j) { continue }
                let other = group[j]
                if let bh = best.startHour, let oh = other.startHour {
                    if abs(bh * 60 + best.startMinute - oh * 60 - other.startMinute) <= 120 {
                        // Merge: prefer higher-priority source overall, best description by quality
                        let descs = [best.descriptionText, other.descriptionText]
                        if other.source < best.source {
                            best = other
                        }
                        // Combine descriptions if they have complementary info
                        let cleanDescs = descs.map { cleanDescForMerge($0) }.filter { !$0.isEmpty }
                        if cleanDescs.count == 2 && descOverlap(cleanDescs[0], cleanDescs[1]) < 0.3 {
                            // Low overlap = complementary info, combine them
                            let ranked = cleanDescs.sorted { descQuality($0) > descQuality($1) }
                            best.descriptionText = ranked.joined(separator: " ")
                        } else {
                            let ranked = descs.sorted { descQuality($0) > descQuality($1) }
                            best.descriptionText = ranked[0]
                        }
                        // Caption time override
                        if other.source == .caption {
                            best.startHour = other.startHour
                            best.startMinute = other.startMinute
                            best.endHour = other.endHour
                            best.endMinute = other.endMinute
                            best.isMidnightEnd = other.isMidnightEnd
                        }
                        used.insert(j)
                    }
                } else if best.startHour == nil && other.startHour != nil {
                    best.startHour = other.startHour; best.startMinute = other.startMinute
                    best.endHour = other.endHour; best.endMinute = other.endMinute
                    best.isMidnightEnd = other.isMidnightEnd
                    if other.descriptionText.count > best.descriptionText.count { best.descriptionText = other.descriptionText }
                    used.insert(j)
                }
            }
            used.insert(i)
            merged.append(best)
        }
        result.append(contentsOf: merged)
    }
    return result
}

// MARK: - Year Inference

private func inferYear(month: Int, day: Int, currentYear: Int, currentDate: Date) -> Int {
    let currentMonth = Calendar.current.component(.month, from: currentDate)
    if month < currentMonth - 2 { return currentYear + 1 }
    return currentYear
}

// MARK: - Output Formatting

private func formatEvent(_ raw: RawEvent, currentYear: Int, currentDate: Date) -> ExtractedEvent? {
    let year = raw.year ?? currentYear

    if raw.dateOnly {
        let start = fmtDate(year: year, month: raw.month, day: raw.day)
        let end = raw.endDay.map { fmtDate(year: year, month: raw.endMonth ?? raw.month, day: $0) }
        return ExtractedEvent(datetimeStart: start, datetimeEnd: end, description: raw.descriptionText)
    }

    guard let sh = raw.startHour else { return nil }
    let start = fmtDatetime(year: year, month: raw.month, day: raw.day, hour: sh, minute: raw.startMinute)

    var end: String? = nil
    if let eh = raw.endHour {
        if raw.isMidnightEnd, let nd = nextDay(year: year, month: raw.month, day: raw.day) {
            end = fmtDatetime(year: nd.0, month: nd.1, day: nd.2, hour: 0, minute: 0)
        } else if eh < sh, let nd = nextDay(year: year, month: raw.month, day: raw.day) {
            end = fmtDatetime(year: nd.0, month: nd.1, day: nd.2, hour: eh, minute: raw.endMinute)
        } else {
            end = fmtDatetime(year: year, month: raw.month, day: raw.day, hour: eh, minute: raw.endMinute)
        }
    }

    return ExtractedEvent(datetimeStart: start, datetimeEnd: end, description: raw.descriptionText)
}

private func fmtDatetime(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> String {
    String(format: "%04d-%02d-%02d %02d:%02d", year, month, day, hour, minute)
}

private func fmtDate(year: Int, month: Int, day: Int) -> String {
    String(format: "%04d-%02d-%02d", year, month, day)
}

private func nextDay(year: Int, month: Int, day: Int) -> (Int, Int, Int)? {
    var c = DateComponents(); c.year = year; c.month = month; c.day = day
    guard let d = Calendar.current.date(from: c),
          let n = Calendar.current.date(byAdding: .day, value: 1, to: d) else { return nil }
    let cal = Calendar.current
    return (cal.component(.year, from: n), cal.component(.month, from: n), cal.component(.day, from: n))
}
