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
    echo "msg:Compacting:system" > "$STATUS_FILE"; sleep 3
    echo "msg:Responding:responding" > "$STATUS_FILE"; sleep 3
    echo "idle" > "$STATUS_FILE"
    echo "Demo complete."
    exit 0
fi

echo "Claude Touch Bar Bridge started."

last_state=""
last_word=""
idle_count=0
IDLE_THRESHOLD=3

while true; do
    # Get number of Terminal windows
    win_count=$(osascript -e 'tell application "Terminal" to count windows' 2>/dev/null)
    win_count=${win_count:-0}

    spinner_word=""
    tail_content=""

    # Check each window's selected tab (separate calls preserve UTF-8)
    for (( i=1; i<=win_count; i++ )); do
        tab_content=$(osascript -e "tell application \"Terminal\" to get contents of selected tab of window $i" 2>/dev/null | tail -15)
        found=$(echo "$tab_content" | grep -oE '[·✢✳✶✻✽] [A-Z][a-z]+…' | tail -1 | sed 's/^[^ ]* //;s/…$//')
        if [[ -n "$found" ]]; then
            spinner_word="$found"
            tail_content="$tab_content"
        fi
    done

    # Also check for compacting message (blue spinner, no standard spinner word)
    compact_detected=""
    if [[ -z "$spinner_word" ]]; then
        for (( i=1; i<=win_count; i++ )); do
            tab_content=$(osascript -e "tell application \"Terminal\" to get contents of selected tab of window $i" 2>/dev/null | tail -10)
            if echo "$tab_content" | grep -qE 'Compacting conversation'; then
                spinner_word="Compacting"
                tail_content="$tab_content"
                compact_detected="1"
                break
            fi
        done
    fi

    if [[ -n "$spinner_word" ]]; then
        idle_count=0

        # Detect mode from terminal context
        mode="thinking"

        # Check for compacting (system blue)
        if [[ -n "$compact_detected" ]]; then
            mode="system"
        # Check for tool execution indicators (⏺ Bash, ⏺ Read, ⏺ Write, etc.)
        elif echo "$tail_content" | grep -qE '⏺ (Bash|Read|Write|Edit|Glob|Grep|WebSearch|WebFetch|Agent)'; then
            mode="tool-use"
        fi

        # Check for "Running…" which indicates tool execution
        if echo "$tail_content" | grep -qE 'Running…|Searching…'; then
            mode="tool-use"
        fi

        # Check for streaming response (↓ with token count changing = responding)
        token_count=""
        if echo "$tail_content" | grep -qE '↓ [0-9]'; then
            mode="responding"
            token_count=$(echo "$tail_content" | grep -oE '↓ [0-9,]+' | tail -1 | sed 's/↓ //')
        fi

        # Include token count when available so Swift app can detect activity
        # Format: msg:word:mode or msg:word:mode:tokencount
        if [[ -n "$token_count" ]]; then
            echo "msg:$spinner_word:$mode:$token_count" > "$STATUS_FILE"
        else
            echo "msg:$spinner_word:$mode" > "$STATUS_FILE"
        fi

        if [[ "$spinner_word" != "$last_word" || "$last_state" != "working" ]]; then
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
