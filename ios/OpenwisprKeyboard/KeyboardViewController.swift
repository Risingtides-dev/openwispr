import UIKit
import SwiftUI
import os

private let keyboardLog = Logger(subsystem: "dev.smathdaddy.openwispr", category: "Keyboard")

final class KeyboardViewController: UIInputViewController {
    private var hosting: UIHostingController<KeyboardView>?
    private let model = KeyboardModel()
    private let ipcObserver = KordIPCObserver()
    private let keyHaptic = UIImpactFeedbackGenerator(style: .light)
    private var fallbackTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        keyboardLog.info("viewDidLoad")

        model.insert = { [weak self] text in
            self?.textDocumentProxy.insertText(text)
        }
        model.deleteBackward = { [weak self] in
            self?.textDocumentProxy.deleteBackward()
        }
        model.advanceToNextKeyboard = { [weak self] in
            self?.advanceToNextInputMode()
        }
        model.openApp = { [weak self] in
            self?.openHostApp()
        }
        model.haptic = { [weak self] in
            self?.keyHaptic.impactOccurred()
        }
        model.hasFullAccess = hasFullAccess
        model.needsInputModeSwitchKey = needsInputModeSwitchKey
        model.syncEngineState()
        model.loadContent()
        keyboardLog.info("loaded hasFullAccess=\(self.hasFullAccess, privacy: .public) recents=\(self.model.recents.count, privacy: .public)")

        // The engine pushes results and state changes over Darwin notifications,
        // so the keyboard reacts instantly instead of polling SQLite on a timer.
        ipcObserver.observe(.result) { [weak self] in
            self?.model.syncEngineState()
        }
        ipcObserver.observe(.state) { [weak self] in
            self?.model.syncEngineState()
        }

        let host = UIHostingController(rootView: KeyboardView(model: model))
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)
        hosting = host
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Coming back from the app: if it left a transcript for us, insert it now.
        model.hasFullAccess = hasFullAccess
        model.needsInputModeSwitchKey = needsInputModeSwitchKey
        keyboardLog.info("viewWillAppear hasFullAccess=\(self.hasFullAccess, privacy: .public)")
        if let pending = SharedConfig.pendingInsert {
            SharedConfig.pendingInsert = nil
            model.insertText(pending)
            keyboardLog.info("inserted pending text length=\(pending.count, privacy: .public)")
        }
        model.syncEngineState()
        model.loadContent()
        keyHaptic.prepare()
        startFallbackTimer()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        fallbackTimer?.invalidate()
        fallbackTimer = nil
    }

    /// Catches missed Darwin notifications and heartbeat staleness.
    private func startFallbackTimer() {
        fallbackTimer?.invalidate()
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.model.hasFullAccess = self.hasFullAccess
            self.model.syncEngineState()
        }
    }

    /// Open the container app via its URL scheme so it can record + transcribe.
    private func openHostApp() {
        guard let url = AppBrand.url("activate") else { return }
        keyboardLog.info("extensionContext.open requested")
        extensionContext?.open(url) { success in
            keyboardLog.info("extensionContext.open completed success=\(success, privacy: .public)")
        }
    }
}
