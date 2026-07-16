import SwiftUI
import os

private let appLog = Logger(subsystem: "dev.smathdaddy.openwispr", category: "App")

@main
struct OpenwisprIOSApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var engine = BackgroundDictationEngine.shared
    @State private var activationRequested = false
    @State private var selectedTab: AppTab = .record
    @State private var showImport = false

    var body: some Scene {
        WindowGroup {
            RootView(
                activationRequested: $activationRequested,
                selectedTab: $selectedTab,
                showImport: $showImport
            )
                .environmentObject(engine)
                .task {
                    await syncCloudNotes()
                }
                .onOpenURL { url in
                    // windtalker://activate — keyboard asked us to arm the mic engine.
                    appLog.info("onOpenURL scheme=\(url.scheme ?? "", privacy: .public) host=\(url.host ?? "", privacy: .public)")
                    if url.isFileURL {
                        queueOpenedDocument(url)
                    } else if url.host == "activate" || url.host == "record" {
                        activationRequested = true
                    } else if url.host == "settings" {
                        activationRequested = false
                        selectedTab = .settings
                    } else if url.host == "notes" {
                        activationRequested = false
                        selectedTab = .notes
                    } else if url.host == "history" {
                        activationRequested = false
                        selectedTab = .history
                    } else if url.host == "import" {
                        activationRequested = false
                        showImport = true
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await syncCloudNotes() }
                    }
                }
        }
    }

    private func syncCloudNotes() async {
        do {
            _ = try KordCloudNotesSync.syncFromStore()
            appLog.info("cloud notes sync complete")
        } catch {
            appLog.notice("cloud notes sync skipped: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func queueOpenedDocument(_ url: URL) {
        activationRequested = false

        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            _ = try SharedConfig.enqueueSharedFileImport(
                fileURL: url,
                suggestedName: url.lastPathComponent,
                source: "Open in Windtalker"
            )
            appLog.info("opened document queued name=\(url.lastPathComponent, privacy: .public)")
        } catch {
            appLog.error("opened document import failed: \(error.localizedDescription, privacy: .public)")
        }
        showImport = true
    }
}

struct RootView: View {
    @Binding var activationRequested: Bool
    @Binding var selectedTab: AppTab
    @Binding var showImport: Bool

    var body: some View {
        if activationRequested {
            ActivationView {
                activationRequested = false
            }
        } else {
            ContentView(selectedTab: $selectedTab, showImport: $showImport)
        }
    }
}
