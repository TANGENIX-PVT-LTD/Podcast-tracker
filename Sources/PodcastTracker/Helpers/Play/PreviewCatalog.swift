import SwiftUI

/// Static renders of Play components for visual QA (used by `PlayKitTests.renderPreviews`).
@MainActor
enum PreviewCatalog {
    static func renderAll(_ write: (String, AnyView, ColorScheme) -> Void) {
        for scheme in [ColorScheme.light, .dark] {
            let suffix = scheme == .dark ? "-dark" : ""
            let background = scheme == .dark ? Color(hex: 0x131722) : Color(hex: 0xF7F7F7)
            write("controls\(suffix)", AnyView(controls.padding(24).frame(width: 420).background(background)), scheme)
        }
    }

    static var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button("Continue") {}.buttonStyle(.chunky)
            Button("Check") {}.buttonStyle(.chunky(.success))
            HStack {
                Button("Skip") {}.buttonStyle(.chunky(.secondary, size: .small, fullWidth: false))
                Button("Refill · 100") {}.buttonStyle(.chunky(.gem, size: .small, fullWidth: false))
                Button("Locked") {}.buttonStyle(.chunky(.flame, size: .small, fullWidth: false)).disabled(true)
            }
            PlayProgressBar(value: 0.62)
            PlayProgressBar(value: 0.3, tint: Play.Palette.flame, height: 12)
            HStack(spacing: 18) {
                PlayStatPill(symbol: "flame.fill", value: "12", color: Play.Palette.flame)
                PlayStatPill(symbol: "diamond.fill", value: "240", color: Play.Palette.gem)
                PlayStatPill(symbol: "bolt.fill", value: "1,280", color: Play.Palette.gold)
            }
            Text("Chunky card").font(Play.rounded(17, .bold)).frame(maxWidth: .infinity, alignment: .leading).padding(16).chunkyCard()
            EchoSays(mood: .happy, text: "4 minutes keeps your 12-day flame alive!")
        }
    }
}
