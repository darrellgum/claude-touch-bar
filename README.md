# Claude Touch Bar

> It only took 10 years and an AI coding agent to finally justify that strip of OLED.

> Monitor Claude Code's activity from your MacBook Pro Touch Bar — no need to keep the terminal visible.

A lightweight macOS utility that displays [Claude Code](https://docs.anthropic.com/en/docs/claude-code)'s real-time working status (spinner, activity word, and color-coded state) directly in the Touch Bar Control Strip. Works across all apps — keep coding in your editor while Claude thinks in the background.

![macOS](https://img.shields.io/badge/macOS-Touch_Bar-black) ![Swift](https://img.shields.io/badge/Swift-5-orange) ![License](https://img.shields.io/badge/license-MIT-blue)

## Why?

If you use Claude Code (Anthropic's CLI coding agent) on a MacBook Pro with a Touch Bar, you've probably found yourself switching back to Terminal just to check if Claude is still thinking, running a tool, or waiting for input. This solves that — a persistent glanceable status right in your Touch Bar.

## What it shows

When Claude Code is working in Terminal.app, the Touch Bar displays:

- **Animated spinner + status word** (e.g. `✶ Thinking…`, `✻ Reading…`) — matching Claude Code's own spinner characters and words exactly
- **Warm orange** — Claude is actively working (receiving tokens)
- **Shifting to red** — stalled (no new tokens for 3+ seconds), smoothly interpolated
- **Lighter warm** — tool execution (reading files, running commands, etc.)
- **Gray** — idle / ready

Tap the Touch Bar item to instantly bring Terminal.app to the foreground.

## Requirements

- MacBook Pro with Touch Bar (2016–2020 models)
- macOS with Xcode Command Line Tools (`xcode-select --install`)
- Terminal.app running [Claude Code](https://docs.anthropic.com/en/docs/claude-code)

## Quick start

```bash
git clone https://github.com/darrellgum/claude-touch-bar.git
cd claude-touch-bar
bash run.sh
```

That's it. The script builds the app and starts monitoring automatically.

## How it works

Two components work together:

1. **`ClaudeTouchBar.swift`** — A native Swift app that injects a custom item into the Touch Bar Control Strip using Apple's private `DFRFoundation` framework. It renders colored text on a black background and handles spinner animation, stalled detection, and smooth color transitions.

2. **`claude-touchbar-bridge.sh`** — A bash bridge that reads Terminal.app's content via AppleScript, detects Claude Code's spinner state and working mode (thinking, tool-use, or responding), and writes status updates to `/tmp/claude-touchbar-status`.

The bridge polls Terminal every 300ms and classifies Claude's activity. The Swift app polls the status file and animates the Touch Bar with matching colors and spinner characters.

### Color logic

The colors faithfully reproduce Claude Code's own terminal behavior:

| State | Color | RGB |
|-------|-------|-----|
| Active (thinking/responding) | Claude orange | `(215, 119, 87)` |
| Stalled (3s+ no new tokens) | Shifts to red | `(171, 43, 63)` |
| Tool execution | Light shimmer | `(235, 159, 127)` |
| Idle / ready | Gray | `(120, 120, 120)` |

The stalled transition uses smooth easing (`intensity += delta * 0.1` per 50ms tick), ramping from orange to red over 2 seconds after a 3-second inactivity threshold — exactly matching Claude Code's internal rendering logic.

## Demo mode

To preview all states without running Claude Code:

```bash
bash claude-touchbar-bridge.sh demo
```

## Manual build

```bash
bash build.sh
open ClaudeTouchBar.app
```

## Files

| File | Purpose |
|------|---------|
| `ClaudeTouchBar.swift` | Touch Bar app (spinner, colors, stalled detection) |
| `claude-touchbar-bridge.sh` | Terminal scraper (reads Claude Code status via AppleScript) |
| `DFRPrivate.h` | Bridging header for Apple's private Touch Bar APIs |
| `build.sh` | Compiles the Swift app into the `.app` bundle |
| `run.sh` | One-command build + launch |
| `ClaudeTouchBar.app/` | macOS app bundle (required for system tray APIs) |

## Related

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) — Anthropic's agentic coding tool
- [Claude](https://claude.ai) — Anthropic's AI assistant

## License

MIT
