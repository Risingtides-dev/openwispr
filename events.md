# openwispr — events ledger

time:      [05:57] [07-16-26]
agent:     [claude] [fable 5]
worktree:  claude/ios-voice-keyboard-oBcac
type:      [feature-request]
area:      [frontend]

Rebranded the iOS app Kord -> Windtalker (display names, windtalker:// scheme, new waveform-on-gradient icon generated from brand-kit tokens). Full visual redesign: new KordTheme design system with magenta->purple gradient accents on near-black layered surfaces, reworked Home/Record/Activation views and the entire keyboard UI. Performance rework: Darwin-notification IPC replaces the 50-100ms polling loops between keyboard and app, keyboard model now separates cheap engine-state syncs from SQLite content loads and publishes only on change, engine downsamples audio to 16 kHz PCM16 for ~6x smaller Groq uploads, and in-flight dictations abort cleanly on audio interruptions. Verified by simulator install (app arms engine, activation flow works). Device install to John's iPhone 16 Pro pending Developer Mode enable.
_________________________________________________________________________________
