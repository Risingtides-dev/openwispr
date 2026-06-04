import UIKit
import SwiftUI

final class KeyboardViewController: UIInputViewController {
    private var hosting: UIHostingController<KeyboardView>?
    private let model = KeyboardModel()

    override func viewDidLoad() {
        super.viewDidLoad()

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
        model.hasFullAccess = hasFullAccess
        model.needsInputModeSwitchKey = needsInputModeSwitchKey
        model.refresh()

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
        if let pending = SharedConfig.pendingInsert {
            SharedConfig.pendingInsert = nil
            textDocumentProxy.insertText(pending)
        }
        model.refresh()
    }

    /// Open the container app via its URL scheme so it can record + transcribe.
    /// `openURL:` isn't exposed on UIInputViewController, so we walk the
    /// responder chain to find an object that responds to it.
    private func openHostApp() {
        guard let url = URL(string: "openwispr://record") else { return }
        var responder: UIResponder? = self
        let selector = sel_registerName("openURL:")
        while let r = responder {
            if r.responds(to: selector) {
                r.perform(selector, with: url)
                return
            }
            responder = r.next
        }
    }
}
