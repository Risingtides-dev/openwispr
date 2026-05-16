import UIKit
import SwiftUI

final class KeyboardViewController: UIInputViewController {
    private var hosting: UIHostingController<KeyboardView>?

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
            hasFullAccess: hasFullAccess,
            needsInputModeSwitchKey: needsInputModeSwitchKey
        )

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
    }
}
