import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let doneButton = UIButton(type: .system)
    private var started = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.025, green: 0.027, blue: 0.031, alpha: 1)
        configureUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !started else { return }
        started = true
        Task { await importSharedContent() }
    }

    private func configureUI() {
        titleLabel.text = "Windtalker"
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 30, weight: .black)
        titleLabel.textAlignment = .center

        messageLabel.text = "Importing shared item..."
        messageLabel.textColor = UIColor(white: 0.74, alpha: 1)
        messageLabel.font = .systemFont(ofSize: 16, weight: .medium)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0

        doneButton.setTitle("Done", for: .normal)
        doneButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        doneButton.tintColor = .white
        doneButton.backgroundColor = UIColor(red: 1.0, green: 0.34, blue: 0.12, alpha: 1)
        doneButton.layer.cornerRadius = 6
        doneButton.isHidden = true
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [titleLabel, messageLabel, doneButton])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            doneButton.heightAnchor.constraint(equalToConstant: 48)
        ])
    }

    @MainActor
    private func setMessage(_ message: String, doneVisible: Bool = true) {
        messageLabel.text = message
        doneButton.isHidden = !doneVisible
    }

    @MainActor
    private func importSharedContent() async {
        guard let providers = providersFromContext(), !providers.isEmpty else {
            setMessage("Nothing shareable was sent to Windtalker.")
            return
        }

        do {
            for provider in providers {
                if let text = try await loadText(from: provider) {
                    SharedConfig.saveSharedTextImport(text, title: provider.suggestedName ?? "Shared transcript")
                    setMessage("Transcript saved to Windtalker Notes and History.")
                    return
                }

                if let pending = try await queueFile(from: provider) {
                    setMessage("Recording saved to Windtalker. Open Windtalker > Import to transcribe \(pending.title).")
                    return
                }
            }
            setMessage("Windtalker can import text transcripts and audio files.")
        } catch {
            setMessage("Import failed: \(error.localizedDescription)")
        }
    }

    private func providersFromContext() -> [NSItemProvider]? {
        let items = extensionContext?.inputItems as? [NSExtensionItem]
        return items?.flatMap { $0.attachments ?? [] }
    }

    private func loadText(from provider: NSItemProvider) async throws -> String? {
        for identifier in [UTType.plainText.identifier, UTType.text.identifier] {
            guard provider.hasItemConformingToTypeIdentifier(identifier) else { continue }
            return try await withCheckedThrowingContinuation { continuation in
                provider.loadItem(forTypeIdentifier: identifier, options: nil) { item, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    if let text = item as? String {
                        continuation.resume(returning: text)
                    } else if let data = item as? Data {
                        continuation.resume(returning: String(data: data, encoding: .utf8))
                    } else if let url = item as? URL {
                        continuation.resume(returning: try? String(contentsOf: url, encoding: .utf8))
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
        return nil
    }

    private func queueFile(from provider: NSItemProvider) async throws -> PendingSharedImport? {
        let identifiers = provider.registeredTypeIdentifiers.filter { identifier in
            guard let type = UTType(identifier) else { return false }
            return type.conforms(to: .audio) ||
                type.conforms(to: .movie) ||
                type.conforms(to: .data) ||
                type.conforms(to: .item)
        }

        for identifier in identifiers {
            if let pending = try await loadFile(from: provider, identifier: identifier) {
                return pending
            }
        }
        return nil
    }

    private func loadFile(from provider: NSItemProvider, identifier: String) async throws -> PendingSharedImport? {
        let suggestedName = provider.suggestedName
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<PendingSharedImport?, Error>) in
            provider.loadFileRepresentation(forTypeIdentifier: identifier) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }
                do {
                    let pending = try SharedConfig.enqueueSharedFileImport(
                        fileURL: url,
                        suggestedName: suggestedName,
                        source: "Apple Notes"
                    )
                    continuation.resume(returning: pending)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    @objc private func doneTapped() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
