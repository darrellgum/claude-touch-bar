#!/bin/bash
# Build the Claude Touch Bar app
set -e

cd "$(dirname "$0")"

echo "Building Claude Touch Bar..."

# Ensure app bundle structure exists
mkdir -p ClaudeTouchBar.app/Contents/MacOS

swiftc \
    -import-objc-header DFRPrivate.h \
    -framework AppKit \
    -F /System/Library/PrivateFrameworks \
    -framework DFRFoundation \
    -target x86_64-apple-macosx12.0 \
    -o ClaudeTouchBar.app/Contents/MacOS/ClaudeTouchBar \
    ClaudeTouchBar.swift

echo "Build successful!"
echo ""
echo "To run:  bash run.sh"
