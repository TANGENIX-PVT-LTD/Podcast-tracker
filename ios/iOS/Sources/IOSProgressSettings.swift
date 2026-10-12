import SwiftUI
import UserNotifications

struct IOSProgressView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let onRescue: () -> Void
    @State private var displayedMonth = Date()
    @State private var showScheduleDay = false

    var body: some View {
        ZStack {
            ThemeBackdrop()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: PodSpacing.section) {
                    overview
                    goals
                    calendarCard
                    rescueReview
                    IOSAchievementsGrid()
                }
                .padding(PodSpacing.page)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Progress")
        .sheet(isPresented: $showScheduleDay) { IOSScheduleDaySheet(day: viewModel.selectedCalendarDate) }
    }

    private var overview: some View {
        IOSGlassSurface(cornerRadius: 24, tint: .accentColor.opacity(0.1)) {
            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(.tertiary.opacity(0.25), lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: viewModel.stats.levelProgress)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: viewModel.stats.currentLevel.iconName).font(.title2).foregroundStyle(.tint)
                }
                .frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Level \(viewModel.stats.currentLevel.number)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(viewModel.stats.currentLevel.title).font(.title2.bold())
                    Text("\(viewModel.stats.totalXP) total XP · \(viewModel.stats.formattedTotalTime) learned")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(18)
        }
    }

    private var goals: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            goalCard(
                "Daily",
                value: viewModel.todayActivity?.watchedSeconds ?? 0,
                target: viewModel.habitSettings.currentDailyGoalMinutes * 60,
                label: "\(viewModel.todayWatchedMinutes) / \(Int(viewModel.habitSettings.currentDailyGoalMinutes)) min"
            )
            goalCard(
                "Weekly",
                value: viewModel.stats.weeklySecondsWatched,
                target: viewModel.stats.weeklyGoalHours * 3600,
                label: "\(viewModel.stats.formattedWeeklyTime) / \(viewModel.stats.weeklyGoalHours.formatted())h"
            )
        }
    }

    private func goalCard(_ title: String, value: Double, target: Double, label: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            ProgressView(value: min(value / max(target, 1), 1))
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .podCard(cornerRadius: 18)
    }

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(displayedMonth.formatted(.dateTime.month(.wide).year())).font(.title3.bold())
                Spacer()
                Button("Previous", systemImage: "chevron.left") { shiftMonth(-1) }.labelStyle(.iconOnly)
                Button("Today") { displayedMonth = Date(); viewModel.selectedCalendarDate = Date() }.font(.caption.weight(.semibold))
                Button("Next", systemImage: "chevron.right") { shiftMonth(1) }.labelStyle(.iconOnly)
            }
            IOSMonthGrid(
                month: displayedMonth,
                selection: $viewModel.selectedCalendarDate,
                activities: viewModel.activities,
                scheduledDates: viewModel.podcasts.compactMap(\.scheduledAt)
            )
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.selectedCalendarDate.formatted(date: .abbreviated, time: .omitted)).font(.headline)
                    if let activity = viewModel.activity(for: viewModel.selectedCalendarDate) {
                        Text("\(Int(activity.watchedSeconds / 60)) min · \(activity.sessions) sessions · \(activity.xpEarned) XP")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No recorded activity").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Schedule", systemImage: "calendar.badge.plus") { showScheduleDay = true }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
            }
            let scheduled = viewModel.scheduledPodcasts(on: viewModel.selectedCalendarDate)
            ForEach(scheduled) { podcast in
                Button { viewModel.selectPodcast(podcast) } label: {
                    HStack {
                        Image(systemName: "play.rectangle.fill").foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(podcast.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                            Text(podcast.scheduledAt?.formatted(date: .omitted, time: .shortened) ?? "Scheduled")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(17)
        .podCard(cornerRadius: 22)
    }

    private var rescueReview: some View {
        let insights = viewModel.weeklyRescueInsights
        return VStack(alignment: .leading, spacing: 15) {
            HStack {
                Label("Distraction replacement", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                    .font(.title3.bold())
                Spacer()
                Button("Rescue", systemImage: "bolt.fill", action: onRescue).buttonStyle(.glassProminent)
            }
            HStack(spacing: 18) {
                insight("Kept", "\(insights.completed)")
                insight("Reclaimed", "\(insights.reclaimedMinutes)m")
                insight("Rate", insights.completionRate?.formatted(.percent.precision(.fractionLength(0))) ?? "—")
            }
            Text(insights.coachingMessage).font(.subheadline).foregroundStyle(.secondary)
            if let cue = insights.leadingCue {
                Label("Biggest pull: \(cue.title)", systemImage: cue.symbolName).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
        }
        .padding(17)
        .podCard(cornerRadius: 22)
    }

    private func insight(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.title3.bold()).contentTransition(.numericText())
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func shiftMonth(_ value: Int) {
        displayedMonth = Calendar.current.date(byAdding: .month, value: value, to: displayedMonth) ?? displayedMonth
    }
}

private struct IOSMonthGrid: View {
    let month: Date
    @Binding var selection: Date
    let activities: [DailyLearningActivity]
    let scheduledDates: [Date]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)

    private var days: [Date?] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let blanks = Array<Date?>(repeating: nil, count: calendar.component(.weekday, from: interval.start) - 1)
        return blanks + range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: interval.start) }.map(Optional.some)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 7) {
            ForEach(Calendar.current.veryShortWeekdaySymbols, id: \.self) {
                Text($0).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
            ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                if let date { day(date) } else { Color.clear.frame(height: 42) }
            }
        }
    }

    private func day(_ date: Date) -> some View {
        let key = LearningCalendar.dateKey(for: date)
        let activity = activities.first { $0.dateKey == key }
        let isScheduled = scheduledDates.contains { Calendar.current.isDate($0, inSameDayAs: date) }
        let isSelected = Calendar.current.isDate(date, inSameDayAs: selection)
        return Button { selection = date } label: {
            VStack(spacing: 3) {
                Text("\(Calendar.current.component(.day, from: date))").font(.caption.monospacedDigit())
                HStack(spacing: 3) {
                    Circle().fill(activity?.goalCompleted == true ? Color.green : activity == nil ? Color.clear : Color.accentColor).frame(width: 5, height: 5)
                    Circle().fill(isScheduled ? Color.orange : Color.clear).frame(width: 5, height: 5)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(isSelected ? Color.accentColor : .clear, in: Circle())
            .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
    }
}

private struct IOSAchievementsGrid: View {
    @EnvironmentObject private var viewModel: AppViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Achievements", subtitle: "Earned through consistent learning")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 12)], spacing: 12) {
                ForEach(viewModel.achievements) { achievement in
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Image(systemName: achievement.iconName).font(.title2).foregroundStyle(achievement.isUnlocked ? Color.accentColor : .secondary)
                            Spacer()
                            if achievement.isUnlocked { Image(systemName: "checkmark.seal.fill").foregroundStyle(.green) }
                        }
                        Text(achievement.title).font(.subheadline.weight(.semibold))
                        Text(achievement.description).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                    }
                    .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
                    .padding(14)
                    .podCard(cornerRadius: 17)
                    .opacity(achievement.isUnlocked ? 1 : 0.62)
                }
            }
        }
    }
}

struct IOSSettingsView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        ZStack {
            ThemeBackdrop()
            List {
                Section("Experience") {
                    NavigationLink { IOSAppearanceSettings() } label: { settingsLabel("Appearance", "paintpalette.fill", .purple) }
                    NavigationLink { IOSHabitSettings() } label: { settingsLabel("Learning goals", "target", .blue) }
                    NavigationLink { IOSNotificationSettings() } label: { settingsLabel("Notifications", "bell.badge.fill", .red) }
                }
                Section("Workspace") {
                    NavigationLink { BrainSettingsView() } label: { settingsLabel("Personal memory", "brain", .purple) }
                    NavigationLink { IOSAISettings() } label: { settingsLabel("AI & transcripts", "sparkles", .indigo) }
                    NavigationLink { IOSDownloadSettings() } label: { settingsLabel("Downloads", "arrow.down.circle.fill", .green) }
                    NavigationLink { IOSCategorySettings() } label: { settingsLabel("Categories", "tag.fill", .orange) }
                    NavigationLink { IOSCollectionSettings() } label: { settingsLabel("Collections", "rectangle.stack.fill", .teal) }
                }
                Section("Account") {
                    NavigationLink { IOSAccountSettings() } label: { settingsLabel("PodTrackio account", "person.crop.circle.fill", .cyan) }
                }
                Section {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    Text("Raw transcripts, downloaded media, and API keys stay on this device. Learning data and compact summaries sync through Supabase.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Settings")
        .onDisappear { viewModel.saveData(); viewModel.rescheduleNotifications() }
    }

    private func settingsLabel(_ title: String, _ symbol: String, _ color: Color) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }
}

private struct IOSAppearanceSettings: View {
    @AppStorage(AppTheme.storageKey) private var selectedTheme = AppTheme.system.rawValue
    var body: some View {
        ZStack {
            ThemeBackdrop()
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    ForEach(AppTheme.allCases) { theme in
                        Button { selectedTheme = theme.rawValue } label: {
                            VStack(alignment: .leading, spacing: 11) {
                                HStack {
                                    ForEach(Array(theme.previewColors.enumerated()), id: \.offset) { _, color in Circle().fill(color).frame(width: 21, height: 21) }
                                    Spacer()
                                    if selectedTheme == theme.rawValue { Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.tint) }
                                }
                                Text(theme.name).font(.headline).foregroundStyle(.primary)
                                Text(theme.detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                            .padding(15)
                        }
                        .buttonStyle(.plain)
                        .podCard(cornerRadius: 18)
                        .overlay { RoundedRectangle(cornerRadius: 18).stroke(selectedTheme == theme.rawValue ? theme.tint : .clear, lineWidth: 2) }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Appearance")
    }
}

private struct IOSHabitSettings: View {
    @EnvironmentObject private var viewModel: AppViewModel
    var body: some View {
        Form {
            Section("Daily learning") {
                Toggle("Adaptive Build-Up Mode", isOn: $viewModel.habitSettings.adaptiveBuildUpEnabled)
                LabeledContent("Current target", value: "\(Int(viewModel.habitSettings.currentDailyGoalMinutes)) minutes")
                Slider(value: $viewModel.habitSettings.currentDailyGoalMinutes, in: 5...180, step: 5)
                LabeledContent("Long-term target", value: "\(Int(viewModel.habitSettings.targetDailyGoalMinutes)) minutes")
                Slider(value: $viewModel.habitSettings.targetDailyGoalMinutes, in: max(5, viewModel.habitSettings.currentDailyGoalMinutes)...240, step: 5)
            }
            Section("Consistency") {
                LabeledContent("Minimum streak session", value: "\(Int(viewModel.habitSettings.minimumQualifyingSessionMinutes)) minutes")
                Stepper("Weekly goal: \(viewModel.stats.weeklyGoalHours.formatted()) hours", value: $viewModel.stats.weeklyGoalHours, in: 1...40, step: 0.5)
            }
            Section {
                Text("The daily target rises by five minutes after five successful days in the previous week. It never drops automatically.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Learning Goals")
        .onChange(of: viewModel.habitSettings.currentDailyGoalMinutes) { _, value in viewModel.setDailyGoal(value) }
        .onDisappear { viewModel.setWeeklyGoal(viewModel.stats.weeklyGoalHours) }
    }
}

private struct IOSNotificationSettings: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject private var manager = NotificationManager.shared

    var body: some View {
        Form {
            Section("Delivery") {
                Toggle("Learning reminders", isOn: $viewModel.notificationPreferences.isEnabled)
                LabeledContent("Permission", value: statusText)
                if manager.authorizationStatus != .authorized {
                    Button("Allow Notifications") {
                        Task { _ = await manager.requestAuthorization(); viewModel.rescheduleNotifications() }
                    }
                }
            }
            Section("Daily cues") {
                DatePicker("Morning", selection: timeBinding(\.morning), displayedComponents: .hourAndMinute)
                DatePicker("Afternoon", selection: timeBinding(\.afternoon), displayedComponents: .hourAndMinute)
                DatePicker("Evening", selection: timeBinding(\.evening), displayedComponents: .hourAndMinute)
            }
            Section("Reminder days") {
                ForEach(Array(Calendar.current.weekdaySymbols.enumerated()), id: \.offset) { index, name in
                    Toggle(name, isOn: Binding(
                        get: { viewModel.notificationPreferences.enabledWeekdays.contains(index + 1) },
                        set: { enabled in
                            if enabled { viewModel.notificationPreferences.enabledWeekdays.insert(index + 1) }
                            else { viewModel.notificationPreferences.enabledWeekdays.remove(index + 1) }
                        }
                    ))
                }
            }
            Section("Quiet hours") {
                Toggle("Use quiet hours", isOn: $viewModel.notificationPreferences.quietHoursEnabled)
                DatePicker("From", selection: timeBinding(\.quietHoursStart), displayedComponents: .hourAndMinute)
                DatePicker("Until", selection: timeBinding(\.quietHoursEnd), displayedComponents: .hourAndMinute)
            }
            Section("Adaptive rescue") {
                if let pattern = viewModel.learnedDistractionPattern {
                    Label("\(pattern.cue.title) · \(weekday(pattern.weekday)) at \(formatTime(pattern.hour, pattern.minute))", systemImage: pattern.cue.symbolName)
                    Text("Learned from \(pattern.observations) similar Rescue attempts stored on this device.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("After three similar Rescue attempts, PodTrackio can intervene before that pattern—once per week, not every day.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Notifications")
        .onDisappear { viewModel.saveData(); viewModel.rescheduleNotifications() }
    }

    private var statusText: String {
        switch manager.authorizationStatus {
        case .authorized, .provisional, .ephemeral: "Allowed"
        case .denied: "Denied in Settings"
        case .notDetermined: "Not requested"
        @unknown default: "Unknown"
        }
    }

    private func timeBinding(_ keyPath: WritableKeyPath<NotificationPreferences, NotificationPreferences.TimeOfDay>) -> Binding<Date> {
        Binding(
            get: {
                let value = viewModel.notificationPreferences[keyPath: keyPath]
                return Calendar.current.date(from: DateComponents(hour: value.hour, minute: value.minute)) ?? Date()
            },
            set: { date in
                let values = Calendar.current.dateComponents([.hour, .minute], from: date)
                viewModel.notificationPreferences[keyPath: keyPath] = .init(hour: values.hour ?? 0, minute: values.minute ?? 0)
            }
        )
    }

    private func weekday(_ value: Int) -> String {
        let names = Calendar.current.weekdaySymbols
        return names.indices.contains(value - 1) ? names[value - 1] : "Weekly"
    }

    private func formatTime(_ hour: Int, _ minute: Int) -> String {
        Calendar.current.date(from: DateComponents(hour: hour, minute: minute))?.formatted(date: .omitted, time: .shortened)
            ?? String(format: "%02d:%02d", hour, minute)
    }
}

private struct IOSAISettings: View {
    @State private var groqKey = ""
    @State private var transcriptKey = ""
    @State private var hasGroq = KeychainStore.groqAPIKey() != nil
    @State private var hasTranscript = KeychainStore.transcriptAPIKey() != nil
    @State private var status: String?
    @State private var isTesting = false

    var body: some View {
        Form {
            Section("TranscriptAPI") {
                SecureField(hasTranscript ? "Stored in Keychain" : "TranscriptAPI key", text: $transcriptKey)
                HStack {
                    Button("Save") { saveTranscript() }.disabled(transcriptKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Remove", role: .destructive) { removeTranscript() }.disabled(!hasTranscript)
                }
            }
            Section("Groq") {
                SecureField(hasGroq ? "Stored in Keychain" : "gsk_…", text: $groqKey)
                HStack {
                    Button("Save") { saveGroq() }.disabled(groqKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Remove", role: .destructive) { removeGroq() }.disabled(!hasGroq)
                    Button("Test") { testGroq() }.disabled(!hasGroq || isTesting)
                    if isTesting { ProgressView() }
                }
            }
            Section("Models") {
                LabeledContent("Summaries", value: "openai/gpt-oss-120b")
                LabeledContent("Transcription", value: "whisper-large-v3-turbo")
            }
            if let status { Section { Text(status).font(.footnote).foregroundStyle(.secondary) } }
            Section {
                Text("Keys remain in this device’s Keychain. They are never saved to PodTrackio JSON or Supabase.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("AI & Transcripts")
    }

    private func saveTranscript() {
        do { try KeychainStore.saveTranscriptAPIKey(transcriptKey); transcriptKey = ""; hasTranscript = true; status = "TranscriptAPI key saved securely." }
        catch { status = error.localizedDescription }
    }
    private func removeTranscript() {
        do { try KeychainStore.removeTranscriptAPIKey(); hasTranscript = false; status = "TranscriptAPI key removed." }
        catch { status = error.localizedDescription }
    }
    private func saveGroq() {
        do { try KeychainStore.saveGroqAPIKey(groqKey); groqKey = ""; hasGroq = true; status = "Groq key saved securely." }
        catch { status = error.localizedDescription }
    }
    private func removeGroq() {
        do { try KeychainStore.removeGroqAPIKey(); hasGroq = false; status = "Groq key removed." }
        catch { status = error.localizedDescription }
    }
    private func testGroq() {
        guard let key = KeychainStore.groqAPIKey() else { return }
        isTesting = true
        status = nil
        Task {
            do { try await GroqClient.shared.testConnection(apiKey: key); status = "Connected to Groq." }
            catch { status = error.localizedDescription }
            isTesting = false
        }
    }
}

private struct IOSDownloadSettings: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject private var mediaStore = LocalMediaStore.shared
    private var records: [DownloadRecord] { mediaStore.records.values.sorted { $0.downloadedAt > $1.downloadedAt } }

    var body: some View {
        Form {
            Section("Storage") {
                LabeledContent("Used", value: bytes(mediaStore.storageUsedBytes))
                LabeledContent("Available", value: bytes(mediaStore.remainingStorageBytes))
                ProgressView(value: Double(mediaStore.storageUsedBytes), total: Double(mediaStore.settings.maximumStorageBytes))
                Text("Downloads stop at 8 GB. Unfinished episodes are never removed automatically.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Future download quality") {
                Picker("Quality", selection: $mediaStore.settings.quality) {
                    ForEach(DownloadQuality.allCases) { Text($0.title).tag($0) }
                }
            }
            if !mediaStore.transientStates.isEmpty {
                Section("Download queue") {
                    ForEach(mediaStore.transientStates.keys.sorted(), id: \.self) { videoID in
                        if let state = mediaStore.transientStates[videoID] {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(viewModel.podcasts.first(where: { $0.youtubeVideoId == videoID })?.title ?? videoID).lineLimit(1)
                                    Text(state.label).font(.caption).foregroundStyle(.secondary)
                                    if state == .downloading {
                                        let fraction = mediaStore.activeDownloadProgress[videoID] ?? 0
                                        ProgressView(value: fraction)
                                        Text("\(Int((fraction * 100).rounded()))% downloaded")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .monospacedDigit()
                                    }
                                }
                                Spacer()
                                if state == .queued || state == .downloading {
                                    Button("Cancel", systemImage: "xmark.circle") { mediaStore.cancel(videoID: videoID) }.labelStyle(.iconOnly)
                                }
                            }
                        }
                    }
                }
            }
            Section("Downloaded episodes") {
                if records.isEmpty {
                    ContentUnavailableView("No Downloads", systemImage: "arrow.down.circle")
                } else {
                    ForEach(records) { record in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(viewModel.podcasts.first(where: { $0.youtubeVideoId == record.videoID })?.title ?? record.videoID).lineLimit(2)
                                Text("\(bytes(record.byteCount))\(record.resolutionHeight.map { " · \($0)p" } ?? "")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Delete", systemImage: "trash", role: .destructive) { mediaStore.deleteDownload(videoID: record.videoID) }.labelStyle(.iconOnly)
                        }
                    }
                    Button("Delete Completed Downloads", role: .destructive) {
                        mediaStore.deleteCompletedDownloads(podcasts: viewModel.podcasts)
                    }
                }
            }
        }
        .navigationTitle("Downloads")
    }

    private func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }
}

private struct IOSCategorySettings: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var editor: IOSCategoryDraft?
    @State private var deleting: LearningCategory?
    @State private var replacementID: String?

    var body: some View {
        List {
            ForEach(viewModel.categories) { category in
                HStack {
                    Image(systemName: category.symbolName).foregroundStyle(category.color).frame(width: 28)
                    VStack(alignment: .leading) {
                        Text(category.name)
                        Text("\(viewModel.podcasts.filter { $0.categoryID == category.id }.count) episodes")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Edit", systemImage: "pencil") { editor = .init(category) }.labelStyle(.iconOnly)
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        deleting = category
                        replacementID = viewModel.categories.first(where: { $0.id != category.id })?.id
                    }
                    .labelStyle(.iconOnly)
                    .disabled(viewModel.categories.count == 1)
                }
            }
            .onMove { viewModel.moveCategories(from: $0, to: $1) }
        }
        .navigationTitle("Categories")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New Category", systemImage: "plus") { editor = .new(sortOrder: viewModel.categories.count) }
            }
        }
        .sheet(item: $editor) { IOSCategoryEditor(draft: $0) }
        .sheet(item: $deleting) { category in
            IOSDeleteCategorySheet(category: category, replacementID: $replacementID)
        }
    }
}

private struct IOSCategoryDraft: Identifiable {
    var id: String
    var name: String
    var symbolName: String
    var colorToken: String
    var sortOrder: Int
    var isNew: Bool
    init(_ category: LearningCategory) {
        id = category.id; name = category.name; symbolName = category.symbolName; colorToken = category.colorToken; sortOrder = category.sortOrder; isNew = false
    }
    static func new(sortOrder: Int) -> Self {
        .init(id: UUID().uuidString.lowercased(), name: "", symbolName: "book.closed.fill", colorToken: "blue", sortOrder: sortOrder, isNew: true)
    }
    private init(id: String, name: String, symbolName: String, colorToken: String, sortOrder: Int, isNew: Bool) {
        self.id = id; self.name = name; self.symbolName = symbolName; self.colorToken = colorToken; self.sortOrder = sortOrder; self.isNew = isNew
    }
}

private struct IOSCategoryEditor: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State var draft: IOSCategoryDraft
    @State private var errorMessage: String?
    private let symbols = ["book.closed.fill", "brain.head.profile", "cpu", "atom", "briefcase.fill", "chart.line.uptrend.xyaxis", "heart.fill", "globe", "function", "lightbulb.fill", "graduationcap.fill", "figure.mind.and.body"]
    private let colors = ["blue", "indigo", "purple", "pink", "red", "orange", "yellow", "green", "mint", "teal", "cyan", "brown", "gray"]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $draft.name)
                Picker("Symbol", selection: $draft.symbolName) { ForEach(symbols, id: \.self) { Label($0, systemImage: $0).tag($0) } }
                Picker("Color", selection: $draft.colorToken) { ForEach(colors, id: \.self) { Text($0.capitalized).tag($0) } }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .navigationTitle(draft.isNew ? "New Category" : "Edit Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        do {
            if draft.isNew {
                try viewModel.createCategory(name: draft.name, symbolName: draft.symbolName, colorToken: draft.colorToken)
            } else {
                try viewModel.updateCategory(.init(id: draft.id, name: draft.name, symbolName: draft.symbolName, colorToken: draft.colorToken, sortOrder: draft.sortOrder))
            }
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct IOSDeleteCategorySheet: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    let category: LearningCategory
    @Binding var replacementID: String?
    @State private var errorMessage: String?
    private var episodeCount: Int { viewModel.podcasts.filter { $0.categoryID == category.id }.count }

    var body: some View {
        NavigationStack {
            Form {
                Section { Text("Delete \(category.name)?").font(.headline) }
                if episodeCount > 0 {
                    Section("Move \(episodeCount) episodes to") {
                        Picker("Replacement", selection: $replacementID) {
                            ForEach(viewModel.categories.filter { $0.id != category.id }) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .navigationTitle("Delete Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Delete", role: .destructive) { remove() } }
            }
        }
        .presentationDetents([.medium])
    }

    private func remove() {
        do { try viewModel.deleteCategory(id: category.id, replacementID: episodeCount > 0 ? replacementID : nil); dismiss() }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct IOSCollectionSettings: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var deleting: PodcastCollection?
    var body: some View {
        List {
            if viewModel.collections.isEmpty {
                ContentUnavailableView("No Collections", systemImage: "rectangle.stack", description: Text("Import a YouTube playlist to create one."))
            } else {
                ForEach(viewModel.collections.sorted { $0.sortOrder < $1.sortOrder }) { collection in
                    HStack {
                        Image(systemName: "rectangle.stack.fill").foregroundStyle(.tint)
                        VStack(alignment: .leading) {
                            Text(collection.title)
                            Text("\(viewModel.podcasts.filter { $0.collectionIDs.contains(collection.id) }.count) episodes")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Delete", systemImage: "trash", role: .destructive) { deleting = collection }.labelStyle(.iconOnly)
                    }
                }
            }
        }
        .navigationTitle("Collections")
        .confirmationDialog(
            "Delete collection?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { collection in
            Button("Delete \(collection.title)", role: .destructive) { viewModel.deleteCollection(collection) }
        } message: { _ in Text("Episodes remain in your library.") }
    }
}

private struct IOSAccountSettings: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var confirmSignOut = false
    var body: some View {
        Form {
            Section("Signed in") {
                LabeledContent("Name", value: authManager.displayName ?? "—")
                LabeledContent("Email", value: authManager.email ?? "—")
            }
            Section("Sync") {
                Button("Refresh from Supabase", systemImage: "arrow.triangle.2.circlepath") { viewModel.refreshCloudData() }
                Text("Playback position, library, categories, activity, compact summaries, and collections sync. Downloads and raw transcripts stay local.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Button("Sign Out", role: .destructive) { confirmSignOut = true }
            }
        }
        .navigationTitle("Account")
        .confirmationDialog("Sign out of PodTrackio?", isPresented: $confirmSignOut) {
            Button("Sign Out", role: .destructive) { authManager.signOut() }
        } message: {
            Text("Your local learning workspace remains on this device.")
        }
    }
}
