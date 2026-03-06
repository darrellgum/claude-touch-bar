#!/bin/bash
# Launch both the Touch Bar app and the bridge monitor
set -e

cd "$(dirname "$0")"

# Build if needed
BINARY="ClaudeTouchBar.app/Contents/MacOS/ClaudeTouchBar"
if [[ ! -f "$BINARY" ]] || [[ ClaudeTouchBar.swift -nt "$BINARY" ]]; then
    echo "Building..."
    bash build.sh
fi

cleanup() {
    echo ""
    echo "Shutting down Claude Touch Bar..."
    kill $BRIDGE_PID 2>/dev/null
    kill $APP_PID 2>/dev/null
    echo "idle" > /tmp/claude-touchbar-status
    exit 0
}
trap cleanup SIGINT SIGTERM

# Start the bridge monitor in background
bash claude-touchbar-bridge.sh &
BRIDGE_PID=$!

# Start the Touch Bar app
open ClaudeTouchBar.app &
APP_PID=$!

echo ""
echo "==================================="
echo " Claude Touch Bar is running!"
echo "==================================="
echo ""
echo " The Touch Bar now shows Claude Code's live status."
echo " Tap the Touch Bar item to bring Terminal to the front."
echo ""
echo " Run a demo:  bash claude-touchbar-bridge.sh demo"
echo ""
echo " Press Ctrl+C to stop."

wait $BRIDGE_PID
