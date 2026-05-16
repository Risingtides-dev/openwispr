import SwiftUI

struct KeyboardView: View {
    let insertAndCopy: (String) -> Void
    let deleteBackward: () -> Void
    let advanceToNextKeyboard: () -> Void
    let hasFullAccess: Bool
    let needsInputModeSwitchKey: Bool

    @StateObject private var recorder = AudioRecorder()
    @State private var phase: Phase = .idle
    @State private var message: String?

    enum Phase { case idle, recording, transcribing }

    var body: some View {
        VStack(spacing: 8) {
            statusLine
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                if needsInputModeSwitchKey {
                    sideButton(systemImage: "globe", action: advanceToNextKeyboard)
                } else {
                    Color.clear.frame(width: 56)
                }
                Spacer()
                micButton
                Spacer()
                sideButton(systemImage: "delete.left", action: deleteBackward)
            }
            .padding(.horizontal, 16)
            Spacer(minLength: 0)
            helpLine
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 260)
    }

    @ViewBuilder private var statusLine: some View {
        if let message {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        } else {
            Text(phaseLabel)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var phaseLabel: String {
        switch phase {
        case .idle: return "Tap to record"
        case .recording: return "Recording — tap to stop"
        case .transcribing: return "Transcribing..."
        }
    }

    @ViewBuilder private var helpLine: some View {
        if !hasFullAccess {
            Text("Turn on Allow Full Access for openwispr in Settings > General > Keyboard")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    private var micButton: some View {
        Button(action: micTapped) {
            ZStack {
                Circle()
                    .fill(micColor)
                    .frame(width: 88, height: 88)
                    .shadow(radius: 2, y: 1)
                Group {
                    switch phase {
                    case .idle: Image(systemName: "mic.fill")
                    case .recording: Image(systemName: "stop.fill")
                    case .transcribing: ProgressView().tint(.white)
                    }
                }
                .font(.system(size: 32, weight: .semibold))
                .foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)
        .disabled(!hasFullAccess || phase == .transcribing)
        .opacity(hasFullAccess ? 1 : 0.4)
    }

    private var micColor: Color {
        switch phase {
        case .idle: return .accentColor
        case .recording: return .red
        case .transcribing: return .gray
        }
    }

    private func sideButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .medium))
                .frame(width: 56, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func micTapped() {
        message = nil
        switch phase {
        case .idle:
            do {
                try recorder.start()
                phase = .recording
            } catch {
                message = "Mic error: \(error.localizedDescription)"
            }
        case .recording:
            let url: URL
            do {
                url = try recorder.stop()
            } catch {
                message = "Stop error: \(error.localizedDescription)"
                phase = .idle
                return
            }
            phase = .transcribing
            Task { await transcribe(fileURL: url) }
        case .transcribing:
            break
        }
    }

    private func transcribe(fileURL: URL) async {
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let apiKey = Secrets.groqApiKey
        guard !apiKey.isEmpty, apiKey != "gsk_REPLACE_ME" else {
            await setError("Set Secrets.groqApiKey in OpenwisprKeyboard/Secrets.swift.")
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
            guard !trimmed.isEmpty else {
                await setError("No speech detected.")
                return
            }
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
            await MainActor.run {
                insertAndCopy(final)
                phase = .idle
            }
        } catch {
            await setError(error.localizedDescription)
        }
    }

    @MainActor
    private func setError(_ text: String) {
        message = text
        phase = .idle
    }
}
