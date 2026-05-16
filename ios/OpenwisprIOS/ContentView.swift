import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            Form {
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
    }
}
