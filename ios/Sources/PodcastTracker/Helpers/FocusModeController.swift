import Combine
import Foundation

#if os(iOS)
import DeviceActivity
import FamilyControls
import ManagedSettings

@MainActor
final class FocusModeController: ObservableObject {
    static let shared = FocusModeController()
    @Published private(set) var state = FocusSnapshotStore.loadState()
    @Published private(set) var authorization = AuthorizationCenter.shared.authorizationStatus
    @Published var message: String?
    private(set) var justUnlocked = false
    var selection: FamilyActivitySelection { FocusSnapshotStore.loadSelection() }

    func authorize() async {
        do { try await AuthorizationCenter.shared.requestAuthorization(for: .individual); refresh() }
        catch { message = "Screen Time access was not granted. \(error.localizedDescription)"; refresh() }
    }

    func configure(enabled: Bool, selection: FamilyActivitySelection? = nil) {
        guard !state.isLocked else { message = "Complete today's target before changing Focus Mode."; return }
        if enabled {
            guard FocusSnapshotStore.authorized else {
                message = "Allow Screen Time access first."; return
            }
            let choice = selection ?? self.selection
            guard !choice.applicationTokens.isEmpty, choice.categoryTokens.isEmpty, choice.webDomainTokens.isEmpty else {
                message = "Choose individual apps only. Leave PodTrackio and playback apps unselected."; return
            }
            do {
                try FocusSnapshotStore.saveSelection(choice)
                try DeviceActivityCenter().startMonitoring(.podtrackioDaily, during: DeviceActivitySchedule(
                    intervalStart: DateComponents(hour: 0, minute: 0, second: 0),
                    intervalEnd: DateComponents(hour: 23, minute: 59, second: 59), repeats: true))
            } catch { message = "Could not activate daily blocking: \(error.localizedDescription)"; return }
        } else { DeviceActivityCenter().stopMonitoring([.podtrackioDaily]) }
        guard state.configure(enabled: enabled) else { return }
        persistAndApply()
    }

    func updateGoal(target: Double, localSeconds: Double, sharedSeconds: Double? = nil, owner: String?) {
        let locked = state.isLocked
        let before = state.creditedSeconds
        state.updateGoal(target: target, localSeconds: localSeconds, sharedSeconds: sharedSeconds, owner: owner)
        justUnlocked = locked && !state.isLocked
        if justUnlocked || Int(before / 15) != Int(state.creditedSeconds / 15) { checkpoint() }
    }

    func refresh() {
        authorization = AuthorizationCenter.shared.authorizationStatus
        persistAndApply()
    }

    func checkpoint() { persistAndApply() }

    private func persistAndApply() {
        do { _ = try FocusSnapshotStore.readState(); try FocusSnapshotStore.saveState(state); FocusSnapshotStore.apply() }
        catch { message = "Focus progress could not be saved: \(error.localizedDescription)" }
    }
}
#else
import AppKit
import UniformTypeIdentifiers

@MainActor
final class FocusModeController: ObservableObject {
    static let shared = FocusModeController()
    @Published private(set) var state: FocusDayState
    @Published var message: String?
    private(set) var justUnlocked = false
    private var observer: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var midnightTimer: Timer?
    private let defaults = UserDefaults.standard

    private init() {
        state = defaults.data(forKey: "podtrackio.focus.v1").flatMap { try? JSONDecoder().decode(FocusDayState.self, from: $0) } ?? FocusDayState()
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.enforce() } }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.refresh() } }
        scheduleMidnightCheck()
    }

    func chooseApps() {
        guard !state.isLocked else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Choose distracting apps. PodTrackio stays available. Apps are hidden, never terminated."
        guard panel.runModal() == .OK else { return }
        let bundles = panel.urls.compactMap(Bundle.init(url:)).filter { $0.bundleIdentifier != Bundle.main.bundleIdentifier }
        state.selectedBundleIDs = bundles.compactMap(\.bundleIdentifier)
        state.selectedNames = bundles.map { ($0.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? ($0.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? $0.bundleURL.deletingPathExtension().lastPathComponent }
        checkpoint()
    }

    func configure(enabled: Bool) {
        guard !enabled || !state.selectedBundleIDs.isEmpty else { message = "Choose at least one distracting app first."; return }
        guard state.configure(enabled: enabled) else { message = "Complete today's target before changing Focus Mode."; return }
        refresh()
    }

    func updateGoal(target: Double, localSeconds: Double, sharedSeconds: Double? = nil, owner: String?) {
        let locked = state.isLocked
        let before = state.creditedSeconds
        state.updateGoal(target: target, localSeconds: localSeconds, sharedSeconds: sharedSeconds, owner: owner)
        justUnlocked = locked && !state.isLocked
        if justUnlocked || Int(before / 15) != Int(state.creditedSeconds / 15) { checkpoint() }
    }

    func checkpoint() {
        do { defaults.set(try JSONEncoder().encode(state), forKey: "podtrackio.focus.v1") }
        catch { message = "Focus progress could not be saved: \(error.localizedDescription)" }
    }

    func refresh() { checkpoint(); enforce(); scheduleMidnightCheck() }

    private func scheduleMidnightCheck() {
        midnightTimer?.invalidate()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!
        midnightTimer = Timer.scheduledTimer(withTimeInterval: max(1, tomorrow.timeIntervalSinceNow + 0.25), repeats: false) { [weak self] _ in
            Task { @MainActor in self?.refresh(); AppViewModel.shared.refreshCloudData() }
        }
    }

    private func enforce() {
        guard state.isLocked, let application = NSWorkspace.shared.frontmostApplication,
              let id = application.bundleIdentifier, state.selectedBundleIDs.contains(id) else { return }
        let hidden = application.hide()
        message = hidden ? "\(state.remainingMinutes) learning minutes first. Your app is still running safely."
            : "macOS could not hide this app. The Mac gate is best effort."
        NotificationCenter.default.post(name: .showFocusLearningGate, object: nil)
    }
}

extension Notification.Name { static let showFocusLearningGate = Notification.Name("showFocusLearningGate") }
#endif
