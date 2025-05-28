#!/bin/bash

# Build script for BreakTime macOS app

APP_NAME="Refrain"
BUNDLE_ID="com.tsteele.refrain"
INFO_PLIST="Info.plist"

echo "Building $APP_NAME..."

# Clean up any previous build
rm -rf "$APP_NAME.app"

# Create app bundle structure
mkdir -p "$APP_NAME.app/Contents/MacOS"
mkdir -p "$APP_NAME.app/Contents/Resources"

# Copy Info.plist
cp Info.plist "$APP_NAME.app/Contents/"

# Compile Swift code with simpler approach
swiftc -o "$APP_NAME.app/Contents/MacOS/$APP_NAME" \
    -target x86_64-apple-macos11.0 \
    Refrain.swift

# Check if compilation was successful
if [ $? -eq 0 ]; then
    # Make executable
    chmod +x "$APP_NAME.app/Contents/MacOS/$APP_NAME"
    
    echo "✅ Build complete! You can now run the app by double-clicking $APP_NAME.app"
    echo ""
    echo "To install the app:"
    echo "1. Copy $APP_NAME.app to your Applications folder"
    echo "2. Right-click and select 'Open' the first time to bypass Gatekeeper"
    echo "3. The app will appear in your menu bar with a live countdown timer"
    echo ""
    echo "Features:"
    echo "- Menu bar shows countdown to next break (👁️ for micro, ☕️ for long breaks)"
    echo "- Click the countdown timer to see both timers updating live every second"
    echo "- Default: 20-second breaks every 20 minutes, 10-minute breaks every 60 minutes"
    echo "- Fully configurable through the Preferences window"
    echo "- Pause/resume breaks as needed"
    echo "- Optional: Start automatically on login"
else
    echo "❌ Build failed. Please check the Swift code for errors."
    exit 1
fi 