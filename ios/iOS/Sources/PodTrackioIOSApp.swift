import SwiftUI
import UIKit

@MainActor
final class PodTrackioAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        NotificationManager.shared.registerBeforeLaunchCompletes()
        // PlayerController configures the session immediately before playback.
        // Keeping audio activation out of launch removes unnecessary startup work.
        return true
    }
}

@main
struct PodTrackioIOSApp: App {
    @UIApplicationDelegateAdaptor(PodTrackioAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = AppViewModel.shared
    @StateObject private var authManager = AuthManager.shared

    var body: some Scene {
        WindowGroup {
            IOSRootView()
                .environmentObject(viewModel)
                .environmentObject(authManager)
                .applyingAppTheme()
                .fontDesign(.rounded)
                #if DEBUG
                .task { PlayDemo.installIfRequested(viewModel, auth: authManager) }
                #endif
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                viewModel.refreshCloudData()
            case .background:
                viewModel.saveData()
            default:
                break
            }
        }
    }
}
