import AVFoundation
import SwiftUI
#if os(iOS)
import CoreHaptics
import UIKit
#else
import AppKit
#endif

/// Named feedback moments. Each haptic pattern is authored against the matching animation's keyframes
/// (see the celebration views), so sound, motion and touch land on the same beat.
enum PlayCue: String, CaseIterable {
    case press, release, tap, select, tick, pop, correct, wrong, success, ignite, streakFlip, chestShake, levelUp, freeze
    /// Choreography beats: a soft landing, a heavy low thud, a big slam with tail, a shake swing.
    case land, thud, impact, swing

    var sound: String? {
        switch self {
        case .press, .release, .tap, .success, .land, .thud, .impact, .swing: nil
        case .select, .tick: "tick"
        case .pop: "pop"
        case .correct: "correct"
        case .wrong: "wrong"
        case .ignite: "ignite"
        case .streakFlip: "streak"
        case .chestShake: "chest"
        case .levelUp: "levelup"
        case .freeze: "freeze"
        }
    }
}

@MainActor
enum PlayFeedback {
    static var hapticsEnabled: Bool { AppViewModel.shared.habitLoop.hapticsEnabled }
    static var soundsEnabled: Bool { AppViewModel.shared.habitLoop.soundsEnabled }

    /// Plays the haptic and (optionally) the sound for a cue at the same instant.
    static func play(_ cue: PlayCue, sound: Bool = true, intensity: Float = 1) {
        if hapticsEnabled { PlayHaptics.shared.play(cue, intensity: intensity) }
        if sound, soundsEnabled, let name = cue.sound { PlaySounds.shared.play(name) }
    }

    /// `rate` > 1 raises pitch: count-ups climb in pitch as they near the total.
    static func sound(_ name: String, rate: Float = 1, volume: Float? = nil) {
        if soundsEnabled { PlaySounds.shared.play(name, rate: rate, volume: volume) }
    }

    /// Spin up the haptic engine and audio buffers before a moment so the first beat lands on time.
    static func prewarm() {
        PlayHaptics.shared.prewarm()
        PlaySounds.shared.preload()
    }
}

// MARK: - Haptics

@MainActor
final class PlayHaptics {
    static let shared = PlayHaptics()

    #if os(iOS)
    private var engine: CHHapticEngine?
    private var supportsCore = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    private init() { prepare() }

    private func prepare() {
        guard supportsCore else { return }
        do {
            let engine = try CHHapticEngine()
            engine.playsHapticsOnly = true
            engine.isAutoShutdownEnabled = true
            engine.resetHandler = { [weak engine] in try? engine?.start() }
            try engine.start()
            self.engine = engine
        } catch { supportsCore = false }
    }

    func prewarm() {
        guard supportsCore else { return }
        if engine == nil { prepare() }
        engine?.start { _ in }
    }

    func play(_ cue: PlayCue, intensity: Float = 1) {
        guard supportsCore, let engine else { return fallback(cue) }
        do {
            var events = Self.events(for: cue)
            if intensity != 1 {
                events = events.map { event in
                    let params = event.eventParameters.map {
                        $0.parameterID == .hapticIntensity ? CHHapticEventParameter(parameterID: .hapticIntensity, value: min(1, $0.value * intensity)) : $0
                    }
                    return CHHapticEvent(eventType: event.type, parameters: params, relativeTime: event.relativeTime, duration: event.duration)
                }
            }
            let pattern = try CHHapticPattern(events: events, parameterCurves: Self.curves(for: cue))
            try engine.start()
            try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
        } catch { fallback(cue) }
    }

    private func fallback(_ cue: PlayCue) {
        switch cue {
        case .correct, .success, .streakFlip, .levelUp: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .wrong: UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .tick, .select: UISelectionFeedbackGenerator().selectionChanged()
        case .ignite, .chestShake: UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        default: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    private static func hit(_ time: TimeInterval, _ intensity: Float, _ sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient, parameters: [
            .init(parameterID: .hapticIntensity, value: intensity), .init(parameterID: .hapticSharpness, value: sharpness)
        ], relativeTime: time)
    }

    private static func hum(_ time: TimeInterval, _ duration: TimeInterval, _ intensity: Float, _ sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticContinuous, parameters: [
            .init(parameterID: .hapticIntensity, value: intensity), .init(parameterID: .hapticSharpness, value: sharpness)
        ], relativeTime: time, duration: duration)
    }

    static func events(for cue: PlayCue) -> [CHHapticEvent] {
        switch cue {
        case .press: [hit(0, 0.55, 0.65)]
        case .release: [hit(0, 0.3, 0.8)]
        case .land: [hit(0, 0.65, 0.45)]
        case .thud: [hit(0, 1.0, 0.1), hum(0, 0.08, 0.6, 0.05)]
        // The "slam": a sharp crack, then a body rumble that dies away.
        case .impact: [hit(0, 1.0, 0.85), hum(0.01, 0.28, 1.0, 0.2)]
        case .swing: [hit(0, 0.75, 0.2)]
        case .tap: [hit(0, 0.4, 0.5)]
        case .select: [hit(0, 0.35, 0.9)]
        case .tick: [hit(0, 0.28, 0.95)]
        case .pop: [hit(0, 0.7, 0.6)]
        case .correct: [hit(0, 0.6, 0.5), hit(0.09, 1.0, 0.75)]
        case .wrong: [hit(0, 0.9, 0.12), hit(0.12, 0.85, 0.12)]
        case .success: [hit(0, 0.5, 0.4), hit(0.12, 1.0, 0.6)]
        // Flame grows grey → orange over 450ms, then pops.
        case .ignite: [hum(0, 0.45, 1.0, 0.25), hit(0.45, 1.0, 0.9)]
        // Odometer flips: one hard click, then a short decaying rumble.
        case .streakFlip: [hit(0, 1.0, 1.0), hum(0.02, 0.22, 0.7, 0.3)]
        // Three escalating wobbles, then the lid bursts at 1.0s.
        case .chestShake: [hit(0, 0.45, 0.3), hum(0, 0.12, 0.35, 0.2), hit(0.35, 0.65, 0.35), hum(0.35, 0.12, 0.5, 0.2),
                           hit(0.70, 0.85, 0.4), hum(0.70, 0.12, 0.65, 0.2), hum(0.98, 0.3, 1.0, 0.3), hit(1.0, 1.0, 1.0)]
        // Swell, then three sparkles as the badge lands.
        case .levelUp: [hum(0, 0.6, 1.0, 0.3), hit(0.62, 0.6, 1.0), hit(0.76, 0.8, 1.0), hit(0.9, 1.0, 1.0)]
        case .freeze: (0..<5).map { hit(Double($0) * 0.05, 0.55 - Float($0) * 0.08, 1.0) }
        }
    }

    static func curves(for cue: PlayCue) -> [CHHapticParameterCurve] {
        switch cue {
        case .ignite:
            [CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [.init(relativeTime: 0, value: 0.15), .init(relativeTime: 0.45, value: 0.9)], relativeTime: 0),
             CHHapticParameterCurve(parameterID: .hapticSharpnessControl, controlPoints: [.init(relativeTime: 0, value: 0.1), .init(relativeTime: 0.45, value: 0.5)], relativeTime: 0)]
        case .streakFlip:
            [CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [.init(relativeTime: 0.02, value: 0.8), .init(relativeTime: 0.24, value: 0)], relativeTime: 0)]
        case .impact:
            [CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [.init(relativeTime: 0.01, value: 1), .init(relativeTime: 0.29, value: 0)], relativeTime: 0)]
        case .levelUp:
            [CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [.init(relativeTime: 0, value: 0.2), .init(relativeTime: 0.6, value: 0.8)], relativeTime: 0)]
        default: []
        }
    }
    #else
    private init() {}

    /// Mac trackpads only render a few generic patterns, and only while a finger is down.
    func prewarm() {}

    func play(_ cue: PlayCue, intensity: Float = 1) {
        let performer = NSHapticFeedbackManager.defaultPerformer
        switch cue {
        case .tick, .select, .release, .swing: performer.perform(.alignment, performanceTime: .now)
        case .press, .tap, .pop, .land: performer.perform(.generic, performanceTime: .now)
        default: performer.perform(.levelChange, performanceTime: .now)
        }
    }
    #endif
}

// MARK: - Sounds

@MainActor
final class PlaySounds {
    static let shared = PlaySounds()
    private var players: [String: [AVAudioPlayer]] = [:]

    private init() {
        #if os(iOS)
        // Never interrupt the user's podcast or music: UI cues mix in.
        let session = AVAudioSession.sharedInstance()
        if session.category == .soloAmbient { try? session.setCategory(.ambient, options: [.mixWithOthers]) }
        #endif
    }

    private static var bundle: Bundle {
        #if SWIFT_PACKAGE
        .module
        #else
        .main
        #endif
    }

    private static let names = ["tick", "pop", "correct", "wrong", "ignite", "streak", "chest", "levelup", "complete", "freeze"]

    func preload() { for name in Self.names where players[name] == nil { load(name) } }

    private func load(_ name: String) {
        guard let url = Self.bundle.url(forResource: name, withExtension: "wav", subdirectory: "Sounds")
                ?? Self.bundle.url(forResource: name, withExtension: "wav") else { return }
        // Several voices per cue so rapid ticks overlap instead of cutting each other off.
        players[name] = (0..<(name == "tick" || name == "pop" ? 4 : 2)).compactMap { _ in try? AVAudioPlayer(contentsOf: url) }
        players[name]?.forEach { $0.enableRate = true; $0.prepareToPlay() }
    }

    func play(_ name: String, rate: Float = 1, volume: Float? = nil) {
        if players[name] == nil { load(name) }
        guard let voices = players[name], !voices.isEmpty else { return }
        let player = voices.first { !$0.isPlaying } ?? voices[0]
        player.volume = volume ?? (name == "tick" ? 0.5 : 0.85)
        player.rate = rate
        player.currentTime = 0
        player.play()
    }
}
