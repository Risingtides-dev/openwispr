import SwiftUI
import UIKit

struct HistoryView: View {
    @State private var entries: [TranscriptEntry] = []
    @State private var copiedID: String?

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty {
                    ContentUnavailableView("No dictations yet", systemImage: "clock")
                        .foregroundStyle(KordTheme.muted)
                        .listRowBackground(KordTheme.void)
                } else {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(formatDate(entry.createdAt))
                                    .font(KordTheme.label(12, weight: .medium))
                                    .foregroundStyle(KordTheme.muted)
                                Spacer()
                                Button {
                                    UIPasteboard.general.string = entry.text
                                    copiedID = entry.id
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                        if copiedID == entry.id { copiedID = nil }
                                    }
                                } label: {
                                    Label(copiedID == entry.id ? "Copied" : "Copy", systemImage: "doc.on.doc")
                                        .labelStyle(.iconOnly)
                                }
                                .buttonStyle(.borderless)

                                Button(role: .destructive) {
                                    SharedConfig.deleteTranscript(id: entry.id)
                                    load()
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                        .labelStyle(.iconOnly)
                                }
                                .buttonStyle(.borderless)
                            }

                            Text(entry.text)
                                .font(KordTheme.body(16))
                                .foregroundStyle(KordTheme.text)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(KordTheme.raised)
                }
            }
            .scrollContentBackground(.hidden)
            .background(KordTheme.void)
            .tint(KordTheme.ember)
            .navigationTitle("History")
            .toolbarBackground(KordTheme.void, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        SharedConfig.clearTranscriptHistory()
                        load()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .disabled(entries.isEmpty)
                }
            }
            .onAppear { load() }
        }
    }

    private func load() {
        entries = SharedConfig.transcriptHistory
    }

    private func formatDate(_ milliseconds: Double) -> String {
        let date = Date(timeIntervalSince1970: milliseconds / 1000)
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
