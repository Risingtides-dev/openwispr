import SwiftUI
import AVFAudio
import UIKit

struct ContentView: View {
    @EnvironmentObject var session: FlowSession
    @State private var micGranted = false
    @State private var micAsked = false
    @State private var requesting = false
    @State private var now = Date()

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            Form {
                Section("Flow session") {
                    if session.isActive {
                        HStack {
                            Circle().fill(.red).frame(width: 10, height: 10)
                            Text(session.isRecording ? "Recording utterance…" : "Listening")
                            Spacer()
                            if let expires = session.expiresAt {
                                Text(remaining(until: expires)).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                        Button(role: .destructive) { session.stopSession() } label: {
                            Label("Stop session", systemImage: "stop.circle")
                        }
                    } else {
                        Button {
                            session.startSession()
                        } label: {
                            Label("Start 15-minute Flow session", systemImage: "play.circle.fill")
                        }
                        .disabled(!micGranted)
                        Text(micGranted
                             ? "Once started, swipe back to your text field and tap the openwispr orb to dictate."
                             : "Grant microphone access first.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let err = session.errorMessage {
                        Text(err).font(.footnote).foregroundStyle(.red)
                    }
                }

                if !session.lastTranscript.isEmpty {
                    Section("Last transcript") {
                        Text(session.lastTranscript).font(.callout)
                    }
                }

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
                }

                Section("Setup") {
                    Label("Settings > General > Keyboard > Keyboards > Add New Keyboard > openwispr", systemImage: "1.circle")
                    Label("Tap openwispr in that list and turn on Allow Full Access", systemImage: "2.circle")
                    Label("Tap the openwispr orb once: opens this app, starts a 15-minute session, swipe back", systemImage: "3.circle")
                    Label("Tap the orb to start an utterance; tap again to stop and auto-insert", systemImage: "4.circle")
                }

                Section("Configuration") {
                    Text("API key is hardcoded in OpenwisprIOS/Secrets.swift.")
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
        .onReceive(tick) { now = $0 }
    }

    private var statusLabel: String {
        if !micAsked { return "not asked" }
        return micGranted ? "granted" : "denied"
    }

    private func remaining(until: Date) -> String {
        let secs = max(0, Int(until.timeIntervalSince(now)))
        return String(format: "%d:%02d", secs / 60, secs % 60)
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
