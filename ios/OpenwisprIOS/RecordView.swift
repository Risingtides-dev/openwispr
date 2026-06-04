import SwiftUI
import AVFoundation

/// The actual dictation surface, living in the container app where mic access
/// is fully supported. Records, transcribes via Groq, saves the result to the
/// App Group, and (when launched from the keyboard) flags it for auto-insert.
struct RecordView: View {
    /// True when the app was opened via openwispr://record from the keyboard.
    let cameFromKeyboard: Bool
    /// Called after a transcript is produced when we came from the keyboard,
    /// so the app can bounce the user back to where they were typing.
    var onFinishedForKeyboard: (() -> Void)?

    @StateObject private var recorder = AudioRecorder()
    @State private var phase: Phase = .idle
    @State private var message: String?
    @State private var lastTranscript: String?

    enum Phase { case idle, recording, transcribing }

    var body: some View {
        VStack(spacing: 20) {
            statusLine
            micButton
            if let lastTranscript {
                Text(lastTranscript)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
        }
        .padding()
        .onAppear {
            if cameFromKeyboard && phase == .idle { start() }
        }
    }

    @ViewBuilder private var statusLine: some View {
        if let message {
            Text(message).font(.callout).foregroundStyle(.red).multilineTextAlignment(.center)
        } else {
            Text(label).font(.callout).foregroundStyle(.secondary)
        }
    }

    private var label: String {
        switch phase {
        case .idle: return "Tap to record"
        case .recording: return "Recording — tap to stop"
        case .transcribing: return "Transcribing..."
        }
    }

    private var micButton: some View {
        Button(action: micTapped) {
            ZStack {
                Circle().fill(color).frame(width: 120, height: 120).shadow(radius: 3, y: 1)
                switch phase {
                case .idle: Image(systemName: "mic.fill").font(.system(size: 44, weight: .semibold)).foregroundColor(.white)
                case .recording: Image(systemName: "stop.fill").font(.system(size: 44, weight: .semibold)).foregroundColor(.white)
                case .transcribing: ProgressView().tint(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(phase == .transcribing)
    }

    private var color: Color {
        switch phase {
        case .idle: return .accentColor
        case .recording: return .red
        case .transcribing: return .gray
        }
    }

    private func micTapped() {
        message = nil
        switch phase {
        case .idle: start()
        case .recording:
            let url: URL
            do { url = try recorder.stop() }
            catch { message = "Stop error: \(error.localizedDescription)"; phase = .idle; return }
            phase = .transcribing
            Task { await transcribe(fileURL: url) }
        case .transcribing: break
        }
    }

    private func start() {
        message = nil
        do { try recorder.start(); phase = .recording }
        catch { message = "Mic error: \(error.localizedDescription)" }
    }

    @MainActor
    private func transcribe(fileURL: URL) async {
        defer { try? FileManager.default.removeItem(at: fileURL) }

        guard let apiKey = SharedConfig.groqApiKey, !apiKey.isEmpty else {
            setError("Add a Groq API key in Settings.")
            return
        }
        do {
            let raw = try await GroqClient.transcribe(
                fileURL: fileURL,
                apiKey: apiKey,
                model: SharedConfig.transcribeModel,
                vocabulary: SharedConfig.vocabulary
            )
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { setError("No speech detected."); return }

            let final: String
            if SharedConfig.cleanupEnabled {
                final = (try? await GroqClient.cleanup(
                    text: trimmed,
                    apiKey: apiKey,
                    model: SharedConfig.cleanupModel,
                    systemPrompt: SharedConfig.cleanupPrompt,
                    vocabulary: SharedConfig.vocabulary
                )) ?? trimmed
            } else {
                final = trimmed
            }

            SharedConfig.addTranscript(final)
            lastTranscript = final
            phase = .idle
            if cameFromKeyboard {
                SharedConfig.pendingInsert = final
                onFinishedForKeyboard?()
            } else {
                UIPasteboard.general.string = final
            }
        } catch {
            setError(error.localizedDescription)
        }
    }

    private func setError(_ text: String) {
        message = text
        phase = .idle
    }
}
