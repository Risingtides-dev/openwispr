import SwiftUI
import Combine

enum KordKeyboardMode {
    case letters
    case symbols
}

/// State + callbacks the view controller wires up. The keyboard never records;
/// the app owns the mic engine; the keyboard sends commands and inserts results.
///
/// Refresh architecture: engine state syncs are driven by Darwin notifications
/// (instant) with a slow fallback timer. SQLite-backed content (recents, menu
/// counts) loads only on appear, after inserts, and when results land — never
/// on a hot polling loop.
final class KeyboardModel: ObservableObject {
    var insert: (String) -> Void = { _ in }
    var deleteBackward: () -> Void = {}
    var advanceToNextKeyboard: () -> Void = {}
    var openApp: () -> Void = {}
    var haptic: () -> Void = {}

    @Published var keyboardMode: KordKeyboardMode = .letters
    @Published var isShifted = false
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published var hasFullAccess = false
    @Published var needsInputModeSwitchKey = true
    @Published var recents: [String] = []
    @Published var engineAlive = false
    @Published var engineStatus: EngineStatus = .inactive
    @Published var activeRequestID: String?
    @Published var isListening = false
    @Published var isProcessing = false
    @Published var level: Double = 0
    @Published var errorMessage: String?
    @Published var isMenuOpen = false
    @Published var menuPage = 0
    @Published var noteCount = 0
    @Published var latestNoteText = ""
    @Published var historyCount = 0
    @Published var latestHistoryText = ""
    @Published var cleanupStyle = SharedConfig.cleanupStyle

    private var levelTimer: Timer?
    private var undoStack: [String] = []
    private var redoStack: [String] = []

    deinit {
        levelTimer?.invalidate()
    }

    /// Cheap sync of engine + result state. UserDefaults reads only.
    func syncEngineState() {
        let alive = SharedConfig.isEngineAlive()
        let status = alive ? SharedConfig.engineStatus : EngineStatus.inactive
        let error = SharedConfig.engineLastError
        let style = SharedConfig.cleanupStyle

        if engineAlive != alive { engineAlive = alive }
        if engineStatus != status { engineStatus = status }
        if errorMessage != error { errorMessage = error }
        if cleanupStyle != style { cleanupStyle = style }

        if let activeRequestID,
           let result = SharedConfig.dictationResult,
           result.id == activeRequestID {
            SharedConfig.dictationResult = nil
            isListening = false
            isProcessing = false
            self.activeRequestID = nil
            if let text = result.text, !text.isEmpty {
                insertText(text)
            } else {
                errorMessage = result.error ?? "Dictation failed."
            }
            loadContent()
        }

        if !alive {
            if isListening { isListening = false }
            if isProcessing { isProcessing = false }
            activeRequestID = nil
        }

        updateLevelPolling()
    }

    /// SQLite-backed content: recents + menu data. Call sparingly.
    func loadContent() {
        let freshRecents = SharedConfig.recentTranscripts
        if recents != freshRecents { recents = freshRecents }

        let notes = SharedConfig.notes
        noteCount = notes.count
        if let note = notes.first {
            latestNoteText = [note.title, note.body]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ": ")
        } else {
            latestNoteText = ""
        }

        let history = SharedConfig.transcriptHistory
        historyCount = history.count
        latestHistoryText = history.first?.text ?? ""
    }

    private func updateLevelPolling() {
        let shouldPoll = isListening || engineStatus == .listening
        if shouldPoll {
            guard levelTimer == nil else { return }
            levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self else { return }
                let fresh = SharedConfig.engineLevel
                if abs(fresh - self.level) > 0.015 { self.level = fresh }
            }
        } else {
            levelTimer?.invalidate()
            levelTimer = nil
            if level != 0 { level = 0 }
        }
    }

    func micTapped() {
        guard hasFullAccess else { return }
        haptic()
        isMenuOpen = false
        syncEngineState()
        guard engineAlive else {
            openApp()
            return
        }

        if isListening {
            let id = activeRequestID ?? UUID().uuidString
            _ = SharedConfig.issueDictationCommand(.stop, id: id)
            isListening = false
            isProcessing = true
            updateLevelPolling()
            return
        }

        guard !isProcessing else { return }
        let id = SharedConfig.issueDictationCommand(.start)
        activeRequestID = id
        isListening = true
        isProcessing = false
        errorMessage = nil
        updateLevelPolling()
    }

    func toggleMenu() {
        haptic()
        if !isMenuOpen { loadContent() }
        isMenuOpen.toggle()
    }

    func closeMenu() {
        isMenuOpen = false
    }

    func cycleCleanupStyle() {
        haptic()
        let next = cleanupStyle.next
        cleanupStyle = next
        SharedConfig.cleanupStyle = next
    }

    func insertText(_ text: String) {
        guard !text.isEmpty else { return }
        insert(text)
        undoStack.append(text)
        redoStack.removeAll()
        updateHistoryState()
    }

    func typeLetter(_ letter: String) {
        haptic()
        let text = isShifted ? letter.uppercased() : letter
        insertText(text)
        if isShifted {
            isShifted = false
        }
    }

    func typeSymbol(_ symbol: String) {
        haptic()
        insertText(symbol)
    }

    func insertSpace() {
        haptic()
        insertText(" ")
    }

    func insertReturn() {
        haptic()
        insertText("\n")
    }

    func deleteTapped() {
        haptic()
        deleteBackward()
        redoStack.removeAll()
        updateHistoryState()
    }

    func toggleShift() {
        haptic()
        isShifted.toggle()
    }

    func toggleKeyboardMode() {
        haptic()
        keyboardMode = keyboardMode == .letters ? .symbols : .letters
        isShifted = false
    }

    func undoLastInsert() {
        haptic()
        guard let last = undoStack.popLast() else { return }
        for _ in last {
            deleteBackward()
        }
        redoStack.append(last)
        updateHistoryState()
    }

    func redoLastInsert() {
        haptic()
        guard let next = redoStack.popLast() else { return }
        insert(next)
        undoStack.append(next)
        updateHistoryState()
    }

    func deactivateEngine() {
        haptic()
        _ = SharedConfig.issueDictationCommand(.deactivate)
        SharedConfig.engineStatus = .inactive
        SharedConfig.engineHeartbeatAt = 0
        SharedConfig.engineLevel = 0
        SharedConfig.engineLastError = nil
        engineAlive = false
        engineStatus = .inactive
        level = 0
        isListening = false
        isProcessing = false
        activeRequestID = nil
        updateLevelPolling()
    }

    private func updateHistoryState() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }
}

// MARK: - Keyboard styling

private enum KeyStyle {
    static let bed = KordTheme.void
    static let key = KordTheme.elevated
    static let keyPressed = Color(hex: 0x33333B)
    static let special = KordTheme.raised
    static let keyText = KordTheme.text
    static let radius: CGFloat = 8
    static let height: CGFloat = 44
}

private struct KeyButtonStyle: ButtonStyle {
    var fill: Color = KeyStyle.key

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? KeyStyle.keyPressed : fill)
            .clipShape(RoundedRectangle(cornerRadius: KeyStyle.radius, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 0, y: 1)
            .scaleEffect(configuration.isPressed ? 1.03 : 1)
            .animation(.easeOut(duration: 0.06), value: configuration.isPressed)
    }
}

struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        VStack(spacing: 8) {
            if model.isMenuOpen && !isCaptureActive {
                menuPanel
            } else {
                mainPanel
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .frame(height: keyboardHeight)
        .background(KeyStyle.bed)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(KordTheme.borderSubtle)
                .frame(height: 0.5)
        }
    }

    private var keyboardHeight: CGFloat {
        if model.isMenuOpen && !isCaptureActive {
            return 300
        }
        return isCaptureActive ? 260 : 324
    }

    private var isCaptureActive: Bool {
        model.isListening ||
        model.isProcessing ||
        model.engineStatus == .listening ||
        model.engineStatus == .processing
    }

    private var mainPanel: some View {
        VStack(spacing: 8) {
            recentsRow
            controlRow
            if isCaptureActive {
                capturePanel
            } else {
                virtualKeyboard
            }
        }
    }

    // Tap-to-insert chips of recent dictations.
    @ViewBuilder private var recentsRow: some View {
        if model.recents.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "waveform")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(KordTheme.accentGradient)
                Text("Tap the mic to dictate")
                    .font(KordTheme.label(13, weight: .medium))
                    .foregroundStyle(KordTheme.muted)
            }
            .frame(height: 32)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.recents, id: \.self) { text in
                        Button { model.insertText(text) } label: {
                            Text(text)
                                .lineLimit(1)
                                .font(KordTheme.body(14))
                                .foregroundStyle(KordTheme.secondary)
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .frame(maxWidth: 220, alignment: .leading)
                                .background(KordTheme.raised)
                                .overlay {
                                    Capsule().strokeBorder(KordTheme.borderSubtle, lineWidth: 1)
                                }
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
            }
            .frame(height: 32)
        }
    }

    private var controlRow: some View {
        HStack(spacing: 8) {
            toolbarButton(systemImage: "line.3.horizontal", action: model.toggleMenu)
            toolbarButton(systemImage: "arrow.uturn.backward", isEnabled: model.canUndo, action: model.undoLastInsert)
            toolbarButton(systemImage: "arrow.uturn.forward", isEnabled: model.canRedo, action: model.redoLastInsert)
            Spacer(minLength: 4)
            Button(action: model.cycleCleanupStyle) {
                HStack(spacing: 6) {
                    Text(model.cleanupStyle.title)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(KordTheme.muted)
                }
                .font(KordTheme.label(15))
                .foregroundStyle(KordTheme.text)
                .padding(.horizontal, 14)
                .frame(minWidth: 84)
                .frame(height: 40)
                .background(KordTheme.raised)
                .overlay {
                    Capsule().strokeBorder(KordTheme.borderMuted, lineWidth: 1)
                }
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cleanup style: \(model.cleanupStyle.title)")
            micButton
        }
        .padding(.horizontal, 12)
    }

    // MARK: Mic

    private var micButton: some View {
        Group {
            if model.hasFullAccess && !model.engineAlive, let activateURL = AppBrand.url("activate") {
                Link(destination: activateURL) {
                    voicePill(title: "Activate", systemImage: "waveform", style: .outlined)
                }
            } else if model.isListening {
                Button(action: model.micTapped) {
                    voicePill(title: "Done", systemImage: "checkmark", style: .filled)
                }
            } else if model.isProcessing {
                voicePill(title: "Working", systemImage: nil, style: .outlined, isProcessing: true)
            } else {
                Button(action: model.micTapped) {
                    voicePill(title: "Start", systemImage: "waveform", style: .filled)
                }
                .disabled(!model.hasFullAccess)
            }
        }
        .buttonStyle(.plain)
        .opacity(model.hasFullAccess ? 1 : 0.4)
    }

    private enum VoicePillStyle {
        case filled
        case outlined
    }

    @ViewBuilder
    private func voicePill(
        title: String,
        systemImage: String?,
        style: VoicePillStyle,
        isProcessing: Bool = false
    ) -> some View {
        HStack(spacing: 7) {
            if isProcessing {
                ProgressView()
                    .tint(KordTheme.text)
                    .scaleEffect(0.72)
            }
            Text(title)
                .font(KordTheme.label(15))
                .lineLimit(1)
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .bold))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background {
            if style == .filled {
                Capsule().fill(KordTheme.accentGradient)
            } else {
                Capsule()
                    .fill(KordTheme.raised)
                    .overlay {
                        Capsule().strokeBorder(KordTheme.magenta.opacity(0.6), lineWidth: 1)
                    }
            }
        }
        .clipShape(Capsule())
    }

    // MARK: Menu

    private var menuPanel: some View {
        VStack(spacing: 12) {
            menuHeader
            menuPages
            pageDots
            HStack {
                toolbarButton(systemImage: "globe", action: model.advanceToNextKeyboard)
                    .accessibilityLabel("Next keyboard")
                Spacer()
            }
            .padding(.horizontal, 12)
        }
    }

    private var menuHeader: some View {
        HStack(spacing: 10) {
            Button(action: model.closeMenu) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(KordTheme.text)
                    .frame(width: 48, height: 48)
                    .kordPanel(radius: KordTheme.radiusSmall)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            Text(AppBrand.name)
                .font(KordTheme.display(18))
                .foregroundStyle(KordTheme.text)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let settingsURL = AppBrand.url("settings") {
                Link(destination: settingsURL) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(KordTheme.secondary)
                        .frame(width: 48, height: 48)
                        .kordPanel(radius: KordTheme.radiusSmall)
                }
            }

            engineToggle
        }
        .padding(.horizontal, 12)
    }

    private var engineToggle: some View {
        Group {
            if model.engineAlive {
                Button(action: model.deactivateEngine) {
                    toggleShape(isOn: true)
                }
            } else if let activateURL = AppBrand.url("activate") {
                Link(destination: activateURL) {
                    toggleShape(isOn: false)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func toggleShape(isOn: Bool) -> some View {
        Capsule()
            .fill(isOn ? AnyShapeStyle(KordTheme.accentGradient) : AnyShapeStyle(KordTheme.elevated))
            .frame(width: 64, height: 36)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .frame(width: 28, height: 28)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .padding(.horizontal, 4)
            }
            .overlay {
                Capsule().strokeBorder(KordTheme.borderMuted, lineWidth: 1)
            }
            .frame(width: 64, height: 48)
    }

    private var menuPages: some View {
        TabView(selection: $model.menuPage) {
            recentMenuPage.tag(0)
            notesMenuPage.tag(1)
            historyMenuPage.tag(2)
            settingsMenuPage.tag(3)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 150)
    }

    private var recentMenuPage: some View {
        VStack(spacing: 10) {
            menuTitle("Recent")
            if model.recents.isEmpty {
                menuEmptyText("Recent dictations show here.")
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(model.recents.prefix(2)), id: \.self) { text in
                        Button {
                            model.insertText(text)
                            model.closeMenu()
                        } label: {
                            Text(text)
                                .font(KordTheme.body(15))
                                .foregroundStyle(KordTheme.text)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .frame(height: 40)
                                .kordPanel(radius: KordTheme.radiusSmall)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var notesMenuPage: some View {
        routeMenuPage(
            title: "Notes",
            value: countText(model.noteCount, singular: "note"),
            detail: previewText(model.latestNoteText, fallback: "Open notes"),
            systemImage: "note.text",
            urlString: "\(AppBrand.primaryScheme)://notes"
        )
    }

    private var historyMenuPage: some View {
        routeMenuPage(
            title: "History",
            value: countText(model.historyCount, singular: "transcript"),
            detail: previewText(model.latestHistoryText, fallback: "Open history"),
            systemImage: "clock.arrow.circlepath",
            urlString: "\(AppBrand.primaryScheme)://history"
        )
    }

    private var settingsMenuPage: some View {
        routeMenuPage(
            title: "Windtalker Settings",
            value: model.engineAlive ? "Engine on" : "Engine off",
            detail: "Models, language, cleanup, and vocabulary",
            systemImage: "slider.horizontal.3",
            urlString: "\(AppBrand.primaryScheme)://settings"
        )
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(index == model.menuPage
                          ? AnyShapeStyle(KordTheme.accentGradientHorizontal)
                          : AnyShapeStyle(KordTheme.borderStrong))
                    .frame(width: index == model.menuPage ? 18 : 6, height: 5)
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.menuPage)
    }

    private func routeMenuPage(
        title: String,
        value: String,
        detail: String,
        systemImage: String,
        urlString: String
    ) -> some View {
        VStack(spacing: 12) {
            menuTitle(title)
            if let url = URL(string: urlString) {
                Link(destination: url) {
                    routeCard(value: value, detail: detail, systemImage: systemImage)
                }
                .buttonStyle(.plain)
            } else {
                routeCard(value: value, detail: detail, systemImage: systemImage)
            }
        }
        .padding(.horizontal, 20)
    }

    private func routeCard(value: String, detail: String, systemImage: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(KordTheme.accentGradient)
                .frame(width: 46, height: 46)
                .background(KordTheme.elevated)
                .clipShape(RoundedRectangle(cornerRadius: KordTheme.radiusSmall, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(KordTheme.title(18))
                    .foregroundStyle(KordTheme.text)
                    .lineLimit(1)
                Text(detail)
                    .font(KordTheme.body(13))
                    .foregroundStyle(KordTheme.muted)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(KordTheme.faint)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: 96)
        .kordPanel()
    }

    private func menuTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(KordTheme.label(11, weight: .bold))
            .foregroundStyle(KordTheme.muted)
            .tracking(1.2)
    }

    private func menuEmptyText(_ text: String) -> some View {
        Text(text)
            .font(KordTheme.body(15))
            .foregroundStyle(KordTheme.muted)
            .frame(maxWidth: .infinity)
            .frame(height: 88)
    }

    private func countText(_ count: Int, singular: String) -> String {
        count == 1 ? "1 \(singular)" : "\(count) \(singular)s"
    }

    private func previewText(_ text: String, fallback: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    // MARK: Keys

    private var virtualKeyboard: some View {
        VStack(spacing: 8) {
            switch model.keyboardMode {
            case .letters:
                letterKeyboard
            case .symbols:
                symbolKeyboard
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .frame(height: 208)
    }

    private var letterKeyboard: some View {
        VStack(spacing: 8) {
            keyRow(["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"])
            keyRow(["a", "s", "d", "f", "g", "h", "j", "k", "l"])
                .padding(.horizontal, 18)
            HStack(spacing: 6) {
                specialKey(systemImage: model.isShifted ? "shift.fill" : "shift", isActive: model.isShifted, action: model.toggleShift)
                    .frame(width: 46)
                keyRow(["z", "x", "c", "v", "b", "n", "m"])
                specialKey(systemImage: "delete.left", action: model.deleteTapped)
                    .frame(width: 46)
            }
            bottomRow(modeLabel: "123")
        }
    }

    private var symbolKeyboard: some View {
        VStack(spacing: 8) {
            keyRow(["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"], symbolMode: true)
            keyRow(["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""], symbolMode: true)
            HStack(spacing: 6) {
                modeKey("#+=")
                    .frame(width: 58)
                keyRow([".", ",", "?", "!", "'"], symbolMode: true)
                specialKey(systemImage: "delete.left", action: model.deleteTapped)
                    .frame(width: 58)
            }
            bottomRow(modeLabel: "ABC")
        }
    }

    private func bottomRow(modeLabel: String) -> some View {
        HStack(spacing: 6) {
            specialKey(systemImage: "globe", action: model.advanceToNextKeyboard)
                .frame(width: 46)
            modeKey(modeLabel)
                .frame(width: 58)
            spaceKey
            returnKey
                .frame(width: 84)
        }
    }

    private func keyRow(_ keys: [String], symbolMode: Bool = false) -> some View {
        HStack(spacing: 6) {
            ForEach(keys, id: \.self) { key in
                textKey(displayLabel(for: key, symbolMode: symbolMode)) {
                    if symbolMode {
                        model.typeSymbol(key)
                    } else {
                        model.typeLetter(key)
                    }
                }
            }
        }
    }

    private func displayLabel(for key: String, symbolMode: Bool) -> String {
        symbolMode ? key : (model.isShifted ? key.uppercased() : key)
    }

    private var spaceKey: some View {
        Button(action: model.insertSpace) {
            Text("space")
                .font(KordTheme.body(15, weight: .medium))
                .foregroundStyle(KordTheme.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: KeyStyle.height)
        }
        .buttonStyle(KeyButtonStyle())
        .accessibilityLabel("Space")
    }

    private var returnKey: some View {
        Button(action: model.insertReturn) {
            Image(systemName: "return")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: KeyStyle.height)
                .background(KordTheme.accentGradient)
                .clipShape(RoundedRectangle(cornerRadius: KeyStyle.radius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Return")
    }

    private func modeKey(_ label: String) -> some View {
        Button(action: model.toggleKeyboardMode) {
            Text(label)
                .font(KordTheme.label(14))
                .foregroundStyle(KordTheme.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: KeyStyle.height)
        }
        .buttonStyle(KeyButtonStyle(fill: KeyStyle.special))
    }

    private func textKey(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(KordTheme.body(22, weight: .regular))
                .foregroundStyle(KeyStyle.keyText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .frame(height: KeyStyle.height)
        }
        .buttonStyle(KeyButtonStyle())
    }

    private func specialKey(
        systemImage: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isActive ? KordTheme.void : KordTheme.text)
                .frame(maxWidth: .infinity)
                .frame(height: KeyStyle.height)
        }
        .buttonStyle(KeyButtonStyle(fill: isActive ? KordTheme.text : KeyStyle.special))
    }

    private func toolbarButton(
        systemImage: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(KordTheme.secondary)
                .frame(width: 40, height: 40)
                .background(KordTheme.raised)
                .overlay {
                    Circle().strokeBorder(KordTheme.borderSubtle, lineWidth: 1)
                }
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
    }

    // MARK: Capture

    private var capturePanel: some View {
        VStack(spacing: 14) {
            if model.isListening || model.engineStatus == .listening {
                ListeningWaveform(level: max(model.level, 0.08))
                    .frame(width: 148, height: 62)
                VStack(spacing: 2) {
                    Text("Listening")
                        .font(KordTheme.title(16))
                        .foregroundStyle(KordTheme.text)
                    Text("iPhone Microphone")
                        .font(KordTheme.body(13))
                        .foregroundStyle(KordTheme.muted)
                }
            } else if model.isProcessing || model.engineStatus == .processing {
                ProgressView()
                    .tint(KordTheme.magenta)
                    .scaleEffect(1.2)
                Text("Transcribing...")
                    .font(KordTheme.body(15))
                    .foregroundStyle(KordTheme.muted)
            } else if !model.hasFullAccess {
                Text("Turn on Allow Full Access for Windtalker in Settings > General > Keyboard")
                    .font(KordTheme.body(12))
                    .foregroundStyle(KordTheme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            } else if model.engineAlive {
                Text("Windtalker activated")
                    .font(KordTheme.body(15))
                    .foregroundStyle(KordTheme.muted)
            } else {
                Text("Tap Activate, then swipe back here")
                    .font(KordTheme.body(15))
                    .foregroundStyle(KordTheme.muted)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 128)
    }
}

private struct ListeningWaveform: View {
    let level: Double

    private let multipliers: [Double] = [0.34, 0.58, 0.86, 0.48, 0.72, 0.95, 0.64, 0.44, 0.76, 0.52]

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            HStack(alignment: .center, spacing: 7) {
                ForEach(0..<multipliers.count, id: \.self) { index in
                    Capsule()
                        .fill(KordTheme.accentGradient)
                        .frame(width: 6, height: barHeight(index: index, time: time))
                }
            }
        }
    }

    private func barHeight(index: Int, time: TimeInterval) -> CGFloat {
        let clampedLevel = min(max(level, 0.04), 1)
        let voiceBoost = clampedLevel * 46 * multipliers[index]
        let idleMotion = (sin(time * 7.5 + Double(index) * 0.72) + 1) * 5
        return CGFloat(10 + voiceBoost + idleMotion)
    }
}
