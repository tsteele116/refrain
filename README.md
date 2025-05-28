# Refrain - Mac Break Reminder App

An admittedly vibe-coded native macOS application that reminds you to take regular screen breaks

## Features

- **Two types of breaks:**
  - Micro breaks: 20-second eye rest breaks every 20 minutes (default)
  - Long breaks: 10-minute breaks every 60 minutes (default)
- **Fully configurable intervals and durations**
- **Native macOS integration:**
  - Menu bar app with live countdown timer
  - System notifications
  - Full-screen break windows with countdown timers
- **Live countdown display**: Menu bar shows time until next break with visual icons
  - 👁️ for micro breaks (eye rest)
  - ☕️ for long breaks
  - ⏸️ when paused
- **Pause/resume functionality**
- **Skip break option** during break windows
- **Persistent settings** saved between app launches
- **Start on Login** option to automatically launch with macOS

## Building the App

1. Make sure you have Xcode command line tools installed:
   ```bash
   xcode-select --install
   ```

2. Make the build script executable and run it:
   ```bash
   chmod +x build.sh
   ./build.sh
   ```

3. The script will create `Refrain.app` in the current directory.

## Installation

1. Copy `Refrain.app` to your Applications folder
2. Right-click the app and select "Open" the first time to bypass Gatekeeper
3. The app will appear in your menu bar with a countdown timer showing time until next break

## Usage

### Menu Bar Display
The menu bar icon shows:
- **👁️ 19:45** - Time until next micro break (eye rest)
- **☕️ 58:30** - Time until next long break
- **⏸️** - When breaks are paused

### Menu Bar Controls
- Click the countdown timer in your menu bar to access:
  - **Live Timer Status**: Watch both countdowns update in real-time
    - 👁️ Micro Break: 19:45 → 19:44 → 19:43...
    - ☕️ Long Break: 58:30 → 58:29 → 58:28...
  - **Preferences**: Configure break intervals and durations
  - **Pause/Resume Breaks**: Temporarily disable break reminders
  - **Quit**: Exit the application

### Break Windows
When it's time for a break, the app will:
1. Send a system notification
2. Display a full-screen break window with:
   - Break type and instructions
   - Countdown timer
   - "Skip Break" button if you need to continue working

### Customization
Access Preferences from the menu bar to configure:
- **Micro Break Interval**: How often to show 20-second breaks (default: 20 minutes)
- **Micro Break Duration**: How long micro breaks last (default: 20 seconds)
- **Long Break Interval**: How often to show long breaks (default: 60 minutes)
- **Long Break Duration**: How long long breaks last (default: 10 minutes)
- **Start on Login**: Automatically launch Refrain when you log into macOS

## Default Settings

- **Micro breaks**: 20 seconds every 20 minutes
- **Long breaks**: 10 minutes every 60 minutes

These match common recommendations for computer eye strain prevention and ergonomic health.

## Technical Details

- Built with Swift and AppKit for native macOS performance
- Uses UserNotifications framework for system notifications
- Settings are automatically saved to UserDefaults
- Runs as a menu bar app (LSUIElement = true)
- Requires macOS 11.0 or later

## Troubleshooting

### App won't open
- Make sure you right-clicked and selected "Open" the first time
- Check that you have macOS 11.0 or later

### No notifications appearing
- Check System Preferences > Notifications > Refrain
- Make sure notifications are enabled for the app

### Break windows not appearing
- The app may need accessibility permissions in some cases
- Check System Preferences > Security & Privacy > Privacy > Accessibility

### Start on Login not working
The app tries multiple methods to add itself to login items:
1. **Modern API** (macOS 13+): Uses SMAppService
2. **Legacy API**: Uses SMLoginItemSetEnabled  
3. **AppleScript fallback**: Directly adds to System Events

If automatic setup fails, you'll see a dialog with manual instructions:
1. Open System Preferences → Users & Groups
2. Click your user account → Login Items tab
3. Click "+" and select Refrain.app
4. For best results, copy Refrain.app to Applications folder first

The preferences window shows ✅ when Refrain is actually in your login items.

