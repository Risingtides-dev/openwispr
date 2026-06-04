import SwiftUI

@main
struct OpenwisprIOSApp: App {
    @State private var recordRequested = false

    var body: some Scene {
        WindowGroup {
            RootView(recordRequested: $recordRequested)
                .onOpenURL { url in
                    // openwispr://record — keyboard asked us to dictate.
                    if url.host == "record" { recordRequested = true }
                }
        }
    }
}

struct RootView: View {
    @Binding var recordRequested: Bool

    var body: some View {
        if recordRequested {
            NavigationStack {
                RecordView(
                    cameFromKeyboard: true,
                    onFinishedForKeyboard: {
                        // Text is staged in the App Group; send the user back to
                        // the app they were typing in. Suspending returns focus
                        // to the previous foreground app, where the keyboard
                        // auto-inserts the pending transcript.
                        recordRequested = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            UIApplication.shared.perform(NSSelectorFromString("suspend"))
                        }
                    }
                )
                .navigationTitle("openwispr")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { recordRequested = false }
                    }
                }
            }
        } else {
            ContentView()
        }
    }
}
