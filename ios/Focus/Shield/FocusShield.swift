import ManagedSettings
import ManagedSettingsUI
import UIKit

final class FocusShield: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        let state = FocusSnapshotStore.loadState()
        let minutes = Int(ceil(state.remainingSeconds() / 60))
        return ShieldConfiguration(backgroundBlurStyle: .systemMaterial, backgroundColor: .systemBackground,
            icon: UIImage(systemName: "headphones.circle.fill"),
            title: .init(text: "The scroll can wait.", color: .label),
            subtitle: .init(text: "\(minutes) minutes of learning first. Open PodTrackio to finish today's target.", color: .secondaryLabel),
            primaryButtonLabel: .init(text: "Back to learning", color: .white), primaryButtonBackgroundColor: .systemBlue)
    }
}
