import UIKit
import SwiftUI

final class KeyboardViewController: UIInputViewController {
    private var hosting: UIHostingController<KeyboardView>?
    private var rootView: KeyboardView?

    override func viewDidLoad() {
        super.viewDidLoad()

        let root = KeyboardView(
            insertAndCopy: { [weak self] text in
                guard let self else { return }
                self.textDocumentProxy.insertText(text)
                UIPasteboard.general.string = text
            },
            deleteBackward: { [weak self] in
                self?.textDocumentProxy.deleteBackward()
            },
            advanceToNextKeyboard: { [weak self] in
                self?.advanceToNextInputMode()
            },
            openContainer: { [weak self] url in
                self?.openURL(url)
            },
            hasFullAccess: hasFullAccess,
            needsInputModeSwitchKey: needsInputModeSwitchKey
        )
        rootView = root

        let host = UIHostingController(rootView: root)
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

        registerListeners()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        rootView?.refreshFromState()
        deliverPendingTranscriptIfAny()
    }

    deinit {
        unregisterListeners()
    }

    private func openURL(_ url: URL) {
        var responder: UIResponder? = self
        while let r = responder {
            if r.responds(to: #selector(UIApplication.open(_:options:completionHandler:))) {
                _ = r.perform(#selector(UIApplication.open(_:options:completionHandler:)), with: url, with: [:])
                return
            }
            responder = r.next
        }
    }

    private func registerListeners() {
        let observer = Unmanaged.passUnretained(self).toOpaque()
        DarwinNotify.observe(FlowSessionState.DarwinNotification.transcriptReady, observer: observer) { _, observer, _, _, _ in
            guard let observer else { return }
            let vc = Unmanaged<KeyboardViewController>.fromOpaque(observer).takeUnretainedValue()
            DispatchQueue.main.async { vc.deliverPendingTranscriptIfAny() }
        }
        DarwinNotify.observe(FlowSessionState.DarwinNotification.utteranceAck, observer: observer) { _, observer, _, _, _ in
            guard let observer else { return }
            let vc = Unmanaged<KeyboardViewController>.fromOpaque(observer).takeUnretainedValue()
            DispatchQueue.main.async { vc.rootView?.refreshFromState() }
        }
        DarwinNotify.observe(FlowSessionState.DarwinNotification.sessionEnded, observer: observer) { _, observer, _, _, _ in
            guard let observer else { return }
            let vc = Unmanaged<KeyboardViewController>.fromOpaque(observer).takeUnretainedValue()
            DispatchQueue.main.async { vc.rootView?.refreshFromState() }
        }
    }

    private func unregisterListeners() {
        let observer = Unmanaged.passUnretained(self).toOpaque()
        DarwinNotify.remove(FlowSessionState.DarwinNotification.transcriptReady, observer: observer)
        DarwinNotify.remove(FlowSessionState.DarwinNotification.utteranceAck, observer: observer)
        DarwinNotify.remove(FlowSessionState.DarwinNotification.sessionEnded, observer: observer)
    }

    private func deliverPendingTranscriptIfAny() {
        let counter = FlowSessionState.latestTranscriptCounter
        let lastInserted = FlowSessionState.lastInsertedCounter
        guard counter > lastInserted, let text = FlowSessionState.latestTranscript, !text.isEmpty else { return }
        textDocumentProxy.insertText(text)
        UIPasteboard.general.string = text
        FlowSessionState.lastInsertedCounter = counter
        rootView?.transcriptDelivered()
    }
}
