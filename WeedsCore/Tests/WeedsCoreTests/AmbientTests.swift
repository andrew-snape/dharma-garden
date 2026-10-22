import Foundation
import CoreGraphics
import Testing
@testable import WeedsCore
@testable import WeedsArt

struct AmbientTests {
    @Test func dayIsBirdsNotCrickets() {
        let mix = AmbientMix.resolve(phase: .day, condition: .clear, temperatureC: 22, theme: .farm)
        #expect(mix.birds > 0.5)
        #expect(mix.crickets == 0)
        #expect(mix.rain == 0)
    }

    @Test func warmNightIsCricketsNotBirds() {
        let mix = AmbientMix.resolve(phase: .night, condition: .clear, temperatureC: 20, theme: .farm)
        #expect(mix.crickets > 0.5)
        #expect(mix.birds == 0)
    }

    @Test func coldNightHasNoCrickets() {
        let mix = AmbientMix.resolve(phase: .night, condition: .clear, temperatureC: 4, theme: .farm)
        #expect(mix.crickets == 0)
    }

    @Test func rainFollowsTheWeatherAndQuietsTheBirds() {
        let dry = AmbientMix.resolve(phase: .day, condition: .clear, temperatureC: 15, theme: .farm)
        let wet = AmbientMix.resolve(phase: .day, condition: .rain, temperatureC: 15, theme: .farm)
        let storm = AmbientMix.resolve(phase: .day, condition: .thunderstorm, temperatureC: 15, theme: .farm)
        #expect(wet.rain > 0.5)
        #expect(storm.rain > wet.rain)
        #expect(wet.birds < dry.birds)
        #expect(storm.birds == 0)
    }

    @Test func theUrbanThemeIsQuieter() {
        let farm = AmbientMix.resolve(phase: .day, condition: .clear, temperatureC: 22, theme: .farm)
        let urban = AmbientMix.resolve(phase: .day, condition: .clear, temperatureC: 22, theme: .urban)
        #expect(urban.birds < farm.birds)
    }

    private func render(_ mix: AmbientMix, level: Double = 1, seconds: Double = 8) -> [Float] {
        let synth = AmbientSynth(sampleRate: 22_050)
        synth.setTarget(mix, level: level)
        synth.settle()
        let frames = Int(22_050 * seconds)
        var out = [Float](repeating: 0, count: frames * 2)
        out.withUnsafeMutableBufferPointer { synth.render(into: $0.baseAddress!, frames: frames) }
        return out
    }

    private func peak(_ samples: [Float]) -> Float { samples.map { abs($0) }.max() ?? 0 }

    @Test func silentMixRendersSilence() {
        #expect(peak(render(.silent)) == 0)
    }

    @Test func eachLayerMakesSoundWithinBounds() {
        for mix in [AmbientMix(birds: 1), AmbientMix(crickets: 1), AmbientMix(rain: 1)] {
            let samples = render(mix)
            let p = peak(samples)
            #expect(p > 0.005)
            #expect(p <= 1)
            #expect(samples.allSatisfy { $0.isFinite })
        }
    }

    @Test func masterLevelZeroIsSilent() {
        #expect(peak(render(AmbientMix(birds: 1, crickets: 1, rain: 1), level: 0)) == 0)
    }

    @Test func ambienceStaysSoft() {
        // Everything at once still sits well under full scale, so it stays under the music.
        #expect(peak(render(AmbientMix(birds: 1, crickets: 1, rain: 1))) < 0.6)
    }
}

struct SideChoreTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func garden(coins: Int = 5) -> Garden {
        var g = Garden(now: now)
        g.coins = coins
        g.plants = []
        g.weeds = []
        return g
    }

    private func fading(id: Int = 1) -> Plant {
        var p = Plant(id: id, flower: .daisy, position: GroundPoint(x: 0.5, y: 0.5))
        p.progress = 1
        p.bloomHoursElapsed = Tuning.bloomDays * 24 + 10
        return p
    }

    @Test func emptyGardenOffersOnlyTheBirds() {
        #expect(SideChore.available(garden: garden(), readyAt: [:], now: now, visitorCount: 0) == [.feedBirds])
    }

    @Test func birdsNeedCoinsAndRoomForVisitors() {
        #expect(SideChore.available(garden: garden(coins: 0), readyAt: [:], now: now, visitorCount: 0).isEmpty)
        #expect(SideChore.available(garden: garden(), readyAt: [:], now: now, visitorCount: Tuning.maxVisitors).isEmpty)
    }

    @Test func cooldownHidesAChoreUntilItsTime() {
        let later = now.addingTimeInterval(60)
        let ready = [SideChore.feedBirds.rawValue: later]
        #expect(SideChore.available(garden: garden(), readyAt: ready, now: now, visitorCount: 0).isEmpty)
        #expect(SideChore.available(garden: garden(), readyAt: ready, now: later, visitorCount: 0) == [.feedBirds])
    }

    @Test func deadheadNeedsAFadingPlant() {
        var g = garden()
        #expect(!SideChore.available(garden: g, readyAt: [:], now: now, visitorCount: 3).contains(.deadhead))
        g.plants = [fading()]
        #expect(SideChore.available(garden: g, readyAt: [:], now: now, visitorCount: 3).contains(.deadhead))
    }

    @Test func deadheadingBringsAFadingPlantBackIntoBloom() {
        var g = garden()
        g.plants = [fading()]
        #expect(g.plants[0].lifeStage == .fading)
        #expect(GardenEngine.deadhead(in: &g) == 1)
        #expect(g.plants[0].lifeStage == .blooming)
        #expect(GardenEngine.deadhead(in: &g) == 0)
    }

    @Test func compostFeedsTheSoilOnceUntilItRunsOut() {
        var g = garden()
        g.plants = [fading()]
        #expect(SideChore.available(garden: g, readyAt: [:], now: now, visitorCount: 3).contains(.compost))
        #expect(GardenEngine.compost(in: &g) == 1)
        #expect(g.soil.fertiliserHours[SoilField.cellIndex(of: g.plants[0].position)] == Tuning.compostHours)
        #expect(GardenEngine.compost(in: &g) == 0)
        #expect(!SideChore.available(garden: g, readyAt: [:], now: now, visitorCount: 3).contains(.compost))
    }

    @Test func feedingTheBirdsCostsACoin() {
        var g = garden(coins: 2)
        #expect(GardenEngine.feedBirds(in: &g))
        #expect(g.coins == 1)
        g.coins = 0
        #expect(!GardenEngine.feedBirds(in: &g))
        #expect(g.coins == 0)
    }
}

struct AwaySummaryTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func countsWhatRipenedAndWhatAppeared() {
        var before = Garden(now: start)
        before.plants = []
        before.weeds = []
        var growing = Plant(id: 1, flower: .daisy, position: GroundPoint(x: 0.4, y: 0.5))
        growing.progress = 0.8
        before.plants = [growing]

        var after = before
        after.lastSimulatedAt = start.addingTimeInterval(50 * 3600)
        after.plants[0].progress = 1
        after.plants[0].bloomHoursElapsed = 0
        after.plants[0].moisture = 80
        after.weeds = [Weed(id: 9, position: GroundPoint(x: 0.5, y: 0.5))]

        let summary = GardenEngine.awaySummary(from: before, to: after)
        #expect(summary.hoursAway == 50)
        #expect(summary.ripened == 1)
        #expect(summary.newWeeds == 1)
        #expect(summary.awayText == "2 days")
        #expect(summary.lines == ["1 plant ripened", "1 weed appeared"])
    }

    @Test func aNewVolunteerIsNotCountedAsRipened() {
        let before = Garden(now: start)
        var after = before
        var volunteer = Plant(id: 77, flower: .daisy, position: GroundPoint(x: 0.4, y: 0.5))
        volunteer.progress = 1
        volunteer.moisture = 80
        after.plants = [volunteer]
        #expect(GardenEngine.awaySummary(from: before, to: after).ripened == 0)
    }

    @Test func aQuietGardenHasNothingToReport() {
        let g = Garden(now: start)
        #expect(GardenEngine.awaySummary(from: g, to: g).isEmpty)
    }
}

struct SceneFramingTests {
    @Test func aFourThreeWindowShowsTheWholeScene() {
        let size = SceneFraming.coverSize(in: CGSize(width: 800, height: 600))
        #expect(abs(size.width - 800) < 0.001)
        #expect(abs(size.height - 600) < 0.001)
    }

    @Test func aWideWindowCropsTheTopAndBottom() {
        let container = CGSize(width: 1600, height: 800)
        let size = SceneFraming.coverSize(in: container)
        #expect(size.width == 1600)
        #expect(size.height > container.height)
    }

    @Test func aTallWindowCropsTheSidesButNeverBeyondTheLimit() {
        let container = CGSize(width: 800, height: 900)
        let size = SceneFraming.coverSize(in: container)
        #expect(size.width >= container.width)
        #expect(container.width / size.width >= SceneFraming.minVisibleWidth - 0.001)
    }

    @Test func aNarrowTallWindowLeavesBandsInsteadOfCuttingThePatch() {
        let container = CGSize(width: 600, height: 1200)
        let size = SceneFraming.coverSize(in: container)
        #expect(size.height < container.height)
    }

    @Test func anEmptyContainerHasNoScene() {
        #expect(SceneFraming.coverSize(in: .zero) == .zero)
    }
}
