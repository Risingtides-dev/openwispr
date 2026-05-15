import SwiftUI

struct ContentView: View {
    @State private var apiKey: String = SharedConfig.groqApiKey ?? ""
    @State private var transcribeModel: String = SharedConfig.transcribeModel
    @State private var cleanupModel: String = SharedConfig.cleanupModel
    @State private var cleanupEnabled: Bool = SharedConfig.cleanupEnabled
    @State private var vocabulary: String = SharedConfig.vocabulary
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
                    TextField("Transcribe model", text: $transcribeModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle("Clean up transcript", isOn: $cleanupEnabled)
                    if cleanupEnabled {
                        TextField("Cleanup model", text: $cleanupModel)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }

                Section("Vocabulary") {
                    TextField("Comma-separated terms", text: $vocabulary, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Button("Save") { save() }
                    if let savedAt {
                        Text("Saved \(savedAt.formatted(date: .omitted, time: .standard))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Setup") {
                    Label("Add openwispr in Settings > General > Keyboard > Keyboards", systemImage: "1.circle")
                    Label("Tap openwispr and turn on Allow Full Access", systemImage: "2.circle")
                    Label("Long-press the globe key in any app to switch to openwispr", systemImage: "3.circle")
                }
            }
            .navigationTitle("openwispr")
        }
    }

    private func save() {
        SharedConfig.groqApiKey = apiKey.trimmingCharacters(in: .whitespaces)
        SharedConfig.transcribeModel = transcribeModel.trimmingCharacters(in: .whitespaces)
        SharedConfig.cleanupModel = cleanupModel.trimmingCharacters(in: .whitespaces)
        SharedConfig.cleanupEnabled = cleanupEnabled
        SharedConfig.vocabulary = vocabulary
        savedAt = Date()
    }
}
