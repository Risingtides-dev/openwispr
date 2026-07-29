# PRD: openwispr → Forge

A rebrand and product expansion turning openwispr from a generic voice-to-text widget into a voice-driven prompt workbench for engineers who drive AI coding agents (Claude Code, Cursor, Codex, Copilot, Devin, Aider, etc.).

> Status: draft for discussion. Author: rebrand exploration. Target build: Electron desktop, macOS first (Windows/Linux Phase 3).

---

## 1. Executive Summary

openwispr today: hotkey, speak, get cleaned text pasted at your cursor. Powered by Groq Whisper (transcribe) + Groq `gpt-oss-20b` (cleanup). About 1,700 lines of plain JS in an Electron shell. No bundler, no framework. Persistent state lives at `~/Library/Application Support/openwispr/`.

The opportunity: agentic engineers spend more time writing *prompts* than writing *code*. They re-type the same scaffolding ("Read these files first, plan before editing, write tests, …") into every new Claude Code or Cursor session. They paraphrase the same architectural context across days of work. The friction is not transcription — it is **going from a half-formed spoken thought to a precise, expert-grade brief that an agent can execute on the first try**.

Forge keeps the openwispr loop (hotkey → speak → paste) and inserts a configurable **enhancement** stage between transcription cleanup and paste. It adds a **prompt vault** so reusable instructions, role briefs, and stack-specific context become one keystroke away. The same widget the user already knows becomes a launchpad for sending high-quality prompts into whichever agent surface is focused.

---

## 2. Vision & Positioning

**One-liner.** Forge: speak the rough idea, paste the expert prompt.

**Why now.** Coding agents are now a real interface; the bottleneck has shifted from typing speed to thinking precision. A tool that meets the engineer at the spoken-thought boundary and refines it on the way to the agent collapses the slowest part of the loop.

**Where Forge sits.** Not an agent. Not an IDE plugin. A foreground voice/prompt tool that lives outside the agent and works with every agent. The user never edits inside Forge; they speak, optionally pick a mode, and the result lands wherever their cursor was.

**Adjacent tools and how Forge differs.**

| Tool | Overlap | Differentiator |
|---|---|---|
| Wispr Flow, MacWhisper | Voice-to-text dictation | Forge adds prompt-engineering layer and a prompt library; agent-focused output |
| PromptLayer, LangSmith | Prompt management | Those target API developers; Forge targets seat-of-pants agent users with voice-in |
| Raycast snippets, TextExpander | Text expansion | Forge composes voice + library + AI enhancement, not just static expansion |
| GitHub Copilot Chat, Cursor chat | Agent UI | Forge is upstream of the agent; output goes *into* those tools |

---

## 3. Target User

**Primary persona: the agentic engineer.**
- Drives at least one coding agent daily (Claude Code, Cursor Composer, Codex, Aider, Devin, Continue, Cline).
- Pastes context into agent chat boxes constantly: file paths, repro steps, constraints, "act like a …".
- Maintains a `prompts/` folder somewhere (Notion, Obsidian, dotfiles) with handwritten scaffolding.
- Cares about prompt quality but does not want to stop typing flow to engineer prompts mid-task.
- Comfortable with hotkeys, terminals, JSON config; intolerant of UI ceremony.

**Secondary persona: prompt-curious power user.**
- Uses ChatGPT/Claude.ai daily but not via SDK.
- Has noticed that better phrasing yields dramatically better results and wants help getting there without learning prompt engineering as a discipline.

**Not the target.** Casual dictation users (Wispr Flow already serves them); team prompt-management for orgs (different product, B2B, comes later if ever).

---

## 4. Naming & Rebrand

Three candidates, in order of recommendation:

1. **Forge** — primary. Verb energy. "Forge a prompt" reads naturally. Connotes craft + heat + refinement (raw thought → finished tool). Domain availability and trademark conflict should be checked; `forge.app`, `useforge.dev`, `forge.so`, etc.
2. **Brief** — secondary. "Brief an agent" is the literal action. Calm, professional, short. Risk: very common English word, hard to SEO.
3. **Conjure** — tertiary. Plays well with "summoning" prompts. Risk: leans cute/mystical, off-tone for engineers.

This PRD uses **Forge** as the working name. All identifiers below assume a rename pass; nothing in the rebrand depends on the final string. Bundle ID candidate: `dev.smathdaddy.forge`. App name: `Forge`. Tray glyph: `fg` (two-char text per repo convention, no emojis anywhere).

Migration concern: openwispr v0.1 users have config at `~/Library/Application Support/openwispr/`. Forge v1.0 either (a) keeps that path under the old name for one release with a soft pointer, or (b) ships a one-time migrator. Recommendation: (b), since the bundle ID change forces a TCC re-prompt anyway and the user already has to re-grant mic + accessibility. The migrator runs once at first launch, copies `config.json` / `notes.json` / `transcripts.json` to `~/Library/Application Support/forge/`, and writes a `migrated-from-openwispr.json` breadcrumb so it never re-runs.

---

## 5. Product Surface

Forge keeps openwispr's three surfaces and adds one. None of them are mandatory; the widget alone is enough for casual use.

### 5.1 The widget (existing, lightly extended)
- 156×64 floating pill, frameless, always-on-top, non-focusable, drag-anywhere.
- States: `idle`, `recording`, `thinking`, `enhancing` (new), `done`, `error`.
- Right-click menu adds: **Library**, **Modes**, in addition to existing Notes/History/Settings.
- A short mode badge appears on the widget when a non-default mode is armed (e.g., `plan`, `debug`, `review`). Two-character text only; no emoji.

### 5.2 The library window (new)
- Replaces or sits alongside today's Notes/History tabs in the existing settings window.
- Three columns: **Prompts** (vault), **Modes** (enhancement system prompts), **Snippets** (verbatim text expanders that get injected by token).
- Quick-find via `Cmd+P` style fuzzy search across all three. Selection inserts into widget output or copies to clipboard, depending on context.

### 5.3 Settings window (existing, extended)
- Adds tabs: **Library**, **Modes**, **Routing**, **Provider**.
- Existing tabs (Notes, History, Settings) retained for continuity in v1; Notes may be deprecated in v1.1 if usage analytics show it is rarely opened (it overlaps with the Prompt vault).

### 5.4 The palette (new, optional)
- Global hotkey opens a small spotlight-style window over the current screen.
- Search the prompt vault, pick one, hit `Enter` → it pastes at the cursor.
- Same hotkey customizable in settings, default `Cmd+Shift+'`.
- Implemented as a second `BrowserWindow` mirroring the widget's security posture (`contextIsolation: true`, `nodeIntegration: false`, no remote module, ever).

---

## 6. Core Features

### F1. Voice capture and transcription
Unchanged from openwispr. `MediaRecorder` → `audio/webm` blob → Groq `whisper-large-v3-turbo`. Vocabulary glossary still works.

### F2. Cleanup (existing, retained as a stage)
The existing strict-cleanup prompt remains the *first* post-transcription stage. It removes filler, fixes spoken punctuation, preserves intent. It does **not** rewrite content. This stage is what makes Forge safe to use for the casual "just transcribe me" cases that still matter.

### F3. Enhancement modes (new — the core rebrand)
After cleanup, the user can route the cleaned text through one of N enhancement modes. Each mode is a named system prompt + a small set of parameters that turn the cleaned transcript into an expert-grade brief in that mode's voice. See §7 for the full design.

Default modes shipped in v1:
- `passthrough` — no enhancement (current behavior).
- `plan` — convert a vague description into a step-by-step plan a coding agent can execute. Output sections: Goal, Constraints, Plan, Acceptance Criteria.
- `debug` — convert a "X is broken, I think Y" into a structured bug brief: Repro, Expected, Observed, Hypotheses, First Diagnostic Step.
- `review` — turn "look at this and tell me what's wrong" into a precise code-review brief with explicit invariants to check.
- `spec` — convert a feature description into a tight technical spec: API surface, data shape, edge cases, out-of-scope.
- `commit` — produce a Conventional-Commits-style message from a description of what changed and why.
- `pr` — produce a PR description (summary, motivation, test plan) from a description of the change.

Users add, edit, reorder, and delete modes freely. Modes are JSON; no code required.

### F4. Prompt vault (new)
A flat, searchable, taggable list of saved prompts. Each entry has:
- Name (short).
- Body (markdown or plain text).
- Tags (e.g., `claude-code`, `nextjs`, `bug-template`).
- Variables (`{{filepath}}`, `{{stack}}`) that are prompted-for on insert.
- Optional default routing target (see F6).

Prompts can be **composed** of snippets via `{{snippet:name}}` syntax, resolved at insert-time. The vault is the answer to "I keep typing the same agent scaffolding."

### F5. Snippets (new, lightweight)
Verbatim text expanders. A snippet `{{snippet:react-conv}}` always expands to the same text. Distinct from prompts (which are full briefs) and from modes (which are AI-driven). Use for: project descriptions, agent house rules, tech-stack one-liners.

### F6. Routing (new)
The output of any Forge action lands at the user's cursor by default (today's behavior). Users may configure named routes:
- **Cursor** — default, paste at cursor.
- **Clipboard only** — no paste.
- **Append to file** — write to a configured path (e.g., `~/forge-outbox.md`); useful for queueing prompts before pasting.
- **Per-app rules** — when the focused app is X, prefer mode Y or routing Z. Implemented via `app.getFocusedWindow()` plus a macOS-level frontmost-app lookup. See §9 for the implementation note (it requires shelling out to `osascript` since Electron has no first-class focused-app API).

### F7. Provider abstraction (new)
Today openwispr is hardcoded to Groq. v1 keeps Groq as the default but introduces a thin provider layer so users can swap in:
- Anthropic (Claude Haiku for cleanup, Claude Sonnet/Opus for enhancement).
- OpenAI (gpt-4o-mini, gpt-4.1).
- Local (Ollama for both cleanup and enhancement; `whisper.cpp` for transcribe).
- Custom OpenAI-compatible base URL.

API keys remain in the renderer-side config (acceptable per AGENTS.md threat model since this is a personal-use, local tool). Per-stage provider/model selection: transcribe / cleanup / enhance can each pick their own provider independently.

### F8. History, versioning, audit (extension)
The existing transcripts store grows from `{raw, text}` to `{raw, cleaned, enhanced, mode, routedTo, latencyMs}`. The history pane gains a diff view: raw vs cleaned vs enhanced, so the user can see what each stage changed. They can re-run any stage on a past transcript with a different mode.

---

## 7. Enhancement Mode System

The heart of the rebrand. Designed to be *user-editable* and *predictable*; the default modes are reference implementations, not magic.

### 7.1 Anatomy of a mode

A mode is a JSON object:

```json
{
  "id": "plan",
  "label": "Plan",
  "description": "Turn a vague description into a step-by-step plan for an agent.",
  "model": "anthropic/claude-sonnet-4-6",
  "temperature": 0.2,
  "maxOutputTokens": 1200,
  "systemPrompt": "You are a senior staff engineer briefing an autonomous coding agent...",
  "userTemplate": "<brief>{{transcript}}</brief>\n\nContext: {{context}}",
  "outputContract": {
    "format": "markdown",
    "mustContain": ["Goal", "Constraints", "Plan", "Acceptance Criteria"]
  },
  "postProcessor": null
}
```

Fields:
- `model`, `temperature`, `maxOutputTokens` — per-mode, can override the global default. A mode for `commit` is faster/cheaper; `plan` may pick a stronger model.
- `systemPrompt` — the expert voice. This is where the "turn basic descriptions into expertise" magic actually lives; see §7.3.
- `userTemplate` — Mustache-style template that wraps the cleaned transcript before sending. Variables: `{{transcript}}`, `{{context}}`, `{{date}}`, `{{stack}}`, and any user-defined `{{snippet:name}}`.
- `outputContract` — optional. If `mustContain` is set, the post-processor verifies the headings are present and silently retries once (same transcript, prepended note) if missing.
- `postProcessor` — optional path to a small built-in transform: `strip-fences`, `extract-first-codeblock`, `to-title-case`, etc. Plain string identifiers, no user code execution (security boundary).

### 7.2 Mode arming UX

Three ways to choose a mode:

1. **Default.** Each user sets a default mode in settings. Most engineers will pin `plan` or `passthrough`.
2. **Prefix.** Speak the mode name as the first word: "debug ..." or "review ...". The cleanup stage detects the prefix, strips it, and arms the mode for this utterance only. The list of recognized prefixes is exactly the user's mode IDs.
3. **Pre-arm.** Right-click the widget → Modes → pick one. The widget shows the mode badge until the user records once or clears it.

### 7.3 The system-prompt library (built-in modes)

The shipped defaults are not throwaways. Each one is engineered against real failure modes of underspecified agent briefs. Sketch of the `plan` mode's system prompt (full versions live in code):

```
You are a senior staff engineer producing a briefing for an autonomous
coding agent. Input arrives as the cleaned transcript of an engineer's
spoken thoughts about a task, wrapped in <brief>...</brief> tags.

Your output must be a Markdown document with exactly these sections,
in this order:

## Goal
One sentence. The smallest accurate statement of what success looks
like for the user, in the user's voice.

## Constraints
A bulleted list. Include only constraints the user stated or that
follow necessarily from them. Mark inferred constraints with "(inferred)".

## Plan
A numbered list of 3-8 steps. Each step is independently verifiable.
First step is always investigation (read code, run a command, search
docs) - never start with editing.

## Acceptance Criteria
A bulleted list. Each item is something the agent can self-check
before declaring done.

ABSOLUTE RULES:
- Never invent file paths, function names, or APIs that were not
  mentioned by the user. If you need one, write {{ASK:filename}} as
  a placeholder; the user will fill it before sending.
- Never apologize, hedge, or explain your reasoning outside the
  sections above.
- Never include code blocks. The agent writes the code; you brief it.
```

Why this design wins over "make it sound smart":
- It is **deterministic in shape**, so the user knows what they will get.
- It **refuses to hallucinate** identifiers — the `{{ASK:...}}` token is a checked-in safety valve.
- It **separates plan from execution** — the same anti-pattern that wastes hours of agent time when a user types a vague "fix the auth bug, I think it's in the JWT thing" and the agent immediately starts editing.

Similar engineered system prompts exist for `debug`, `review`, `spec`, `commit`, `pr`. They are the product — they are what users would otherwise spend a year accumulating in their personal prompt library. Forge ships with them as a starting point and users specialize from there.

### 7.4 The "context" channel

`{{context}}` in the user template is filled by an optional sidecar input the user can supply per-utterance:
- Active clipboard contents (toggleable per mode — useful when the user just copied a code snippet and wants to brief about it).
- Current selection in the focused app (macOS Accessibility API; expensive permission and brittle; ship behind a flag in v1.1).
- A pinned-context drawer in the widget where the user pastes one-off context that persists for the next utterance and then clears.

Out of scope for v1: pulling files from the user's repo. That belongs to the agent, not to Forge.

### 7.5 Cost and latency budget

Each mode declares its expected cost and latency. Library entries show a per-call estimate (e.g., `plan ≈ $0.004, ≈ 1.4s`). This matters because users will run enhancement dozens of times a day. The default mode set is tuned so the median p50 enhancement latency from "end recording" to "pasted" stays under 2.5s on a reasonable network — within the boundary where the engineer hasn't switched contexts away from the focused app.

---

## 8. Data Model

All persisted state lives at `~/Library/Application Support/forge/`. JSON files, atomic writes, no database for v1.

```
config.json         # global settings
modes.json          # array of Mode
prompts.json        # array of Prompt
snippets.json       # array of Snippet
transcripts.json    # capped at 500 most recent
routes.json         # array of Route (focused-app rules)
migrated-from-openwispr.json   # one-time migration breadcrumb
```

Type sketches:

```ts
type Mode = {
  id: string;
  label: string;
  description: string;
  provider: 'groq' | 'anthropic' | 'openai' | 'ollama' | 'custom';
  model: string;
  temperature: number;
  maxOutputTokens: number;
  systemPrompt: string;
  userTemplate: string;
  outputContract: { format: 'markdown' | 'text'; mustContain?: string[] } | null;
  postProcessor: 'strip-fences' | 'extract-first-codeblock' | null;
  builtIn: boolean;
};

type Prompt = {
  id: string;
  name: string;
  body: string;
  tags: string[];
  variables: Array<{ name: string; default?: string }>;
  defaultRouteId?: string;
  createdAt: number;
  updatedAt: number;
};

type Snippet = { id: string; name: string; body: string };

type Transcript = {
  id: string;
  createdAt: number;
  raw: string;
  cleaned: string;
  enhanced: string | null;
  modeId: string | null;
  routedTo: string;
  latencyMs: { transcribe: number; cleanup: number; enhance?: number };
};

type Route = {
  id: string;
  name: string;
  matchFrontmostApp?: string;
  modeId?: string;
  destination: 'paste' | 'clipboard' | 'file';
  filePath?: string;
};
```

Schema versioning: each file gets a top-level `{ "schemaVersion": 1, "items": [...] }` wrapper. Migrations run at app start; never blocking the widget, which falls back to defaults if a migration is in progress.

---

## 9. Architecture (Electron-specific)

### 9.1 Process model

Stays as openwispr today, plus one new window:

- **Main** (`main.js`) — owns window lifecycle, OS integration (clipboard, globalShortcut, Tray, accessibility paste), file I/O for all four JSON stores, network calls for cleanup/enhancement (moved from renderer; see §9.3).
- **Widget renderer** (`index.html` + `renderer.js`) — DOM, MediaRecorder, audio viz, drag.
- **Settings renderer** (`settings.html` + `settings-renderer.js`) — multi-tab UI; library editor; mode editor; history.
- **Palette renderer** (new, `palette.html` + `palette-renderer.js`) — Spotlight-style search-and-insert.

All three renderers run with `contextIsolation: true`, `nodeIntegration: false`, sandboxed, behind `preload.js`. No exception. Per AGENTS.md: the only legal renderer→main bridge is `contextBridge.exposeInMainWorld('api', ...)`.

### 9.2 New IPC surface

Adds to the existing `notes` and `transcripts` namespaces:

```js
contextBridge.exposeInMainWorld('api', {
  // ... existing surface ...

  modes: {
    list: () => ipcRenderer.invoke('modes-list'),
    get:  (id) => ipcRenderer.invoke('modes-get', id),
    upsert: (mode) => ipcRenderer.invoke('modes-upsert', mode),
    delete: (id) => ipcRenderer.invoke('modes-delete', id),
    reorder: (ids) => ipcRenderer.invoke('modes-reorder', ids)
  },
  prompts: {
    list: () => ipcRenderer.invoke('prompts-list'),
    upsert: (p) => ipcRenderer.invoke('prompts-upsert', p),
    delete: (id) => ipcRenderer.invoke('prompts-delete', id),
    render: (id, vars) => ipcRenderer.invoke('prompts-render', id, vars)
  },
  snippets: {
    list: () => ipcRenderer.invoke('snippets-list'),
    upsert: (s) => ipcRenderer.invoke('snippets-upsert', s),
    delete: (id) => ipcRenderer.invoke('snippets-delete', id)
  },
  pipeline: {
    run: (rawTranscript, opts) => ipcRenderer.invoke('pipeline-run', rawTranscript, opts),
    onProgress: (cb) => ipcRenderer.on('pipeline-progress', (_e, p) => cb(p))
  },
  routes: {
    list: () => ipcRenderer.invoke('routes-list'),
    upsert: (r) => ipcRenderer.invoke('routes-upsert', r),
    delete: (id) => ipcRenderer.invoke('routes-delete', id),
    frontmostApp: () => ipcRenderer.invoke('routes-frontmost-app')
  },
  palette: {
    open: () => ipcRenderer.send('palette-open'),
    close: () => ipcRenderer.send('palette-close'),
    insert: (text) => ipcRenderer.invoke('palette-insert', text)
  }
});
```

Channel names follow the existing `verb-noun` and namespaced convention; IPC args are sanitized in main (typed validators on every handler) since AGENTS.md treats renderer messages as untrusted.

### 9.3 Where network calls live

Today, `recorder.js` runs in the renderer and `fetch`es Groq directly. Acceptable for the openwispr scope but increasingly wrong as Forge expands:

- Multiple providers, each with their own auth header shape — keeping that in the renderer leaks complexity into the wrong process.
- Per-mode model/provider routing — main owns config; renderer would have to round-trip config back to itself.
- Cost and latency telemetry per stage — easier to attribute in main.
- Future: provider keys may move into the macOS Keychain (`safeStorage.encryptString`), which is main-only.

Recommendation: **move all model API calls into main**. The renderer captures the audio blob, sends it over IPC as a transferable `Uint8Array`, and receives stage-by-stage progress events. The renderer becomes thinner; the widget stays responsive; provider sprawl stays contained.

Migration step in code:
- New `~/openwispr/desktop/pipeline.js` (main-side) replaces `recorder.js`'s network code.
- `recorder.js` becomes audio-only (capture + viz + chunking).
- The new `pipeline-run` handler is a single IPC handler that orchestrates transcribe → cleanup → enhance → route, emitting `pipeline-progress` events at each stage boundary.

### 9.4 Frontmost-app detection (for per-app routing)

Electron has no cross-platform "frontmost app" API. On macOS:

```js
function frontmostApp() {
  return new Promise((resolve) => {
    execFile('osascript', ['-e',
      'tell application "System Events" to ' +
      'name of first application process whose frontmost is true'
    ], (err, stdout) => {
      resolve(err ? null : stdout.trim());
    });
  });
}
```

Reuses the Accessibility permission already granted for paste. Sampled lazily (only when the pipeline is about to route, not on every keystroke).

### 9.5 Palette window

Reuses widget patterns. `BrowserWindow` with `frame: false`, `transparent: true`, `alwaysOnTop`, `focusable: true` (unlike the widget — the palette *does* take focus, since the user is typing into it). Positioned centered on the currently-focused display via `screen.getDisplayNearestPoint(screen.getCursorScreenPoint())`. Closes on blur. Global hotkey toggles open/close. Implementation is ~150 lines: a list, a search input, an enter-to-insert handler.

### 9.6 Bundler decision: still no

Per AGENTS.md the project ships with no bundler intentionally. Forge does not change that calculus *yet*. Reasons to revisit later:
- A mode editor with syntax-highlighted system-prompt editing wants a code editor component (CodeMirror 6) — those ship ESM-only.
- Variable templating and validation could benefit from a typed shared module between main and renderer.

If/when a bundler is added, choose **Vite** (rationale already in AGENTS.md). The first migration target is the settings renderer only; the widget renderer can remain plain JS indefinitely because its surface area is tiny.

### 9.7 Code signing & notarization

Unchanged from AGENTS.md guidance. Ad-hoc signing for dev. For shipping Forge publicly, the Developer ID + notarize flow described in AGENTS.md §"Code signing on macOS" applies as-is. The bundle ID change (`dev.smathdaddy.openwispr` → `dev.smathdaddy.forge`) does force every existing user to re-grant TCC permissions on first Forge launch — this is acceptable and called out in the in-app migration screen.

### 9.8 Auto-update

openwispr has no auto-update today. For a public Forge release, add `electron-updater` pointed at a GitHub Releases feed. Reasons to defer: it adds ~6 MB and a network check at startup. Ship v1 manual; add auto-update in v1.2 once there are users with installed builds to update.

---

## 10. UX Flows

Three flows cover ~95% of use. All start from a focused agent input box in another app (Cursor chat, Claude Code terminal, browser textarea).

### Flow A: Quick voice → enhanced prompt (default path)

1. User taps hotkey. Widget glows red, viz spins.
2. User speaks: "ok we need to add rate limiting to the public posts endpoint, redis-backed, sliding window, return 429 with a retry-after header, and we need integration tests for the 429 path"
3. User taps hotkey again. Widget shows `thinking`, then `enhancing` (mode `plan` is the user's default).
4. ~2 seconds later: a 6-line plan, with Goal / Constraints / Plan / Acceptance Criteria, is pasted at the cursor in the agent chat. User hits Enter, agent starts work.

Failure modes:
- Mic blocked → widget shows `mic?`, opens settings tab on Permissions.
- Provider down → widget shows `down`, history retains raw + cleaned + a stub `enhanced: null`. User can retry from history.
- Enhancement returned malformed (missing required sections) → one silent retry; if still bad, fall back to the cleaned text and surface a passive notice in the widget label.

### Flow B: Spoken mode prefix

User taps hotkey, says "debug the websocket reconnect is dropping messages on safari but only after the tab has been backgrounded for thirty seconds". The cleanup stage detects the `debug` prefix, strips it, sends the remainder through the `debug` mode, and the user gets a structured bug brief.

### Flow C: Palette → saved prompt

User taps `Cmd+Shift+'`. Palette opens centered, focused. They type `next` and see all prompts tagged `nextjs`. Pick one ("Next.js app router scaffolding rules"). If the prompt has `{{filepath}}` variable, an inline mini-form asks for it. Press Enter. Prompt body, with variables resolved and snippets expanded, pastes at the cursor.

### Cross-cutting: settings has Library / Modes / Routing tabs

- **Library** — table of prompts, edit pane on the right, search + tag filter on top.
- **Modes** — table of modes; click one to edit name/system prompt/model/temperature; "test" button runs the mode against a sample transcript ("Add a feature to the user model that prevents duplicate emails") so users can iterate.
- **Routing** — table of routes; "When frontmost app is Cursor, use mode `spec` and paste."

---

## 11. Phased Roadmap

Calendar-weeks-rough; assumes one developer working part-time.

### Phase 0 — Internal alpha (existing) — 0 weeks
openwispr today. Voice + cleanup + paste. Baseline.

### Phase 1 — Forge v1.0: Modes + Vault — 4 weeks
- Rename: app, bundle ID, README, settings header. Migration on first launch.
- Refactor: move network calls from `recorder.js` (renderer) to `pipeline.js` (main).
- Data: add `modes.json`, `prompts.json`, `snippets.json`. Schema-versioned wrappers.
- IPC: extend preload surface (see §9.2).
- UI: new Modes tab and Library tab in settings; widget gains mode badge.
- Built-in modes: ship `passthrough`, `plan`, `debug`, `review`, `spec`, `commit`, `pr` with engineered system prompts (see §7.3).
- Default-mode setting; spoken-prefix detection in cleanup stage.
- Acceptance: a single user can record, route through a non-default mode, and paste, in under 3 seconds median.

### Phase 2 — Forge v1.1: Palette + Routing + Provider abstraction — 3 weeks
- Spotlight-style palette window with fuzzy search across vault.
- Variable resolution + snippet expansion at insert time.
- Provider layer: Anthropic and OpenAI in addition to Groq; per-stage provider selection.
- Routing: per-app rules using `osascript` frontmost-app lookup.
- History v2: diff view raw/cleaned/enhanced; rerun-with-different-mode.

### Phase 3 — Forge v1.2: Cross-platform + auto-update — 4 weeks
- Windows build (paste-at-cursor via `nut.js` or native `SendInput` since AppleScript is mac-only).
- Linux build (paste-at-cursor via `xdotool` / `ydotool`).
- `electron-updater` against GitHub Releases.
- Code signing for Win (EV cert; nightmare to obtain — budget separately).
- Telemetry opt-in: aggregate per-mode usage, latency, model choice — no transcript content, ever.

### Phase 4 — Forge v1.3+: Optional power features — open-ended
- Selection-based context (Accessibility API): read the focused text field's contents and include as `{{context}}`.
- Project profiles: a "stack snapshot" per directory, auto-loaded based on the frontmost editor's open folder.
- Local-model mode using Ollama + `whisper.cpp` for fully offline operation.
- Team-shared prompt library (sync-able as a git-tracked folder; no service, no cloud).
- Plugin SDK: third-party modes as signed bundles. Treat with extreme suspicion; security review before shipping.

---

## 12. Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Enhancement latency makes the flow worse than typing | Medium | High | Hard budget: p50 < 2.5s end-to-end. Show a clear `enhancing` state. Allow fallback-to-cleaned on timeout. Cache provider connections. |
| Mode system prompts hallucinate filenames/APIs | High | High | Built-in `{{ASK:...}}` token pattern; explicit rules in system prompts; users learn the convention and trust grows. |
| Provider key leakage from renderer | Low | High | Move all API calls to main (§9.3). Eventually back keys with `safeStorage`. |
| Users edit a mode and break it, get bad output, blame Forge | Medium | Medium | Built-in modes are read-only; "duplicate to customize." Test-mode button gives instant feedback before save. |
| Scope creep into agent-orchestrator territory | High | Medium | Hard product rule: Forge does not call code agents, run shells, or write files. It produces text, paste it, done. |
| macOS Accessibility permission re-prompts annoying users | High | Low | Document clearly in onboarding. The bundle-ID change on rename is a one-time tax; subsequent updates with proper signing won't reset. |
| Whisper mistranscribes mode prefix ("debug" → "the bug") and silently arms the wrong mode | Medium | Medium | Match against full mode IDs only; require exact lowercase token; show the armed mode in the widget label before sending. |
| Bundle bloat from new deps (palette code editor, syntax highlighter) | Medium | Medium | AGENTS.md rule: every dep costs 200 MB of `.app`. Pick small ones (CodeMirror 6 is fine; never Monaco). Audit deps quarterly. |
| Trademark conflict on "Forge" | Medium | High | Run trademark + npm + domain check before public launch. Have Brief / Conjure ready as fallbacks. |
| Local-only data means users lose prompts on machine wipe | Medium | Medium | Document the data directory. Ship a one-click "export library to JSON" early. Sync is a Phase 4 problem. |

---

## 13. Success Metrics

Forge is a personal-use tool, so success is measured per-user, not aggregated, in v1. Once telemetry ships (Phase 3, opt-in), the metrics that matter:

**Activation.** % of installs that complete at least one enhanced-prompt round-trip within 24 hours. Target: 70%.

**Mode diversity.** Median number of distinct modes used per user per week. Target: ≥ 3 by week 4 of usage. Below that, users are just using `passthrough` and Forge is a worse Wispr Flow.

**Latency p50/p95.** End-to-end (stop recording → text pasted) median and 95th percentile. Hard targets: p50 < 2.5s, p95 < 6s. Anything above and the flow loses to typing.

**Library use.** Median palette opens per active user per week. Target: ≥ 10. Below that, the vault is dead weight.

**Retention.** D7 / D30 of users who completed the first enhanced round-trip. Targets: D7 60%, D30 40%. (Aggressive; this is a tool-belt product.)

**Cost per active user per day.** Aggregate of model API spend / DAU. This is *their* spend, not ours, but matters because if it crosses ~$0.50/day the user notices and churns.

**Negative metric: cleanup-only sessions.** A session that has zero enhanced-mode uses. If this rises over time, the modes are failing to be useful.

---

## 14. Open Questions

1. **Do we ship the prompt vault as flat or hierarchical?** Flat with tags is simpler and matches how engineers `grep` their notes. Hierarchical (folders) matches what they expect from filesystems. Lean: flat + tags + favorites.
2. **Should snippets live in their own file or inside prompts?** Pulling them out enables sharing across prompts but adds a join at render time. Lean: separate file, accept the join cost.
3. **What is the right default model per mode?** Cheap and fast (Groq, Haiku) for `commit` and `cleanup`; capable (Sonnet 4.6+, gpt-4.1) for `plan` and `spec`. Tune empirically once we have real usage. Worth A/B-ing per user if telemetry exists.
4. **How aggressive should the spoken-prefix detection be?** Strict (exact match, case-insensitive, one token, followed by space). Avoid fuzzy matching — false positives are worse than misses.
5. **Should the widget itself stay non-focusable on Windows/Linux?** macOS's `focusable: false` semantics don't fully port; on Windows it loses click-through. Punt to Phase 3.
6. **Where do users discover modes they don't know about?** A "tour" pane in settings is heavyweight. A small "did you know?" toast on the third use of `passthrough` is lighter and reaches the right user.
7. **Is there a free tier story?** openwispr already requires users to bring their own Groq key. Forge inherits that. No managed service is in scope.
8. **What does telemetry never collect?** Transcripts. Prompts. Snippets. Enhanced output. Names of focused apps. Period. Telemetry is structural only: mode-id, provider-id, latency-ms, ok/err.

---

## Appendix A: File-level change estimate for Phase 1

For the team estimating effort:

| File | Status | Notes |
|---|---|---|
| `desktop/package.json` | Edit | Rename `name`, `productName`, `appId`, dock name. |
| `desktop/main.js` | Heavy edit | Migration runner; new IPC handlers (modes, prompts, snippets, pipeline, routes, palette); palette window factory. ~200 net new lines. |
| `desktop/preload.js` | Edit | Add namespaces per §9.2. ~30 net new lines. |
| `desktop/pipeline.js` | **New** | Orchestrator: transcribe → cleanup → enhance → route. Provider layer. ~250 lines. |
| `desktop/providers/groq.js` | **New** | Existing Groq calls factored out. ~80 lines. |
| `desktop/providers/anthropic.js` | **New** | Phase 1 if Anthropic is a launch provider; else Phase 2. |
| `desktop/recorder.js` | Heavy edit | Drop the network calls; audio capture + chunking only. ~30 lines down to ~20. |
| `desktop/renderer.js` | Edit | Switch from `window.openwispr` direct calls to `window.api.pipeline.run()`. Add mode-badge UI. |
| `desktop/settings.html` | Heavy edit | New Library / Modes / Routing tabs. Mode editor with code-area for system prompts. |
| `desktop/settings.css` (split out) | **New** | Settings styles, separated from `styles.css` for size. |
| `desktop/palette.html` | **New** | Palette markup. ~30 lines. |
| `desktop/palette-renderer.js` | **New** | Palette logic (search, select, insert). ~150 lines. |
| `desktop/modes/built-in.json` | **New** | Shipped mode JSON. ~7 entries, each with a multi-paragraph system prompt. |
| `desktop/build/` | Edit | Replace icon source; rerun `npm run icon`. |
| `AGENTS.md` | Edit | Document the rename, the new sub-files, the pipeline.js move. |
| `desktop/README.md` | Heavy edit | Rewrite for Forge. |

Approximate Phase 1 LOC delta: +900 / -200, on top of today's ~1,700 line desktop app. Manageable in 4 weeks part-time.

## Appendix B: A worked example, end to end

User taps hotkey in a Cursor chat input, says:

> "I want to add a feature where users can star a project and we send them a digest email weekly with what changed in the projects they starred."

Cleanup output (passthrough cleanup):

> I want to add a feature where users can star a project and we send them a digest email weekly with what changed in the projects they starred.

User's default mode is `plan`. Enhancement output:

```markdown
## Goal
Let users opt into a weekly digest email summarizing changes to projects they have starred.

## Constraints
- Email frequency is weekly (stated).
- Users explicitly star projects to subscribe (stated).
- Digest is per-user and project-scoped (inferred).
- "What changed" scope is not specified — needs definition (commits? releases? activity? all of the above?) {{ASK:change-scope}}

## Plan
1. Read the existing project + user models and any current notification or email subsystem to understand how to extend rather than fork.
2. Decide the data model: a `stars` join table on (user_id, project_id, starred_at) is the obvious shape. Confirm no existing equivalent.
3. Define "change" — commit the chosen scope to a doc in the repo before writing code. The agent must not guess.
4. Build the star/unstar endpoints and the corresponding UI affordance. Cover the toggle + idempotency.
5. Build the digest job: scheduled weekly per user; pulls starred projects; computes the change set per the agreed scope; renders an email; sends via the existing mail provider.
6. Tests: unit for digest computation; integration for the full star → digest → email path; ensure idempotent re-runs do not double-send.

## Acceptance Criteria
- A user can star and unstar a project from the project page.
- Starring is idempotent and reflected in the database immediately.
- A weekly job exists, is scheduled, and produces one email per user with at least one starred project.
- The email content matches the agreed change scope and renders correctly in at least one major mail client.
- Tests cover star toggle, digest job, and email content shape.
```

That is the difference Forge makes: from one rambling sentence to a brief a coding agent can act on without first asking five clarifying questions. The `{{ASK:change-scope}}` placeholder makes the missing-context explicit instead of letting the agent invent it.
