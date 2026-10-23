import SwiftUI

struct MainView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var authManager: AuthManager

    var body: some View {
        Group {
            if authManager.isAuthenticated {
                authenticatedContent
            } else {
                LoginView()
            }
        }
        .onOpenURL { authManager.handleCallback(url: $0) }
        #if DEBUG
        .task { PlayDemo.installIfRequested(viewModel, auth: authManager) }
        #endif
        .applyingAppTheme()
    }

    private var authenticatedContent: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $viewModel.selectedSection) { section in
                Label(section.rawValue, systemImage: section.icon).tag(section)
            }
            .navigationTitle("PodTrackio")
            .listStyle(.sidebar)
            .safeAreaInset(edge: .top) {
                StreakBadge().padding(.horizontal, 16).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .safeAreaInset(edge: .bottom) {
                if viewModel.isTracking, let podcast = viewModel.selectedPodcast {
                    ActiveSessionView(podcast: podcast)
                        .environmentObject(viewModel)
                        .padding(10)
                }
            }
        } detail: {
            ZStack {
                ThemeBackdrop()
                Group {
                    if let podcast = viewModel.selectedPodcast {
                        PlayerView(podcast: podcast)
                    } else {
                        switch viewModel.selectedSection {
                        case .today: TodayView()
                        case .library: LibraryView()
                        case .progress: LearningProgressView()
                        case .brain: BrainView()
                        }
                    }
                }
            }
            .navigationTitle(viewModel.selectedPodcast?.title ?? viewModel.selectedSection.rawValue)
            .toolbar {
                if viewModel.selectedPodcast != nil {
                    ToolbarItem {
                        Button("Back", systemImage: "chevron.backward") { viewModel.selectedPodcast = nil }
                            .help("Back to \(viewModel.selectedSection.rawValue)")
                    }
                    ToolbarSpacer(.fixed)
                }
                ToolbarItemGroup {
                    Button("Add Episode", systemImage: "plus") { viewModel.showAddPodcast = true }
                        .keyboardShortcut("n", modifiers: .command)
                    SettingsLink { Label("Settings", systemImage: "gearshape") }
                }
                if viewModel.selectedPodcast != nil {
                    ToolbarItem(placement: .principal) { PlayerGoalChip() }
                }
                if viewModel.selectedPodcast != nil {
                    ToolbarSpacer(.fixed)
                    ToolbarItem {
                        Button("Learning Inspector", systemImage: "sidebar.trailing") {
                            viewModel.inspectorPresented.toggle()
                        }
                    }
                }
            }
        }
        .searchable(text: $viewModel.searchText, placement: .toolbar, prompt: "Search episodes and categories")
        .sheet(isPresented: $viewModel.showFocusGate) { FocusModeSettingsView() }
        .sheet(isPresented: $viewModel.showAddPodcast) { AddPodcastSheet() }
        .sheet(isPresented: $viewModel.showRescueSheet) { DistractionRescueSheet() }
        .overlay(alignment: .top) { AchievementToast() }
        .overlay { PlayMomentsOverlay() }
        .onChange(of: viewModel.selectedSection) { _, _ in viewModel.selectedPodcast = nil }
        .onChange(of: viewModel.selectedPodcast?.id) { old, new in
            if old != nil && new == nil { PlayMoments.shared.playerClosed(viewModel: viewModel) }
        }
        .task { PlayMoments.shared.checkFreeze(viewModel: viewModel) }
    }

}

private struct ActiveSessionView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let podcast: Podcast
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Learning now").font(.caption).foregroundStyle(.secondary)
            Text(podcast.title).font(.callout.weight(.semibold)).lineLimit(2)
            HStack {
                Text(viewModel.currentSessionSeconds.formattedTime).monospacedDigit()
                Spacer()
                if let commitment = viewModel.activeCommitment {
                    Text("\(Int(ceil(commitment.remainingSeconds / 60))) min left")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                } else {
                    Label("Playing", systemImage: "waveform")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .chunkyCard(cornerRadius: 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Active learning session, \(podcast.title), \(viewModel.currentSessionSeconds.formattedTime)")
    }
}
