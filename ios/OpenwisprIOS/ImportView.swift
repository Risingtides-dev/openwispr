import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    private enum ImportFileKind {
        case audio
        case text
        case pdf
        case rtf
        case unsupported
    }

    private enum ImportPhase: Equatable {
        case idle
        case reading
        case transcribing
        case complete(String)
        case failed(String)
    }

    @State private var showingImporter = false
    @State private var createNote = true
    @State private var phase: ImportPhase = .idle
    @State private var latestTitle = ""
    @State private var latestText = ""
    @State private var pendingImports: [PendingSharedImport] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    intakeBox
                    pendingImportsPanel
                    saveOptions
                    statusPanel
                    latestPanel
                }
                .padding(18)
            }
            .background(KordTheme.void.ignoresSafeArea())
            .navigationTitle("Import")
            .toolbarBackground(KordTheme.void, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .tint(KordTheme.ember)
            .onAppear(perform: loadPendingImports)
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: allowedContentTypes,
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    Task { await process(urls: urls) }
                case .failure(let error):
                    phase = .failed(error.localizedDescription)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(KordTheme.ember)
                    .frame(width: 52, height: 52)
                    .kordPanel()

                VStack(alignment: .leading, spacing: 4) {
                    Text("IMPORT")
                        .font(KordTheme.label(12, weight: .bold))
                        .foregroundStyle(KordTheme.ember)
                        .tracking(0)
                    Text("One intake for files, recordings, and notes.")
                        .font(KordTheme.title(20))
                        .foregroundStyle(KordTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("Pick audio, PDF, RTF, Markdown, or plain text from Files. Windtalker transcribes audio, extracts document text, saves History, and can create Notes.")
                .font(KordTheme.body(16))
                .foregroundStyle(KordTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .kordPanel()
    }

    private var intakeBox: some View {
        Button {
            phase = .idle
            showingImporter = true
        } label: {
            VStack(spacing: 16) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(KordTheme.ember)

                Text("Choose files")
                    .font(KordTheme.title(20, weight: .bold))
                    .foregroundStyle(KordTheme.text)

                Text("Audio, PDF, RTF, Markdown, or text")
                    .font(KordTheme.body(16))
                    .foregroundStyle(KordTheme.muted)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 172)
            .overlay {
                RoundedRectangle(cornerRadius: KordTheme.radius, style: .continuous)
                    .stroke(KordTheme.ember.opacity(0.75), style: StrokeStyle(lineWidth: 1, dash: [7, 6]))
            }
            .kordPanel()
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }

    @ViewBuilder private var pendingImportsPanel: some View {
        if !pendingImports.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Shared to Windtalker")
                ForEach(pendingImports) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.kind == .audio ? "waveform" : "doc.text")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(KordTheme.ember)
                            .frame(width: 36)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(KordTheme.label(17))
                                .foregroundStyle(KordTheme.text)
                                .lineLimit(1)
                            Text(item.source)
                                .font(KordTheme.label(12, weight: .medium))
                                .foregroundStyle(KordTheme.muted)
                        }

                        Spacer(minLength: 0)

                        Button {
                            Task { await process(pendingImport: item) }
                        } label: {
                            Text(item.kind == .audio ? "Transcribe" : "Import")
                                .font(KordTheme.label(12, weight: .bold))
                                .foregroundStyle(KordTheme.text)
                                .padding(.horizontal, 10)
                                .frame(height: 32)
                                .background(KordTheme.raised)
                                .clipShape(RoundedRectangle(cornerRadius: KordTheme.radius, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: KordTheme.radius, style: .continuous)
                                        .stroke(KordTheme.rail, lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .disabled(isBusy)
                    }
                    .padding(14)
                    .kordPanel()
                }
            }
        }
    }

    private var saveOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Save")
            Toggle(isOn: $createNote) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Create note")
                        .font(KordTheme.label(17))
                        .foregroundStyle(KordTheme.text)
                    Text("Also save the import as a Windtalker note.")
                        .font(KordTheme.body(13))
                        .foregroundStyle(KordTheme.muted)
                }
            }
            .toggleStyle(.switch)
            .padding(14)
            .kordPanel()
        }
    }

    @ViewBuilder private var statusPanel: some View {
        switch phase {
        case .idle:
            EmptyView()
        case .reading:
            progressPanel("Reading file...")
        case .transcribing:
            progressPanel("Transcribing audio...")
        case .complete(let message):
            messagePanel(message, systemImage: "checkmark", color: KordTheme.live)
        case .failed(let message):
            messagePanel(message, systemImage: "exclamationmark.triangle", color: KordTheme.ember)
        }
    }

    @ViewBuilder private var latestPanel: some View {
        if !latestText.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle(latestTitle.isEmpty ? "Latest Import" : latestTitle)
                Text(latestText)
                    .font(KordTheme.body(16))
                    .foregroundStyle(KordTheme.text)
                    .lineLimit(10)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .kordPanel()
            }
        }
    }

    private var allowedContentTypes: [UTType] {
        uniqueTypes(["m4a", "mp3", "wav", "aac", "webm"], fallback: .audio) +
            uniqueTypes(["txt", "md", "markdown"], fallback: .text) +
            uniqueTypes(["rtf"], fallback: .rtf) +
            [.plainText, .pdf]
    }

    private func progressPanel(_ message: String) -> some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(KordTheme.text)
            Text(message)
                .font(KordTheme.label(16))
                .foregroundStyle(KordTheme.text)
            Spacer()
        }
        .padding(14)
        .kordPanel()
    }

    private func messagePanel(_ message: String, systemImage: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 24)
            Text(message)
                .font(KordTheme.body(16))
                .foregroundStyle(KordTheme.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .kordPanel()
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(KordTheme.label(12, weight: .bold))
            .foregroundStyle(KordTheme.muted)
            .tracking(0)
    }

    private var isBusy: Bool {
        phase == .reading || phase == .transcribing
    }

    @MainActor
    private func process(urls: [URL]) async {
        guard !urls.isEmpty else { return }
        var imported = 0
        var failed: [String] = []

        for url in urls {
            let result = await process(url: url, showFinalPhase: urls.count == 1)
            if result {
                imported += 1
            } else {
                failed.append(displayName(for: url))
            }
        }

        if urls.count > 1 {
            if failed.isEmpty {
                phase = .complete("Imported \(imported) files into Windtalker.")
            } else if imported > 0 {
                phase = .complete("Imported \(imported) files. \(failed.count) could not be processed.")
            } else {
                phase = .failed("Windtalker could not process those files.")
            }
        }
    }

    @MainActor
    private func process(url: URL, showFinalPhase: Bool = true) async -> Bool {
        latestTitle = displayName(for: url)
        latestText = ""

        do {
            switch importFileKind(for: url) {
            case .audio:
                guard let apiKey = SharedConfig.groqApiKey, !apiKey.isEmpty else {
                    phase = .failed("Add a Groq API key in Settings before importing audio.")
                    return false
                }
                phase = .reading
                let copiedURL = try copyToTemporaryFile(url)
                defer { try? FileManager.default.removeItem(at: copiedURL) }
                phase = .transcribing
                let result = try await TranscriptionPipeline.transcribe(fileURL: copiedURL)
                if save(text: result.text, raw: result.raw, title: latestTitle, audioFileURL: copiedURL) {
                    if showFinalPhase {
                        phase = .complete("Imported audio and saved a transcript.")
                    }
                    return true
                }
            case .text:
                phase = .reading
                let text = try readTextFile(url)
                if save(text: text, raw: nil, title: latestTitle) {
                    if showFinalPhase {
                        phase = .complete("Imported document text into Windtalker.")
                    }
                    return true
                }
            case .pdf:
                phase = .reading
                let text = try readPDF(url)
                if save(text: text, raw: nil, title: latestTitle) {
                    if showFinalPhase {
                        phase = .complete("Imported PDF text into Windtalker.")
                    }
                    return true
                }
            case .rtf:
                phase = .reading
                let text = try readRichText(url)
                if save(text: text, raw: nil, title: latestTitle) {
                    if showFinalPhase {
                        phase = .complete("Imported rich text into Windtalker.")
                    }
                    return true
                }
            case .unsupported:
                phase = .failed("Windtalker can import audio, PDF, RTF, Markdown, and plain text files.")
                return false
            }
        } catch {
            phase = .failed(error.localizedDescription)
            return false
        }
        return false
    }

    @MainActor
    private func process(pendingImport: PendingSharedImport) async {
        latestTitle = pendingImport.title
        latestText = ""

        guard let fileURL = SharedConfig.fileURL(for: pendingImport) else {
            phase = .failed("The shared file could not be found.")
            SharedConfig.removePendingSharedImport(id: pendingImport.id)
            loadPendingImports()
            return
        }

        do {
            switch pendingImport.kind {
            case .audio:
                guard let apiKey = SharedConfig.groqApiKey, !apiKey.isEmpty else {
                    phase = .failed("Add a Groq API key in Settings before transcribing shared audio.")
                    return
                }
                phase = .transcribing
                let result = try await TranscriptionPipeline.transcribe(fileURL: fileURL)
                if save(text: result.text, raw: result.raw, title: pendingImport.title, audioFileURL: fileURL) {
                    SharedConfig.removePendingSharedImport(id: pendingImport.id, deleteFile: true)
                    loadPendingImports()
                    phase = .complete("Shared recording transcribed and saved to Windtalker.")
                }
            case .textFile:
                phase = .reading
                let text = try String(contentsOf: fileURL, encoding: .utf8)
                if save(text: text, raw: nil, title: pendingImport.title) {
                    SharedConfig.removePendingSharedImport(id: pendingImport.id, deleteFile: true)
                    loadPendingImports()
                    phase = .complete("Shared transcript saved to Windtalker.")
                }
            case .file:
                _ = await process(url: fileURL)
                SharedConfig.removePendingSharedImport(id: pendingImport.id, deleteFile: true)
                loadPendingImports()
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func save(text: String, raw: String?, title: String, audioFileURL: URL? = nil) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            latestText = ""
            phase = .failed("The import did not contain any text.")
            return false
        }

        SharedConfig.addTranscript(
            cleaned,
            raw: raw,
            source: "Import",
            title: title.isEmpty ? "Imported transcript" : title,
            audioFileURL: audioFileURL
        )
        if createNote {
            SharedConfig.saveNote(OpenwisprNote(
                title: title.isEmpty ? "Imported transcript" : title,
                body: cleaned
            ))
        }
        latestText = cleaned
        return true
    }

    private func importFileKind(for url: URL) -> ImportFileKind {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "m4a", "mp3", "wav", "aac", "webm", "caf", "aif", "aiff":
            return .audio
        case "pdf":
            return .pdf
        case "rtf":
            return .rtf
        case "txt", "md", "markdown", "text":
            return .text
        default:
            if let type = UTType(filenameExtension: ext) {
                if type.conforms(to: .audio) { return .audio }
                if type.conforms(to: .pdf) { return .pdf }
                if type.conforms(to: .rtf) { return .rtf }
                if type.conforms(to: .text) { return .text }
            }
            return .unsupported
        }
    }

    private func readTextFile(_ url: URL) throws -> String {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func readPDF(_ url: URL) throws -> String {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let document = PDFDocument(url: url) else {
            throw NSError(
                domain: "kord.import",
                code: -20,
                userInfo: [NSLocalizedDescriptionKey: "Windtalker could not open that PDF."]
            )
        }

        var pages: [String] = []
        for index in 0..<document.pageCount {
            if let pageText = document.page(at: index)?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
               !pageText.isEmpty {
                pages.append(pageText)
            }
        }
        return pages.joined(separator: "\n\n")
    }

    private func readRichText(_ url: URL) throws -> String {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        let text = try NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
        return text.string
    }

    private func copyToTemporaryFile(_ url: URL) throws -> URL {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let ext = url.pathExtension.isEmpty ? "m4a" : url.pathExtension
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("kord-import-\(UUID().uuidString)")
            .appendingPathExtension(ext)
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }

    private func displayName(for url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Imported transcript" : name
    }

    private func loadPendingImports() {
        pendingImports = SharedConfig.pendingSharedImports
    }

    private func uniqueTypes(_ extensions: [String], fallback: UTType) -> [UTType] {
        var types = [fallback]
        for ext in extensions {
            if let type = UTType(filenameExtension: ext), !types.contains(type) {
                types.append(type)
            }
        }
        return types
    }
}
