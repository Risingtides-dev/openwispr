import SwiftUI

struct NotesView: View {
    @State private var notes: [OpenwisprNote] = []
    @State private var editingNote: OpenwisprNote?

    var body: some View {
        NavigationStack {
            List {
                if notes.isEmpty {
                    ContentUnavailableView("No notes yet", systemImage: "note.text")
                        .foregroundStyle(KordTheme.muted)
                        .listRowBackground(KordTheme.void)
                } else {
                    ForEach(notes) { note in
                        Button {
                            editingNote = note
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(noteTitle(note))
                                    .font(KordTheme.label(17))
                                    .foregroundStyle(KordTheme.text)
                                    .lineLimit(1)
                                if !note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text(note.body)
                                        .font(KordTheme.body(15))
                                        .foregroundStyle(KordTheme.muted)
                                        .lineLimit(2)
                                }
                                Text(formatDate(note.updatedAt))
                                    .font(KordTheme.label(12, weight: .medium))
                                    .foregroundStyle(KordTheme.muted.opacity(0.7))
                            }
                        }
                    }
                    .onDelete(perform: delete)
                    .listRowBackground(KordTheme.raised)
                }
            }
            .scrollContentBackground(.hidden)
            .background(KordTheme.void)
            .tint(KordTheme.ember)
            .navigationTitle("Notes")
            .toolbarBackground(KordTheme.void, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: createNote) {
                        Label("New Note", systemImage: "square.and.pencil")
                    }
                }
            }
            .onAppear { load() }
            .task { await syncCloudNotes() }
            .sheet(item: $editingNote, onDismiss: {
                load()
                Task { await syncCloudNotes() }
            }) { note in
                NoteEditorView(note: note, onChange: load)
            }
        }
    }

    private func load() {
        notes = SharedConfig.notes
    }

    private func createNote() {
        let note = OpenwisprNote()
        SharedConfig.saveNote(note)
        load()
        editingNote = note
        Task { await syncCloudNotes() }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            SharedConfig.deleteNote(id: notes[index].id)
        }
        load()
        Task { await syncCloudNotes() }
    }

    private func syncCloudNotes() async {
        do {
            _ = try KordCloudNotesSync.syncFromStore()
            await MainActor.run { load() }
        } catch {
            // Sync is opportunistic: notes remain local if iCloud is unavailable.
        }
    }

    private func noteTitle(_ note: OpenwisprNote) -> String {
        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        let body = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = body.split(separator: "\n").first, !first.isEmpty {
            return String(first.prefix(60))
        }
        return "Untitled"
    }

    private func formatDate(_ milliseconds: Double) -> String {
        let date = Date(timeIntervalSince1970: milliseconds / 1000)
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct NoteEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = AudioRecorder()
    @State private var note: OpenwisprNote
    @State private var phase: Phase = .idle
    @State private var message: String?

    let onChange: () -> Void

    enum Phase {
        case idle
        case recording
        case transcribing
    }

    init(note: OpenwisprNote, onChange: @escaping () -> Void) {
        _note = State(initialValue: note)
        self.onChange = onChange
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                recordControl
                    .padding(.top, 12)

                if let message {
                    Text(message)
                        .font(KordTheme.body(16))
                        .foregroundStyle(KordTheme.ember)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                TextField("Title", text: $note.title)
                    .font(KordTheme.title(22))
                    .foregroundStyle(KordTheme.text)
                    .padding(12)
                    .kordPanel()
                    .padding(.horizontal)

                TextEditor(text: $note.body)
                    .font(KordTheme.body(17))
                    .foregroundStyle(KordTheme.text)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .kordPanel()
                    .padding(.horizontal)
            }
            .background(KordTheme.void)
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(KordTheme.void, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .tint(KordTheme.ember)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        save()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        SharedConfig.deleteNote(id: note.id)
                        onChange()
                        dismiss()
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
            .onChange(of: note.title) { _, _ in save() }
            .onChange(of: note.body) { _, _ in save() }
            .onDisappear { save() }
        }
    }

    @ViewBuilder private var recordControl: some View {
        Button(action: recordTapped) {
            HStack(spacing: 8) {
                switch phase {
                case .idle:
                    Image(systemName: "mic.fill")
                case .recording:
                    Image(systemName: "stop.fill")
                case .transcribing:
                    ProgressView()
                }
                Text(recordLabel)
                    .font(KordTheme.label(16))
            }
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(KordTheme.text)
        .padding(.vertical, 12)
        .background(phase == .recording ? KordTheme.ember : KordTheme.raised)
        .clipShape(RoundedRectangle(cornerRadius: KordTheme.radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: KordTheme.radius, style: .continuous)
                .stroke(KordTheme.rail, lineWidth: 1)
        }
        .buttonStyle(.plain)
        .disabled(phase == .transcribing)
        .padding(.horizontal)
    }

    private var recordLabel: String {
        switch phase {
        case .idle: return "Record into note"
        case .recording: return "Stop"
        case .transcribing: return "Transcribing..."
        }
    }

    private func recordTapped() {
        message = nil
        switch phase {
        case .idle:
            guard let apiKey = SharedConfig.groqApiKey, !apiKey.isEmpty else {
                message = "Add a Groq API key in Settings."
                return
            }
            do {
                try recorder.start()
                phase = .recording
            } catch {
                message = "Mic error: \(error.localizedDescription)"
            }
        case .recording:
            let url: URL
            do {
                url = try recorder.stop()
            } catch {
                message = "Stop error: \(error.localizedDescription)"
                phase = .idle
                return
            }
            phase = .transcribing
            Task { await transcribeIntoNote(fileURL: url) }
        case .transcribing:
            break
        }
    }

    @MainActor
    private func transcribeIntoNote(fileURL: URL) async {
        defer { try? FileManager.default.removeItem(at: fileURL) }

        do {
            let result = try await TranscriptionPipeline.transcribe(fileURL: fileURL)
            append(result.text)
            SharedConfig.addTranscript(
                result.text,
                raw: result.raw,
                source: "Note",
                title: note.title.isEmpty ? "Note recording" : note.title,
                audioFileURL: fileURL
            )
            phase = .idle
        } catch {
            message = error.localizedDescription
            phase = .idle
        }
    }

    private func append(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let separator: String
        if note.body.isEmpty || note.body.hasSuffix("\n") || note.body.hasSuffix(" ") {
            separator = ""
        } else {
            separator = " "
        }
        note.body += separator + trimmed
        save()
    }

    private func save() {
        SharedConfig.saveNote(note)
        onChange()
    }
}
