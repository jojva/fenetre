# fenêtre

A minimal macOS window switcher — a personal replacement for [AltTab.app](https://alt-tab-macos.netlify.app/).

## Why

The built-in ⌘-Tab only switches between *apps*. `fenêtre` switches between
individual *windows* across all apps, which is the whole point.

## Stack

- **Swift + AppKit** (Xcode project).

The entire app is macOS-framework glue — Accessibility API, an AppKit overlay,
and (later) ScreenCaptureKit — so Swift is the path of least resistance and has
first-class access to every API involved. Rust was considered and dropped: it
would be pure FFI tax with no portability payoff, since every line is
macOS-specific anyway. AltTab itself is Swift and serves as a reference.

## v1 scope — the usable core

- **Window-level switching** across all apps (Accessibility API: `NSWorkspace`
  for the app list → `AXUIElement` per app → window list + titles).
- **Overlay**: a borderless, always-on-top, *non-activating* `NSPanel` showing a
  horizontal row of app-icon + window-title cells, current selection
  highlighted. Non-activating is the key detail — showing the overlay must not
  steal focus, or the target window can't be raised correctly.
- **Commit** = activate the app + `kAXRaiseAction` on the chosen window.
- **MRU ordering** (most-recently-used first) — what makes alt-tab feel right.
- **Hotkey**: ⌥-Tab via `RegisterEventHotKey` (hold ⌥, Tab to cycle, release to
  commit).
- Requires only the **Accessibility** permission.

## Deferred (v2+)

- Live thumbnails (ScreenCaptureKit + Screen Recording permission).
- Overriding the *real* ⌘-Tab (`CGEventTap` to swallow the system shortcut).
- Preferences UI, multi-monitor polish, minimized/hidden filtering, type-to-filter.

## Notes

- Runs as an agent app (`LSUIElement` — no Dock icon).
- Prompts for Accessibility permission on first run (`AXIsProcessTrustedWithOptions`).
- No paid Apple Developer account needed for personal use (ad-hoc signing).
