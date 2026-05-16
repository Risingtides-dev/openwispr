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
            MicOrb(
                isRecording: phase == .recording,
                isTranscribing: phase == .transcribing,
                level: recorder.level
            )
        }
        .buttonStyle(.plain)
        .disabled(!hasFullAccess || phase == .transcribing)
        .opacity(hasFullAccess ? 1 : 0.4)
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

struct MicOrb: View {
    let isRecording: Bool
    let isTranscribing: Bool
    let level: Double

    @State private var rippleA = false
    @State private var rippleB = false
    @State private var rotation: Double = 0

    private let segments = 22
    private let baseSize: CGFloat = 88

    var body: some View {
        ZStack {
            if isRecording {
                ripple(scale: rippleA ? 1.7 : 1.0, opacity: rippleA ? 0 : 0.5)
                    .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false), value: rippleA)
                ripple(scale: rippleB ? 1.9 : 1.0, opacity: rippleB ? 0 : 0.35)
                    .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false).delay(0.5), value: rippleB)
            }

            Circle()
                .fill(orbColor)
                .frame(width: baseSize, height: baseSize)
                .blur(radius: isRecording ? CGFloat(10 + level * 18) : 6)
                .opacity(isRecording ? 0.55 + level * 0.4 : 0.3)

            if isRecording {
                segmentRing
            }

            Circle()
                .fill(LinearGradient(
                    colors: [orbColor, orbColor.opacity(0.65)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: baseSize - 8, height: baseSize - 8)
                .scaleEffect(isRecording ? 1.0 + CGFloat(level) * 0.08 : 1.0)
                .shadow(color: orbColor.opacity(0.55), radius: 5, y: 1)
                .animation(.easeOut(duration: 0.08), value: level)

            icon
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: 120, height: 120)
        .onAppear {
            rippleA = true
            rippleB = true
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }

    @ViewBuilder private var icon: some View {
        if isTranscribing {
            ProgressView().tint(.white)
        } else if isRecording {
            Image(systemName: "stop.fill")
        } else {
            Image(systemName: "mic.fill")
        }
    }

    private var orbColor: Color {
        if isTranscribing { return Color(white: 0.55) }
        if isRecording { return Color(red: 0.95, green: 0.32, blue: 0.32) }
        return Color(red: 0.45, green: 0.55, blue: 0.95)
    }

    private func ripple(scale: CGFloat, opacity: Double) -> some View {
        Circle()
            .stroke(orbColor.opacity(opacity), lineWidth: 2)
            .frame(width: baseSize, height: baseSize)
            .scaleEffect(scale)
    }

    private var segmentRing: some View {
        ZStack {
            ForEach(0..<segments, id: \.self) { i in
                let angle = Double(i) / Double(segments) * 360.0
                Capsule()
                    .fill(orbColor.opacity(0.65 + level * 0.35))
                    .frame(width: 2, height: 5 + CGFloat(level) * 12)
                    .offset(y: -(baseSize / 2 + 6))
                    .rotationEffect(.degrees(angle + rotation))
            }
        }
        .animation(.easeOut(duration: 0.08), value: level)
    }
}
