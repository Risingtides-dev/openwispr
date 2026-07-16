import SwiftUI

struct ActivationView: View {
    @EnvironmentObject private var engine: BackgroundDictationEngine
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            KordTheme.void
                .ignoresSafeArea()

            // Soft brand glow behind the content.
            Circle()
                .fill(KordTheme.purple.opacity(0.18))
                .frame(width: 420, height: 420)
                .blur(radius: 90)
                .offset(y: -140)
                .frame(maxWidth: .infinity)
                .ignoresSafeArea()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(KordTheme.secondary)
                    .frame(width: 44, height: 44)
                    .background(KordTheme.raised)
                    .clipShape(Circle())
                    .overlay {
                        Circle().strokeBorder(KordTheme.borderSubtle, lineWidth: 1)
                    }
            }
            .padding(.top, 24)
            .padding(.trailing, 20)

            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 8) {
                    Image("KordMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 74, height: 74)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(KordTheme.borderMuted, lineWidth: 1)
                        }
                        .padding(.bottom, 8)

                    Text(AppBrand.name)
                        .font(KordTheme.display(22))
                        .foregroundStyle(KordTheme.text)
                    Text(AppBrand.tagline)
                        .font(KordTheme.body(13, weight: .medium))
                        .foregroundStyle(KordTheme.accentGradientHorizontal)
                }

                waveform(level: max(0.2, engine.level))
                    .frame(width: 128, height: 88)

                VStack(spacing: 12) {
                    Text("Swipe back to your app")
                        .font(KordTheme.display(30))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(KordTheme.text)

                    HStack(spacing: 8) {
                        statusDot
                        Text(statusText)
                            .font(KordTheme.title(16, weight: .medium))
                            .foregroundStyle(KordTheme.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(KordTheme.raised)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule().strokeBorder(KordTheme.borderSubtle, lineWidth: 1)
                    }
                }

                Text("Windtalker keeps the microphone armed so the keyboard can start and stop dictation without switching apps again.")
                    .font(KordTheme.body(15))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(KordTheme.muted)
                    .padding(.horizontal, 40)

                Spacer()

                HStack(spacing: 10) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(KordTheme.accentGradient)
                    Text("Swipe right on the bar below")
                        .font(KordTheme.label(16))
                        .foregroundStyle(KordTheme.text)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .kordAccentPanel(radius: KordTheme.radiusLarge)
                .padding(.bottom, 42)
            }
        }
        .onAppear {
            engine.activate()
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 9, height: 9)
    }

    private var dotColor: Color {
        switch engine.status {
        case .armed, .listening: return KordTheme.live
        case .processing: return KordTheme.magenta
        case .error: return KordTheme.danger
        case .inactive: return KordTheme.faint
        }
    }

    private var statusText: String {
        switch engine.status {
        case .inactive:
            return "Activating iPhone Microphone..."
        case .armed:
            return "Windtalker is activated"
        case .listening:
            return "Listening"
        case .processing:
            return "Transcribing..."
        case .error:
            return engine.lastError ?? "Activation failed"
        }
    }

    private func waveform(level: Double) -> some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 8) {
                ForEach(0..<5, id: \.self) { index in
                    Capsule()
                        .fill(KordTheme.accentGradient)
                        .frame(width: 10, height: barHeight(index: index, level: level, time: time))
                }
            }
        }
    }

    private func barHeight(index: Int, level: Double, time: TimeInterval) -> CGFloat {
        let multipliers: [Double] = [0.72, 0.42, 0.88, 0.5, 0.78]
        let idle = (sin(time * 6 + Double(index) * 0.9) + 1) * 4
        return CGFloat(24 + idle + level * 50 * multipliers[index])
    }
}
