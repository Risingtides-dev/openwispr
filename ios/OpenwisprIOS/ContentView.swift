import SwiftUI
import AVFAudio
import UIKit

struct ContentView: View {
    @State private var micGranted = false
    @State private var micAsked = false
    @State private var requesting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Microphone") {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(statusLabel).foregroundStyle(.secondary)
                    }
                    if !micAsked {
                        Button(requesting ? "Asking…" : "Grant microphone access") {
                            requestMic()
                        }
                        .disabled(requesting)
                    } else if !micGranted {
                        Button("Open Settings") { openSettings() }
                    }
                    Text("Required so the openwispr keyboard can record audio when Full Access is enabled.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Setup") {
                    Label("Settings > General > Keyboard > Keyboards > Add New Keyboard > openwispr", systemImage: "1.circle")
                    Label("Tap openwispr in that list and turn on Allow Full Access", systemImage: "2.circle")
                    Label("Long-press the globe key in any app to switch to openwispr, then tap the mic", systemImage: "3.circle")
                }

                Section("Configuration") {
                    Text("This dev build hardcodes the Groq API key in OpenwisprKeyboard/Secrets.swift. App Groups aren't available on the free Personal Team, so there's no in-app key entry yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Link("Get a Groq key", destination: URL(string: "https://console.groq.com/keys")!)
                }
            }
            .navigationTitle("openwispr")
        }
        .onAppear {
            refresh()
            if !micAsked { requestMic() }
        }
    }

    private var statusLabel: String {
        if !micAsked { return "not asked" }
        return micGranted ? "granted" : "denied"
    }

    private func refresh() {
        let perm = AVAudioApplication.shared.recordPermission
        micGranted = perm == .granted
        micAsked = perm != .undetermined
    }

    private func requestMic() {
        guard !requesting else { return }
        requesting = true
        AVAudioApplication.requestRecordPermission { _ in
            DispatchQueue.main.async {
                refresh()
                requesting = false
            }
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
