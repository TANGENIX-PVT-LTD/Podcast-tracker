import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

extension DeviceActivityName { static var podtrackioDaily: Self { Self("podtrackio.daily-learning") } }

enum FocusSnapshotStore {
    static let appGroup = "group.com.tangenix.podtrackio"
    static var store: ManagedSettingsStore { ManagedSettingsStore(named: .init("podtrackio.learning")) }

    private static func url(_ name: String) throws -> URL {
        guard let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return directory.appendingPathComponent(name)
    }

    static func readState() throws -> FocusDayState {
        let path = try url("focus-day-v1.json")
        guard FileManager.default.fileExists(atPath: path.path) else { return FocusDayState() }
        let state = try JSONDecoder().decode(FocusDayState.self, from: Data(contentsOf: path))
        guard (1...6).contains(state.blocks), state.creditedSeconds.isFinite, state.creditedSeconds >= 0,
              state.creditedSeconds <= 86400,
              state.dailyTargetSeconds.isFinite, (300...14400).contains(state.dailyTargetSeconds),
              (state.remoteSeconds ?? 0).isFinite, (state.remoteSeconds ?? 0) >= 0, LearningCalendar.date(from: state.day) != nil else {
            throw CocoaError(.coderReadCorrupt)
        }
        return state
    }
    static func loadState() -> FocusDayState {
        do { return try readState() }
        catch {
            var unavailable = FocusDayState()
            unavailable.enabled = (try? url("focus-day-v1.json")).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            unavailable.blocks = 6
            return unavailable
        }
    }
    static func saveState(_ state: FocusDayState) throws {
        try JSONEncoder().encode(state).write(to: url("focus-day-v1.json"), options: .atomic)
    }
    static func loadSelection() -> FamilyActivitySelection {
        guard let path = try? url("focus-apps-v1.json"), let data = try? Data(contentsOf: path),
              let choice = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else { return .init() }
        return choice
    }
    static func saveSelection(_ selection: FamilyActivitySelection) throws {
        try JSONEncoder().encode(selection).write(to: url("focus-apps-v1.json"), options: .atomic)
    }
    static var authorized: Bool {
        let status = AuthorizationCenter.shared.authorizationStatus
        if #available(iOS 26.4, *), status == .approvedWithDataAccess { return true }
        return status == .approved
    }
    static func apply() {
        guard let state = try? readState() else { return }
        guard authorized, state.isLocked else {
            store.clearAllSettings(); return
        }
        let tokens = loadSelection().applicationTokens
        if !tokens.isEmpty { store.shield.applications = tokens }
    }
}
