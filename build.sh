#!/bin/bash

# Build script for BreakTime macOS app

APP_NAME="Refrain"
SWIFT_FILE="Refrain.swift"
INFO_PLIST="Info.plist"
BUNDLE_ID="com.tsteele.refrain"

# Create necessary directories
APP_BUNDLE_PATH="${APP_NAME}.app/Contents/MacOS"
RESOURCES_PATH="${APP_NAME}.app/Contents/Resources"
mkdir -p "${APP_BUNDLE_PATH}"
mkdir -p "${RESOURCES_PATH}"

# Compile Swift code
echo "Building ${APP_NAME}..."
swiftc -o "${APP_BUNDLE_PATH}/${APP_NAME}" "${SWIFT_FILE}" -import-objc-header "Refrain-Bridging-Header.h" # Assuming you might need a bridging header later

# Check if compilation was successful
if [ $? -ne 0 ]; then
    echo "❌ Build failed. Please check the Swift code for errors."
    exit 1
fi

# Copy Info.plist
cp "${INFO_PLIST}" "${APP_NAME}.app/Contents/Info.plist"

# Update placeholder in Info.plist (if any, e.g., YOUR_TEAM_ID - though not critical for local builds)
# sed -i '' "s/YOUR_TEAM_ID/YOUR_ACTUAL_TEAM_ID/g" "${APP_NAME}.app/Contents/Info.plist"

# Set executable permissions (though swiftc usually does this)
chmod +x "${APP_BUNDLE_PATH}/${APP_NAME}"

echo "✅ Build complete! ${APP_NAME}.app has been created."
echo ""
echo "-----------------------------------------------------"
echo "              INSTALLATION & USAGE                   "
echo "-----------------------------------------------------"
echo ""
echo "RECOMMENDED METHOD (for most users):"
echo "1. Go to the project's GitHub Releases page:"
echo "   https://github.com/tsteele116/refrain/releases"
echo "2. Download the latest 'Refrain.app.zip' file."
echo "3. Unzip the file to get Refrain.app."
echo "4. Drag Refrain.app to your Applications folder."
echo "5. Right-click (or Control-click) Refrain.app and select 'Open'."
   echo "   You might need to do this twice or confirm in System Settings > Privacy & Security due to Gatekeeper."
echo ""
echo "DEVELOPER METHOD (if you built from source):"
echo "1. You've just built ${APP_NAME}.app in the current directory."
echo "2. Copy ${APP_NAME}.app to your Applications folder."
echo "3. Right-click and select 'Open' the first time to bypass Gatekeeper."
echo "4. The app will appear in your menu bar."
echo ""
echo "Features:
- Menu bar shows countdown to next break (👁️ for micro, ☕️ for long breaks)
- Click the countdown timer to see both timers updating live every second
- Default: 20-second breaks every 20 minutes, 10-minute breaks every 60 minutes
- Fully configurable through the Preferences window
- Pause/resume breaks, manually start breaks, or reset all timers from the menu
- Optional: Start automatically on login
- Timers pause if Mac is idle for a minute, resume when active"
echo "-----------------------------------------------------" 