#!/bin/bash
# claude-touchbar-bridge.sh
# Reads Claude Code's spinner state and mode from Terminal.app
# Passes word + mode so the Touch Bar can show accurate colors:
#   - claude orange: actively receiving tokens
#   - shifts to red: stalled (no new tokens for 3+ seconds)
#   - lighter shimmer: tool execution

STATUS_FILE="/tmp/claude-touchbar-status"

if [[ "$1" == "demo" ]]; then
    echo "Demo mode..."
    echo "msg:Thinking:thinking" > "$STATUS_FILE"; sleep 4
    echo "msg:Pondering:thinking" > "$STATUS_FILE"; sleep 5  # will go red (stalled)
    echo "msg:Reading:tool-use" > "$STATUS_FILE"; sleep 3
    echo "msg:Writing:tool-use" > "$STATUS_FILE"; sleep 3
    echo "msg:Responding:responding" > "$STATUS_FILE"; sleep 3
    echo "idle" > "$STATUS_FILE"
    echo "Demo complete."
    exit 0
fi

echo "Claude Touch Bar Bridge started."

last_state=""
last_word=""
idle_count=0
IDLE_THRESHOLD=5

while true; do
    # Read the last lines of terminal content
    tail_content=$(osascript -e 'tell application "Terminal" to get contents of selected tab of front window' 2>/dev/null | tail -15)

    # Find spinner word
    spinner_word=$(echo "$tail_content" | grep -oE '[·✢✳✶✻✽] [A-Z][a-z]+…' | tail -1 | sed 's/^[^ ]* //;s/…$//')

    if [[ -n "$spinner_word" ]]; then
        idle_count=0

        # Detect mode from terminal context
        # Look for indicators near the spinner line
        mode="thinking"

        # Check for tool execution indicators (⏺ Bash, ⏺ Read, ⏺ Write, etc.)
        if echo "$tail_content" | grep -qE '⏺ (Bash|Read|Write|Edit|Glob|Grep|WebSearch|WebFetch|Agent)'; then
            mode="tool-use"
        fi

        # Check for "Running…" which indicates tool execution
        if echo "$tail_content" | grep -qE 'Running…|Searching…'; then
            mode="tool-use"
        fi

        # Check for streaming response (↓ with token count changing = responding)
        if echo "$tail_content" | grep -qE '↓ [0-9]'; then
            mode="responding"
        fi

        if [[ "$spinner_word" != "$last_word" || "$last_state" != "working" ]]; then
            echo "msg:$spinner_word:$mode" > "$STATUS_FILE"
            last_word="$spinner_word"
            last_state="working"
        fi
    else
        idle_count=$((idle_count + 1))
        if [[ "$idle_count" -ge "$IDLE_THRESHOLD" && "$last_state" != "idle" ]]; then
            echo "idle" > "$STATUS_FILE"
            last_state="idle"
            last_word=""
        fi
    fi

    sleep 0.3
done
