# openwispr iOS

A SwiftUI voice keyboard built around a long-running container "Flow Session" that does the actual audio capture and Groq transcription, while the keyboard extension just signals start/stop and inserts the resulting text.

## Why this architecture

iOS deliberately blocks keyboard extensions from holding the audio input — the system logs `CMSUtility_IsAllowedToStartRecording ... was NOT allowed ... because it is an extension`. AVAudioRecorder, AVAudioEngine, AudioQueue all fail with OSStatus `'!rec'` (561145187) inside a keyboard. No entitlement flips that off.

The workable path, used by WisprFlow and similar dictation keyboards, is:

1. Keyboard → opens the container app once per "session" via a URL scheme.
2. Container starts an audio session with the **audio** background mode, keeps an AVAudioEngine running for ~15 minutes.
3. Keyboard signals utterance start/stop via **Darwin notifications** (cross-process kernel signals; carry no payload).
4. Container writes recorded utterances to a WAV file, sends to Groq, drops the transcript into the **App Group** UserDefaults along with a counter.
5. Keyboard observes a `transcriptReady` Darwin notification, reads the App Group, calls `textDocumentProxy.insertText` so the result appears in the focused field.

End user experience: tap the orb the first time → opens openwispr app to start a session → swipe back → from then on, tap orb to dictate, text inserts automatically.

## Requirements

- Paid Apple Developer account (App Groups + Audio background mode are paid-account capabilities).
- iOS 17+ on the target device.
- A Groq API key — paste it into `Shared/Secrets.swift` (gitignored).

## Layout

- `OpenwisprIOS/` — container app. Owns `FlowSession`, handles the `openwispr://` URL scheme, shows the session/permission UI.
- `OpenwisprKeyboard/` — keyboard extension. Renders the mic orb, posts Darwin notifications, inserts text on transcript ready.
- `Shared/` — files compiled into both targets:
  - `FlowSessionState.swift` — App Group state schema + Darwin notification names + helpers.
  - `GroqClient.swift` — Whisper + chat completions API calls (container uses this).
  - `SharedConfig.swift` — model IDs + cleanup prompt.
  - `Secrets.swift` — Groq API key (gitignored, copy from `.example`).

## Build

```
brew install xcodegen
cd ios
cp Shared/Secrets.swift.example Shared/Secrets.swift
# edit Shared/Secrets.swift, paste your gsk_... key
xcodegen generate
open openwispr.xcodeproj
```

In Xcode, on each of the two targets (Signing & Capabilities tab):

1. Tick **Automatically manage signing**, pick your Team.
2. Capabilities → confirm both **App Groups** has `group.dev.smathdaddy.openwispr` ticked. The entitlements files reference it; Xcode registers it with your team automatically.
3. Container only — Capabilities → **Background Modes** → tick **Audio, AirPlay, and Picture in Picture**. Already wired in `OpenwisprIOS/Info.plist`.

If the default bundle ID prefix `dev.smathdaddy.openwispr.ios` is taken on your team, change `bundleIdPrefix` in `project.yml` and re-run `xcodegen generate`.

## First-run on the device

1. Build & run the container app on your iPhone (paid signing). Grant microphone permission when prompted.
2. **Settings → General → Keyboard → Keyboards → Add New Keyboard → openwispr.**
3. Tap **openwispr** in that list, toggle **Allow Full Access** on.
4. Switch back to your text field of choice. Long-press the globe key → openwispr.

### Using the keyboard

- Tap the orb. If no session is active, openwispr opens, starts a 15-minute session, returns to you (swipe right on the home indicator).
- Once the session is live, the orb glows blue. Tap to start an utterance; the orb turns red and grows ripples. Tap again to stop. The orb shows a spinner while Groq transcribes (1-2 seconds), then the text inserts into the focused field automatically.
- Session ends after 15 minutes (or sooner if you stop it manually from the openwispr app).

## Memory + battery

- Container keeps AVAudioEngine running for the session duration, but only writes audio between utterance start/stop, so memory stays small.
- iOS shows the red recording indicator (top of status bar) while a session is active. Expected; this is the privacy contract.
- 15 minutes is a soft default in `FlowSession.sessionDuration` — adjust if you want longer sessions.

## Mirroring the desktop pipeline

`Shared/GroqClient.swift` matches `desktop/recorder.js`:

- `transcribe` → `POST /audio/transcriptions` (multipart, WAV body, `response_format=text`, `temperature=0`).
- `cleanup` → `POST /chat/completions` using `SharedConfig.cleanupPrompt`, the same prompt as `desktop/main.js`'s `DEFAULT_CONFIG.cleanupPrompt`.
