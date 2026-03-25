/// EventExtractionService.swift
/// ============================
/// Extracts structured date/time events from unstructured text sources using
/// Apple's NSDataDetector for date recognition, supplemented by regex for
/// time ranges and structured text patterns.
///
/// ## Approach: NSDataDetector (Experiment B)
/// NSDataDetector handles full date expressions ("March 4th", "7 de abril de 2026",
/// "WEDNESDAY, MARCH 25 | 8 PM EST"). Regex supplements for time ranges ("7-11pm",
/// "7-Midnite"), structured caption lines, and edge cases.
///
/// ## Pipeline
/// ```
/// Inputs → Preprocess → Strategy Selection → Date/Time Extraction
///        → Event Assembly → Dedup → Sort → Output
/// ```
///
/// Three parsing strategies are selected based on input shape:
/// 1. **Structured Caption** — "Apr. 2, 7-8PM: description" lines (Yu and Me pattern)
/// 2. **Multi-Event Flyer** — day-of-week + date headers (DDOOLL pattern)
/// 3. **Single/Few Event** — NSDataDetector across all sources (most real posts)

import Foundation

// MARK: - Public API

enum EventExtractionService {

    /// Extracts structured events from unstructured text sources.
    ///
    /// - Parameters:
    ///   - ocrTexts: Array of text strings recognized from images via OCR.
    ///   - altTexts: Array of image alt text strings from the page HTML.
    ///   - caption: The post caption text.
    ///   - currentDate: The current date, used to infer the year for dates that omit it.
    /// - Returns: Array of extracted events with start/end datetimes and descriptions,
    ///   sorted chronologically.
    static func extractEvents(
        ocrTexts: [String],
        altTexts: [String],
        caption: String,
        currentDate: Date
    ) -> [ExtractedEvent] {
        let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let nonEmptyOCR = ocrTexts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let nonEmptyAlt = altTexts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        // 1. Early exit: nothing to work with
        guard !nonEmptyOCR.isEmpty || !nonEmptyAlt.isEmpty || !trimmedCaption.isEmpty else {
            return []
        }

        // 2. Past-event detection
        if isPastEventRecap(caption: trimmedCaption, altTexts: nonEmptyAlt, currentDate: currentDate) {
            return []
        }

        // 3. Try structured caption parsing (Yu and Me Books pattern)
        if let events = parseStructuredCaption(trimmedCaption, currentDate: currentDate), events.count >= 3 {
            return events.map { formatEvent($0, currentDate: currentDate) }
                .sorted { $0.datetimeStart < $1.datetimeStart }
        }

        // 4. Typo correction from caption
        let typoCorrection = detectTypoCorrection(in: trimmedCaption)

        // 5. Try flyer parsing (multi-event with day-of-week headers)
        let combinedOCR = ocrTexts.joined(separator: "\n")
        let flyerEvents = parseFlyerText(normalizeText(combinedOCR), currentDate: currentDate)
        if flyerEvents.count >= 2 {
            return flyerEvents.map { formatEvent($0, currentDate: currentDate) }
                .sorted { $0.datetimeStart < $1.datetimeStart }
        }

        // 6. Check for multi-day date range (Big Apple Tango pattern)
        let allText = (ocrTexts + [trimmedCaption]).joined(separator: "\n")
        if let rangeEvent = detectDateRangeEvent(in: allText, ocrTexts: nonEmptyOCR, caption: trimmedCaption, currentDate: currentDate) {
            return [formatEvent(rangeEvent, currentDate: currentDate)]
        }

        // 7. Single/few event extraction
        let rawEvents = parseSingleEvents(
            ocrTexts: nonEmptyOCR, altTexts: nonEmptyAlt, caption: trimmedCaption,
            currentDate: currentDate, typoCorrection: typoCorrection
        )

        guard !rawEvents.isEmpty else { return [] }

        // 8. Deduplicate, format, sort
        let deduped = deduplicateEvents(rawEvents)
        return deduped.map { formatEvent($0, currentDate: currentDate) }
            .sorted { $0.datetimeStart < $1.datetimeStart }
    }
}

// MARK: - Internal Types

extension EventExtractionService {

    /// Intermediate event representation before final formatting.
    private struct RawEvent {
        var date: DateComponents
        var startTime: (hour: Int, minute: Int)?
        var endTime: (hour: Int, minute: Int)?
        var endDate: DateComponents?
        var description: String
        var dateOnly: Bool = false
    }

    /// A parsed time range like "7-11pm" or "8PM - 12AM".
    private struct TimeRange {
        let startHour: Int
        let startMinute: Int
        let endHour: Int
        let endMinute: Int
        let isEndMidnight: Bool
    }
}

// MARK: - Step 1: Past-Event Detection

extension EventExtractionService {

    /// Returns true if the post is a recap of a past event, not a future event announcement.
    private static func isPastEventRecap(caption: String, altTexts: [String], currentDate: Date) -> Bool {
        let lowerCaption = caption.lowercased()
        let pastIndicators = ["last night", "last week", "last weekend", "came out last",
                              "who came out", "thank you to the incredible crowd"]
        let hasPastIndicator = pastIndicators.contains { lowerCaption.contains($0) }
        guard hasPastIndicator else { return false }

        // Check if any alt text mentions a date on or before currentDate
        let calendar = Calendar.current
        let currentComps = calendar.dateComponents([.year, .month, .day], from: currentDate)
        for alt in altTexts {
            if let altDate = detectFirstDate(in: alt, currentDate: currentDate) {
                if let aYear = altDate.year, let aMonth = altDate.month, let aDay = altDate.day,
                   let cYear = currentComps.year, let cMonth = currentComps.month, let cDay = currentComps.day {
                    let altVal = aYear * 10000 + aMonth * 100 + aDay
                    let curVal = cYear * 10000 + cMonth * 100 + cDay
                    if altVal <= curVal { return true }
                }
            }
        }
        // Even without alt text date confirmation, strong past indicators are enough
        return hasPastIndicator && lowerCaption.contains("last night")
    }
}

// MARK: - Step 2: Text Normalization

extension EventExtractionService {

    /// Normalizes dashes and whitespace for consistent parsing.
    private static func normalizeText(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "\u{2013}", with: "-") // en-dash
        result = result.replacingOccurrences(of: "\u{2014}", with: "-") // em-dash
        result = result.replacingOccurrences(of: "\u{2018}", with: "'") // left single quote
        result = result.replacingOccurrences(of: "\u{2019}", with: "'") // right single quote
        return result
    }
}

// MARK: - Step 3a: Structured Caption Parser

extension EventExtractionService {

    /// Parses captions with repeated "Apr. N, time: description" lines.
    /// Returns nil if the caption doesn't match this pattern.
    private static func parseStructuredCaption(_ caption: String, currentDate: Date) -> [RawEvent]? {
        let normalized = normalizeText(caption)
        let lines = normalized.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        // Pattern: "Apr. 2, 7-8PM: ..." or "Apr. 12, 12-4PM: ..."
        let linePattern = #"(?i)^(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\.?\s+(\d{1,2}),?\s+(.+)"#
        guard let lineRegex = try? NSRegularExpression(pattern: linePattern) else { return nil }

        var events: [RawEvent] = []

        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = lineRegex.firstMatch(in: line, range: range) else { continue }

            guard let monthRange = Range(match.range(at: 1), in: line),
                  let dayRange = Range(match.range(at: 2), in: line),
                  let restRange = Range(match.range(at: 3), in: line) else { continue }

            let monthStr = String(line[monthRange])
            let dayStr = String(line[dayRange])
            let rest = String(line[restRange])

            guard let month = parseMonthName(monthStr), let day = Int(dayStr) else { continue }

            let year = Calendar.current.component(.year, from: currentDate)
            let dateComps = DateComponents(year: year, month: month, day: day)

            // Extract time and description from rest
            // Pattern: "7-8PM: description" or "12-4PM: description" or "7:30PM: description"
            let timeDescPattern = #"(?i)^(\d{1,2}(?::\d{2})?)\s*(?:(AM|PM))?\s*(?:-\s*(\d{1,2}(?::\d{2})?)\s*(AM|PM))?\s*:?\s*(.+)"#
            guard let timeDescRegex = try? NSRegularExpression(pattern: timeDescPattern) else { continue }
            let restNS = NSRange(rest.startIndex..., in: rest)
            guard let timeMatch = timeDescRegex.firstMatch(in: rest, range: restNS) else { continue }

            let startTimeStr = Range(timeMatch.range(at: 1), in: rest).map { String(rest[$0]) } ?? ""
            let startAmPm = Range(timeMatch.range(at: 2), in: rest).map { String(rest[$0]).uppercased() }
            let endTimeStr = Range(timeMatch.range(at: 3), in: rest).map { String(rest[$0]) }
            let endAmPm = Range(timeMatch.range(at: 4), in: rest).map { String(rest[$0]).uppercased() }
            let desc = Range(timeMatch.range(at: 5), in: rest).map { String(rest[$0]).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""

            // Parse start time
            let (startH, startM) = parseTimeComponents(startTimeStr)
            // Parse end time
            var endTime: (hour: Int, minute: Int)?
            if let endStr = endTimeStr {
                let (endH, endM) = parseTimeComponents(endStr)
                let resolvedEndAmPm = endAmPm ?? startAmPm ?? "PM"
                let resolvedEndHour = convertTo24Hour(hour: endH, amPm: resolvedEndAmPm)
                endTime = (resolvedEndHour, endM)
            }

            // Resolve start AM/PM
            let resolvedStartAmPm: String
            if let sap = startAmPm {
                resolvedStartAmPm = sap
            } else if let eap = endAmPm {
                if startH == 12 {
                    resolvedStartAmPm = "PM"
                } else if eap == "PM" && startH < 12 {
                    resolvedStartAmPm = inferStartAmPm(startHour: startH, endHour: endTime?.hour ?? startH, endAmPm: eap)
                } else {
                    resolvedStartAmPm = eap
                }
            } else {
                resolvedStartAmPm = "PM"
            }

            let resolvedStartHour = convertTo24Hour(hour: startH, amPm: resolvedStartAmPm)

            let description = cleanStructuredDescription(desc)

            events.append(RawEvent(
                date: dateComps,
                startTime: (resolvedStartHour, startM),
                endTime: endTime,
                description: description
            ))
        }

        return events.count >= 3 ? events : nil
    }

    /// Cleans up a structured caption description: removes trailing metadata.
    private static func cleanStructuredDescription(_ desc: String) -> String {
        var result = desc
        // Remove trailing @mentions and hashtags
        result = result.replacingOccurrences(of: #"\s*@\w+\s*$"#, with: "", options: .regularExpression)
        // Remove trailing period
        if result.hasSuffix(".") { result = String(result.dropLast()) }
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }
}

// MARK: - Step 3b: Multi-Event Flyer Parser

extension EventExtractionService {

    /// Parses flyer-style text with day-of-week + date headers.
    /// Handles garbled OCR day-of-week abbreviations (e.g., "ri" instead of "Fri").
    private static func parseFlyerText(_ text: String, currentDate: Date) -> [RawEvent] {
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        // Match any short word (2-5 chars) followed by " - " and a month name + day.
        // This handles garbled OCR like "ri - March 27th" (should be "Fri").
        let headerPattern = #"(?i)^(\w{2,5})\s*[-–]\s*((?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\s+\d{1,2}.*)$"#
        guard let headerRegex = try? NSRegularExpression(pattern: headerPattern) else { return [] }

        var eventBlocks: [(headerLine: String, bodyLines: [String])] = []

        for (i, line) in lines.enumerated() {
            let nsRange = NSRange(line.startIndex..., in: line)
            if headerRegex.firstMatch(in: line, range: nsRange) != nil {
                var body: [String] = []
                var j = i + 1
                while j < lines.count {
                    let nextNS = NSRange(lines[j].startIndex..., in: lines[j])
                    if headerRegex.firstMatch(in: lines[j], range: nextNS) != nil { break }
                    if !lines[j].isEmpty { body.append(lines[j]) }
                    j += 1
                }
                eventBlocks.append((headerLine: line, bodyLines: body))
            }
        }

        var events: [RawEvent] = []
        let year = Calendar.current.component(.year, from: currentDate)

        for block in eventBlocks {
            let fullText = ([block.headerLine] + block.bodyLines).joined(separator: " ")

            // Extract date using NSDataDetector on the part after the dash
            let dateText = block.headerLine.replacingOccurrences(
                of: #"(?i)^\w{2,5}\s*[-–]\s*"#, with: "", options: .regularExpression)
            guard let dateComps = detectFirstDate(in: dateText, currentDate: currentDate) else { continue }
            var date = dateComps
            date.year = year

            // Extract time range from the full block text
            let timeRange = extractTimeRange(from: fullText)

            // Extract description
            let description = extractFlyerDescription(header: block.headerLine, body: block.bodyLines)

            events.append(RawEvent(
                date: date,
                startTime: timeRange.map { ($0.startHour, $0.startMinute) },
                endTime: timeRange.map { ($0.endHour, $0.endMinute) },
                endDate: nil,
                description: description
            ))
        }

        return events
    }

    /// Extracts event description from a flyer block by removing date prefix and time suffix.
    private static func extractFlyerDescription(header: String, body: [String]) -> String {
        // Remove the word + dash + month + day prefix from header
        let prefixPattern = #"(?i)^\w{2,5}\s*[-–]\s*(?:January|February|March|April|May|June|July|August|September|October|November|December|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\w*\s+\d{1,2}(?:st|nd|rd|th)?\s*"#
        let afterDate = header.replacingOccurrences(of: prefixPattern, with: "", options: .regularExpression)

        var descParts = [afterDate.trimmingCharacters(in: .whitespacesAndNewlines)]
        descParts.append(contentsOf: body)

        var fullDesc = descParts.joined(separator: " ")

        // Remove time range at the end (e.g., "7-11pm", "7-Midnite", "7-10:30pm")
        let timePattern = #"(?i)\s+\d{1,2}(?::\d{2})?\s*(?:AM|PM)?\s*[-–]\s*(?:\d{1,2}(?::\d{2})?\s*(?:AM|PM)|[Mm]id(?:nite|night))\s*$"#
        fullDesc = fullDesc.replacingOccurrences(of: timePattern, with: "", options: .regularExpression)

        // Remove trailing "+" and partial names (e.g., "+ Nic")
        let trailingPlusPattern = #"\s*\+\s*\w+\s*$"#
        fullDesc = fullDesc.replacingOccurrences(of: trailingPlusPattern, with: "", options: .regularExpression)

        // Remove trailing DM/email/inquire lines
        let inquirePattern = #"(?i)\s*To inquire about.*$"#
        fullDesc = fullDesc.replacingOccurrences(of: inquirePattern, with: "", options: .regularExpression)

        return fullDesc.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Step 3c: Single/Few Event Parser

extension EventExtractionService {

    /// Extracts events from posts that don't fit the structured or flyer patterns.
    private static func parseSingleEvents(
        ocrTexts: [String], altTexts: [String], caption: String,
        currentDate: Date, typoCorrection: TimeRange?
    ) -> [RawEvent] {
        let year = Calendar.current.component(.year, from: currentDate)

        let allOCR = ocrTexts.joined(separator: "\n")
        let normalizedOCR = normalizeText(allOCR)
        let normalizedCaption = normalizeText(caption)

        // Try to find dates — prefer OCR, then caption, then alt text, then Spanish
        var dateComps: DateComponents?

        // 1. Try OCR first
        dateComps = detectFirstDate(in: normalizedOCR, currentDate: currentDate)

        // 2. Try caption (filtering out non-event dates)
        if dateComps == nil {
            dateComps = detectFirstEventDate(in: normalizedCaption, currentDate: currentDate)
        }

        // 3. Try alt text (filtering out metadata "Photo by ... on DATE")
        if dateComps == nil {
            for alt in altTexts {
                let cleaned = stripAltTextMetadata(alt)
                if let d = detectFirstDate(in: normalizeText(cleaned), currentDate: currentDate) {
                    dateComps = d
                    break
                }
            }
        }

        // 4. Try Spanish date pattern
        if dateComps == nil {
            let allText = (ocrTexts + [caption]).joined(separator: "\n")
            dateComps = detectSpanishDate(in: allText)
        }

        guard var date = dateComps else { return [] }
        date.year = date.year ?? year

        // Extract time — typo correction overrides everything
        var startTime: (hour: Int, minute: Int)?
        var endTime: (hour: Int, minute: Int)?

        if let correction = typoCorrection {
            startTime = (correction.startHour, correction.startMinute)
            endTime = (correction.endHour, correction.endMinute)
        } else {
            // Try dual timezone first
            let allText = (ocrTexts + [caption]).joined(separator: "\n")
            if let tzTime = extractDualTimezone(from: allText) {
                startTime = tzTime
            }

            // Try time range from OCR/caption
            if startTime == nil {
                if let tr = extractTimeRange(from: normalizedOCR) {
                    startTime = (tr.startHour, tr.startMinute)
                    endTime = (tr.endHour, tr.endMinute)
                } else if let tr = extractTimeRange(from: normalizedCaption) {
                    startTime = (tr.startHour, tr.startMinute)
                    endTime = (tr.endHour, tr.endMinute)
                }
            }

            // Try standalone time from various sources
            if startTime == nil {
                if let st = extractStandaloneTime(from: normalizedCaption) {
                    startTime = st
                } else if let st = extractStandaloneTime(from: normalizedOCR) {
                    startTime = st
                }
            }

            // Check for "Puertas" / doors time (Spanish events)
            let puertasTime = extractPuertasTime(from: (ocrTexts + [caption]).joined(separator: "\n"))
            if let pt = puertasTime {
                startTime = pt
                endTime = nil
            }

            // If still no time, try NSDataDetector time extraction
            if startTime == nil {
                let allSources = normalizedOCR + "\n" + normalizedCaption
                if let nsdTime = extractTimeFromNSDataDetector(in: allSources, currentDate: currentDate) {
                    startTime = nsdTime
                }
            }
        }

        // Extract description
        let description = extractSingleEventDescription(
            ocrTexts: ocrTexts, caption: caption
        )

        guard !description.isEmpty else { return [] }

        return [RawEvent(
            date: date,
            startTime: startTime,
            endTime: endTime,
            description: description
        )]
    }

    /// Extracts a description for single-event posts by combining OCR title and caption title.
    /// Uses both sources so the fuzzy matcher (50% word overlap) gets enough matching words.
    private static func extractSingleEventDescription(ocrTexts: [String], caption: String) -> String {
        let normalizedCaption = normalizeText(caption)

        // If caption starts with a typo correction, skip that line
        var captionForDesc = normalizedCaption
        if captionForDesc.lowercased().contains("***typo") || captionForDesc.lowercased().contains("****typo") {
            let lines = captionForDesc.components(separatedBy: "\n")
            captionForDesc = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Get OCR title lines
        let ocrCombined = normalizeText(ocrTexts.joined(separator: "\n"))
        let ocrLines = ocrCombined.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let meaningfulOCRLines = ocrLines.filter { line in
            line.count >= 3 && !isOCRNoise(line)
        }

        let ocrTitle = extractEventTitle(from: meaningfulOCRLines)

        // Get caption title (first 2 non-empty, non-metadata lines)
        let captionTitle = extractCaptionTitle(from: captionForDesc)

        // Decide strategy:
        // If OCR title is mostly noise (short, garbled), prefer caption
        // If caption is very long (a paragraph), prefer concise OCR title
        // Otherwise, combine for best fuzzy-match coverage
        let ocrQuality = assessTitleQuality(ocrTitle)
        let captionQuality = assessTitleQuality(captionTitle)

        if ocrQuality < 2 && captionQuality >= 2 {
            return captionTitle
        }
        if captionQuality < 2 && ocrQuality >= 2 {
            return ocrTitle
        }
        if !ocrTitle.isEmpty && !captionTitle.isEmpty {
            // Combine both for maximum fuzzy-match coverage
            return "\(ocrTitle) \(captionTitle)"
        }
        return captionTitle.isEmpty ? ocrTitle : captionTitle
    }

    /// Extracts the first 2 non-empty, non-metadata lines from a caption as a title.
    private static func extractCaptionTitle(from caption: String) -> String {
        let lines = caption.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var titleLines: [String] = []
        for line in lines {
            let lower = line.lowercased()
            // Skip metadata lines
            if lower.contains("#") && lower.hasPrefix("#") { continue }
            if lower.contains("rsvp") || lower.contains("register") { continue }
            if lower.contains("tinyurl") || lower.contains("bit.ly") { continue }
            // Skip lines that are just times/dates
            if line.range(of: #"(?i)^(📅|⏰|📍|🔗|🗓️)"#, options: .regularExpression) != nil { continue }

            // Clean emoji
            let cleaned = removeEmoji(line).trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.count < 3 { continue }

            titleLines.append(cleaned)
            if titleLines.count >= 2 { break }
        }

        return titleLines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Counts meaningful words (4+ characters) in a title string. Returns the count as a quality score.
    private static func assessTitleQuality(_ title: String) -> Int {
        let words = title.lowercased().split(whereSeparator: \.isWhitespace)
        return words.filter { $0.count >= 4 }.count
    }

    /// Removes emoji characters from a string.
    private static func removeEmoji(_ text: String) -> String {
        text.unicodeScalars.filter { !$0.properties.isEmojiPresentation }.map(String.init).joined()
    }
}

// MARK: - Step 4: NSDataDetector Date Detection

extension EventExtractionService {

    /// Detects the first date in text using NSDataDetector, skipping relative references
    /// like "today" or "tomorrow" that resolve to the current date rather than an event date.
    private static func detectFirstDate(in text: String, currentDate: Date) -> DateComponents? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return nil
        }
        let nsRange = NSRange(text.startIndex..., in: text)
        var result: DateComponents?

        // Relative date words that NSDataDetector resolves to today/tomorrow — skip these.
        let relativeWords: Set<String> = ["today", "now", "tonight", "tomorrow", "yesterday"]

        detector.enumerateMatches(in: text, options: [], range: nsRange) { match, _, stop in
            guard let match = match, let date = match.date,
                  let swiftRange = Range(match.range, in: text) else { return }

            let matchedText = String(text[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip relative date references
            if relativeWords.contains(matchedText.lowercased()) { return }

            let calendar = Calendar.current
            var comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)

            // Override year if the text doesn't contain an explicit 4-digit year
            let hasExplicitYear = matchedText.range(of: #"\d{4}"#, options: .regularExpression) != nil
            if !hasExplicitYear {
                comps.year = calendar.component(.year, from: currentDate)
            }

            // We only want the date part, not time (time is handled separately)
            comps.hour = nil
            comps.minute = nil

            result = comps
            stop.pointee = true
        }

        return result
    }

    /// Detects a date in text, filtering out non-event dates like deadlines.
    private static func detectFirstEventDate(in text: String, currentDate: Date) -> DateComponents? {
        let lines = text.components(separatedBy: "\n")
        for line in lines {
            let lower = line.lowercased()
            if lower.contains("deadline") || lower.contains("early bird") { continue }
            if let date = detectFirstDate(in: line, currentDate: currentDate) {
                return date
            }
        }
        return nil
    }

    /// Detects Spanish-format dates like "7 de abril de 2026".
    private static func detectSpanishDate(in text: String) -> DateComponents? {
        let pattern = #"(?i)(\d{1,2})\s+de\s+(enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|octubre|noviembre|diciembre)\s+de\s+(\d{4})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: nsRange) else { return nil }

        guard let dayRange = Range(match.range(at: 1), in: text),
              let monthRange = Range(match.range(at: 2), in: text),
              let yearRange = Range(match.range(at: 3), in: text) else { return nil }

        let day = Int(text[dayRange])
        let monthStr = String(text[monthRange]).lowercased()
        let year = Int(text[yearRange])

        let spanishMonths = ["enero": 1, "febrero": 2, "marzo": 3, "abril": 4, "mayo": 5,
                             "junio": 6, "julio": 7, "agosto": 8, "septiembre": 9,
                             "octubre": 10, "noviembre": 11, "diciembre": 12]
        guard let month = spanishMonths[monthStr] else { return nil }

        return DateComponents(year: year, month: month, day: day)
    }

    /// Extracts a time that NSDataDetector parsed as part of a date expression.
    private static func extractTimeFromNSDataDetector(in text: String, currentDate: Date) -> (hour: Int, minute: Int)? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return nil
        }
        let nsRange = NSRange(text.startIndex..., in: text)
        var result: (hour: Int, minute: Int)?

        detector.enumerateMatches(in: text, options: [], range: nsRange) { match, _, stop in
            guard let match = match, let date = match.date else { return }
            let calendar = Calendar.current
            let hour = calendar.component(.hour, from: date)
            let minute = calendar.component(.minute, from: date)
            // Only use if it looks like a real time (not midnight default)
            if hour != 0 || minute != 0 {
                result = (hour, minute)
                stop.pointee = true
            }
        }

        return result
    }
}

// MARK: - Step 5: Time Extraction (Regex)

extension EventExtractionService {

    /// Extracts a time range like "7-11pm", "7-Midnite", "8PM - 12AM", "11:30AM-12:30PM".
    /// Uses alternation for the end part so "7-Midnite" (no digit before Midnite) is handled.
    private static func extractTimeRange(from text: String) -> TimeRange? {
        // Two alternatives for the end of the range:
        //   (a) digits + AM/PM: "11pm", "12AM", "10:30pm"
        //   (b) Midnite/midnight with no preceding digits
        let pattern = #"(?i)(\d{1,2}(?::\d{2})?)\s*(AM|PM)?\s*[-–]\s*(?:(\d{1,2}(?::\d{2})?)\s*(AM|PM)|([Mm]id(?:nite|night)))"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: nsRange) else { return nil }

        guard let startRange = Range(match.range(at: 1), in: text) else { return nil }

        let startStr = String(text[startRange])
        let startAmPm = Range(match.range(at: 2), in: text).map { String(text[$0]).uppercased() }

        let (startH, startM) = parseTimeComponents(startStr)

        // Check which alternative matched for end
        let isMidniteEnd = match.range(at: 5).location != NSNotFound
        let isDigitEnd = match.range(at: 3).location != NSNotFound

        let resolvedEndHour: Int
        let resolvedEndMinute: Int
        let isEndMidnight: Bool

        if isMidniteEnd {
            // "7-Midnite" pattern
            resolvedEndHour = 0
            resolvedEndMinute = 0
            isEndMidnight = true
        } else if isDigitEnd {
            // "7-11pm" pattern
            let endStr = Range(match.range(at: 3), in: text).map { String(text[$0]) } ?? "0"
            let endAmPm = Range(match.range(at: 4), in: text).map { String(text[$0]).uppercased() }
            let (endH, endM) = parseTimeComponents(endStr)
            resolvedEndHour = convertTo24Hour(hour: endH, amPm: endAmPm ?? "PM")
            resolvedEndMinute = endM
            isEndMidnight = (resolvedEndHour == 0 && resolvedEndMinute == 0)
        } else {
            return nil
        }

        // Resolve start AM/PM
        let resolvedStartAmPm: String
        if let sap = startAmPm {
            resolvedStartAmPm = sap
        } else if isEndMidnight {
            resolvedStartAmPm = "PM"
        } else if isDigitEnd {
            let endAmPm = Range(match.range(at: 4), in: text).map { String(text[$0]).uppercased() } ?? "PM"
            resolvedStartAmPm = inferStartAmPm(startHour: startH, endHour: resolvedEndHour, endAmPm: endAmPm)
        } else {
            resolvedStartAmPm = "PM"
        }

        let resolvedStartHour = convertTo24Hour(hour: startH, amPm: resolvedStartAmPm)

        return TimeRange(
            startHour: resolvedStartHour, startMinute: startM,
            endHour: resolvedEndHour, endMinute: resolvedEndMinute,
            isEndMidnight: isEndMidnight
        )
    }

    /// Extracts a standalone time like "6:00 PM", "10PM", "7pm" — not part of a range.
    private static func extractStandaloneTime(from text: String) -> (hour: Int, minute: Int)? {
        let pattern = #"(?i)(?<!\d[-–])(\d{1,2}(?::\d{2})?)\s*(AM|PM)\b(?!\s*[-–]\s*\d)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: nsRange) else { return nil }

        guard let timeRange = Range(match.range(at: 1), in: text),
              let ampmRange = Range(match.range(at: 2), in: text) else { return nil }

        let timeStr = String(text[timeRange])
        let amPm = String(text[ampmRange]).uppercased()
        let (h, m) = parseTimeComponents(timeStr)
        return (convertTo24Hour(hour: h, amPm: amPm), m)
    }

    /// Extracts the Eastern time from dual-timezone expressions like "4 PM PT / 7 ET".
    private static func extractDualTimezone(from text: String) -> (hour: Int, minute: Int)? {
        let pattern = #"(?i)(\d{1,2}(?::\d{2})?)\s*(AM|PM)?\s*(?:PT|PST|PDT)\s*/\s*(\d{1,2}(?::\d{2})?)\s*(AM|PM)?\s*(?:ET|EST|EDT)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: nsRange) else { return nil }

        guard let etTimeRange = Range(match.range(at: 3), in: text) else { return nil }
        let etTimeStr = String(text[etTimeRange])
        let etAmPm = Range(match.range(at: 4), in: text).map { String(text[$0]).uppercased() }

        let ptAmPm = Range(match.range(at: 2), in: text).map { String(text[$0]).uppercased() }
        let resolvedAmPm = etAmPm ?? ptAmPm ?? "PM"

        let (h, m) = parseTimeComponents(etTimeStr)
        return (convertTo24Hour(hour: h, amPm: resolvedAmPm), m)
    }

    /// Extracts "Puertas: 6:30 p.m." style door times from Spanish event descriptions.
    private static func extractPuertasTime(from text: String) -> (hour: Int, minute: Int)? {
        let pattern = #"(?i)Puertas:\s*(\d{1,2}(?::\d{2})?)\s*(a\.?\s*m\.?|p\.?\s*m\.?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: nsRange) else { return nil }

        guard let timeRange = Range(match.range(at: 1), in: text),
              let ampmRange = Range(match.range(at: 2), in: text) else { return nil }

        let timeStr = String(text[timeRange])
        let amPmRaw = String(text[ampmRange]).replacingOccurrences(of: ".", with: "").replacingOccurrences(of: " ", with: "").uppercased()
        let (h, m) = parseTimeComponents(timeStr)
        return (convertTo24Hour(hour: h, amPm: amPmRaw), m)
    }
}

// MARK: - Step 6: Typo Correction

extension EventExtractionService {

    /// Detects caption typo corrections like "****TYPO - 8PM - 12AM***".
    private static func detectTypoCorrection(in caption: String) -> TimeRange? {
        let pattern = #"(?i)\*+\s*TYPO\s*[-–]?\s*(\d{1,2}(?::\d{2})?)\s*(AM|PM)\s*[-–]\s*(\d{1,2}(?::\d{2})?)\s*(AM|PM)\s*\*+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(caption.startIndex..., in: caption)
        guard let match = regex.firstMatch(in: caption, range: nsRange) else { return nil }

        guard let startRange = Range(match.range(at: 1), in: caption),
              let startAmPmRange = Range(match.range(at: 2), in: caption),
              let endRange = Range(match.range(at: 3), in: caption),
              let endAmPmRange = Range(match.range(at: 4), in: caption) else { return nil }

        let (startH, startM) = parseTimeComponents(String(caption[startRange]))
        let startAmPm = String(caption[startAmPmRange]).uppercased()
        let (endH, endM) = parseTimeComponents(String(caption[endRange]))
        let endAmPm = String(caption[endAmPmRange]).uppercased()

        let isEndMidnight = (endAmPm == "AM" && endH == 12)
        let resolvedEndHour = isEndMidnight ? 0 : convertTo24Hour(hour: endH, amPm: endAmPm)

        return TimeRange(
            startHour: convertTo24Hour(hour: startH, amPm: startAmPm),
            startMinute: startM,
            endHour: resolvedEndHour,
            endMinute: endM,
            isEndMidnight: isEndMidnight
        )
    }
}

// MARK: - Step 7: Date Range Detection

extension EventExtractionService {

    /// Detects multi-day date ranges like "May 14-17, 2026" and returns a date-only RawEvent.
    private static func detectDateRangeEvent(
        in text: String, ocrTexts: [String], caption: String, currentDate: Date
    ) -> RawEvent? {
        let normalized = normalizeText(text)
        let pattern = #"(?i)(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{1,2})\s*[-–]\s*(\d{1,2}),?\s*(\d{4})?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(normalized.startIndex..., in: normalized)
        guard let match = regex.firstMatch(in: normalized, range: nsRange) else { return nil }

        guard let monthRange = Range(match.range(at: 1), in: normalized),
              let startDayRange = Range(match.range(at: 2), in: normalized),
              let endDayRange = Range(match.range(at: 3), in: normalized) else { return nil }

        let monthStr = String(normalized[monthRange])
        let startDay = Int(normalized[startDayRange])
        let endDay = Int(normalized[endDayRange])
        let year: Int
        if match.range(at: 4).location != NSNotFound,
           let yearRange = Range(match.range(at: 4), in: normalized),
           let y = Int(normalized[yearRange]) {
            year = y
        } else {
            year = Calendar.current.component(.year, from: currentDate)
        }

        guard let month = parseMonthName(monthStr), let sd = startDay, let ed = endDay else { return nil }
        guard ed > sd else { return nil }

        let description = extractMultiDayDescription(ocrTexts: ocrTexts, caption: caption)

        return RawEvent(
            date: DateComponents(year: year, month: month, day: sd),
            startTime: nil,
            endTime: nil,
            endDate: DateComponents(year: year, month: month, day: ed),
            description: description,
            dateOnly: true
        )
    }

    /// Extracts a description for multi-day events from the caption's title line.
    /// Cleans "— Early Bird Reminder" suffixes rather than skipping the line.
    private static func extractMultiDayDescription(ocrTexts: [String], caption: String) -> String {
        let lines = caption.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in lines {
            let lower = line.lowercased()
            if lower.contains("#") && lower.hasPrefix("#") { continue }
            if lower.hasPrefix("📅") || lower.hasPrefix("🔗") || lower.hasPrefix("✔") { continue }
            if lower.hasPrefix("don't miss") || lower.hasPrefix("secure your") { continue }
            if lower.hasPrefix("🌟") || lower.hasPrefix("💥") || lower.hasPrefix("🙌") { continue }

            // Clean emoji and whitespace
            var cleaned = removeEmoji(line).trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.count < 5 { continue }
            if cleaned.contains("@") && cleaned.count < 20 { continue }

            // Remove " — Early Bird Reminder" or similar suffixes
            let suffixPattern = #"\s*[-–—]\s*(?:Early Bird|Reminder|Tickets|RSVP).*$"#
            cleaned = cleaned.replacingOccurrences(of: suffixPattern, with: "", options: .regularExpression)
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

            if cleaned.count >= 5 {
                return cleaned
            }
        }

        return ""
    }
}

// MARK: - Step 8: Deduplication

extension EventExtractionService {

    /// Deduplicates events with the same date and start time, keeping the best description.
    private static func deduplicateEvents(_ events: [RawEvent]) -> [RawEvent] {
        var seen: [String: RawEvent] = [:]
        for event in events {
            let key: String
            if let st = event.startTime {
                key = "\(event.date.month ?? 0)-\(event.date.day ?? 0)-\(st.hour)-\(st.minute)"
            } else {
                key = "\(event.date.month ?? 0)-\(event.date.day ?? 0)-none"
            }
            if let existing = seen[key] {
                if event.description.count > existing.description.count {
                    seen[key] = event
                }
            } else {
                seen[key] = event
            }
        }
        return Array(seen.values)
    }
}

// MARK: - Step 9: Formatting

extension EventExtractionService {

    /// Converts a RawEvent to a final ExtractedEvent with formatted datetime strings.
    private static func formatEvent(_ raw: RawEvent, currentDate: Date) -> ExtractedEvent {
        let year = raw.date.year ?? Calendar.current.component(.year, from: currentDate)
        let month = raw.date.month ?? 1
        let day = raw.date.day ?? 1

        let startDateStr = String(format: "%04d-%02d-%02d", year, month, day)

        let datetimeStart: String
        if raw.dateOnly {
            datetimeStart = startDateStr
        } else if let st = raw.startTime {
            datetimeStart = String(format: "%@ %02d:%02d", startDateStr, st.hour, st.minute)
        } else {
            datetimeStart = startDateStr
        }

        let datetimeEnd: String?
        if raw.dateOnly, let ed = raw.endDate {
            let ey = ed.year ?? year
            let em = ed.month ?? month
            let edDay = ed.day ?? day
            datetimeEnd = String(format: "%04d-%02d-%02d", ey, em, edDay)
        } else if let et = raw.endTime {
            if et.hour == 0 && et.minute == 0 {
                // Midnight = next calendar day at 00:00
                let calendar = Calendar.current
                let dateComps = DateComponents(year: year, month: month, day: day)
                if let baseDate = calendar.date(from: dateComps) {
                    let nextDay = calendar.date(byAdding: .day, value: 1, to: baseDate)!
                    let nextComps = calendar.dateComponents([.year, .month, .day], from: nextDay)
                    datetimeEnd = String(format: "%04d-%02d-%02d 00:00",
                                         nextComps.year!, nextComps.month!, nextComps.day!)
                } else {
                    datetimeEnd = String(format: "%@ 00:00", startDateStr)
                }
            } else {
                datetimeEnd = String(format: "%@ %02d:%02d", startDateStr, et.hour, et.minute)
            }
        } else {
            datetimeEnd = nil
        }

        return ExtractedEvent(
            datetimeStart: datetimeStart,
            datetimeEnd: datetimeEnd,
            description: raw.description
        )
    }
}

// MARK: - Utility Helpers

extension EventExtractionService {

    /// Parses a time string like "7", "10", "6:30", "11:30" into (hour, minute).
    private static func parseTimeComponents(_ str: String) -> (hour: Int, minute: Int) {
        let parts = str.split(separator: ":")
        let hour = Int(parts[0]) ?? 0
        let minute = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
        return (hour, minute)
    }

    /// Converts 12-hour time to 24-hour. "PM" adds 12 (except 12 PM stays 12). "AM" keeps as-is (except 12 AM = 0).
    private static func convertTo24Hour(hour: Int, amPm: String) -> Int {
        if amPm == "AM" {
            return hour == 12 ? 0 : hour
        } else { // PM
            return hour == 12 ? 12 : hour + 12
        }
    }

    /// Infers AM/PM for the start of a range given the end's AM/PM.
    private static func inferStartAmPm(startHour: Int, endHour: Int, endAmPm: String) -> String {
        if endAmPm == "PM" {
            if startHour == 12 { return "PM" }
            if startHour > endHour % 12 && startHour != 12 { return "AM" }
            return "PM"
        }
        return endAmPm
    }

    /// Parses month name (full or abbreviated) to month number.
    private static func parseMonthName(_ name: String) -> Int? {
        let lower = name.lowercased().prefix(3)
        let months = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
                      "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12]
        return months[String(lower)]
    }

    /// Returns true if a line appears to be OCR noise (mostly symbols, very few letters).
    private static func isOCRNoise(_ line: String) -> Bool {
        let stripped = line.replacingOccurrences(of: #"[^a-zA-Z]"#, with: "", options: .regularExpression)
        return stripped.count < 3
    }

    /// Strips alt text metadata prefix like "Photo by X on March 25, 2026. May be..."
    private static func stripAltTextMetadata(_ alt: String) -> String {
        let pattern = #"(?i)^(?:Photo|Video) by .+? on .+?\.\s*"#
        return alt.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }

    /// Extracts event title from meaningful OCR lines, filtering out dates, times, and noise.
    private static func extractEventTitle(from lines: [String]) -> String {
        var titleLines: [String] = []
        // Patterns to exclude: day-of-week, dates with month names, standalone times, years
        let dateTimePattern = #"(?i)^(mon|tue|wed|thu|fri|sat|sun)\w*[\s,]"#
        let monthPattern = #"(?i)^(january|february|march|april|may|june|july|august|september|october|november|december|MARCH|APRIL|MAY)\s+\d"#
        let yearPattern = #"^\d{4}$"#
        let timeOnlyPattern = #"(?i)^\d{1,2}(?::\d{2})?\s*(am|pm)"#

        for line in lines {
            // Skip day-of-week headers
            if line.range(of: dateTimePattern, options: .regularExpression) != nil { continue }
            // Skip month+day dates
            if line.range(of: monthPattern, options: .regularExpression) != nil { continue }
            // Skip standalone years
            if line.range(of: yearPattern, options: .regularExpression) != nil { continue }
            // Skip standalone times
            if line.range(of: timeOnlyPattern, options: .regularExpression) != nil { continue }
            // Skip metadata/links
            if line.lowercased().contains("rsvp") { continue }
            if line.lowercased().contains("register") { continue }
            if line.lowercased().contains("tinyurl") || line.lowercased().contains("bit.ly") { continue }
            if line.lowercased().contains("venmo") || line.lowercased().contains("cashapp") { continue }
            // Skip lines starting with symbols
            if line.hasPrefix("+") || line.hasPrefix("*") || line.hasPrefix("§") { continue }
            // Skip bare @handles
            if line.contains("@") && !line.contains(" ") { continue }
            if line.count < 4 { continue }

            titleLines.append(line)
            if titleLines.count >= 3 { break }
        }

        return titleLines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
