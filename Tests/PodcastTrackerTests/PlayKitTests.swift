import AppKit
import Foundation
import SwiftUI
import Testing
@testable import PodcastTracker

@Suite("Play kit")
struct PlayKitTests {
    @Test func svgParserHandlesAbsoluteRelativeAndImplicitCommands() {
        let path = SVGPath.parse("M10 10 L20 10 l0 10 H10 v-10 Z")
        #expect(path.boundingRect.integral == CGRect(x: 10, y: 10, width: 10, height: 10))
        let curve = SVGPath.parse("M0 0 C0 -10 20 -10 20 0 S40 10 40 0")
        #expect(curve.boundingRect.maxX == 40)
        #expect(SVGPath.tokenize("M1-2.5.5").count == 4)
    }

    @Test func echoGeometryStaysInsideItsViewport() {
        let body = SVGPath.parse(EchoSpec.body).boundingRect
        #expect(body.minX >= 20 && body.maxX <= 180 && body.minY >= 30 && body.maxY <= 182)
        #expect(SVGPath.parse(EchoSpec.band).boundingRect.minY > -10)
    }

    @Test func weekStripMarksLearnedFrozenTodayAndFuture() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .current
        let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 12))) // Friday
        var loop = HabitLoop(); loop.startedDay = "2026-09-01"
        for day in ["2026-10-19", "2026-10-20", "2026-10-22"] { loop.events.append(.init(id: "playback/d/\(day)", day: day, kind: "playback", value: 600)) }
        let strip = loop.weekStrip(activities: [], now: today, calendar: calendar)
        #expect(strip.map(\.letter) == ["M", "T", "W", "T", "F", "S", "S"])
        #expect(strip[0].state == .done && strip[2].state == .frozen && strip[4].state == .today && strip[6].state == .future)
        #expect(StreakMilestones.next(after: 14) == 30 && StreakMilestones.previous(before: 20) == 14)
    }

    /// Visual QA: `PODTRACKIO_RENDER_DIR=/path swift test --filter renderPreviews` writes PNGs of key components.
    @MainActor @Test func renderPreviews() throws {
        guard let directory = ProcessInfo.processInfo.environment["PODTRACKIO_RENDER_DIR"] else { return }
        func write<V: View>(_ name: String, _ view: V, scheme: ColorScheme = .light) throws {
            let renderer = ImageRenderer(content: view.environment(\.colorScheme, scheme))
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
            try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
        }
        let moods = HStack(spacing: 12) { ForEach(EchoMood.allCases, id: \.self) { mood in VStack { EchoView(mood: mood, size: 120); Text(mood.rawValue) } } }
            .padding(20).background(Color.white)
        try write("echo-moods", moods)
        let darkMoods = moods.background(Color(hex: 0x131722))
        try write("echo-moods-dark", darkMoods, scheme: .dark)
        PreviewCatalog.renderAll { name, view, scheme in try? write(name, view, scheme: scheme) }
    }
}
