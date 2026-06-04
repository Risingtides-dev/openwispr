import SwiftUI
import Combine

/// State + callbacks the view controller wires up. The keyboard never records;
/// it opens the app to dictate, then inserts the text the app hands back.
final class KeyboardModel: ObservableObject {
    var insert: (String) -> Void = { _ in }
    var deleteBackward: () -> Void = {}
    var advanceToNextKeyboard: () -> Void = {}
    var openApp: () -> Void = {}

    @Published var hasFullAccess = false
    @Published var needsInputModeSwitchKey = true
    @Published var recents: [String] = []

    func refresh() {
        recents = SharedConfig.recentTranscripts
    }
}

struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        VStack(spacing: 8) {
            recentsRow
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                if model.needsInputModeSwitchKey {
                    sideButton(systemImage: "globe", action: model.advanceToNextKeyboard)
                } else {
                    Color.clear.frame(width: 56)
                }
                Spacer()
                micButton
                Spacer()
                sideButton(systemImage: "delete.left", action: model.deleteBackward)
            }
            .padding(.horizontal, 16)
            Spacer(minLength: 0)
            helpLine
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 260)
    }

    // Tap-to-insert chips of recent dictations.
    @ViewBuilder private var recentsRow: some View {
        if model.recents.isEmpty {
            Text("Tap the mic to dictate in openwispr")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.recents, id: \.self) { text in
                        Button { model.insert(text) } label: {
                            Text(text)
                                .lineLimit(1)
                                .font(.callout)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(maxWidth: 220, alignment: .leading)
                                .background(.quaternary, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var micButton: some View {
        Button(action: model.openApp) {
            ZStack {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 88, height: 88)
                    .shadow(radius: 2, y: 1)
                Image(systemName: "mic.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)
        .disabled(!model.hasFullAccess)
        .opacity(model.hasFullAccess ? 1 : 0.4)
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

    @ViewBuilder private var helpLine: some View {
        if !model.hasFullAccess {
            Text("Turn on Allow Full Access for openwispr in Settings > General > Keyboard")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }
}
