# openwispr iOS

A SwiftUI keyboard extension that records audio, transcribes it with Groq Whisper, and drops the result into the focused text field (and onto the clipboard).

## Layout

- `OpenwisprIOS/` — container app. Stores the Groq API key in a shared App Group so the keyboard can read it.
- `OpenwisprKeyboard/` — the keyboard extension itself. Single mic button, AVAudioRecorder, multipart POST to Groq, `textDocumentProxy.insertText`, `UIPasteboard.general.string`.
- `Shared/` — code compiled into both targets (currently `SharedConfig.swift`).

## Build

There is no checked-in `.xcodeproj`. Generate it with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```
brew install xcodegen
cd ios
xcodegen generate
open openwispr.xcodeproj
```

Then in Xcode:

1. Select both targets and set the **Team** under Signing & Capabilities. The default bundle prefix is `dev.smathdaddy.openwispr.ios`; if that ID is taken on your team, change `bundleIdPrefix` in `project.yml` and re-run `xcodegen generate`.
2. Confirm the **App Group** `group.dev.smathdaddy.openwispr` is enabled on both targets. The entitlements files reference it; Xcode will register it the first time you build with a signed identity.
3. Run on a device (mic and keyboard extensions don't work reliably in the Simulator).

## First-run on the device

1. Open the openwispr app, paste your Groq API key (`gsk_...`), tap Save.
2. **Settings → General → Keyboard → Keyboards → Add New Keyboard** → openwispr.
3. Tap **openwispr** in that list and toggle **Allow Full Access** on. Required for network access (Groq) and recording.
4. In any app, long-press the globe key, pick openwispr, tap the mic. iOS will prompt for microphone permission once.

## Why "Allow Full Access"

iOS keyboards default to a strict sandbox with no network. The keyboard needs `RequestsOpenAccess = YES` and the user-granted Full Access toggle to reach `api.groq.com`. The container app holds the API key; the keyboard reads it through the App Group's `UserDefaults` suite.

## Why insertText *and* clipboard

`textDocumentProxy.insertText(text)` writes directly into the focused field — this is the actual auto-paste. The clipboard write is a redundancy: if the user is in a context where `insertText` is no-op (rare; some secure fields), they can long-press → Paste.

iOS does **not** expose any API for a keyboard extension to fire a paste action itself. There is no equivalent to the desktop app's `osascript Cmd+V`.

## Memory budget

Keyboard extensions are killed by the OS around ~60 MB resident. Recording at 16 kHz mono AAC keeps the buffer small; the transcribed string is tiny. Avoid loading large models or images into the keyboard target.

## Mirroring the desktop pipeline

`OpenwisprKeyboard/GroqClient.swift` is a direct port of `desktop/recorder.js`:

- `transcribe` → `POST /audio/transcriptions` (multipart, `response_format=text`, `temperature=0`).
- `cleanup` → `POST /chat/completions` with the same system prompt as `desktop/main.js` `DEFAULT_CONFIG.cleanupPrompt`, wrapping the transcript in `<transcript>...</transcript>`.

If you tweak prompts or models in the desktop app, mirror the change here. The two clients are intentionally not sharing code yet (AGENTS.md "Step-by-step: scaffold a new sub-project" step 4 recommends extracting to `~/openwispr/shared/` once both apps are live).
