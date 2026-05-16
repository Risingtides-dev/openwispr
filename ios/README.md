# openwispr iOS

A SwiftUI keyboard extension that records audio, transcribes it with Groq Whisper, and drops the result into the focused text field (and onto the clipboard).

## Layout

- `OpenwisprIOS/` — container app. Onboarding instructions only in this dev build.
- `OpenwisprKeyboard/` — keyboard extension. Single mic button, `AVAudioRecorder`, multipart POST to Groq, `textDocumentProxy.insertText`, `UIPasteboard.general.string`.
- `Shared/` — code compiled into both targets. Just `SharedConfig.swift` (model names, cleanup prompt) for now.

## Dev flow: free Personal Team

This setup deliberately avoids App Groups so it works with a **free Apple ID / Personal Team** — no paid Apple Developer Program enrollment needed.

Trade-offs of the free path:
- App Groups capability is paid-account only, so the container app and keyboard extension can't share storage. The Groq API key is hardcoded in the keyboard target at `OpenwisprKeyboard/Secrets.swift` (gitignored) instead of being entered into the container UI.
- Builds installed via Xcode are valid for **7 days** — you re-run from Xcode every week to refresh the provisioning profile.
- Limit of 3 App IDs total on a free Personal Team. The container + keyboard use 2 of those slots.

When you upgrade to the paid program, swap back to App-Groups-based storage and the container's API key form.

## Build

There is no checked-in `.xcodeproj`. Generate it with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```
brew install xcodegen
cd ios
cp OpenwisprKeyboard/Secrets.swift.example OpenwisprKeyboard/Secrets.swift
# edit Secrets.swift, paste your gsk_... key
xcodegen generate
open openwispr.xcodeproj
```

In Xcode:

1. Select both targets and pick your **Team** under Signing & Capabilities (your Apple ID becomes "Your Name (Personal Team)").
2. If the default bundle ID `dev.smathdaddy.openwispr.ios` is taken on your team, change `bundleIdPrefix` in `project.yml` and re-run `xcodegen generate`.

### Run on the iOS Simulator (no device needed)

Pick an iOS 17+ simulator in the run-target dropdown and hit ⌘R. The keyboard works in the simulator: add it via the simulated Settings app, switch to it in any text field, tap the mic — the simulator captures audio from the host Mac's microphone.

### Run on your iPhone

Plug the phone in, select it in the run-target dropdown, hit ⌘R. The build is valid for 7 days; after that, re-run from Xcode.

## First-run on the device

1. Open the openwispr app on the phone (just to register the keyboard with iOS).
2. **Settings → General → Keyboard → Keyboards → Add New Keyboard** → openwispr.
3. Tap **openwispr** in that list and toggle **Allow Full Access** on. Required for network access (Groq) and recording.
4. In any app, long-press the globe key, pick openwispr, tap the mic. iOS will prompt for microphone permission once.

## Why "Allow Full Access"

iOS keyboards default to a strict sandbox with no network. The keyboard needs `RequestsOpenAccess = YES` (set in `OpenwisprKeyboard/Info.plist`) and the user-granted Full Access toggle to reach `api.groq.com`.

## Why `insertText` *and* clipboard

`textDocumentProxy.insertText(text)` writes directly into the focused field — this is the actual auto-paste. The clipboard write is a redundancy: if the user is in a context where `insertText` is no-op (rare; some secure fields), they can long-press → Paste.

iOS does **not** expose any API for a keyboard extension to fire a paste action itself. There is no equivalent to the desktop app's `osascript Cmd+V`.

## Memory budget

Keyboard extensions are killed by the OS around ~60 MB resident. Recording at 16 kHz mono AAC keeps the buffer small; the transcribed string is tiny. Avoid loading large models or images into the keyboard target.

## Mirroring the desktop pipeline

`OpenwisprKeyboard/GroqClient.swift` is a direct port of `desktop/recorder.js`:

- `transcribe` → `POST /audio/transcriptions` (multipart, `response_format=text`, `temperature=0`).
- `cleanup` → `POST /chat/completions` with the same system prompt as `desktop/main.js` `DEFAULT_CONFIG.cleanupPrompt`, wrapping the transcript in `<transcript>...</transcript>`.
