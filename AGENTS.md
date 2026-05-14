# openwispr — AGENTS guide

This file is loaded into every Claude session that works under `~/openwispr/`. It exists to give the next agent enough context to make a correct change without re-deriving everything.

## What this repository is

openwispr is a personal voice-to-text tool (a WisprFlow-style hotkey dictation app). `~/openwispr/` is the workspace root. Sub-projects live one level down:

- `~/openwispr/desktop/` — the live Electron app. Production binary at `/Applications/openwispr.app`.
- (future) `~/openwispr/pwa/`, `~/openwispr/shared/`, etc.

Persistent state — config, notes, transcripts — lives at `~/Library/Application Support/openwispr/`. Bundle ID: `dev.smathdaddy.openwispr`.

## Repository conventions

- **No emojis.** Anywhere — code, copy, UI labels, file content, chat responses. Use 1–2 char text alternatives when a design pattern usually expects an emoji (tray title, status dot).
- **Read the file before recommending an edit.** Model IDs, file paths, IPC channel names, and validators change session to session. Don't trust memory; verify.
- **Trim copy.** UI labels stay short. Move detail into a help line *below* the control, not jammed into the label.
- **Don't add dependencies casually.** Every dep gets dragged into the ~200 MB `.app` bundle. Prefer the stdlib / Web Platform when possible.
- **No backwards-compat shims for code that isn't shipped to anyone yet.** Just change the code.

## Step-by-step: scaffold a new sub-project under the workspace

When the user asks for a new piece (PWA, shared library, etc.):

1. `mkdir ~/openwispr/<name>` — kebab-case the directory.
2. Inside it, initialize the appropriate build system (`npm init -y` for Node/web, `cargo init` for Rust, etc.).
3. Add a one-page `README.md` describing what it is and how to run/build.
4. If it shares logic with the desktop app (e.g., the Groq transcription pipeline in `desktop/recorder.js`), extract that logic into `~/openwispr/shared/` first and import from both — don't duplicate.
5. Add a section to this `AGENTS.md` documenting the new sub-project's quirks.
6. Wire any cross-project commands at the workspace root if useful (e.g., a top-level `package.json` with `workspaces` for npm sub-projects).

```
~/openwispr/
├── AGENTS.md            # this file
├── desktop/             # Electron app
│   ├── main.js
│   ├── preload.js
│   ├── renderer.js
│   ├── recorder.js
│   ├── index.html
│   ├── settings.html
│   ├── styles.css
│   ├── build/           # icon source + iconset + icns
│   ├── dist/            # electron-builder output
│   └── package.json
└── <new-name>/
```

## Electron best practices for this project

### Security: context isolation is non-negotiable

Every `BrowserWindow` must specify:
```js
webPreferences: {
  preload: path.join(__dirname, 'preload.js'),
  contextIsolation: true,
  nodeIntegration: false
}
```

- `contextIsolation: true` runs preload scripts in a separate JS world from page scripts. Without it, page scripts can rewrite preload globals.
- `nodeIntegration: false` keeps Node APIs out of the renderer entirely.
- `enableRemoteModule` is deprecated and removed — never add it back.
- If you must load a third-party URL (signup flow, OAuth), open it via `shell.openExternal` or a sandboxed `<webview>`, never a normal `BrowserWindow` with IPC access.

### contextBridge is the only legal renderer-to-main bridge

In `preload.js`:
```js
const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('api', {
  // request/response — caller awaits a result
  getConfig: () => ipcRenderer.invoke('get-config'),
  // fire-and-forget — caller doesn't need a result
  openExternal: (url) => ipcRenderer.send('open-external', url),
  // subscription — main pushes to renderer
  onHotkeyToggle: (cb) => ipcRenderer.on('hotkey-toggle', cb)
});
```

Rules:
- Never expose `ipcRenderer` itself. Only wrap specific channels.
- Never expose `fs`, `child_process`, `path`, or any Node API directly. If the renderer needs filesystem access, define a typed IPC handler in main and call that.
- Sanitize all IPC arguments coming from the renderer. Even though you wrote the renderer, treat its messages as untrusted — a future XSS becomes RCE without this discipline.

### Main vs renderer: division of responsibility

Main process (`main.js`) owns:
- Window lifecycle (`BrowserWindow` creation, focus, destruction).
- Native OS integrations: `clipboard`, `globalShortcut`, `Tray`, `Menu`, `app.dock`.
- Persistent file I/O (`config.json`, `notes.json`, `transcripts.json` under `app.getPath('userData')`).
- External-process invocation (`execFile('osascript', ...)` for Cmd+V paste).

Renderer owns:
- DOM, CSS, in-page state.
- `MediaRecorder`, Web Audio (`AudioContext`, `AnalyserNode`), Canvas drawing.
- `fetch` to APIs (Groq Whisper + chat completions). API keys are user-config; living in the renderer is acceptable.
- User-input event handling.

Rule of thumb: anything that touches the filesystem or OS goes through IPC. Anything that touches the DOM stays in the renderer.

### IPC patterns

| Pattern | Renderer side | Main side | When to use |
|---|---|---|---|
| Request/response | `ipcRenderer.invoke(name, ...args)` returns `Promise` | `ipcMain.handle(name, (e, ...args) => result)` | Caller needs the result |
| Fire-and-forget | `ipcRenderer.send(name, ...args)` | `ipcMain.on(name, (e, ...args) => {})` | Side-effect only |
| Broadcast | `ipcRenderer.on(name, (e, ...args) => {})` | `webContents.send(name, ...args)` | Main → renderer notification |

Naming: `verb-noun` (`get-config`, `save-notes`, `set-widget-position`). Group related channels into a namespace object exposed via contextBridge so the renderer surface stays organized:
```js
notes: {
  list: () => ipcRenderer.invoke('notes-list'),
  create: () => ipcRenderer.invoke('notes-create'),
  update: (id, fields) => ipcRenderer.invoke('notes-update', id, fields),
  delete: (id) => ipcRenderer.invoke('notes-delete', id)
}
```

### Bundling: when (and when not) to add Vite or Webpack

The desktop app uses **no bundler** today. Renderer code is plain JS via `<script>` tags. Intentional reasons:

- Smaller attack surface (no minifier, no module loader to compromise).
- Fast iteration (no rebuild between edit and reload).
- No transpiler/babel version drift.

Add a bundler **only when**:
- TypeScript with build-time type checking becomes worth the cost.
- An npm package you need ships ESM-only or uses Node-style imports.
- File count grows enough that ad-hoc `<script>` ordering becomes painful.
- Tree-shaking would actually shrink the bundle by a meaningful amount (rare at this size).

**If you add a bundler, choose Vite.** Reasons:
- First-class Electron support via `create-electron-vite` and `vite-plugin-electron`.
- ESM-native, fast HMR.
- `vite build` outputs a static `dist/` directory ready for electron-builder to package.
- Webpack still works but is slower and configures worse.

Minimal Vite config for an Electron renderer:
```js
import { defineConfig } from 'vite';
export default defineConfig({
  base: './',  // relative paths so file:// URLs resolve
  build: {
    outDir: 'dist-renderer',
    rollupOptions: {
      input: { index: 'index.html', settings: 'settings.html' }
    }
  }
});
```

The main process (`main.js`, `preload.js`) is plain Node — no bundler required unless you migrate to TypeScript.

### Code signing on macOS

The desktop app uses **ad-hoc signing** today, automatically applied by electron-builder when no signing-identity env vars are present:
- Identifies as the bundle ID with a generated certificate.
- Works for personal use but Gatekeeper blocks the first launch (right-click → Open to bypass).
- **TCC permissions reset on every rebuild** because the binary hash changes. After `npm run dist`, re-grant Microphone (and Accessibility, for paste) under **System Settings → Privacy & Security**.

To upgrade to a real signed build:
1. Obtain an **Apple Developer ID Application** certificate ($99/year) and install it in your login keychain.
2. Set env vars before building:
   ```bash
   export CSC_LINK=/path/to/cert.p12
   export CSC_KEY_PASSWORD=<pkcs12-password>
   ```
3. electron-builder auto-detects and signs with that identity.
4. To **notarize** (so Gatekeeper opens without warning):
   ```bash
   export APPLE_ID=you@example.com
   export APPLE_APP_SPECIFIC_PASSWORD=<one of these from appleid.apple.com>
   export APPLE_TEAM_ID=<10-char team id>
   ```
   Add `"notarize": true` under `build.mac` in `package.json`. Notarization round-trips the build through Apple's notary service (~3–5 min for a small app).

### Automated build pipeline

Current flow is manual. To automate via GitHub Actions, create `.github/workflows/build.yml`:

```yaml
name: Build
on:
  push:
    tags: ['v*']
jobs:
  mac:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 20, cache: 'npm', cache-dependency-path: desktop/package-lock.json }
      - run: cd desktop && npm ci
      - run: cd desktop && npm run dist
        env:
          CSC_LINK: ${{ secrets.MAC_CSC_LINK }}
          CSC_KEY_PASSWORD: ${{ secrets.MAC_CSC_KEY_PASSWORD }}
          APPLE_ID: ${{ secrets.APPLE_ID }}
          APPLE_APP_SPECIFIC_PASSWORD: ${{ secrets.APPLE_APP_SPECIFIC_PASSWORD }}
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
      - uses: softprops/action-gh-release@v2
        with:
          files: desktop/dist/mac-arm64/*.zip
```

For Linux and Windows, add matrix entries (`runs-on: ubuntu-latest`, `runs-on: windows-latest`) with platform-appropriate signing configs.

### Electron-specific gotchas you will hit

- `app.dock.hide()` on macOS strips the Dock entry entirely (menu-bar-only apps). Removing it puts the app in Cmd-Tab and Dock. The `LSUIElement` Info.plist key (set via `extendInfo` in `package.json`'s `build.mac`) controls this; `LSUIElement: false` shows the app in Dock and switcher.
- `focusable: false` on a `BrowserWindow` makes it non-activating on macOS — clicks still fire but the window never takes keyboard focus. **Critical side effect**: CSS `-webkit-app-region: drag` does not work with `focusable: false`. Implement dragging in JS via `setPosition` over IPC. The widget here does this.
- `globalShortcut.register` only accepts modifiers (`Command`, `Control`, `Alt`, `Shift`) plus character/function keys. **Fn is not supported** — to capture Fn or low-level keys you'd need `uiohook-napi` (native module).
- `globalShortcut` callbacks can fire on key-repeat. Debounce in main if accidental re-trigger would be destructive.
- Renderer console messages don't reach stdout by default in a packaged app. Forward them via `webContents.on('console-message', ...)` in main, and launch the packaged app from a terminal to see output: `/Applications/openwispr.app/Contents/MacOS/openwispr 2>&1 | tee /tmp/openwispr.log`.
- `tccutil reset Microphone <bundleId>` is the supported way to force a re-prompt for mic permission during development.

## PWA integration

Two distinct stories — be clear which you're building.

### Story A: a separate PWA that openwispr can launch

The PWA lives at `~/openwispr/pwa/` as its own project, gets deployed to a static host (Cloudflare Pages, Vercel, GitHub Pages), and the desktop app opens it via `shell.openExternal(url)`. This is the **recommended pattern** for new sub-projects.

Concerns stay separated:
- Desktop app owns native integration (global hotkey, system clipboard, paste-at-cursor).
- PWA owns the in-browser story (offline cache, installability, push notifications if you want them).

### Story B: PWA-style behavior inside the Electron renderer

The Electron renderer *is* Chromium and supports the full PWA stack: service workers, Web App Manifest, Cache Storage API, IndexedDB, Background Sync. This is **rarely useful for openwispr** — the app is already installed locally and offline-capable through IPC, so adding a service worker buys you complexity without solving a real problem.

The exception: if you want one codebase that ships as both a web PWA and an Electron app, build it as a PWA and have Electron load the same bundle.

### Service worker registration

In the PWA's HTML entry:
```html
<script>
  if ('serviceWorker' in navigator) {
    window.addEventListener('load', () => {
      navigator.serviceWorker.register('/sw.js', { scope: '/' })
        .then((reg) => console.log('SW registered:', reg.scope))
        .catch((err) => console.error('SW registration failed:', err));
    });
  }
</script>
```

Inside Electron, **service workers only register on secure contexts** — HTTPS or `localhost`, not `file://`. If the PWA is loaded into an Electron window directly from disk, start a local HTTP server in main and load from `http://127.0.0.1:<port>`:

```js
const http = require('http');
const handler = require('serve-handler');  // npm i serve-handler
const server = http.createServer((req, res) =>
  handler(req, res, { public: path.join(__dirname, 'pwa-dist') })
);
server.listen(0, '127.0.0.1', () => {
  const port = server.address().port;
  win.loadURL(`http://127.0.0.1:${port}`);
});
```

Never expose this server beyond `127.0.0.1`.

### Web App Manifest (W3C-compliant)

`manifest.json` at the PWA root:
```json
{
  "name": "openwispr",
  "short_name": "openwispr",
  "id": "/",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#1c1c1f",
  "theme_color": "#1c1c1f",
  "orientation": "any",
  "icons": [
    { "src": "/icons/icon-192.png", "sizes": "192x192", "type": "image/png", "purpose": "any" },
    { "src": "/icons/icon-512.png", "sizes": "512x512", "type": "image/png", "purpose": "any" },
    { "src": "/icons/icon-maskable.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable" }
  ],
  "categories": ["productivity", "utilities"]
}
```

Link from each HTML entry:
```html
<link rel="manifest" href="/manifest.json">
<meta name="theme-color" content="#1c1c1f">
```

Spec-conformance checklist (W3C Web App Manifest):
- `name` and `short_name` both present.
- `start_url` resolves under the manifest's scope.
- At least one icon of `192×192` and one of `512×512` PNG.
- At least one icon with `"purpose": "maskable"` for environments that crop icons into platform shapes.
- `display` is one of `fullscreen`, `standalone`, `minimal-ui`, `browser`.
- `id` set explicitly so the install identity is stable across `start_url` changes.

### Offline caching strategies

Pick the strategy by resource type:

| Resource | Strategy | Why |
|---|---|---|
| App shell (HTML / CSS / JS) | **Cache-first** | Loads instantly offline; cache-bust via versioned filenames or a version constant in the SW |
| Trusted API (Groq, etc.) | **Network-first, fall back to cache** | Fresh when online; degraded but usable offline |
| Images, fonts | **Stale-while-revalidate** | Fast first paint, background refresh on next visit |
| User data (notes, transcripts) | **Don't use SW cache** — use **IndexedDB** | SW caches are not durable; CacheStorage can be evicted under pressure |

Hand-rolled `sw.js`:
```js
const VERSION = 'v1.0.3';
const SHELL = `openwispr-shell-${VERSION}`;
const SHELL_URLS = ['/', '/index.html', '/styles.css', '/app.js', '/manifest.json'];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(SHELL).then((c) => c.addAll(SHELL_URLS)));
  self.skipWaiting();
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== SHELL).map((k) => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', (e) => {
  const url = new URL(e.request.url);

  // network-first for the Groq API
  if (url.hostname === 'api.groq.com') {
    e.respondWith(
      fetch(e.request)
        .then((r) => {
          const clone = r.clone();
          caches.open(SHELL).then((c) => c.put(e.request, clone));
          return r;
        })
        .catch(() => caches.match(e.request))
    );
    return;
  }

  // cache-first for the app shell
  if (SHELL_URLS.includes(url.pathname)) {
    e.respondWith(caches.match(e.request).then((r) => r || fetch(e.request)));
    return;
  }

  // stale-while-revalidate for everything else
  e.respondWith(
    caches.match(e.request).then((cached) => {
      const fetched = fetch(e.request).then((r) => {
        const clone = r.clone();
        caches.open(SHELL).then((c) => c.put(e.request, clone));
        return r;
      });
      return cached || fetched;
    })
  );
});
```

For anything non-trivial in production, **use Workbox** (`workbox-window`, `workbox-precaching`, `workbox-routing`, `workbox-strategies`). Workbox handles version migration, opaque responses, range requests, navigation preload, and edge cases you will absolutely get wrong by hand.

### Versioning and cache busting

Bump the `VERSION` constant in the SW whenever shell URLs change. The `activate` handler deletes old shells; new requests refill from the new cache name. For the app shell files themselves, prefer content-hashed filenames (`app.a8f3.js`) so a stale browser revalidating the SW also picks up the fresh asset.

### Integration: loading the PWA in an Electron window

Two options:

1. **Remote URL** — `win.loadURL('https://app.example.com')`. SW registers and works normally. Pro: one bundle on web and desktop. Con: requires internet on first run; loading remote code into a window with IPC access is a security risk if the remote can be compromised.
2. **Local HTTP server** — see the snippet above. SW registers correctly because the origin is `http://127.0.0.1:<port>`. Pro: works fully offline, no IPC-to-remote risk. Con: slightly more boilerplate.

**Never load the PWA with `file://`** if you want service workers to behave per spec.

## Quick command reference

| Task | Command |
|---|---|
| Dev run desktop app | `cd ~/openwispr/desktop && npm start` |
| Build packaged `.app` | `cd ~/openwispr/desktop && npm run dist` |
| Regenerate icon | `cd ~/openwispr/desktop && npm run icon` |
| Reset mic permission for dev | `tccutil reset Microphone dev.smathdaddy.openwispr` |
| Reset paste-permission for dev | `tccutil reset Accessibility dev.smathdaddy.openwispr` |
| Run packaged app with logs visible | `/Applications/openwispr.app/Contents/MacOS/openwispr 2>&1 \| tee /tmp/openwispr.log` |
| Inspect persistent state | `ls ~/Library/Application\ Support/openwispr/` |
