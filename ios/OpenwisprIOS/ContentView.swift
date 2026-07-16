import SwiftUI
import UIKit

enum AppTab: Hashable {
    case home
    case record
    case importData
    case notes
    case history
    case settings
}

private struct ModelOption: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
}

private let transcribeModelOptions = [
    ModelOption(
        id: "whisper-large-v3-turbo",
        title: "whisper-large-v3-turbo · fast",
        detail: "216x realtime · 12% WER · $0.04/hr"
    ),
    ModelOption(
        id: "whisper-large-v3",
        title: "whisper-large-v3 · accurate",
        detail: "189x realtime · 10.3% WER · $0.111/hr"
    )
]

private let cleanupModelOptions = [
    ModelOption(
        id: "openai/gpt-oss-20b",
        title: "gpt-oss-20b · fastest",
        detail: "~1000 tok/sec · OpenAI open weights"
    ),
    ModelOption(
        id: "llama-3.1-8b-instant",
        title: "llama-3.1-8b",
        detail: "~560 tok/sec · Meta"
    ),
    ModelOption(
        id: "openai/gpt-oss-120b",
        title: "gpt-oss-120b · smart",
        detail: "~500 tok/sec · OpenAI open weights, smarter"
    ),
    ModelOption(
        id: "llama-3.3-70b-versatile",
        title: "llama-3.3-70b · smartest",
        detail: "~280 tok/sec · most accurate, slowest"
    )
]

struct ContentView: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView(selectedTab: $selectedTab)
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("Home", systemImage: "square.grid.2x2") }
            .tag(AppTab.home)

            NavigationStack {
                RecordView(cameFromKeyboard: false)
                    .navigationTitle(AppBrand.name)
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("Voice", systemImage: "mic.fill") }
            .tag(AppTab.record)

            ImportView()
                .tabItem { Label("Import", systemImage: "tray.and.arrow.down") }
                .tag(AppTab.importData)

            NotesView()
                .tabItem { Label("Notes", systemImage: "note.text") }
                .tag(AppTab.notes)

            HistoryView()
                .tabItem { Label("History", systemImage: "clock") }
                .tag(AppTab.history)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .tint(KordTheme.ember)
        .preferredColorScheme(.dark)
        .toolbarBackground(KordTheme.void, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
        .onAppear {
            SharedConfig.importDesktopDataIfAvailable()
            applyRequestedTab()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            applyRequestedTab()
        }
    }

    private func applyRequestedTab() {
        guard let requested = SharedConfig.requestedTab else { return }
        SharedConfig.requestedTab = nil
        switch requested {
        case "import":
            selectedTab = .importData
        case "notes":
            selectedTab = .notes
        case "history":
            selectedTab = .history
        case "settings":
            selectedTab = .settings
        default:
            break
        }
    }
}

struct HomeView: View {
    @Binding var selectedTab: AppTab
    @EnvironmentObject private var engine: BackgroundDictationEngine
    @State private var noteCount = 0
    @State private var historyCount = 0
    @State private var recents: [String] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                metrics
                quickActions
                recentPanel
                setupPanel
            }
            .padding(18)
        }
        .background(KordTheme.void.ignoresSafeArea())
        .toolbarBackground(KordTheme.void, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear(perform: reload)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                Image("KordMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(KordTheme.borderMuted, lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 5) {
                    Text(AppBrand.name)
                        .font(KordTheme.display(32))
                        .foregroundStyle(KordTheme.text)
                    Text(AppBrand.tagline)
                        .font(KordTheme.body(14, weight: .medium))
                        .foregroundStyle(KordTheme.accentGradientHorizontal)
                    engineStrip
                }
            }

            Text("A resident vocal keyboard for fast dictation, notes, and text handoff.")
                .font(KordTheme.body(15))
                .foregroundStyle(KordTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kordPanel(radius: KordTheme.radiusLarge)
    }

    private var engineStrip: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(engineAlive ? KordTheme.live : KordTheme.faint)
                .frame(width: 8, height: 8)
            Text(engineLabel)
                .font(KordTheme.label(12, weight: .medium))
                .foregroundStyle(KordTheme.muted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(KordTheme.elevated)
        .clipShape(Capsule())
        .padding(.top, 2)
    }

    private var metrics: some View {
        HStack(spacing: 10) {
            metricCard(title: "Notes", value: "\(noteCount)", tab: .notes)
            metricCard(title: "History", value: "\(historyCount)", tab: .history)
            metricCard(title: "Recent", value: "\(recents.count)", tab: .history)
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Control")
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                actionTile("Voice", "mic.fill", .record)
                actionTile("Import", "tray.and.arrow.down", .importData)
                actionTile("Notes", "note.text", .notes)
                actionTile("Models", "slider.horizontal.3", .settings)
            }
        }
    }

    private var recentPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Recent Dictation")
            if recents.isEmpty {
                Text("Dictated text lands here after the keyboard inserts it.")
                    .font(KordTheme.body(16))
                    .foregroundStyle(KordTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .kordPanel()
            } else {
                ForEach(Array(recents.prefix(3)), id: \.self) { text in
                    Text(text)
                        .font(KordTheme.body(16))
                        .foregroundStyle(KordTheme.text)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .kordPanel()
                }
            }
        }
    }

    private var setupPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Keyboard Setup")
            VStack(alignment: .leading, spacing: 8) {
                setupLine("1", "Add Windtalker in iOS Keyboard settings")
                setupLine("2", "Enable Allow Full Access")
                setupLine("3", "Tap Activate, swipe back, then dictate")
            }
            .padding(14)
            .kordPanel()
        }
    }

    private func metricCard(title: String, value: String, tab: AppTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(KordTheme.display(26))
                    .foregroundStyle(KordTheme.text)
                Text(title)
                    .font(KordTheme.label(12, weight: .medium))
                    .foregroundStyle(KordTheme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .kordPanel()
        }
        .buttonStyle(.plain)
    }

    private func actionTile(_ title: String, _ systemImage: String, _ tab: AppTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(KordTheme.accentGradient)
                    .frame(width: 46, height: 46)
                    .background(KordTheme.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: KordTheme.radiusSmall, style: .continuous))
                Text(title)
                    .font(KordTheme.label(13, weight: .medium))
                    .foregroundStyle(KordTheme.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 96)
            .kordPanel()
        }
        .buttonStyle(.plain)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(KordTheme.label(11, weight: .bold))
            .foregroundStyle(KordTheme.muted)
            .tracking(1.2)
    }

    private func setupLine(_ step: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Text(step)
                .font(KordTheme.label(12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(KordTheme.accentGradient)
                .clipShape(Circle())
            Text(text)
                .font(KordTheme.body(15))
                .foregroundStyle(KordTheme.secondary)
        }
    }

    private var engineAlive: Bool {
        SharedConfig.isEngineAlive()
    }

    private var engineLabel: String {
        guard engineAlive else { return "Engine cold" }
        return SharedConfig.engineStatus.rawValue
    }

    private func reload() {
        noteCount = SharedConfig.notes.count
        historyCount = SharedConfig.transcriptHistory.count
        recents = SharedConfig.recentTranscripts
        _ = engine.status
    }
}

struct SettingsView: View {
    @State private var apiKey: String = SharedConfig.groqApiKey ?? ""
    @State private var transcribeModel: String = SharedConfig.transcribeModel
    @State private var transcribeLanguage: String = SharedConfig.transcribeLanguage
    @State private var cleanupModel: String = SharedConfig.cleanupModel
    @State private var cleanupEnabled: Bool = SharedConfig.cleanupEnabled
    @State private var vocabulary: String = SharedConfig.vocabulary
    @State private var cleanupStyle: KordCleanupStyle = SharedConfig.cleanupStyle
    @State private var cleanupPrompt: String = SharedConfig.cleanupPrompt
    @State private var noteCount: Int = SharedConfig.notes.count
    @State private var historyCount: Int = SharedConfig.transcriptHistory.count
    @State private var savedAt: Date?

    var body: some View {
        NavigationStack {
            Form {
                Section("Groq API key") {
                    SecureField("gsk_...", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Link("Get a key", destination: URL(string: "https://console.groq.com/keys")!)
                }

                Section("Models") {
                    Picker("Transcription", selection: $transcribeModel) {
                        ForEach(modelOptions(transcribeModelOptions, selectedID: transcribeModel)) { option in
                            Text(option.title).tag(option.id)
                        }
                    }
                    Text(modelDetail(for: transcribeModel, in: transcribeModelOptions))
                        .font(KordTheme.body(13))
                        .foregroundStyle(.secondary)

                    TextField("Language (en)", text: $transcribeLanguage)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle("Clean up transcript", isOn: $cleanupEnabled)
                    if cleanupEnabled {
                        Picker("Cleanup", selection: $cleanupModel) {
                            ForEach(modelOptions(cleanupModelOptions, selectedID: cleanupModel)) { option in
                                Text(option.title).tag(option.id)
                            }
                        }
                        Text(modelDetail(for: cleanupModel, in: cleanupModelOptions))
                            .font(KordTheme.body(13))
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Vocabulary") {
                    TextField("Comma-separated terms", text: $vocabulary, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Shared prompt") {
                    Picker("Keyboard style", selection: $cleanupStyle) {
                        ForEach(KordCleanupStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    Text(cleanupStyle.detail)
                        .font(KordTheme.body(13))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Selected style layer")
                            .font(KordTheme.body(12).weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(cleanupStyle.settingsPreview)
                            .font(KordTheme.body(13))
                            .textSelection(.enabled)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .kordPanel()

                    Text("Shared cleanup prompt")
                        .font(KordTheme.body(12).weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $cleanupPrompt)
                        .font(KordTheme.body(13))
                        .frame(minHeight: 180)
                        .textInputAutocapitalization(.sentences)
                        .autocorrectionDisabled()

                    Button("Reset shared prompt") {
                        cleanupPrompt = SharedConfig.defaultCleanupPrompt
                    }
                }

                Section("Desktop import") {
                    Button("Import copied desktop data") {
                        SharedConfig.importDesktopDataIfAvailable()
                        reload()
                        savedAt = Date()
                    }
                    Text("\(noteCount) notes, \(historyCount) past dictations")
                        .font(KordTheme.body(13))
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Save") { save() }
                    if let savedAt {
                        Text("Saved \(savedAt.formatted(date: .omitted, time: .standard))")
                            .font(KordTheme.body(13))
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Setup") {
                    Label("Add Windtalker in Settings > General > Keyboard > Keyboards", systemImage: "1.circle")
                    Label("Tap Windtalker and turn on Allow Full Access", systemImage: "2.circle")
                    Label("Long-press the globe key in any app to switch to Windtalker", systemImage: "3.circle")
                }
            }
            .scrollContentBackground(.hidden)
            .background(KordTheme.void)
            .tint(KordTheme.ember)
            .navigationTitle(AppBrand.name)
            .toolbarBackground(KordTheme.void, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear { reload() }
        }
    }

    private func reload() {
        apiKey = SharedConfig.groqApiKey ?? ""
        transcribeModel = SharedConfig.transcribeModel
        transcribeLanguage = SharedConfig.transcribeLanguage
        cleanupModel = SharedConfig.cleanupModel
        cleanupEnabled = SharedConfig.cleanupEnabled
        vocabulary = SharedConfig.vocabulary
        cleanupStyle = SharedConfig.cleanupStyle
        cleanupPrompt = SharedConfig.cleanupPrompt
        noteCount = SharedConfig.notes.count
        historyCount = SharedConfig.transcriptHistory.count
    }

    private func save() {
        SharedConfig.groqApiKey = apiKey.trimmingCharacters(in: .whitespaces)
        SharedConfig.transcribeModel = transcribeModel
        SharedConfig.transcribeLanguage = transcribeLanguage.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        SharedConfig.cleanupModel = cleanupModel
        SharedConfig.cleanupEnabled = cleanupEnabled
        SharedConfig.vocabulary = vocabulary
        SharedConfig.cleanupStyle = cleanupStyle
        SharedConfig.cleanupPrompt = cleanupPrompt
        savedAt = Date()
    }

    private func modelOptions(_ options: [ModelOption], selectedID: String) -> [ModelOption] {
        guard !selectedID.isEmpty, !options.contains(where: { $0.id == selectedID }) else {
            return options
        }
        return [ModelOption(id: selectedID, title: "\(selectedID) · imported", detail: "Imported from desktop config.")] + options
    }

    private func modelDetail(for id: String, in options: [ModelOption]) -> String {
        options.first(where: { $0.id == id })?.detail ?? "Imported from desktop config."
    }
}
