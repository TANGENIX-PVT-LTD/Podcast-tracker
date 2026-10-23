import DeviceActivity

final class FocusMonitor: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) { FocusSnapshotStore.apply() }
    override func intervalDidEnd(for activity: DeviceActivityName) { FocusSnapshotStore.apply() }
}
