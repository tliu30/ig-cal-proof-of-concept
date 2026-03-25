/// EventExtractionServiceRealPostTests.swift
/// ==========================================
/// Test suite for EventExtractionService using real Instagram post extractions.
///
/// ## Test Organization
/// Tests are organized into five suites covering 11 real-world Instagram posts:
/// 1. Zero Event Posts — non-event content that should produce no events
/// 2. Single Event from Real Posts — six posts each containing exactly one event
/// 3. Multi-Day Date-Only Event — event with date range but no specific times
/// 4. Full Data Multi-Event Flyer — multi-signal input (OCR + alt + caption)
/// 5. Massive Multi-Event Caption — 17 events from a single caption
///
/// ## Data Sources
/// Input data (OCR text, alt text, captions) was extracted from real Instagram posts.
/// Long inputs are loaded from fixture files in test-data/; shorter inputs are inlined.
///
/// ## Contract
/// **DO NOT MODIFY THIS FILE DURING EXPERIMENTS.**
/// Each experiment implements EventExtractionService differently but must pass
/// these same tests. The tests define the expected behavior; the implementation
/// is what varies.

import Foundation
import Testing

@testable import MyFirstiOSApp

// MARK: - Test Utilities

/// Loads a text file from the test-data/ directory relative to this source file.
private func loadTestData(_ filename: String) -> String {
    let thisFile = URL(fileURLWithPath: #filePath)
    let projectRoot = thisFile
        .deletingLastPathComponent() // MyFirstiOSAppTests/
        .deletingLastPathComponent() // project root
    let fileURL = projectRoot.appendingPathComponent("test-data/\(filename)")
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
        fatalError("\(filename) not found at \(fileURL.path)")
    }
    return try! String(contentsOf: fileURL, encoding: .utf8)
}

/// Fixed reference date: 2026-03-25. All tests use this as "today" for year inference.
private let referenceDate: Date = {
    var components = DateComponents()
    components.year = 2026
    components.month = 3
    components.day = 25
    return Calendar.current.date(from: components)!
}()

// MARK: - Fixture Data (loaded from files)

/// Yu and Me Books April events caption (17 events listed).
private let yuAndMeCaption = loadTestData("yuandme-caption.txt")

// MARK: - Zero Event Posts

@Suite("Zero Event Posts")
struct ZeroEventPostTests {

    /// Andrew Bird music video reel — no event information, just a performance clip.
    @Test("Music video reel extracts no events — DWHeslRCICv")
    func musicVideoReel() {
        let results = EventExtractionService.extractEvents(
            ocrTexts: ["POLKA-PAR\ne"],
            altTexts: [],
            caption: "Palindromes through the ages. Some hotshot editing from Bonnaroo to orchestra hall.",
            currentDate: referenceDate
        )
        #expect(results.isEmpty, "Expected no events from a music video reel")
    }

    /// AAFC recap/thank-you post for a past event ("last night"). No future events.
    @Test("Past event recap extracts no events — DWT9awgEeTE")
    func pastEventRecap() {
        let ocrText = """
            WELCOME!
            Building an Asian American Feminist NYC
            Grab some food, mak
            and, we'll get started soon!
            """
        let altText = """
            Photo by ✨Asian Am Feminist Collective on March 25, 2026. \
            May be an image of one or more people, makeup, people standing, \
            office and text that says 'WELCOME! Building an Asian American \
            Feminist NYC Grab some food, mak nd, we'll get started soon !'.
            """
        let caption = """
            ✨THANK YOU to the incredible crowd who came out and filled \
            @woodbine.nyc last night for our panel and community event \
            BUILDING AN ASIAN AMERICAN FEMINIST NYC! We loved meeting and \
            learning alongside so many of you about current issues and how \
            to build power in housing, gender justice, immigration, and \
            community safety for all New Yorkers. Huge thanks to our expert \
            panel featuring. @latchmigopal @whitneyhu Liz OuYang and \
            Rowshon Ara of @drumnyc  for educating us with wisdom, heart, \
            and care. Now everyone go get to know your neighbors! 💜
            """
        let results = EventExtractionService.extractEvents(
            ocrTexts: [ocrText],
            altTexts: [altText, "Photo by ✨Asian Am Feminist Collective on March 25, 2026. May be an image of one or more people, people standing and text."],
            caption: caption,
            currentDate: referenceDate
        )
        #expect(results.isEmpty, "Expected no events from a past event recap post")
    }
}

// MARK: - Single Event Extraction from Real Posts

@Suite("Single Event Extraction from Real Posts")
struct RealPostSingleEventTests {

    /// JVP workshop with dual timezone — uses ET (7 PM) for NYC users.
    /// OCR: "SUNDAY, MARCH 29, 4 PM PT / 7 ET"
    @Test("JVP workshop with timezone conversion — DWM7AK9Evns")
    func jvpWorkshop() {
        let ocrText = """
            TALKING PALESTINE
            at Passover
            AN ANTIZIONIST WORKSHOP ON
            PRACTICING DIFFICULT CONVERSATIONS
            JOIN JVP NEW YORK & JVP BAY AREA ON ZOOM
            SUNDAY, MARCH 29, 4 PM PT / 7 ET
            REGISTER: tinyurl.com/PassoverConvos26
            """
        let altText = """
            Photo by Jewish Voice for Peace Bay Area on March 22, 2026. \
            May be an image of text that says 'TALKING PALESTINE at Passover \
            AN ANTIZIONIST WORKSHOP ON PRACTICING DIFFICULT CONVERSATIONS \
            JOIN JVP NEW YORK & JVP BAY AREA ON ZOOM SUNDAY, MARCH 29, \
            4 PT PT/7ET REGISTER: tihyurl.com/PassoverConvos26 \
            .....・ ........ inrsronomien .... ...... .٠٠٠'.
            """
        let results = EventExtractionService.extractEvents(
            ocrTexts: [ocrText],
            altTexts: [altText],
            caption: "Join us!",
            currentDate: referenceDate
        )
        #expect(results.count == 1, "Expected 1 event, got \(results.count)")
        let expected = ExtractedEvent(
            datetimeStart: "2026-03-29 19:00",
            datetimeEnd: nil,
            description: "Talking Palestine at Passover: An Antizionist Workshop on Practicing Difficult Conversations"
        )
        #expect(
            eventMatches(results.first!, expected: expected),
            "Event mismatch: \(String(describing: results.first))"
        )
    }

    /// Three performing duos at Brothers Wash and Dry — single event, multiple performers.
    @Test("Brothers Wash and Dry with multiple performers — DWO1_myArzG")
    func brothersWashAndDry() {
        let ocrText = """
            Brothers Wash and Dry
            Thurs, March 26" at 7pm
            Paul Sakai & Mark Chinen (Seattle)
            Julie Kim & Lulu West
            Sunjay Jayaram & Evan Crane
            $15 notaflof
            """
        let altText = """
            Photo by Brothers Wash & Dry on March 23, 2026. May be an \
            image of shower and text that says 'BrothersWashand Brothers \
            Wash and Dry Thurs, March 26t at 7pm Paul aSakai&MarkChinen(Setle \
            Sakai & Mark Chinen (Seattle) Julie Kim & Lulu West Sunjay \
            Jayaram & Evan Crane Crane $15 notaflof'.
            """
        let caption = """
            join us for not 1... not 2... but THREE duos this thursday, march 26 at 7pm

            1️⃣ @roykiyo + @machinen.1959
            2️⃣ Julie Kim + @luluwestluluwest
            3️⃣ @sunjayjayaram + @evan.crane_
            """
        let results = EventExtractionService.extractEvents(
            ocrTexts: [ocrText],
            altTexts: [altText],
            caption: caption,
            currentDate: referenceDate
        )
        #expect(results.count == 1, "Expected 1 event, got \(results.count)")
        let expected = ExtractedEvent(
            datetimeStart: "2026-03-26 19:00",
            datetimeEnd: nil,
            description: "Paul Sakai & Mark Chinen, Julie Kim & Lulu West, and Sanay Jayaram & Evan Crane at Brothers Wash and Dry"
        )
        #expect(
            eventMatches(results.first!, expected: expected),
            "Event mismatch: \(String(describing: results.first))"
        )
    }

    /// FRUITFLIES at All Night Skate — caption corrects OCR time "8-12PM" to "8PM - 12AM".
    /// End time midnight = next day 00:00.
    @Test("FRUITFLIES caption corrects OCR time — DWOnARRltPm")
    func fruitflies() {
        let ocr1 = """
            Night
            shate
            APRIL 4,2026
            8-12PM
            ALL NIGHT SKATE
            2026#4R48F$8I~118
            $5-10
            Suggested
            venmo/cashapp @yearoftheteagress
            DJs
            zesty tunes
            all night
            TASHEFF
            POP-UP
            § 1717- —
            NO.AH
            live performance
            STARFRUIT
            + OPEN DECKS SLOTS
            DM @HELIXFANG
            """
        let ocr2 = """
            OPEN DECKS
            We will have 2-3 slots
            for people who want to
            play and practice on
            CDJs, DM @helixfang
            to sign up!
            LIVE
            PERFORMANCE
            NO.ahR
            """
        let caption = """
            ****TYPO - 8PM - 12AM***

            🪰FRUITFLIES 🍌 returns, April 4 at @allnightskate 8-12 AM * on Saturday

            Our NYC pop DJ @tasheffmatthew 🎵 will be joining me playing bops all night (skate.)

            Featuring a popup performance by my esoteric art pop diva @no.ah 👁️‍🗨️

            🚨 We will be featuring 2-3 deck slots for newer DJs who want to play on CDJS. Please dm me if you are interested in playing a 30 min slot ‼️

            5-10 suggested donation (Venmo/cashapp @yearoftheteagress $yearoftheteagress)
            """
        let results = EventExtractionService.extractEvents(
            ocrTexts: [ocr1, ocr2],
            altTexts: [
                "Photo by ℲǝℲǝ / 阿烏 on March 23, 2026. May be an image of poster and text that says 'APRIL 4, 2026 8-12PM ALL NIGHT SKATE'.",
                "Photo by ℲǝℲǝ / 阿烏 on March 23, 2026. May be an image of poster, magazine, card and text that says 'OPEN DECKS'.",
            ],
            caption: caption,
            currentDate: referenceDate
        )
        #expect(results.count == 1, "Expected 1 event, got \(results.count)")
        let expected = ExtractedEvent(
            datetimeStart: "2026-04-04 20:00",
            datetimeEnd: "2026-04-05 00:00",
            description: "FRUITFLIES at All Night Skate"
        )
        #expect(
            eventMatches(results.first!, expected: expected),
            "Event mismatch: \(String(describing: results.first))"
        )
    }

    /// MayDay Strong virtual mass call — virtual/Zoom event.
    /// OCR: "WEDNESDAY, MARCH 25 | 8 PM EST"
    @Test("MayDay virtual mass call — DWPn3BBj4RF")
    func maydayVirtualCall() {
        let ocrText = """
            AFTER NO RINGS,
            WHAT'S NEXT?
            VIRTUAL MASS CALL
            ****
            NO RINGS. NO BILLIONAIRES.
            WEDNESDAY, MARCH 25 | 8 PM EST
            OVE
            BLIC
            RVICES
            PEOPLE OVER
            BILLIONAIRES
            Register: bit.ly/mayday26
            ***
            ***************
            **
            maydaystrong.org
            *********
            WORKERS
            OVER
            BILLIONAIRES
            """
        let altText = """
            Photo by @maydaystrong on March 23, 2026. May be a graphic of \
            poster, magazine and text that says 'AFTER No KINGS, WHAT'S \
            NEXT? VIRTUAL MASS CALL NO KINGS. NO BILLIONAIRES. WEDNESDAY, \
            MARCH 25 8 PM EST Register: bit.ly/mayday26 maydaystrong.org \
            WORKERS OVER BILLIONAIRES'.
            """
        let caption = """
            AFTER KINGS, WHATS NEXT? Join the @maydaystrong coalition made \
            up of unions, organizations, and working people across the nation \
            to learn more #workersoverbillionaires
            """
        let results = EventExtractionService.extractEvents(
            ocrTexts: [ocrText],
            altTexts: [altText],
            caption: caption,
            currentDate: referenceDate
        )
        #expect(results.count == 1, "Expected 1 event, got \(results.count)")
        let expected = ExtractedEvent(
            datetimeStart: "2026-03-25 20:00",
            datetimeEnd: nil,
            description: "After No Kings, What's Next? Virtual Mass Call"
        )
        #expect(
            eventMatches(results.first!, expected: expected),
            "Event mismatch: \(String(describing: results.first))"
        )
    }

    /// Spanish-language podcast launch at Queens Museum.
    /// Doors at 6:30 PM, show at 7:00 PM — uses doors time as datetimeStart.
    @Test("Spanish-language podcast launch — DWT_8OnjsFT")
    func lasReinasDeQueens() {
        let ocrText = """
            RADIO AMBULANTE STUDIOS **iHeartRadio
            PRESENTAN:
            EN EL MUSEO DE QUEENS
            Acompáñanos para una noche para celebrar el estreno oficial de la serie de
            podcast Las Reinas de Queens, conocer a algunas de sus protagonistas y
            honrar a las comunidades que hicieron posible esta historia.
            Lugar: Queens Museum - Flushing Meadows Corona Park, Corona, NY.
            Fecha y hora: 7 de abril de 2026 - Puertas: 6:30 p.m. - Show: 7:00 p.m.
            """
        let altText = """
            Photo by Colectivo Intercultural TRANSgrediendo™ on March 25, 2026. \
            May be an image of poster and text that says 'RAJIO AMBULANTE STUDIOS \
            iHeartRadio PRESENTAN: Reinas DE LAS Queens HISTORIA Y TRANS EN EL \
            MUSEO DE QUEENS Acompáñanos para una noche para celebrar el estreno \
            oficial de la serie de podcast Las Reinas de Queens, conocer a algunas \
            de sus protagonistas y honrar a las comunidades que hicieron posible \
            esta historia. Lugar: Queens Museum -Flushing Meadows Corona Park, \
            Corona, NY. Fecha y hora: 7 de abril de 2026 Puertas: 6:30 p.m. \
            Show: 7:00 p.m.'.
            """
        let caption = """
            Las Reinas de Queens 🔥✨👠❤️

            HISTORIA Y MEMORIA TRANS EN EL MUSEO DE QUEENS

            Radio Ambulante Studios y iHeartRadio te invitan al lanzamiento de su \
            serie podcast: Las Reinas de Queens.

            Una noche especial en el Museo de Queens para celebrar el estreno \
            oficial de la serie, conocer a algunas de sus protagonistas y honrar \
            a las comunidades que hicieron posible esta historia.

            Fecha y hora: 7 de abril de 2026
            Puertas: 6:30 p.m. / Show: 7:00 p.m.
            Lugar: @queensmuseum

            Acompáñanos.
            """
        let results = EventExtractionService.extractEvents(
            ocrTexts: [ocrText],
            altTexts: [altText],
            caption: caption,
            currentDate: referenceDate
        )
        #expect(results.count == 1, "Expected 1 event, got \(results.count)")
        let expected = ExtractedEvent(
            datetimeStart: "2026-04-07 18:30",
            datetimeEnd: nil,
            description: "Las Reinas de Queens: Historia y Memoria Trans en el Museo de Queens"
        )
        #expect(
            eventMatches(results.first!, expected: expected),
            "Event mismatch: \(String(describing: results.first))"
        )
    }

    /// Met Council on Housing volunteer training — date/time from both caption and OCR.
    @Test("Met Council volunteer training — DWT4VwqDJa8")
    func metCouncilTraining() {
        let ocrText = """
            MET COUNCIL ON HOUSING
            Volunteers Needed
            Sign up to become a hotline volunteer today.
            Join our Mutual Aid Volunteer Training
            Where: Met Council Office
            470 Vanderbilt Ave, Brooklyn
            When: Thur, March 26th Time: 6:00 PM
            ALTO AL
            AUMENTO
            DE RENTAL
            Housins Al
            JUSTICES
            Goos СлузЕ
            NOW
            JUSTICIA
            DE INQVILINES
            AHORA!
            MET COUNCIL
            IUNIDAD
            ON HOUSING
            LUCHAI
            HE SURGE
            For more info: Je@metcouncilonhousing.org
            """
        let altText = """
            Photo by Met Council On Housing on March 25, 2026. May be a \
            graphic of poster and text that says 'I MET COUNCIL ON HOUSING \
            Volunteers Needed Sign up to become a hotline volunteer today. \
            Join our Mutual Aid Volunteer Training Where: Met Council Office \
            470 Vanderbilt Ave, Brooklyn Time: 6:00 PM When: Thur, March 26th'.
            """
        let caption = """
            🗣️Come and learn more about the work of Met Council on Housing \
            and how you can provide support/assistance and valuable knowledge \
            to NYC Tenants ☎️

            🗓️Thur, March 26th
            ⏰6:00 PM
            📍Met Council Office, 470 Vanderbilt Ave, Brooklyn
            🔗metcouncilonhousing.org/calendar
            """
        let results = EventExtractionService.extractEvents(
            ocrTexts: [ocrText],
            altTexts: [altText],
            caption: caption,
            currentDate: referenceDate
        )
        #expect(results.count == 1, "Expected 1 event, got \(results.count)")
        let expected = ExtractedEvent(
            datetimeStart: "2026-03-26 18:00",
            datetimeEnd: nil,
            description: "Met Council on Housing Mutual Aid Volunteer Training"
        )
        #expect(
            eventMatches(results.first!, expected: expected),
            "Event mismatch: \(String(describing: results.first))"
        )
    }
}

// MARK: - Multi-Day Date-Only Event

@Suite("Multi-Day Date-Only Event")
struct MultiDayEventTests {

    /// Big Apple Tango Weekend — 4-day event with no specific daily times.
    /// Uses date-only format (no HH:mm) for datetimeStart and datetimeEnd.
    @Test("Big Apple Tango Weekend uses date-only format — DWUE0pZjRvi")
    func bigAppleTangoWeekend() {
        let ocrText = """
            Join us
            For unforgettable Tango Weekend
            www.thobigappletangoweekand.com
            """
        let caption = """
            ✨ The Big Apple Tango Weekend — Early Bird Reminder ✨

            Don't miss your chance to be part of an unforgettable tango \
            experience in New York City 💃🕺

            📅 May 14–17, 2026
            Four days of milongas, music, performances, and connection with \
            dancers from across the country.

            🌟 Featuring special guest artists:
            Jonny Carvajal & Suyay Quiroga
            Ricardo Astrada & Constanza Vieyto

            💥 Early Bird Deadline: March 30 (midnight)
            ✔️ Couples' discount available
            ✔️ Role balance 💪🏼
            ✔️ Limited to 300 dancers for an exceptional dance floor experience

            Secure your spot and be part of something truly special ✨

            🙌🏻 Hosted by Dennis Cante, Tanya Spektor and Renee Rouger

            🔗 Register at the link in bio

            #TangoWeekend #NYCTango #ArgentineTango #Milonga #TangoLife
            """
        let results = EventExtractionService.extractEvents(
            ocrTexts: [ocrText],
            altTexts: [],
            caption: caption,
            currentDate: referenceDate
        )
        #expect(results.count == 1, "Expected 1 event, got \(results.count)")
        let expected = ExtractedEvent(
            datetimeStart: "2026-05-14",
            datetimeEnd: "2026-05-17",
            description: "The Big Apple Tango Weekend"
        )
        #expect(
            eventMatches(results.first!, expected: expected),
            "Event mismatch: \(String(describing: results.first))"
        )
    }
}

// MARK: - Full Data Multi-Event Flyer

@Suite("Full Data Multi-Event Flyer")
struct FullDataMultiEventFlyerTests {

    /// Full OCR text from the DDOOLL event flyer (image 1 of 2).
    /// This is the raw OCR output, slightly different from the simplified event-flyer-ocr.txt.
    static let ocrText = """
        DRINK SPECIALS
        GOOD TIMES
        DDOON
        83 SARATOGA AVE
        TEST KITCHEN
        Wed - March 4th OPEN AUX
        W/ Featured Artist 1 Alkebulan 7-11pm
        Fri - March 13th St. Slayer's Day
        hosted by DJ ILUVDOMRICH 7-Midnite
        Wed - March 18th OPEN AUX
        W/ Special Guest TBA 7-11pm
        ri - March 27th A Caratasrophe PreGame
        Vol.5 with resident DJ Caratasrophe 7-Midnite
        Sat - March 28th Rythms&Release
        Party+JamSession Hoseted By Nelson Bandela + Nic 7-Midnite
        Tues - March 31st M'KAI & friends
        a special evening of music featuring M'vKAI 7-10:30pm
        To inquire about hosting your event with us DM @DDOOLL.2 on instagram or email events@september.com
        """

    /// Alt text from image 1 — contains full event listing from Instagram's image description.
    static let altText = """
        Photo by @ddooll.2 on March 03, 2026. May be an image of poster, \
        calendar, magazine and text that says 'DRINK SPECIALS TEST KITCHEN \
        GOOD TIMES DIOOII 83 SARATOGA AVE Wed March 4th OPEN AUX W/ Featured \
        Artist 1Alkebulan 7-11pm Fri March 13th St. Slayer's Day hosted by \
        DJ ILUVDOMRICH 7-Midnite Wed- March 18th OPEN AUX W/ Special Guest \
        TBA 7-1 7-11pm pm Fri - March 27th A Caratasrophe PreGame Vol.5 with \
        resident DJ Caratasrophe 7-Midnite Sat- March 28th Rythms& \
        Rythms&Release Release Party+JamSession Hoseted By Nelson Bandela Nic \
        7-Midnite Tues- March 31st M\u{2019}KAI & friends a special evening of \
        music featuring Μ\u{2019}νΚΑι 7-10:30pm To inquire about hosting your \
        event with us DM @DDOOLL.2 on instagram or email events@september.com'.
        """

    static let caption = "Got a full month of evening programming ahead. Which one will we see you at?"

    @Test("Extracts exactly 6 events with full input data — DVb33j7lVEm")
    func extractsCorrectCount() {
        let results = EventExtractionService.extractEvents(
            ocrTexts: [Self.ocrText, ""],
            altTexts: [Self.altText, "Video by @ddooll.2 on March 03, 2026. May be an image of cocktail and text."],
            caption: Self.caption,
            currentDate: referenceDate
        )
        #expect(results.count == 6, "Expected 6 events, got \(results.count)")
    }

    @Test("Matches same events as OCR-only flyer test")
    func matchesOCROnlyExpectations() {
        let results = EventExtractionService.extractEvents(
            ocrTexts: [Self.ocrText, ""],
            altTexts: [Self.altText, "Video by @ddooll.2 on March 03, 2026. May be an image of cocktail and text."],
            caption: Self.caption,
            currentDate: referenceDate
        )
        for expected in MultiEventFlyerTests.expectedEvents {
            #expect(
                resultsContain(results, expected: expected),
                "Missing event: \(expected.datetimeStart) — \(expected.description)"
            )
        }
    }
}

// MARK: - Massive Multi-Event Caption Post

@Suite("Massive Multi-Event Caption Post")
struct MassiveMultiEventTests {

    /// Yu and Me Books OCR from image 1 (just a title card).
    static let ocr1 = """
        YU & ME
        books
        april events
        M
        """

    /// Yu and Me Books OCR from image 2 (first event details).
    static let ocr2 = """
        YU & ME BOOKS PRESENTS
        MICHELLE QUAY
        in convo with Porochista Khakpour
        WOODWIND
        HARMONY THE
        NICHTTIME
        REZA GHASSEMI
        INTRODUCTION BY POROCHISTA KHAKPOUR
        TRANSLATED BY MICHELLE QUAY
        Thurs, Apr. 2
        7-8PM ET
        Yu & Me Books
        44 Mulberry
        RSVP @ yuandmebooks.com
        """

    static let alt1 = """
        Photo by Yu and Me Books on March 25, 2026. May be a graphic of \
        book, magazine, poster and text that says 'YU YU&ME & ΜΕ books \
        april aprilevents events'.
        """

    static let alt2 = """
        Photo by Yu and Me Books on March 25, 2026. May be an image of \
        magazine, poster and text that says 'YU & ME BOOKS PRESENTS \
        MICHELLE QUAY in convo with Porochista Khakpour WOODWIND HARMONY \
        IN THE NIGHTTIME REZA GHASSEMI INTRSSUCTION PEROCHISTA HAKPOOR \
        TRANSLATED NICHELLE QUAY Thurs, Apr. Thurs,Apr.2 2 7-8PM ET \
        Yu & Me Books 44 Mulberry RSVP @ yuandmebooks.com'.
        """

    /// All 17 expected events from the Yu and Me Books April calendar.
    static let expectedEvents: [ExtractedEvent] = [
        ExtractedEvent(
            datetimeStart: "2026-04-02 19:00",
            datetimeEnd: "2026-04-02 20:00",
            description: "Book Talk: WOODWIND HARMONY IN THE NIGHTTIME by Michelle Quay with Porochista Khakpour"
        ),
        ExtractedEvent(
            datetimeStart: "2026-04-03 19:00",
            datetimeEnd: "2026-04-03 20:00",
            description: "Book Talk: FLOATER by Herb Tam with Eugene Kim"
        ),
        ExtractedEvent(
            datetimeStart: "2026-04-06 19:30",
            datetimeEnd: nil,
            description: "Generative Poetry Workshop with Lucy Yu"
        ),
        ExtractedEvent(
            datetimeStart: "2026-04-09 19:00",
            datetimeEnd: "2026-04-09 20:00",
            description: "Book Launch: AMERICAN HAN by Lisa Lee with Gina Chung"
        ),
        ExtractedEvent(
            datetimeStart: "2026-04-10 19:00",
            datetimeEnd: "2026-04-10 21:00",
            description: "OFFSITE Launch Party: THE DEAD CAN'T MAKE A LIVING by Ed Lin at Think!Chinatown"
        ),
        ExtractedEvent(
            datetimeStart: "2026-04-12 12:00",
            datetimeEnd: "2026-04-12 16:00",
            description: "Clothing Swap"
        ),
        ExtractedEvent(
            datetimeStart: "2026-04-13 19:00",
            datetimeEnd: "2026-04-13 20:00",
            description: "Book Launch: HONEY IN THE WOUND by Jiyoung Han with Eve J. Chung"
        ),
        ExtractedEvent(
            datetimeStart: "2026-04-17 20:00",
            datetimeEnd: "2026-04-17 21:00",
            description: "No-Pen Mic hosted by Ed Lin"
        ),
        ExtractedEvent(
            datetimeStart: "2026-04-18 19:30",
            datetimeEnd: nil,
            description: "Listening Party with Miss Grit"
        ),
        ExtractedEvent(
            datetimeStart: "2026-04-19 11:30",
            datetimeEnd: "2026-04-19 12:30",
            description: "Meet + Greet with Emily Sun Li and Yu Ting Cheng for MR. CHOW'S NIGHT MARKET"
        ),
        ExtractedEvent(
            datetimeStart: "2026-04-20 19:30",
            datetimeEnd: nil,
            description: "Cinema Craft Night: Harold & Kumar Go to White Castle"
        ),
        ExtractedEvent(
            datetimeStart: "2026-04-21 19:00",
            datetimeEnd: "2026-04-21 20:00",
            description: "Book Launch: UNTIL WE MEET AGAIN by Lily Kim Qian with Deb JJ Lee"
        ),
        ExtractedEvent(
            datetimeStart: "2026-04-23 19:00",
            datetimeEnd: "2026-04-23 20:00",
            description: "Book Talk: TAILBONE by Che Yeun with Sanaë Lemoine and Courtney Zoffness"
        ),
        ExtractedEvent(
            datetimeStart: "2026-04-25 20:00",
            datetimeEnd: "2026-04-25 22:00",
            description: "Find Your Butter Half Mingles Event"
        ),
        ExtractedEvent(
            datetimeStart: "2026-04-26 12:00",
            datetimeEnd: "2026-04-26 17:00",
            description: "Pop-up with Sapphic Graphix for Lesbian Visibility Day"
        ),
        ExtractedEvent(
            datetimeStart: "2026-04-27 19:00",
            datetimeEnd: "2026-04-27 20:00",
            description: "OFFSITE Book Launch: SHIM JUNG TAKES THE DIVE by Julia Riew with Christina Li at Chatham Square Library"
        ),
        ExtractedEvent(
            datetimeStart: "2026-04-28 19:00",
            datetimeEnd: "2026-04-28 20:00",
            description: "Book Launch: DREAMT I FOUND YOU by Jimin Han with Kathleen Kim"
        ),
    ]

    @Test("Extracts 17 events from Yu and Me Books — DWUG-qPkefo")
    func extractsCorrectCount() {
        let results = EventExtractionService.extractEvents(
            ocrTexts: [Self.ocr1, Self.ocr2],
            altTexts: [Self.alt1, Self.alt2],
            caption: yuAndMeCaption,
            currentDate: referenceDate
        )
        #expect(results.count == 17, "Expected 17 events, got \(results.count)")
    }

    @Test("All 17 expected events are present")
    func containsAllExpectedEvents() {
        let results = EventExtractionService.extractEvents(
            ocrTexts: [Self.ocr1, Self.ocr2],
            altTexts: [Self.alt1, Self.alt2],
            caption: yuAndMeCaption,
            currentDate: referenceDate
        )
        for expected in Self.expectedEvents {
            #expect(
                resultsContain(results, expected: expected),
                "Missing event: \(expected.datetimeStart) — \(expected.description)"
            )
        }
    }

    @Test("Events are in chronological order")
    func eventsAreChronological() {
        let results = EventExtractionService.extractEvents(
            ocrTexts: [Self.ocr1, Self.ocr2],
            altTexts: [Self.alt1, Self.alt2],
            caption: yuAndMeCaption,
            currentDate: referenceDate
        )
        for i in 0..<(results.count - 1) {
            #expect(
                results[i].datetimeStart <= results[i + 1].datetimeStart,
                "Events out of order: \(results[i].datetimeStart) after \(results[i + 1].datetimeStart)"
            )
        }
    }
}
