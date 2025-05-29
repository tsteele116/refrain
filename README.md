# Refrain - Mac Break Reminder App

An admittedly vibe-coded native macOS application that reminds you to take regular screen breaks

## Installation

**RECOMMENDED METHOD (for most users):**

1.  Go to the project's GitHub Releases page:
    [https://github.com/tsteele116/refrain/releases](https://github.com/tsteele116/refrain/releases)
2.  Download the latest `Refrain.app.zip` file.
3.  Unzip the file to get `Refrain.app`.
4.  Drag `Refrain.app` to your **Applications** folder.
5.  Right-click (or Control-click) `Refrain.app` and select "Open".
    *   You might need to do this twice or confirm in System Settings > Privacy & Security due to Gatekeeper for the first launch.

**DEVELOPER METHOD (if building from source):**

1.  Ensure you have Xcode command line tools installed:
    ```bash
    xcode-select --install
    ```
2.  Clone the repository.
3.  Make the build script executable and run it:
    ```bash
    chmod +x build.sh
    ./build.sh
    ```
4.  The script will create `Refrain.app` in the project directory.
5.  Copy `Refrain.app` to your Applications folder and open it as described above.

## Features

- **Two types of breaks:**
  - Micro breaks (e.g., 20-second eye rest every 20 minutes)
  - Long breaks (e.g., 10-minute away-from-screen break every 60 minutes)
- **Fully configurable intervals and durations** via Preferences.
- **Native macOS integration:**
  - Menu bar app with live countdown timer.
  - System notifications for break alerts.
  - Full-screen break windows with a countdown timer and a "Break Complete" button.
- **Dynamic Menu Bar Display:** Shows time until the *next* scheduled break with visual icons:
  - 👁️ for upcoming micro breaks.
  - ☕️ for upcoming long breaks.
  - ✅ when a break is complete and awaiting confirmation.
  - 😴 when timers are paused due to system idle.
  - ⏸️ when breaks are manually paused.
- **Menu Bar Controls:**
  - Live countdowns for both micro and long breaks in the dropdown menu.
  - Pause/Resume all breaks.
  - Manually **Start Micro Break Now** or **Start Long Break Now**.
  - **Reset All Timers** to their initial state.
  - Access Preferences.
  - Quit.
- **Idle Detection:** Timers automatically pause if the Mac is idle for a configurable duration (default: 60 seconds) and resume when activity is detected.
- **Persistent Settings:** All configurations are saved between app launches.
- **Start on Login:** Option to automatically launch Refrain when you log into macOS.

## Usage

### Menu Bar Display
The menu bar icon provides an at-a-glance status:
- **👁️ 19:45** - Time until the next micro break.
- **☕️ 58:30** - Time until the next long break.
- **✅** - A break has just finished; click to confirm and resume timers.
- **😴 Idle** - Timers are paused because your Mac is idle.
- **⏸️** - Breaks are manually paused.

### Menu Bar Controls
Click the status item in your menu bar to access:
- **Live Timer Status**: Displays continuously updating countdowns for *both* micro and long breaks.
- **Preferences**: Open the window to configure break intervals, durations, and start-on-login.
- **Start Micro Break Now**: Immediately begin a micro break.
- **Start Long Break Now**: Immediately begin a long break.
- **Pause/Resume Breaks**: Toggle the global pause state for all break timers.
- **Reset All Timers**: Clears all current timer progress and break counts, and restarts fresh timers according to your saved preferences.
- **Quit**: Exit the application.

### Break Windows
When it's time for a break, the app will:
1.  Send a system notification (if enabled).
2.  Display a full-screen break window featuring:
    - Break type and a brief instruction (e.g., "Rest Your Eyes" or "Step Away From Screen").
    - A countdown timer for the break's duration.
    - Statistics: Number of micro/long breaks taken this session, and time until the *next* micro and long breaks (after the current one).
    - A "Break Complete" button. Clicking this (or pressing Enter) dismisses the window and resumes normal work/break cycles.

### Customization
Access **Preferences** from the menu bar to configure:
- Micro Break: Interval (minutes) and Duration (seconds).
- Long Break: Interval (minutes) and Duration (minutes).
- Start Refrain on Login checkbox.

## Default Settings

- **Micro breaks**: 20 seconds every 20 minutes
- **Long breaks**: 10 minutes every 60 minutes

These can be easily changed in the Preferences window.

## Technical Details

- Built with Swift and AppKit for native macOS performance.
- Uses UserNotifications framework for system notifications.
- Uses IOKit to detect system idle time.
- Settings are automatically saved to UserDefaults.
- Runs as a menu bar (agent) application (`LSUIElement = true`).
- Assumed to require macOS 11.0 or later (based on typical Swift project settings, but not strictly enforced by build script).

## Troubleshooting

### App won't open / Gatekeeper
- Ensure `Refrain.app` is in your `/Applications` folder for best results.
- On first launch, you **must** right-click (or Control-click) the app icon and select "Open" from the context menu.
- You may need to confirm this action in a dialog box or by going to `System Settings > Privacy & Security` and allowing the app to run.

### No notifications appearing
- Check `System Settings > Notifications > Refrain`.
- Ensure notifications are enabled and configured to your liking for the app.

### Start on Login not working
The app tries multiple methods to add itself to login items:
1.  **Modern API** (macOS 13+): Uses `SMAppService`.
2.  **Legacy API**: Uses `SMLoginItemSetEnabled`.
3.  **AppleScript fallback**: Directly adds to System Events login items.

If automatic setup fails, the Preferences window may show manual instructions, or the checkbox might not stay checked. You can manually add `Refrain.app` (preferably from your Applications folder) via:
`System Settings > General > Login Items`, then click the "+" under "Open at Login".

The checkbox in Refrain's Preferences window attempts to reflect the actual login item status.

