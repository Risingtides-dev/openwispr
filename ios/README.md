# openwispr iOS

Voice-to-text on iOS, mirroring the desktop app's Groq pipeline.

The **app records and transcribes**; the **keyboard only inserts text**. This split
is deliberate: iOS keyboard extensions can't reliably hold a microphone session
(sandbox + ~60 MB budget + audio-session conflicts), so recording lives in the
container app where mic access is fully supported. The keyboard hands off to the
app, the app hands the text back. This is the proven path every shipping voice
keyboard uses.

## Flow

1. In any text field, switch to the openwispr keyboard and tap the **mic**.
2. The keyboard deep-links into the openwispr app (`openwispr://record`), which
   starts recording immediately.
3. You talk, it transcribes (+ cleans up) via Groq, and stages the result in the
   shared App Group.
4. The app suspends, returning you to your text field. The keyboard reappears and
   **auto-inserts** the transcript.
5. The keyboard also shows a row of **recent transcripts** you can tap to re-insert.

## Layout

- `OpenwisprIOS/` — container app: record, notes, history, and settings tabs.
  - `OpenwisprIOS/Core/` — app-only logic: `AudioRecorder` (AVAudioRecorder),
    `GroqClient` (the transcribe/cleanup HTTP calls, ported from `desktop/recorder.js`),
    and `TranscriptionPipeline` (shared app-side transcription flow).
- `OpenwisprKeyboard/` — the keyboard extension: a mic button that opens the app,
  a tap-to-insert recents row, globe + delete keys. No audio code.
- `Shared/` — compiled into both targets: `SharedConfig` (App Group `UserDefaults`:
  API key, models, vocabulary, notes, full transcript history, recent transcripts,
  and the pending-insert handoff flag).

## Build

There is no checked-in `.xcodeproj`. Generate it with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```
brew install xcodegen
cd ios
xcodegen generate
open openwispr.xcodeproj
```

Then in Xcode:

1. Select both targets and set the **Team** under Signing & Capabilities. The default
   bundle prefix is `dev.smathdaddy.openwispr.ios`; if that ID is taken on your team,
   change `bundleIdPrefix` in `project.yml` and re-run `xcodegen generate`.
2. Confirm the **App Group** `group.dev.smathdaddy.openwispr` is enabled on both targets.
3. Run on a real device. The Simulator can't exercise the keyboard handoff or the mic.

## First-run on the device

1. Open the openwispr app, paste your Groq API key (`gsk_...`), tap Save.
2. **Settings → General → Keyboard → Keyboards → Add New Keyboard** → openwispr.
3. Tap **openwispr** in that list and toggle **Allow Full Access** on. Required so the
   keyboard can open the app and read the shared transcript.
4. In any app, long-press the globe key, pick openwispr, tap the mic. The app opens and
   prompts for microphone permission once.

## Why "Allow Full Access"

A keyboard extension defaults to a strict sandbox. Opening the host app via a URL scheme
and reading the App Group both need `RequestsOpenAccess = YES` plus the user-granted Full
Access toggle. The mic permission itself is granted to the **app**, not the keyboard —
another reason recording lives there.

## Mirroring the desktop pipeline

`OpenwisprIOS/Core/GroqClient.swift` is a direct port of `desktop/recorder.js`:

- `transcribe` → `POST /audio/transcriptions` (multipart, `response_format=text`,
  `temperature=0`, default `language=en`).
- `cleanup` → `POST /chat/completions` with the same system prompt as `desktop/main.js`
  `DEFAULT_CONFIG.cleanupPrompt`, wrapping the transcript in `<transcript>...</transcript>`.

If you tweak prompts or models in the desktop app, mirror the change here. The two clients
intentionally don't share code yet (AGENTS.md recommends extracting to `~/openwispr/shared/`
once both apps are live).

## Desktop data import

The iOS app can import desktop data from the App Group container:

- `config.json` — models, cleanup prompt, vocabulary, and API key if the phone does not
  already have one saved.
- `notes.json` — desktop notes.
- `transcripts.json` — desktop dictation history.

Copy those files into `group.dev.smathdaddy.openwispr` with `devicectl`, then launch the
app or tap **Settings > Import copied desktop data**. Imports merge by ID, so repeated
imports do not duplicate existing notes or transcript history.

## Roadmap

- **Background mic (the Wispr Flow feel):** keep a mic session warm in the app so the
  keyboard mic works without a visible app switch. Needs the `audio` background mode
  entitlement (App Store review scrutiny) + session keepalive/reconnect. Deferred until
  the tap-to-open path is proven on-device.
