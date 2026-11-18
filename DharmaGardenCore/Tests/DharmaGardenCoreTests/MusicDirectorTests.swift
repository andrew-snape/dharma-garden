import Foundation
import Testing
@testable import DharmaGardenCore

struct MusicDirectorTests {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// 2026-10-27 at `hour`:00 UTC.
    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: hour, minute: minute))!
    }

    private let library: [PieceInfo] = PieceMood.allCases.flatMap { mood in
        (1...4).map { PieceInfo(id: "japanese-\(mood.rawValue)-\($0)", mood: mood, duration: 240) }
    }

    private func director(now: Date, seed: UInt64 = 1, catalogue: [PieceInfo]? = nil) -> MusicDirector {
        MusicDirector(catalogue: catalogue ?? library, now: now, seed: seed, calendar: utc)
    }

    @Test func firstPieceWaitsFortyFiveToNinetySeconds() {
        for seed in 1...30 as ClosedRange<UInt64> {
            let start = at(10)
            let d = director(now: start, seed: seed)
            guard case .silent(let until) = d.state else { Issue.record("not silent"); return }
            let wait = until.timeIntervalSince(start)
            #expect(wait >= 45 && wait <= 90)
        }
    }

    @Test func nothingStartsBeforeTheWaitAndAPieceStartsAfter() {
        var d = director(now: at(10))
        #expect(d.tick(now: at(10).addingTimeInterval(44), mood: .day, density: .subtle) == .none)
        let action = d.tick(now: at(10).addingTimeInterval(91), mood: .day, density: .subtle)
        guard case .start(let piece) = action else { Issue.record("no piece"); return }
        #expect(piece.mood == .day)
        #expect(d.state == .playing(piece, endsAt: at(10).addingTimeInterval(91 + 240)))
    }

    @Test func gapAfterAPieceFollowsDensity() {
        for (density, range) in [(MusicDensity.subtle, 360.0...720), (.often, 60...180)] {
            for seed in 1...20 as ClosedRange<UInt64> {
                var d = director(now: at(10), seed: seed)
                let start = at(10).addingTimeInterval(100)
                _ = d.tick(now: start, mood: .day, density: density)
                let end = start.addingTimeInterval(240)
                _ = d.tick(now: end.addingTimeInterval(1), mood: .day, density: density)
                guard case .silent(let until) = d.state else { Issue.record("not silent"); return }
                let gap = until.timeIntervalSince(end)
                #expect(range.contains(gap), "\(density) gap \(gap)")
            }
        }
    }

    @Test func matchesTheMoodAndUsesRainPiecesWhenRaining() {
        for mood in PieceMood.allCases {
            var d = director(now: at(10))
            guard case .start(let piece) = d.tick(now: at(10).addingTimeInterval(100), mood: mood, density: .subtle)
            else { Issue.record("no piece"); return }
            #expect(piece.mood == mood)
        }
    }

    @Test func fallsBackToANeighbouringMood() {
        let onlyDusk = [PieceInfo(id: "a", mood: .dusk, duration: 100)]
        var d = director(now: at(10), catalogue: onlyDusk)
        guard case .start(let piece) = d.tick(now: at(10).addingTimeInterval(100), mood: .rain, density: .often)
        else { Issue.record("no piece"); return }
        #expect(piece.id == "a")
    }

    @Test func neverRepeatsTheLastThree() {
        var d = director(now: at(10))
        var played: [String] = []
        var clock = at(10).addingTimeInterval(100)
        for _ in 0..<40 {
            guard case .start(let piece) = d.tick(now: clock, mood: .day, density: .often) else {
                Issue.record("expected a piece at \(clock)"); return
            }
            played.append(piece.id)
            clock = clock.addingTimeInterval(240 + 200)       // past the end and the longest often-gap
            _ = d.tick(now: clock, mood: .day, density: .often)
            clock = clock.addingTimeInterval(200)
            if clock > at(21) { clock = at(10) }               // stay out of the quiet hours; history carries on
        }
        for i in 3..<played.count {
            #expect(!played[(i - 3)..<i].contains(played[i]), "repeat at \(i)")
        }
        // Only four day pieces exist and three are barred each time, so it cycles through all four.
        #expect(Set(played).count == 4)
    }

    @Test func waitsWhenEveryCandidateWasPlayedRecently() {
        let two = [PieceInfo(id: "a", mood: .day, duration: 10), PieceInfo(id: "b", mood: .day, duration: 10)]
        var d = director(now: at(10), catalogue: two)
        var clock = at(10).addingTimeInterval(100)
        #expect(d.tick(now: clock, mood: .day, density: .often) != .none)
        clock = clock.addingTimeInterval(1000)
        _ = d.tick(now: clock, mood: .day, density: .often)
        clock = clock.addingTimeInterval(1000)
        #expect(d.tick(now: clock, mood: .day, density: .often) != .none)
        clock = clock.addingTimeInterval(1000)
        _ = d.tick(now: clock, mood: .day, density: .often)
        clock = clock.addingTimeInterval(1000)
        // Both are in the last three: nothing is picked, and it tries again a minute later.
        #expect(d.tick(now: clock, mood: .day, density: .often) == .none)
    }

    @Test func noPieceStartsBetweenTenAtNightAndSix() {
        for (hour, quiet) in [(21, false), (22, true), (23, true), (0, true), (5, true), (6, false), (12, false)] {
            let d = director(now: at(10))
            #expect(d.isQuietHour(at(hour, 30)) == quiet, "hour \(hour)")
        }
        var d = director(now: at(23))
        #expect(d.tick(now: at(23, 30), mood: .night, density: .often) == .none)
        #expect(d.tick(now: at(3).addingTimeInterval(86_400), mood: .night, density: .often) == .none)
        guard case .start = d.tick(now: at(6, 1).addingTimeInterval(86_400), mood: .dawn, density: .often) else {
            Issue.record("expected a start at 06:01"); return
        }
    }

    @Test func offNeverPlaysAndStopsAPieceInProgress() {
        var d = director(now: at(10))
        for minute in 0..<600 {
            #expect(d.tick(now: at(10).addingTimeInterval(Double(minute) * 60), mood: .day, density: .off) == .none)
        }
        var e = director(now: at(10))
        _ = e.tick(now: at(10).addingTimeInterval(100), mood: .day, density: .subtle)
        #expect(e.tick(now: at(10).addingTimeInterval(110), mood: .day, density: .off) == .stop)
        // Switched on again: a fresh wait before anything plays.
        #expect(e.tick(now: at(10).addingTimeInterval(120), mood: .day, density: .subtle) == .none)
    }

    @Test func goSilentWaitsAFullGap() {
        var d = director(now: at(10))
        let t = at(10).addingTimeInterval(100)
        _ = d.tick(now: t, mood: .day, density: .subtle)
        d.goSilent(now: t.addingTimeInterval(5), density: .subtle)
        guard case .silent(let until) = d.state else { Issue.record("not silent"); return }
        #expect(until.timeIntervalSince(t) >= 365)
    }

    @Test func sameSeedSamePieces() {
        func run() -> [String] {
            var d = director(now: at(10), seed: 9)
            var out: [String] = []
            var clock = at(10).addingTimeInterval(100)
            for _ in 0..<5 {
                if case .start(let p) = d.tick(now: clock, mood: .dusk, density: .often) { out.append(p.id) }
                clock = clock.addingTimeInterval(500)
                _ = d.tick(now: clock, mood: .dusk, density: .often)
                clock = clock.addingTimeInterval(200)
            }
            return out
        }
        #expect(run() == run())
    }

    @Test func gardenMoodMapsToPieceMood() {
        func mood(_ phase: SunPhase, _ condition: WeatherCondition) -> PieceMood {
            PieceMood(GardenMood(phase: phase, condition: condition, season: .spring))
        }
        #expect(mood(.dawn, .clear) == .dawn)
        #expect(mood(.day, .overcast) == .day)
        #expect(mood(.dusk, .fog) == .dusk)
        #expect(mood(.night, .clear) == .night)
        #expect(mood(.day, .rain) == .rain)
        #expect(mood(.night, .thunderstorm) == .rain)
        #expect(mood(.day, .drizzle) == .day)
    }
}
