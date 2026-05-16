import SwiftUI

struct KeyboardView: View {
    let insertAndCopy: (String) -> Void
    let deleteBackward: () -> Void
    let advanceToNextKeyboard: () -> Void
    let openContainer: (URL) -> Void
    let hasFullAccess: Bool
    let needsInputModeSwitchKey: Bool

    @State private var phase: Phase = .idle
    @State private var message: String?
    @State private var sessionActive: Bool = false
    @State private var sessionExpiresAt: Date?
    @State private var now: Date = Date()

    private let pollTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

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
        .onAppear(perform: refreshFromState)
        .onReceive(pollTimer) { _ in
            now = Date()
            refreshFromState()
        }
    }

    @ViewBuilder private var statusLine: some View {
        if let message {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        } else if !sessionActive {
            Text("Tap to start a Flow session")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 6) {
                Circle().fill(.red).frame(width: 6, height: 6).opacity(sessionActive ? 1 : 0.3)
                Text(sessionStatusText).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var sessionStatusText: String {
        let head: String
        switch phase {
        case .idle: head = "Live · tap to dictate"
        case .recording: head = "Listening · tap to stop"
        case .transcribing: head = "Transcribing…"
        }
        guard let exp = sessionExpiresAt else { return head }
        let secs = max(0, Int(exp.timeIntervalSince(now)))
        return "\(head) · \(secs / 60):\(String(format: "%02d", secs % 60))"
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
        Button(action: orbTapped) {
            MicOrb(
                isRecording: phase == .recording,
                isTranscribing: phase == .transcribing,
                isSessionActive: sessionActive
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

    private func orbTapped() {
        message = nil
        if !FlowSessionState.isSessionActiveAndUnexpired {
            if let url = URL(string: "openwispr://startSession") {
                openContainer(url)
            }
            return
        }
        switch phase {
        case .idle:
            DarwinNotify.post(FlowSessionState.DarwinNotification.startUtterance)
            phase = .recording
        case .recording:
            DarwinNotify.post(FlowSessionState.DarwinNotification.stopUtterance)
            phase = .transcribing
        case .transcribing:
            break
        }
    }

    func refreshFromState() {
        let active = FlowSessionState.isSessionActiveAndUnexpired
        sessionActive = active
        sessionExpiresAt = FlowSessionState.sessionExpiresAt
        if !active {
            phase = .idle
            return
        }
        let utteranceInProgress = FlowSessionState.utteranceInProgress
        switch phase {
        case .idle:
            if utteranceInProgress { phase = .recording }
        case .recording:
            if !utteranceInProgress { phase = .transcribing }
        case .transcribing:
            break
        }
        if let err = FlowSessionState.errorMessage {
            message = err
            phase = .idle
            FlowSessionState.errorMessage = nil
        }
    }

    func transcriptDelivered() {
        phase = .idle
    }
}

struct MicOrb: View {
    let isRecording: Bool
    let isTranscribing: Bool
    let isSessionActive: Bool

    @State private var rippleA = false
    @State private var rippleB = false
    @State private var rotation: Double = 0
    @State private var breathe: Bool = false

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
                .blur(radius: isRecording ? 16 : (isSessionActive ? 9 : 5))
                .opacity(isRecording ? 0.75 : (isSessionActive ? 0.45 : 0.25))

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
                .scaleEffect(breathe ? 1.04 : 1.0)
                .shadow(color: orbColor.opacity(0.55), radius: 5, y: 1)

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
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                breathe = true
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
        if isSessionActive { return Color(red: 0.45, green: 0.55, blue: 0.95) }
        return Color(red: 0.55, green: 0.55, blue: 0.6)
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
                    .fill(orbColor.opacity(0.7))
                    .frame(width: 2, height: 8)
                    .offset(y: -(baseSize / 2 + 6))
                    .rotationEffect(.degrees(angle + rotation))
            }
        }
    }
}
