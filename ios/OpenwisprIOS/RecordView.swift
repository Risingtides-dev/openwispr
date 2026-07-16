import SwiftUI
import AVFoundation
import os

private let recordLog = Logger(subsystem: "dev.smathdaddy.openwispr", category: "RecordView")

/// The actual dictation surface, living in the container app where mic access
/// is fully supported. Records, transcribes via Groq, saves the result to the
/// App Group, and (when launched from the keyboard) flags it for auto-insert.
struct RecordView: View {
    /// True when the app was opened via kord://record from the keyboard.
    let cameFromKeyboard: Bool
    /// Called after a transcript is produced when we came from the keyboard,
    /// so the app can bounce the user back to where they were typing.
    var onFinishedForKeyboard: (() -> Void)?

    @StateObject private var recorder = AudioRecorder()
    @State private var phase: Phase = .idle
    @State private var message: String?
    @State private var lastTranscript: String?
    @State private var pulse = false

    enum Phase { case idle, recording, transcribing }

    var body: some View {
        ZStack {
            KordTheme.void
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer(minLength: 24)

                VStack(spacing: 10) {
                    Image("KordMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(KordTheme.borderMuted, lineWidth: 1)
                        }

                    Text(AppBrand.name)
                        .font(KordTheme.display(26))
                        .foregroundStyle(KordTheme.text)
                    Text(AppBrand.tagline)
                        .font(KordTheme.body(14, weight: .medium))
                        .foregroundStyle(KordTheme.accentGradientHorizontal)
                }

                statusLine
                micButton

                if let lastTranscript {
                    Text(lastTranscript)
                        .font(KordTheme.body(17))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(KordTheme.text)
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .kordPanel()
                        .padding(.horizontal)
                }

                Spacer(minLength: 24)
            }
        }
        .onAppear {
            recordLog.info("onAppear cameFromKeyboard=\(cameFromKeyboard, privacy: .public) phase=\(String(describing: phase), privacy: .public)")
            if cameFromKeyboard && phase == .idle { start() }
        }
    }

    @ViewBuilder private var statusLine: some View {
        if let message {
            Text(message).font(KordTheme.body(16)).foregroundStyle(KordTheme.ember).multilineTextAlignment(.center)
        } else {
            Text(label)
                .font(KordTheme.label(16))
                .foregroundStyle(KordTheme.muted)
                .textCase(.uppercase)
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
                if phase == .recording {
                    Circle()
                        .fill(KordTheme.magenta.opacity(0.22))
                        .frame(width: 168, height: 168)
                        .scaleEffect(pulse ? 1.06 : 0.92)
                        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
                }

                Circle()
                    .fill(phase == .idle ? AnyShapeStyle(KordTheme.accentGradient) : AnyShapeStyle(KordTheme.elevated))
                    .frame(width: 128, height: 128)
                    .overlay {
                        Circle().strokeBorder(
                            phase == .recording ? KordTheme.magenta : KordTheme.borderMuted,
                            lineWidth: phase == .recording ? 2 : 1
                        )
                    }
                    .shadow(
                        color: phase == .idle ? KordTheme.purple.opacity(0.45) : .black.opacity(0.4),
                        radius: 22,
                        y: 10
                    )

                switch phase {
                case .idle: Image(systemName: "mic.fill").font(.system(size: 42, weight: .semibold)).foregroundColor(.white)
                case .recording: Image(systemName: "stop.fill").font(.system(size: 40, weight: .semibold)).foregroundStyle(KordTheme.accentGradient)
                case .transcribing: ProgressView().tint(KordTheme.magenta).scaleEffect(1.3)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(phase == .transcribing)
        .onChange(of: phase) { _, newPhase in
            pulse = newPhase == .recording
        }
    }

    private func micTapped() {
        message = nil
        recordLog.info("mic tapped phase=\(String(describing: phase), privacy: .public)")
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
        do {
            try recorder.start()
            phase = .recording
            recordLog.info("phase=recording")
        } catch {
            recordLog.error("start failed: \(error.localizedDescription, privacy: .public)")
            message = "Mic error: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func transcribe(fileURL: URL) async {
        defer { try? FileManager.default.removeItem(at: fileURL) }

        do {
            recordLog.info("transcribe task started cameFromKeyboard=\(cameFromKeyboard, privacy: .public)")
            let result = try await TranscriptionPipeline.transcribe(fileURL: fileURL)
            SharedConfig.addTranscript(
                result.text,
                raw: result.raw,
                source: cameFromKeyboard ? "Keyboard bounce" : "Recorder",
                title: cameFromKeyboard ? "Keyboard dictation" : "Windtalker recording",
                audioFileURL: fileURL
            )
            lastTranscript = result.text
            phase = .idle
            recordLog.info("transcribe success finalLength=\(result.text.count, privacy: .public)")
            if cameFromKeyboard {
                SharedConfig.pendingInsert = result.text
                recordLog.info("pending insert set length=\(result.text.count, privacy: .public)")
                onFinishedForKeyboard?()
            } else {
                UIPasteboard.general.string = result.text
                recordLog.info("copied transcript to pasteboard")
            }
        } catch {
            recordLog.error("transcribe failed: \(error.localizedDescription, privacy: .public)")
            setError(error.localizedDescription)
        }
    }

    private func setError(_ text: String) {
        recordLog.error("set error: \(text, privacy: .public)")
        message = text
        phase = .idle
    }
}
