import Foundation
import Testing
@testable import DharmaGardenCore

struct ImproviserTests {
    private let minutes = 4.0
    private let seeds: [UInt64] = [1, 2, 3, 4, 5, 6]

    private func count(_ events: [HandpanEvent], from a: Double, to b: Double) -> Int {
        events.filter { $0.time >= a && $0.time < b }.count
    }

    @Test func sameSeedSameEvents() {
        for mood in PieceMood.allCases {
            let a = Improviser.piece(mood: mood, seed: 42, minutes: minutes)
            let b = Improviser.piece(mood: mood, seed: 42, minutes: minutes)
            #expect(a == b)
            #expect(a != Improviser.piece(mood: mood, seed: 43, minutes: minutes))
        }
    }

    @Test func notesComeFromTheScaleAndStayInsideTheDuration() {
        for mood in PieceMood.allCases {
            for seed in seeds {
                let events = Improviser.piece(mood: mood, seed: seed, minutes: minutes)
                #expect(!events.isEmpty)
                #expect(events.allSatisfy { ModalInstrument.scale.contains($0.midi) })
                #expect(events.map(\.time) == events.map(\.time).sorted())
                #expect(events.allSatisfy { $0.time >= 0 && $0.time < minutes * 60 })
            }
        }
    }

    @Test func pieceEndsOnD() {
        for mood in PieceMood.allCases {
            for seed in seeds {
                let events = Improviser.piece(mood: mood, seed: seed, minutes: minutes)
                #expect(events.last.map { $0.midi % 12 == 2 } == true, "\(mood) \(seed)")
                #expect(events.last!.time > minutes * 60 - 32, "the closing note should sit near the end")
            }
        }
    }

    @Test func velocitiesStayGentle() {
        for mood in PieceMood.allCases {
            for seed in seeds {
                for e in Improviser.piece(mood: mood, seed: seed, minutes: minutes) {
                    #expect(e.velocity >= 0.15 && e.velocity <= 0.65)
                }
            }
        }
    }

    @Test func densityIsCalmAndNightIsLowest() {
        var average: [PieceMood: Double] = [:]
        for mood in PieceMood.allCases {
            var total = 0.0
            for seed in seeds {
                let m = PieceMetrics(events: Improviser.piece(mood: mood, seed: seed, minutes: minutes),
                                     duration: minutes * 60)
                #expect(m.notesPerMinute >= 8 && m.notesPerMinute <= 35, "\(mood) \(seed): \(m.notesPerMinute)")
                #expect(m.maxIn10s <= 12, "\(mood) \(seed)")
                total += m.notesPerMinute
            }
            average[mood] = total / Double(seeds.count)
        }
        #expect(average[.night]! < average[.day]!)
        for mood in PieceMood.allCases where mood != .night {
            #expect(average[.night]! < average[mood]!, "\(mood)")
        }
    }

    @Test func phrasesAreSeparatedByRests() {
        for mood in PieceMood.allCases {
            for seed in seeds {
                let piece = Improviser.compose(mood: mood, seed: seed, minutes: minutes)
                for (a, b) in zip(piece.phrases, piece.phrases.dropFirst()) {
                    #expect(b.start - a.end >= 2.0, "\(mood) \(seed): \(b.start - a.end)")
                }
                #expect(piece.phrases.count > 8)
            }
        }
    }

    @Test func openingAndEndingAreSparserThanTheMiddle() {
        let d = minutes * 60
        for mood in PieceMood.allCases {
            var opening = 0, middle = 0, ending = 0
            for seed in seeds {
                let e = Improviser.piece(mood: mood, seed: seed, minutes: minutes)
                opening += count(e, from: 0, to: 30)
                ending += count(e, from: d - 30, to: d)
                middle += count(e, from: d / 2 - 15, to: d / 2 + 15)
            }
            #expect(opening < middle, "\(mood) opening \(opening) vs middle \(middle)")
            #expect(ending < middle, "\(mood) ending \(ending) vs middle \(middle)")
        }
    }

    @Test func moodsDifferInRegister() {
        func meanMidi(_ mood: PieceMood) -> Double {
            seeds.map { PieceMetrics(events: Improviser.piece(mood: mood, seed: $0, minutes: minutes),
                                     duration: minutes * 60).meanMidi }.reduce(0, +) / Double(seeds.count)
        }
        #expect(meanMidi(.dawn) > meanMidi(.dusk))
        #expect(meanMidi(.dawn) > meanMidi(.rain))
    }

    @Test func noPitchDominates() {
        for mood in PieceMood.allCases {
            for seed in seeds {
                let m = PieceMetrics(events: Improviser.piece(mood: mood, seed: seed, minutes: minutes),
                                     duration: minutes * 60)
                #expect(m.topNoteShare < 0.3, "\(mood) \(seed): \(m.topNoteShare)")
            }
        }
    }
}
