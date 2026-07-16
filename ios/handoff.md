# openwispr iOS — resident dictation engine (handoff)

Single source of truth for the current iOS build target. Supersedes the
"tap-to-open, record-in-app, suspend-back" flow, which is glitchy and is NOT the
product we want. We are building the **Wispr Flow resident-engine model**, verified
against Wispr Flow's own on-device UI (screenshots reviewed 2026-06-04).

## What Wispr Flow actually does (confirmed from their UI + iOS docs)

The keyboard never records audio. The **container app** holds a foreground-started
`AVAudioSession` alive in the background; the **keyboard** sends start/stop commands
and renders the listening UI, reading state from the App Group.

Proven by their screenshots:
- Keyboard shows a **"Start"** button (waveform icon), not a live mic.
- First use shows a **"Swipe back to your app"** card with their own copy:
  *"We wish you didn't have to switch apps to use Flow, but Apple now requires it to
  activate the microphone."* — i.e. they accept the one-time app bounce to ARM the
  mic, and made it a polished onboarding step instead of hiding it.
- While dictating **from inside Messages** (app suspended): the **yellow mic dot**
  is lit in the Dynamic Island AND a **yellow mic glyph** shows in the status bar =
  an armed AVAudioSession surviving in the background.
- The keyboard renders "Listening / iPhone Microphone", a level meter, a ✓ confirm
  button, and a tone pill ("Formal"). All of that is the keyboard reading App Group
  state; the audio is captured by the app.

## Non-negotiable iOS rules (design AROUND these — confirmed)

1. A mic `AVAudioSession` CANNOT be started from the background. It must be created
   while the app is foreground, then it survives backgrounding under the `audio`
   UIBackgroundMode. → The first activation MUST be the app-open bounce. Keep it.
2. Keyboard extensions cannot start mic recording and cannot prompt for mic
   permission. Only the container app can. The keyboard only writes commands to the
   App Group and reads results back.
3. Swiping the app away in the app switcher KILLS the engine. Must be detected and
   recovered by re-arming via the app-open bounce.
4. After recording STOPS, iOS may suspend the app. Keep the session ARMED between
   utterances; do NOT fully stop+restart the session from a backgrounded state
   (rule 1 makes the restart fail).
5. The yellow mic indicator stays lit while armed. Expected and unavoidable. Wispr
   shows it; so will we.

## Target architecture

App (container):
- Add `audio` to `UIBackgroundModes`.
- On `openwispr://activate`: foreground, request mic permission if needed, start an
  `AVAudioSession(.record)`, mark `engineAlive` + heartbeat timestamp in the App
  Group, render the "swipe back to your app" affordance, and return the user to the
  prior app WITHOUT tearing down the session.
- The engine observes App Group commands. On `start`: capture the utterance. On
  `stop`: run the existing `GroqClient` transcribe + cleanup, write
  `{requestId, text}` back, refresh heartbeat. Stay armed.
- Handle `AVAudioSession` interruptions (calls/Siri): on `.ended`, re-activate the
  session. Consider a Live Activity / Dynamic Island state to mirror Wispr's
  resilience (their red dot = live activity).

Keyboard (extension):
- Replace the mic-opens-app button with a **Start/Stop** control + a Listening panel
  (level dots, ✓ confirm) — render purely from App Group state.
- BEFORE issuing `start`, check the engine heartbeat. If stale/dead (app killed or
  long-suspended), fall back to the app-open bounce to re-arm, THEN proceed. This
  liveness check is THE fix for the current glitchiness — never assume the engine
  is alive.
- On result available, insert via `textDocumentProxy.insertText`. Keep the
  recents/tap-to-insert row as a secondary surface.
- Keep a tone/mode pill (maps to cleanup on/off or prompt variant) like Wispr's
  "Formal".

Keep the existing tap-to-open `RecordView` path as the cold-start / re-arm fallback.
Do NOT delete it; the resident engine is built ON TOP of it.

## Verify on device (evidence, not assertions)

- After the first bounce + swipe-back, the **yellow mic dot stays lit** while you're
  in another app (= session survived into background).
- 2nd+ uses: Start/Stop from the keyboard while staying in Messages inserts text with
  **no visible app switch**.
- Swipe the app away → keyboard detects dead engine → re-arms via bounce → works again.
- Phone call / Siri mid-session → session recovers on interruption end.

## Honest expectation

Even Wispr has visible seams here (their own help docs describe the keyboard getting
"stuck on the mic button with no waveform" after the bounce). iOS will not allow a
flawless version. The liveness/heartbeat + interruption handling is what moves this
from "glitchy" to "Wispr-level" — not to "perfect."

## Build / install state

- Branch: `claude/ios-voice-keyboard-oBcac`. App + keyboard + share extension build
  clean for both iphonesimulator and generic iOS device destinations.
- Brand is now **Windtalker** (windtalker:// primary scheme; kord:// and
  openwispr:// still registered as legacy).
- IPC: keyboard<->app commands/results/state ride Darwin notifications (KordIPC in
  Shared/) with slow timer fallbacks; do not reintroduce tight polling.
- Audio: engine converts to 16 kHz mono PCM16 before disk/upload (chunkFileSettings
  in BackgroundDictationEngine).
- Target device: John's iPhone 16 Pro "Rising Tides Dev's iPhone"
  (371C40B8-6B1B-5220-87B8-081E9B42CA77), paired over USB. Install requires
  Developer Mode enabled on the phone (Settings > Privacy & Security).
  Install: `xcrun devicectl device install app --device <udid> <path>.app`.
- Team `G4889SDMJ4` (personal) set in `ios/project.yml`. `.xcodeproj` is generated by
  XcodeGen and gitignored — edit `project.yml` then `xcodegen generate`, never the
  pbxproj.
