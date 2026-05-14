# openwispr

A tiny WisprFlow-style floating widget for macOS. Hotkey → speak → paste at cursor.

## Setup

```bash
cd ~/openwispr
npm install
npm start
```

On first run macOS will ask for:

1. **Microphone** access — allow it.
2. **Accessibility** access (for auto-paste) — open System Settings → Privacy & Security → Accessibility, and toggle on "Electron" (or the app's name). Without this, text still lands on your clipboard but won't auto-paste.

## Usage

1. A small pill-shaped widget appears in the bottom-right corner. Drag it anywhere.
2. Double-click the widget (or click the menu bar icon) to open Settings.
3. Paste your Groq API key from https://console.groq.com/keys (free tier is generous).
4. Click the field you want to dictate into, then start recording one of two ways:
   - **Double-click** the widget (single-click stops). Double-click prevents accidental activation.
   - Or **tap the hotkey** (default `Cmd+Shift+;`). Tap again to stop.
5. Speak. The cleaned-up text auto-pastes at your cursor.

Right-click the widget to open Settings. Drag the dotted grip on the left edge to reposition.

## How it works

- **Recording**: Web Audio API MediaRecorder → webm/opus blob.
- **Transcription**: Groq's `whisper-large-v3-turbo` (216× realtime, 12% WER, $0.04/audio-hour).
- **Cleanup**: Groq's `openai/gpt-oss-20b` (~1000 tok/sec, fastest model on Groq) polishes filler words, grammar, punctuation. Toggleable.
- **Paste**: writes to clipboard, simulates Cmd+V via AppleScript.

## Config

Stored at `~/Library/Application Support/openwispr/config.json`.

## Tweaks

- **Hotkey**: any Electron accelerator (e.g. `Alt+Space`, `F19`).
- **Hold-to-talk**: not in v1 — globalShortcut only fires on press. Add `uiohook-napi` later for that.
- **Local Whisper** (no API): swap `transcribe()` in `renderer.js` to call `whisper.cpp` via a local HTTP server.
