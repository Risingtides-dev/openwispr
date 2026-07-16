import SwiftUI
import UIKit

enum AppTab: Hashable {
    case record
    case notes
    case history
    case settings
}

private struct ModelOption: Identifiable, Hashable {
    let id: String
    let title: String
}

private let transcribeModelOptions = [
    ModelOption(id: "whisper-large-v3-turbo", title: "whisper-large-v3-turbo · fast"),
    ModelOption(id: "whisper-large-v3", title: "whisper-large-v3 · accurate")
]

private let cleanupModelOptions = [
    ModelOption(id: "openai/gpt-oss-20b", title: "gpt-oss-20b · fastest"),
    ModelOption(id: "llama-3.1-8b-instant", title: "llama-3.1-8b"),
    ModelOption(id: "openai/gpt-oss-120b", title: "gpt-oss-120b · smart"),
    ModelOption(id: "llama-3.3-70b-versatile", title: "llama-3.3-70b · smartest")
]

struct ContentView: View {
    @Binding var selectedTab: AppTab
    @Binding var showImport: Bool

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                RecordView(cameFromKeyboard: false)
            }
            .tabItem { Label("Voice", systemImage: "mic.fill") }
            .tag(AppTab.record)

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
        .sheet(isPresented: $showImport) {
            ImportView()
        }
        .onAppear {
            applyRequestedTab()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            applyRequestedTab()
        }
    }

    private func applyRequestedTab() {
        // Route requests written by the share extension / keyboard.
        if !SharedConfig.pendingSharedImports.isEmpty {
            showImport = true
        }
        guard let requested = SharedConfig.requestedTab else { return }
        SharedConfig.requestedTab = nil
        switch requested {
        case "import":
            showImport = true
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

struct SettingsView: View {
    @State private var apiKey: String = SharedConfig.groqApiKey ?? ""
    @State private var transcribeModel: String = SharedConfig.transcribeModel
    @State private var transcribeLanguage: String = SharedConfig.transcribeLanguage
    @State private var cleanupModel: String = SharedConfig.cleanupModel
    @State private var cleanupEnabled: Bool = SharedConfig.cleanupEnabled
    @State private var vocabulary: String = SharedConfig.vocabulary
    @State private var cleanupStyle: KordCleanupStyle = SharedConfig.cleanupStyle
    @State private var cleanupPrompt: String = SharedConfig.cleanupPrompt
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
                        Picker("Style", selection: $cleanupStyle) {
                            ForEach(KordCleanupStyle.allCases) { style in
                                Text(style.title).tag(style)
                            }
                        }
                    }
                }

                Section("Vocabulary") {
                    TextField("Comma-separated terms", text: $vocabulary, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    DisclosureGroup("Cleanup prompt") {
                        TextEditor(text: $cleanupPrompt)
                            .font(KordTheme.body(13))
                            .frame(minHeight: 160)
                            .autocorrectionDisabled()
                        Button("Reset to default") {
                            cleanupPrompt = SharedConfig.defaultCleanupPrompt
                        }
                    }
                }

                Section {
                    Button("Save") { save() }
                    if let savedAt {
                        Text("Saved \(savedAt.formatted(date: .omitted, time: .standard))")
                            .font(KordTheme.body(13))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(KordTheme.void)
            .tint(KordTheme.ember)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
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
        return [ModelOption(id: selectedID, title: selectedID)] + options
    }
}
