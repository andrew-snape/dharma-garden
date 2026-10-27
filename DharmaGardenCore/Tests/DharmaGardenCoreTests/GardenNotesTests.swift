import Foundation
import Testing
@testable import DharmaGardenCore

struct GardenNotesTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func sample(_ event: GardenNoteEvent, seeds: ClosedRange<UInt64> = 1...60,
                        x: Double = 0.5, night: Bool = false) -> [[GardenNote]] {
        seeds.map { seed in
            var n = GardenNotes(seed: seed)
            return n.notes(for: event, at: t0, x: x, density: .subtle, night: night)
        }
    }

    @Test func plantIsLow() {
        for notes in sample(.plant) {
            #expect(notes.count == 1)
            #expect([0, 1].contains(notes[0].scaleIndex))
        }
    }

    @Test func waterRisesInTwoOrThreeNotesSpreadOut() {
        var counts = Set<Int>()
        for notes in sample(.water) {
            counts.insert(notes.count)
            #expect((2...3).contains(notes.count))
            #expect(notes[0].delay == 0)
            for i in 1..<notes.count {
                let gap = notes[i].delay - notes[i - 1].delay
                #expect(gap >= 0.4 - 1e-9 && gap <= 0.8 + 1e-9)
                #expect(notes[i].scaleIndex > notes[i - 1].scaleIndex)
            }
        }
        #expect(counts == [2, 3])
    }

    @Test func harvestIsD4AndVisitorsAndFlowersAreUpper() {
        for notes in sample(.harvest) { #expect(notes.map(\.scaleIndex) == [4]) }
        for notes in sample(.visitorSpotted) { #expect((5...8).contains(notes[0].scaleIndex)) }
        for notes in sample(.flowerOpened) { #expect((5...8).contains(notes[0].scaleIndex)) }
    }

    @Test func rainBeganIsASlowFallingRunOfThree() {
        for notes in sample(.rainBegan) {
            #expect(notes.count == 3)
            #expect(notes[0].scaleIndex > notes[1].scaleIndex && notes[1].scaleIndex > notes[2].scaleIndex)
            #expect(notes[1].delay - notes[0].delay >= 1.0)
            #expect(notes.allSatisfy { (0...8).contains($0.scaleIndex) })
        }
    }

    @Test func velocityAndNightAndPan() {
        for notes in sample(.water) + sample(.rainBegan) {
            for note in notes { #expect(note.velocity >= 0.15 && note.velocity <= 0.35) }
        }
        for notes in sample(.water, night: true) + sample(.rainBegan, night: true) {
            for note in notes { #expect(note.velocity >= 0.15 * 0.7 - 1e-9 && note.velocity <= 0.35 * 0.7 + 1e-9) }
        }
        #expect(abs(sample(.plant, x: 0)[0][0].pan + 0.6) < 1e-9)
        #expect(abs(sample(.plant, x: 1)[0][0].pan - 0.6) < 1e-9)
        #expect(abs(sample(.plant, x: 0.5)[0][0].pan) < 1e-9)
    }

    @Test func rateLimitDropsEventsInsideTheWindow() {
        var n = GardenNotes(seed: 1)
        #expect(!n.notes(for: .water, at: t0, density: .subtle, night: false).isEmpty)
        // A long drag: an event every 0.2 s for 5.8 s gives nothing more.
        for i in 1..<30 {
            #expect(n.notes(for: .water, at: t0.addingTimeInterval(Double(i) * 0.2), density: .subtle, night: false).isEmpty)
        }
        #expect(!n.notes(for: .water, at: t0.addingTimeInterval(6.0), density: .subtle, night: false).isEmpty)
    }

    @Test func oftenUsesAThreeSecondWindow() {
        var n = GardenNotes(seed: 1)
        #expect(!n.notes(for: .plant, at: t0, density: .often, night: false).isEmpty)
        #expect(n.notes(for: .plant, at: t0.addingTimeInterval(2.9), density: .often, night: false).isEmpty)
        #expect(!n.notes(for: .plant, at: t0.addingTimeInterval(3.0), density: .often, night: false).isEmpty)
    }

    @Test func flowersAreRare() {
        var n = GardenNotes(seed: 1)
        #expect(!n.notes(for: .flowerOpened, at: t0, density: .often, night: false).isEmpty)
        // Outside the 3 s window but inside two minutes: dropped, and it does not use up the window.
        #expect(n.notes(for: .flowerOpened, at: t0.addingTimeInterval(30), density: .often, night: false).isEmpty)
        #expect(!n.notes(for: .plant, at: t0.addingTimeInterval(31), density: .often, night: false).isEmpty)
        #expect(!n.notes(for: .flowerOpened, at: t0.addingTimeInterval(121), density: .often, night: false).isEmpty)
    }

    @Test func offMakesNoNotes() {
        var n = GardenNotes(seed: 1)
        for event in [GardenNoteEvent.plant, .water, .harvest, .visitorSpotted, .flowerOpened, .rainBegan] {
            #expect(n.notes(for: event, at: t0, density: .off, night: false).isEmpty)
        }
        // And off did not use up the window.
        #expect(!n.notes(for: .plant, at: t0, density: .subtle, night: false).isEmpty)
    }

    @Test func neverTheSameNoteTwiceInARow() {
        for seed in 1...30 as ClosedRange<UInt64> {
            var n = GardenNotes(seed: seed)
            var last: Int?
            var clock = t0
            let events: [GardenNoteEvent] = [.harvest, .harvest, .harvest, .plant, .plant, .water, .rainBegan, .harvest]
            for event in events {
                for note in n.notes(for: event, at: clock, density: .often, night: false) {
                    #expect(note.scaleIndex != last)
                    last = note.scaleIndex
                }
                clock = clock.addingTimeInterval(10)
            }
        }
    }
}
