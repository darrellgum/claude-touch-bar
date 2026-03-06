# Claude Touch Bar

A macOS Touch Bar utility that displays Claude Code's real-time working status in the Control Strip, visible even when you're in another app.

![macOS](https://img.shields.io/badge/macOS-Touch_Bar-black) ![Swift](https://img.shields.io/badge/Swift-5-orange) ![License](https://img.shields.io/badge/license-MIT-blue)

## What it does

When Claude Code is working in Terminal.app, the Touch Bar shows:

- **Spinner + status word** (e.g. `✶ Thinking…`) — matching Claude Code's own spinner characters and words
- **Warm orange** — Claude is actively working (receiving tokens)
- **Shifting to red** — stalled (no new tokens for 3+ seconds), smoothly interpolated
- **Lighter warm** — tool execution (reading files, running commands, etc.)
- **Gray** — idle / ready

Tap the Touch Bar item to bring Terminal.app to the foreground.

## Requirements

- MacBook Pro with Touch Bar (2016–2020 models)
- macOS with Xcode Command Line Tools (`xcode-select --install`)
- Terminal.app running Claude Code

## Quick start

```bash
git clone https://github.com/darrellgum/claude-touch-bar.git
cd claude-touch-bar
bash run.sh
```

That's it. The script builds the app and starts monitoring automatically.

## How it works

Two components work together:

1. **`ClaudeTouchBar.swift`** — A Swift app that injects a custom item into the Touch Bar Control Strip using Apple's private `DFRFoundation` framework. It renders colored text on a black background and handles spinner animation, stalled detection, and color transitions.

2. **`claude-touchbar-bridge.sh`** — A bash script that reads Terminal.app's content via AppleScript, detects Claude Code's spinner state and working mode, and writes status updates to `/tmp/claude-touchbar-status`.

The bridge polls Terminal every 300ms, detects the spinner pattern, and classifies the mode (thinking, tool-use, or responding). The Swift app polls the status file and animates the Touch Bar accordingly.

### Color logic

The colors faithfully reproduce Claude Code's terminal behavior:

| State | Color | RGB |
|-------|-------|-----|
| Active (thinking/responding) | Claude orange | `(215, 119, 87)` |
| Stalled (3s+ no tokens) | Shifts to red | `(171, 43, 63)` |
| Tool execution | Light shimmer | `(235, 159, 127)` |
| Idle | Gray | `(120, 120, 120)` |

The stalled transition uses smooth easing (intensity += delta * 0.1 per 50ms tick), ramping from 0 to full over 2 seconds after the 3-second threshold.

## Demo mode

To see all states without running Claude Code:

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
| `claude-touchbar-bridge.sh` | Terminal scraper (reads Claude Code status) |
| `DFRPrivate.h` | Bridging header for private Touch Bar APIs |
| `build.sh` | Compiles the Swift app into the `.app` bundle |
| `run.sh` | Builds and launches everything |
| `ClaudeTouchBar.app/` | macOS app bundle (required for system tray APIs) |

## License

MIT
