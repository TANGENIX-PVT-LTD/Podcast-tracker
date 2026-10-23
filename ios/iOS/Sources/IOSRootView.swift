import AuthenticationServices
import SwiftUI
import UIKit

struct IOSRootView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        Group {
            if authManager.isAuthenticated {
                IOSAppShell()
            } else {
                IOSLoginView()
            }
        }
        .animation(.smooth(duration: 0.32), value: authManager.isAuthenticated)
        .onOpenURL { url in
            if url.host?.lowercased() == "auth-callback" {
                authManager.handleCallback(url: url)
            } else {
                viewModel.handleAppURL(url)
            }
        }
    }
}

private enum IOSAppTab: Hashable {
    case today, library, progress, brain, settings
}

private enum IOSAppSheet: Identifiable {
    case addEpisode
    case rescue

    var id: Int {
        switch self {
        case .addEpisode: 0
        case .rescue: 1
        }
    }
}

struct IOSAppShell: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var selectedTab: IOSAppTab = .today
    @State private var activeSheet: IOSAppSheet?

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                IOSTodayView(
                    onAdd: { activeSheet = .addEpisode },
                    onRescue: { activeSheet = .rescue }
                )
            }
            .tabItem { Label("Today", systemImage: "sun.max.fill") }
            .tag(IOSAppTab.today)

            NavigationStack {
                IOSLibraryView(onAdd: { activeSheet = .addEpisode })
            }
            .tabItem { Label("Library", systemImage: "books.vertical.fill") }
            .tag(IOSAppTab.library)

            NavigationStack {
                IOSProgressView(onRescue: { activeSheet = .rescue })
            }
            .tabItem { Label("Progress", systemImage: "chart.bar.fill") }
            .tag(IOSAppTab.progress)

            NavigationStack { BrainView() }.tabItem { Label("Brain", systemImage: "brain") }.tag(IOSAppTab.brain)

            NavigationStack {
                IOSSettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            .tag(IOSAppTab.settings)
        }
        .tabViewStyle(.sidebarAdaptable)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .addEpisode:
                IOSEpisodeEditor()
            case .rescue:
                IOSRescueSheet()
            }
        }
        .fullScreenCover(item: $viewModel.selectedPodcast, onDismiss: {
            PlayMoments.shared.playerClosed(viewModel: viewModel)
        }) { podcast in
            IOSPlayerView(podcast: podcast)
        }
        .onChange(of: selectedTab) { PlayFeedback.play(.select, sound: false) }
        .task { PlayMoments.shared.checkFreeze(viewModel: viewModel) }
        .overlay(alignment: .top) { AchievementToast() }
        .overlay { PlayMomentsOverlay(active: viewModel.selectedPodcast == nil) }
        .onChange(of: viewModel.showAddPodcast) { _, shown in
            if shown { activeSheet = .addEpisode; viewModel.showAddPodcast = false }
        }
        .onChange(of: viewModel.showRescueSheet) { _, shown in
            if shown { activeSheet = .rescue; viewModel.showRescueSheet = false }
        }
        .onChange(of: viewModel.selectedSection) { _, section in
            selectedTab = tab(for: section)
        }
        .safeAreaInset(edge: .bottom) {
            if viewModel.isTracking, let podcast = viewModel.selectedPodcast {
                IOSMiniPlayer(podcast: podcast)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 2)
            }
        }
    }

    private func tab(for section: AppSection) -> IOSAppTab {
        switch section {
        case .today: .today
        case .library: .library
        case .progress: .progress
        case .brain: .brain
        }
    }
}

private struct IOSMiniPlayer: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let podcast: Podcast

    var body: some View {
        Button { viewModel.selectedPodcast = podcast } label: {
            HStack(spacing: 12) {
                PodcastThumbnail(podcast: podcast, width: 52, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Learning now").font(.caption2).foregroundStyle(.secondary)
                    Text(podcast.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                }
                Spacer()
                Text(viewModel.currentSessionSeconds.formattedTime)
                    .font(.caption.monospacedDigit())
                Image(systemName: "chevron.up")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
    }
}

struct IOSLoginView: View {
    @EnvironmentObject private var authManager: AuthManager

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 30) {
                    Spacer(minLength: 48)
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 116, height: 116)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .shadow(color: .black.opacity(0.2), radius: 26, y: 14)

                    VStack(spacing: 10) {
                        Text("PodTrackio")
                            .font(.largeTitle.weight(.heavy))
                        Text("Turn podcasts into knowledge you keep.")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    EchoView(mood: .happy, size: 96)

                    IOSGlassSurface(cornerRadius: 28) {
                        VStack(spacing: 16) {
                            SignInWithAppleButton(.continue) { request in
                                authManager.prepareAppleSignInRequest(request)
                            } onCompletion: { result in
                                authManager.handleAppleSignIn(result)
                            }
                            .signInWithAppleButtonStyle(.black)
                            .frame(height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .disabled(authManager.isSigningIn)

                            Button {
                                authManager.signInWithGoogle()
                            } label: {
                                Label("Continue with Google", systemImage: "globe")
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 40)
                            }
                            .buttonStyle(.glassProminent)
                            .disabled(authManager.isSigningIn)

                            if authManager.isSigningIn {
                                HStack(spacing: 9) {
                                    ProgressView()
                                    Text("Connecting securely…")
                                }
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            }

                            if let message = authManager.authErrorMessage, !message.isEmpty {
                                Label(message, systemImage: "exclamationmark.triangle.fill")
                                    .font(.footnote)
                                    .foregroundStyle(.orange)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(22)
                    }

                    VStack(alignment: .leading, spacing: 13) {
                        benefit("Resume from the same moment on Mac and iPhone", icon: "arrow.triangle.2.circlepath")
                        benefit("Keep notes, goals, and summaries in one workspace", icon: "books.vertical.fill")
                        benefit("Protect your session and AI keys with Keychain", icon: "lock.shield.fill")
                    }

                    Text("Your raw transcripts, downloads, and AI keys stay on this device.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func benefit(_ text: String, icon: String) -> some View {
        Label {
            Text(text).font(.subheadline).foregroundStyle(.secondary)
        } icon: {
            Image(systemName: icon).foregroundStyle(.tint).frame(width: 26)
        }
    }
}
