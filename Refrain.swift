import Cocoa
import UserNotifications
import ServiceManagement
import IOKit

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var breakTimer: BreakTimer!
    var preferencesWindow: NSWindow?
    var menuUpdateTimer: Timer?
    
    // References to timer menu items for live updates
    var microBreakMenuItem: NSMenuItem?
    var longBreakMenuItem: NSMenuItem?
    var pausedMenuItem: NSMenuItem?
    
    var menuIsOpen: Bool = false // Track if menu is open
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Ensure app runs as a menu bar (agent) app
        NSApp.setActivationPolicy(.accessory)
        // Request notification permissions
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted {
                print("Notification permission granted")
            }
        }
        
        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.action = #selector(statusBarButtonClicked)
        statusItem.button?.target = self
        
        // Initialize break timer
        breakTimer = BreakTimer()
        breakTimer.appDelegate = self // Set reference for menu bar updates
        breakTimer.start() // This now schedules its core work asynchronously
        
        // Create initial menu (will be updated dynamically)
        // Defer this initial menu update to allow BreakTimer's async start to complete first
        DispatchQueue.main.async { [weak self] in // Use [weak self] for safety
            print("[AppDelegate] applicationDidFinishLaunching: Performing initial deferred updateMenu()")
            self?.updateMenu()
        }
    }
    
    func updateMenu() {
        print("[AppDelegate] updateMenu() called")
        // Defensive: Invalidate menuUpdateTimer before rebuilding menu
        if let timer = menuUpdateTimer {
            print("[AppDelegate] updateMenu() invalidating menuUpdateTimer before menu rebuild")
            timer.invalidate()
            menuUpdateTimer = nil
        }
        if menuIsOpen {
            print("[AppDelegate] updateMenu() skipped menu rebuild because menuIsOpen; updating timer items only")
            updateTimerMenuItems()
            return
        }
        let menu = NSMenu()
        
        // Clear previous references
        microBreakMenuItem = nil
        longBreakMenuItem = nil
        pausedMenuItem = nil
        
        // Check if waiting for break confirmation
        if breakTimer.isWaitingForBreakConfirmation {
            let breakTypeText = breakTimer.lastBreakType == .micro ? "Micro Break" : "Long Break"
            let confirmItem = NSMenuItem(title: "✅ \(breakTypeText) Complete", action: #selector(confirmBreakComplete), keyEquivalent: "")
            menu.addItem(confirmItem)
            menu.addItem(NSMenuItem.separator())
        }
        // Add timer status items
        else if let _ = breakTimer.microBreakStartTime,
                let _ = breakTimer.longBreakStartTime {
            
            // Create timer menu items and store references
            microBreakMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            microBreakMenuItem!.isEnabled = false
            menu.addItem(microBreakMenuItem!)
            
            longBreakMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            longBreakMenuItem!.isEnabled = false
            menu.addItem(longBreakMenuItem!)
            
            menu.addItem(NSMenuItem.separator())
        } else if breakTimer.isPaused { // Covers global pause
            pausedMenuItem = NSMenuItem(title: "⏸️ Breaks Paused", action: nil, keyEquivalent: "")
            pausedMenuItem!.isEnabled = false
            menu.addItem(pausedMenuItem!)
            menu.addItem(NSMenuItem.separator())
        } else if breakTimer.isPausedDueToIdle { // Added check for idle pause for menu display
             pausedMenuItem = NSMenuItem(title: "😴 Idle (Timers Paused)", action: nil, keyEquivalent: "")
             pausedMenuItem!.isEnabled = false
             menu.addItem(pausedMenuItem!)
             menu.addItem(NSMenuItem.separator())
        }
                
        // Manual break start options
        // Enabled if not waiting for confirmation and not globally paused.
        // If idle, still allow manual start (user interaction implies not idle anymore, and BreakTimer handles idle state changes).
        let canManuallyStartBreak = !breakTimer.isWaitingForBreakConfirmation && !breakTimer.isPaused
        
        let startMicroBreakItem = NSMenuItem(title: "Start Micro Break Now", action: #selector(startMicroBreakNow), keyEquivalent: "")
        startMicroBreakItem.isEnabled = canManuallyStartBreak
        menu.addItem(startMicroBreakItem)
        
        let startLongBreakItem = NSMenuItem(title: "Start Long Break Now", action: #selector(startLongBreakNow), keyEquivalent: "")
        startLongBreakItem.isEnabled = canManuallyStartBreak
        menu.addItem(startLongBreakItem)
        
        // Reset Timers option
        let resetTimersItem = NSMenuItem(title: "Reset All Timers", action: #selector(resetAllTimers), keyEquivalent: "")
        menu.addItem(resetTimersItem)

        menu.addItem(NSMenuItem.separator()) // Separator before pause/quit or other app actions

        if breakTimer.isWaitingForBreakConfirmation {
            // Don't show pause/resume when waiting for confirmation
        } else {
            let pauseTitle = breakTimer.isPaused ? "Resume Breaks" : "Pause Breaks"
            menu.addItem(NSMenuItem(title: pauseTitle, action: #selector(toggleBreaks), keyEquivalent: ""))
        }
        // menu.addItem(NSMenuItem(title: "Preferences", action: #selector(showPreferences), keyEquivalent: "")) // REMOVED From here
        // menu.addItem(NSMenuItem.separator()) // This separator might be redundant or need adjustment
        
        // New position for Preferences, grouped with Quit
        // If there was a Pause/Resume item, it would be above this new separator.
        // If not (due to break confirmation), the separator above resetTimersItem serves to separate controls from App/Quit.
        menu.addItem(NSMenuItem.separator()) // Ensure separation for Preferences/Quit group if needed, or adjust existing ones
        menu.addItem(NSMenuItem(title: "Preferences", action: #selector(showPreferences), keyEquivalent: ",")) // ADDED here with key equivalent
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
        statusItem.menu?.delegate = self
        
        // Update timer values
        updateTimerMenuItems()
    }
    
    func updateTimerMenuItems() {
        print("[AppDelegate] updateTimerMenuItems() called")
        guard let microStart = breakTimer.microBreakStartTime,
              let longStart = breakTimer.longBreakStartTime else {
            print("[AppDelegate] updateTimerMenuItems() aborted: missing start times")
            return
        }
        let now = Date()
        let microElapsed = now.timeIntervalSince(microStart)
        let longElapsed = now.timeIntervalSince(longStart)
        let microRemaining = max(0, breakTimer.microBreakInterval - microElapsed)
        let longRemaining = max(0, breakTimer.longBreakInterval - longElapsed)
        
        // Get current break stats for cycle information
        let currentStats = breakTimer.getCurrentBreakStats()
        let cycleInfo = "(Cycle \(currentStats.microBreaksInCurrentLongCycle + 1) of \(currentStats.maxMicroBreaksInLongCycle))"
        // We add +1 to microBreaksInCurrentLongCycle for display because it represents *completed* cycles.
        // So, if 0 are completed, we are in Cycle 1.

        // Update micro break timer
        if let microItem = microBreakMenuItem {
            let microMinutes = Int(microRemaining) / 60
            let microSeconds = Int(microRemaining) % 60
            let microTimeString = String(format: "%d:%02d", microMinutes, microSeconds)
            microItem.title = "👀 Micro Break: \(microTimeString) \(cycleInfo)"
        } else {
            print("[AppDelegate] updateTimerMenuItems: microBreakMenuItem is nil")
        }
        // Update long break timer
        if let longItem = longBreakMenuItem {
            let longMinutes = Int(longRemaining) / 60
            let longSecondsTotal = Int(longRemaining) % 60
            let longTimeString = String(format: "%d:%02d", longMinutes, longSecondsTotal)
            longItem.title = "☕️ Long Break: \(longTimeString)"
        } else {
            print("[AppDelegate] updateTimerMenuItems: longBreakMenuItem is nil")
        }
    }
    
    // NSMenuDelegate method - called right before menu opens
    func menuWillOpen(_ menu: NSMenu) {
        print("[AppDelegate] menuWillOpen: setting menuIsOpen = true")
        menuIsOpen = true
        updateMenu()
        // Start live updates while menu is open - only update timer values, not rebuild menu
        menuUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            print("[AppDelegate] menuUpdateTimer fired")
            self?.updateTimerMenuItems()
        }
    }
    
    // NSMenuDelegate method - called when menu closes
    func menuDidClose(_ menu: NSMenu) {
        print("[AppDelegate] menuDidClose: setting menuIsOpen = false")
        menuIsOpen = false
        // Stop live updates when menu closes
        if let timer = menuUpdateTimer {
            print("[AppDelegate] menuDidClose invalidating menuUpdateTimer")
            timer.invalidate()
        }
        menuUpdateTimer = nil
    }
    
    @objc func statusBarButtonClicked() {
        // Update menu with current timer values before showing
        updateMenu()
        statusItem.menu?.popUp(positioning: nil, at: NSPoint.zero, in: statusItem.button)
    }
    
    @objc func showPreferences() {
        if preferencesWindow == nil {
            let preferencesVC = PreferencesViewController()
            preferencesWindow = NSWindow(contentViewController: preferencesVC)
            preferencesWindow?.title = "Refrain Preferences" // Updated App Name
            preferencesWindow?.styleMask = [.titled, .closable]
            preferencesWindow?.center()
        }
        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func toggleBreaks() {
        breakTimer.togglePause()
        updateMenu()
    }
    
    @objc func confirmBreakComplete() {
        breakTimer.confirmBreakComplete()
    }
    
    @objc func resetAllTimers() {
        print("[AppDelegate] User requested to Reset All Timers.")
        breakTimer.resetAndRestartTimers()
        // The resetAndRestartTimers method in BreakTimer already calls appDelegate.updateMenu()
        // and breakTimer.updateMenuBarDisplay() via DispatchQueue.main.async.
    }
    
    @objc func startMicroBreakNow() {
        print("[AppDelegate] User requested to start Micro Break now.")
        if breakTimer.isPausedDueToIdle {
            print("[AppDelegate] Clearing idle pause flag before starting manual micro break.")
            breakTimer.isPausedDueToIdle = false
            // The call to showMicroBreak() will handle pausing other timers and setting up the break state.
            // It internally calls pauseForBreakConfirmation which also clears isPausedDueToIdle.
            // The displayUpdateTimer will eventually resume normal operation if user remains active.
        }
        breakTimer.showMicroBreak()
        // updateMenu() is handled by the chain of calls originating from showMicroBreak()
    }

    @objc func startLongBreakNow() {
        print("[AppDelegate] User requested to start Long Break now.")
        if breakTimer.isPausedDueToIdle {
            print("[AppDelegate] Clearing idle pause flag before starting manual long break.")
            breakTimer.isPausedDueToIdle = false
        }
        breakTimer.showLongBreak()
        // updateMenu() is handled by the chain of calls originating from showLongBreak()
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        menuUpdateTimer?.invalidate()
        breakTimer?.stop()
    }
}

// Define BreakStats struct globally or ensure it's accessible to both classes
struct BreakStats {
    let microBreaksTaken: Int
    let longBreaksTaken: Int
    let timeUntilNextMicroBreak: TimeInterval 
    let timeUntilNextLongBreak: TimeInterval
    let currentBreakType: BreakType? // To know which break screen we are on
    let microBreaksInCurrentLongCycle: Int
    let maxMicroBreaksInLongCycle: Int
}

class BreakTimer {
    private var microBreakTimer: Timer?
    private var longBreakTimer: Timer?
    private var displayUpdateTimer: Timer?
    private var currentBreakWindow: BreakWindow?
    var isPaused = false // Global pause state (e.g., user manually pauses all breaks)
    var isWaitingForBreakConfirmation = false
    var isPausedDueToIdle = false // New state for idle pause
    let idleThreshold: TimeInterval = 60.0 // Pause timers if idle for 60 seconds
    
    var microBreakInterval: TimeInterval = 20 * 60 
    var microBreakDuration: TimeInterval = 20 
    var longBreakInterval: TimeInterval = 60 * 60 
    var longBreakDuration: TimeInterval = 10 * 60 
    
    var microBreakStartTime: Date?
    var longBreakStartTime: Date?
    var lastBreakType: BreakType? // Which break just occurred

    // For preserving time when one break interrupts another
    private var microBreakAccumulatedElapsed: TimeInterval = 0
    private var longBreakAccumulatedElapsed: TimeInterval = 0
    private var isMicroBreakTimerPausedPendingOtherBreak = false
    private var isLongBreakTimerPausedPendingOtherBreak = false

    weak var appDelegate: AppDelegate?
    
    var microBreaksTakenSession: Int = 0
    var longBreaksTakenSession: Int = 0
    var microBreaksInCurrentLongCycle: Int = 0 // New counter
    
    init() {
        loadSettings()
    }
    
    // For FULL global pause or complete reset
    func stop() {
        print("[BreakTimer] stop() (FULL STOP/RESET) called.")
        microBreakTimer?.invalidate()
        longBreakTimer?.invalidate()
        displayUpdateTimer?.invalidate()
        microBreakTimer = nil
        longBreakTimer = nil
        displayUpdateTimer = nil
        microBreakStartTime = nil
        longBreakStartTime = nil
        microBreakAccumulatedElapsed = 0
        longBreakAccumulatedElapsed = 0
        isMicroBreakTimerPausedPendingOtherBreak = false
        isLongBreakTimerPausedPendingOtherBreak = false
        isPausedDueToIdle = false // Reset idle pause flag on full stop
        print("[BreakTimer] stop(): All timers, start times, and accumulated states reset.")
    }
    
    func start() {
        print("[BreakTimer] start() called - scheduling core logic asynchronously")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            print("[BreakTimer] start() - async block executing")
            
            // If we are starting due to coming back from idle, reset the flag
            if self.isPausedDueToIdle {
                print("[BreakTimer] start() - async: Resuming from idle. Resetting isPausedDueToIdle.")
                self.isPausedDueToIdle = false
            }

            // Reset "paused pending other break" flags at the beginning of start().
            // Their purpose was to prevent (re)scheduling during an active break of the other type.
            // If start() is called, that phase is over, and we should attempt to schedule both timers.
            if self.isMicroBreakTimerPausedPendingOtherBreak {
                print("[BreakTimer] start() - async: Clearing isMicroBreakTimerPausedPendingOtherBreak (was true).")
                self.isMicroBreakTimerPausedPendingOtherBreak = false
            }
            if self.isLongBreakTimerPausedPendingOtherBreak {
                print("[BreakTimer] start() - async: Clearing isLongBreakTimerPausedPendingOtherBreak (was true).")
                self.isLongBreakTimerPausedPendingOtherBreak = false
            }

            guard !self.isPaused else { // Global pause state
                print("[BreakTimer] start() - async: aborted: isPaused (global pause state)")
                self.appDelegate?.statusItem.button?.title = "⏸️"
                self.appDelegate?.updateMenu()
                return 
            }

            let now = Date()
            var effectiveMicroInterval: TimeInterval
            var effectiveLongInterval: TimeInterval

            // Micro Timer Setup
            effectiveMicroInterval = self.microBreakInterval - self.microBreakAccumulatedElapsed
            self.microBreakStartTime = now // Start time for this new segment of activity
            print("[BreakTimer] start() - async: Micro. Accumulated: \(self.microBreakAccumulatedElapsed), Effective Interval: \(effectiveMicroInterval)")
            // With flags cleared above, the !self.isMicroBreakTimerPausedPendingOtherBreak check becomes redundant here but is harmless.
            if effectiveMicroInterval > 0 /* && !self.isMicroBreakTimerPausedPendingOtherBreak */ {
                self.microBreakTimer = Timer.scheduledTimer(withTimeInterval: effectiveMicroInterval, repeats: false) { [weak self] _ in // SINGLE SHOT
                    print("[BreakTimer] microBreakTimer fired (single shot for remaining time)")
                    self?.microBreakAccumulatedElapsed = 0 // Reset after firing for this segment
                    self?.showMicroBreak()
                }
                print("[BreakTimer] start() - async: Micro break timer scheduled for \(effectiveMicroInterval)s")
            } /* else if self.isMicroBreakTimerPausedPendingOtherBreak { // This branch should no longer be taken if start() clears the flag
                 print("[BreakTimer] start() - async: Micro break timer remains paused (should not happen if flag cleared above).")
            } */ else { // This means effectiveMicroInterval <= 0
                print("[BreakTimer] start() - async: Micro break effective interval is <= 0. Triggering immediately or skipping.")
                self.microBreakAccumulatedElapsed = 0
                self.showMicroBreak() // Or handle completion if interval was zero
            }
            // self.isMicroBreakTimerPausedPendingOtherBreak = false // Already done at the start of this async block

            // Long Timer Setup
            effectiveLongInterval = self.longBreakInterval - self.longBreakAccumulatedElapsed
            self.longBreakStartTime = now // Start time for this new segment of activity
            print("[BreakTimer] start() - async: Long. Accumulated: \(self.longBreakAccumulatedElapsed), Effective Interval: \(effectiveLongInterval)")
            // With flags cleared above, the !self.isLongBreakTimerPausedPendingOtherBreak check becomes redundant here but is harmless.
            if effectiveLongInterval > 0 /* && !self.isLongBreakTimerPausedPendingOtherBreak */ {
                self.longBreakTimer = Timer.scheduledTimer(withTimeInterval: effectiveLongInterval, repeats: false) { [weak self] _ in // SINGLE SHOT
                    print("[BreakTimer] longBreakTimer fired (single shot for remaining time)")
                    self?.longBreakAccumulatedElapsed = 0 // Reset after firing for this segment
                    self?.showLongBreak()
                }
                print("[BreakTimer] start() - async: Long break timer scheduled for \(effectiveLongInterval)s")
            } /* else if self.isLongBreakTimerPausedPendingOtherBreak { // This branch should no longer be taken if start() clears the flag
                print("[BreakTimer] start() - async: Long break timer remains paused (should not happen if flag cleared above).")
            } */ else { // This means effectiveLongInterval <= 0
                print("[BreakTimer] start() - async: Long break effective interval is <= 0. Triggering immediately or skipping.")
                self.longBreakAccumulatedElapsed = 0
                self.showLongBreak()
            }
            // self.isLongBreakTimerPausedPendingOtherBreak = false // Already done at the start of this async block
            
            // Display Update Timer - also handles idle checking
            print("[BreakTimer] start() - async: scheduling displayUpdateTimer (and idle checker)")
            self.displayUpdateTimer?.invalidate() // Ensure no duplicates
            self.displayUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.checkIdleTimeAndupdateMenuBarDisplay()
            }
            print("[BreakTimer] start() - async: displayUpdateTimer scheduled successfully")
            
            self.updateMenuBarDisplay() 
            print("[BreakTimer] start() - async: finished initial updateMenuBarDisplay() call")
        }
        print("[BreakTimer] start() finished scheduling core logic asynchronously")
    }
    
    func togglePause() {
        print("[BreakTimer] togglePause() called. isPaused was \(isPaused)")
        isPaused.toggle()
        if isPaused {
            print("[BreakTimer] togglePause(): Now PAUSED (globally)")
            // If we are globally pausing, ensure idle pause is also cleared/reset
            // as global pause takes precedence.
            if isPausedDueToIdle {
                isPausedDueToIdle = false 
                print("[BreakTimer] togglePause(): Clearing isPausedDueToIdle because global pause is being activated.")
            }
            stop() // This will nil out timers and start times, and also reset isPausedDueToIdle
            appDelegate?.statusItem.button?.title = "⏸️"
        } else {
            print("[BreakTimer] togglePause(): Now RESUMING (globally)")
            // isPausedDueToIdle should be false here if stop() was called.
            // start() will handle new start times and scheduling.
            start()
        }
        appDelegate?.updateMenu()
        print("[BreakTimer] togglePause() finished. isPaused is now \(isPaused)")
    }
    
    private func checkIdleTimeAndupdateMenuBarDisplay() {
        // Priority:
        // 1. Global pause (isPaused)
        // 2. Waiting for break confirmation (isWaitingForBreakConfirmation)
        // 3. Idle pause (isPausedDueToIdle)
        // 4. Active timers

        if isPaused { // Globally paused, no need to check idle or update countdowns
            updateMenuBarDisplay()
            return
        }

        if isWaitingForBreakConfirmation { // Break confirmation takes precedence over idle detection for now
            updateMenuBarDisplay()
            return
        }

        // Check for idle time
        if let currentIdleTime = getSystemIdleTime() {
            // print("[BreakTimer] Idle time: \(currentIdleTime)s. Threshold: \(idleThreshold)s") // DEBUG
            if currentIdleTime > idleThreshold {
                if !isPausedDueToIdle {
                    print("[BreakTimer] Idle threshold exceeded. Pausing timers due to idle. System idle for \(currentIdleTime)s.")
                    isPausedDueToIdle = true
                    
                    let now = Date() // Time when idle > threshold is detected
                    // 'currentIdleTime' is from the outer 'if let currentIdleTime = getSystemIdleTime()'
                    // and is the value that triggered this block (i.e., currentIdleTime > idleThreshold)

                    if let microStart = microBreakStartTime, !isMicroBreakTimerPausedPendingOtherBreak {
                        let elapsedThisSegment = now.timeIntervalSince(microStart)
                        // Calculate actual work done by subtracting the *entire* current system idle time
                        // from the duration this timer segment appeared to be running.
                        let actualWorkDoneThisSegment = max(0, elapsedThisSegment - currentIdleTime)
                        microBreakAccumulatedElapsed += actualWorkDoneThisSegment
                        print("[BreakTimer] Idle Pause: Micro timer segment ran for \(elapsedThisSegment)s. System idle for \(currentIdleTime)s. Actual work credited: \(actualWorkDoneThisSegment)s. New total accumulated: \(microBreakAccumulatedElapsed)s")
                    }
                    if let longStart = longBreakStartTime, !isLongBreakTimerPausedPendingOtherBreak {
                        let elapsedThisSegment = now.timeIntervalSince(longStart)
                        let actualWorkDoneThisSegment = max(0, elapsedThisSegment - currentIdleTime)
                        longBreakAccumulatedElapsed += actualWorkDoneThisSegment
                        print("[BreakTimer] Idle Pause: Long timer segment ran for \(elapsedThisSegment)s. System idle for \(currentIdleTime)s. Actual work credited: \(actualWorkDoneThisSegment)s. New total accumulated: \(longBreakAccumulatedElapsed)s")
                    }

                    microBreakTimer?.invalidate()
                    longBreakTimer?.invalidate()
                    microBreakTimer = nil
                    longBreakTimer = nil
                    microBreakStartTime = nil
                    longBreakStartTime = nil

                    print("[BreakTimer] Timers paused due to idle. Accumulated times captured.")
                    appDelegate?.updateMenu()
                }
                updateMenuBarDisplay()
                return 
            } else {
                if isPausedDueToIdle {
                    print("[BreakTimer] System active again. Resuming timers from idle pause.")
                    isPausedDueToIdle = false 
                    start()
                    updateMenuBarDisplay() 
                    appDelegate?.updateMenu()
                    return 
                }
            }
        } else {
            print("[BreakTimer] Could not get system idle time.")
        }
        
        updateMenuBarDisplay()
    }
    
    private func updateMenuBarDisplay() {
        // This method might be called by displayUpdateTimer when one of the break timers is technically paused
        // (e.g. long break timer is paused because a micro break is in its confirmation phase).
        // We need to accurately reflect the *actual* remaining time for each.

        let now = Date()
        var microRemaining: TimeInterval
        var longRemaining: TimeInterval

        if isMicroBreakTimerPausedPendingOtherBreak {
            microRemaining = max(0, microBreakInterval - microBreakAccumulatedElapsed)
            print("[BreakTimer] updateMenuBarDisplay: Micro break timer is paused (pending long break). Remaining based on accumulated: \(microRemaining)")
        } else if let microStart = microBreakStartTime {
            let elapsed = now.timeIntervalSince(microStart)
            microRemaining = max(0, microBreakInterval - (microBreakAccumulatedElapsed + elapsed))
             print("[BreakTimer] updateMenuBarDisplay: Micro break timer active. Start: \(microStart), Elapsed total: \((microBreakAccumulatedElapsed + elapsed)), Remaining: \(microRemaining)")
        } else { // No start time, so timer is effectively not running or just reset
            microRemaining = microBreakInterval
            print("[BreakTimer] updateMenuBarDisplay: Micro break timer has no start time. Displaying full interval.")
        }

        if isLongBreakTimerPausedPendingOtherBreak {
            longRemaining = max(0, longBreakInterval - longBreakAccumulatedElapsed)
            print("[BreakTimer] updateMenuBarDisplay: Long break timer is paused (pending micro break). Remaining based on accumulated: \(longRemaining)")
        } else if let longStart = longBreakStartTime {
            let elapsed = now.timeIntervalSince(longStart)
            longRemaining = max(0, longBreakInterval - (longBreakAccumulatedElapsed + elapsed))
            print("[BreakTimer] updateMenuBarDisplay: Long break timer active. Start: \(longStart), Elapsed total: \((longBreakAccumulatedElapsed + elapsed)), Remaining: \(longRemaining)")
        } else {
            longRemaining = longBreakInterval
            print("[BreakTimer] updateMenuBarDisplay: Long break timer has no start time. Displaying full interval.")
        }
        
        guard let appDelegate = appDelegate else { return }

        if isWaitingForBreakConfirmation { // If waiting for any break confirmation, show ✅
            appDelegate.statusItem.button?.title = "✅"
            return
        }
        
        if isPaused { // Global pause
             appDelegate.statusItem.button?.title = "⏸️"
             return
        }

        if isPausedDueToIdle { 
            appDelegate.statusItem.button?.title = "😴 Idle"
            return
        }

        // If not waiting for confirmation and not globally paused, show the next break countdown.
        let nextBreakTime = min(microRemaining, longRemaining)
        let isNextBreakMicro = microRemaining <= longRemaining
        
        let minutes = Int(nextBreakTime) / 60
        let seconds = Int(nextBreakTime) % 60
        
        let icon = isNextBreakMicro ? "👀" : "☕️"
        let timeString = String(format: "%d:%02d", minutes, seconds)
        
        appDelegate.statusItem.button?.title = "\(icon) \(timeString)"
    }
    
    func showMicroBreak() {
        guard !isPaused && !isWaitingForBreakConfirmation else { return }
        print("[BreakTimer] Showing micro break")
        
        pauseForBreakConfirmation(breakType: .micro)

        let stats = getCurrentBreakStats() // Get current stats (shows completed breaks)

        DispatchQueue.main.async {
            self.currentBreakWindow = BreakWindow(
                duration: self.microBreakDuration,
                breakType: .micro,
                breakTimer: self,
                stats: stats // Pass stats
            )
            self.currentBreakWindow?.show()
            NSApp.activate(ignoringOtherApps: true) // Bring app to front
        }
        // UserNotifications.shared.sendNotification(type: .micro, duration: microBreakDuration) // Already handled by break window
    }
    
    func showLongBreak() {
        guard !isPaused && !isWaitingForBreakConfirmation else { return }
        print("[BreakTimer] Showing long break")
        
        pauseForBreakConfirmation(breakType: .long)

        let stats = getCurrentBreakStats() // Get current stats (shows completed breaks)

        DispatchQueue.main.async {
            self.currentBreakWindow = BreakWindow(
                duration: self.longBreakDuration,
                breakType: .long,
                breakTimer: self,
                stats: stats // Pass stats
            )
            self.currentBreakWindow?.show()
            NSApp.activate(ignoringOtherApps: true) // Bring app to front
        }
        // UserNotifications.shared.sendNotification(type: .long, duration: longBreakDuration) // Already handled by break window
    }
    
    private func pauseForBreakConfirmation(breakType: BreakType) {
        print("[BreakTimer] pauseForBreakConfirmation() called for breakType: \(String(describing: breakType))")
        
        if isPausedDueToIdle {
            print("[BreakTimer] pauseForBreakConfirmation: Clearing isPausedDueToIdle as a break is starting.")
            isPausedDueToIdle = false 
        }

        isWaitingForBreakConfirmation = true
        lastBreakType = breakType // Set this so confirmBreakComplete knows which break was completed
        let now = Date()

        if breakType == .micro {
            print("[BreakTimer] pauseForBreakConfirmation: Micro break occurred.")
            microBreakTimer?.invalidate() // Stop the timer that just fired
            microBreakTimer = nil
            // Pause the long break timer
            if let longStart = longBreakStartTime, !isLongBreakTimerPausedPendingOtherBreak {
                longBreakAccumulatedElapsed += now.timeIntervalSince(longStart)
                print("[BreakTimer] pauseForBreakConfirmation: Long break accumulating \(now.timeIntervalSince(longStart)). Total: \(longBreakAccumulatedElapsed)")
            }
            longBreakTimer?.invalidate() // Ensure it's stopped
            longBreakTimer = nil
            isLongBreakTimerPausedPendingOtherBreak = true
            // longBreakStartTime remains, it's the basis for accumulated time

        } else if breakType == .long {
            print("[BreakTimer] pauseForBreakConfirmation: Long break occurred.")
            longBreakTimer?.invalidate() // Stop the timer that just fired
            longBreakTimer = nil
            // Pause the micro break timer AND reset its accumulated progress
            if microBreakStartTime != nil && !isMicroBreakTimerPausedPendingOtherBreak {
                // The microBreakStartTime != nil check ensures there was a start time to begin with.
                // The !isMicroBreakTimerPausedPendingOtherBreak check ensures it wasn't already paused for some other reason.
                print("[BreakTimer] pauseForBreakConfirmation: Micro break was active (or had a start time), its accumulated time \(microBreakAccumulatedElapsed) will be reset to 0 due to long break.")
            }
            microBreakAccumulatedElapsed = 0 // Reset micro break progress
            microBreakTimer?.invalidate() // Ensure it's stopped
            microBreakTimer = nil
            isMicroBreakTimerPausedPendingOtherBreak = true
            print("[BreakTimer] pauseForBreakConfirmation: Micro break timer paused and its accumulated progress reset.")
        } else {
            print("[BreakTimer] pauseForBreakConfirmation: breakType is unexpected. THIS SHOULD NOT HAPPEN. Performing full stop.")
            stop() // Fallback, but ideally breakType is always valid.
        }
        
        displayUpdateTimer?.invalidate()
        displayUpdateTimer = nil
        print("[BreakTimer] pauseForBreakConfirmation: displayUpdateTimer stopped.")

        appDelegate?.statusItem.button?.title = "✅"
        appDelegate?.updateMenu()
    }
    
    private func showNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, 
                                          content: content, 
                                          trigger: nil)
        
        UNUserNotificationCenter.current().add(request)
    }
    
    private func loadSettings() {
        let defaults = UserDefaults.standard
        microBreakInterval = defaults.double(forKey: "microBreakInterval") != 0 ? 
            defaults.double(forKey: "microBreakInterval") : microBreakInterval
        microBreakDuration = defaults.double(forKey: "microBreakDuration") != 0 ? 
            defaults.double(forKey: "microBreakDuration") : microBreakDuration
        longBreakInterval = defaults.double(forKey: "longBreakInterval") != 0 ? 
            defaults.double(forKey: "longBreakInterval") : longBreakInterval
        longBreakDuration = defaults.double(forKey: "longBreakDuration") != 0 ? 
            defaults.double(forKey: "longBreakDuration") : longBreakDuration
    }
    
    func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(microBreakInterval, forKey: "microBreakInterval")
        defaults.set(microBreakDuration, forKey: "microBreakDuration")
        defaults.set(longBreakInterval, forKey: "longBreakInterval")
        defaults.set(longBreakDuration, forKey: "longBreakDuration")
    }
    
    // Login item management
    func isStartOnLoginEnabled() -> Bool {
        return UserDefaults.standard.bool(forKey: "startOnLogin")
    }
    
    func isActuallyInLoginItems() -> Bool {
        let script = """
        tell application "System Events"
            return name of login items contains "Refrain"
        end tell
        """
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            let output = scriptObject.executeAndReturnError(&error)
            if let error = error {
                print("Error checking login items: \(error)")
                return false
            }
            return output.booleanValue
        }
        return false
    }
    
    func setStartOnLogin(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "startOnLogin")
        
        if enabled {
            addToLoginItems()
        } else {
            removeFromLoginItems()
        }
    }
    
    private func addToLoginItems() {
        // First try the modern API
        if #available(macOS 13.0, *) {
            do {
                try SMAppService.mainApp.register()
                print("Successfully registered with SMAppService")
                return
            } catch {
                print("SMAppService failed: \(error), trying AppleScript fallback")
            }
        }
        
        // Fallback to legacy API
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.tsteele.refrain" // Updated Bundle ID
        let success = SMLoginItemSetEnabled(bundleIdentifier as CFString, true)
        
        if success {
            print("Successfully registered with SMLoginItemSetEnabled")
            return
        }
        
        // Final fallback: Use AppleScript to add to login items
        print("SMLoginItemSetEnabled failed, trying AppleScript fallback")
        addToLoginItemsViaAppleScript()
    }
    
    private func removeFromLoginItems() {
        // First try the modern API
        if #available(macOS 13.0, *) {
            do {
                try SMAppService.mainApp.unregister()
                print("Successfully unregistered with SMAppService")
                return
            } catch {
                print("SMAppService unregister failed: \(error), trying AppleScript fallback")
            }
        }
        
        // Fallback to legacy API
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.tsteele.refrain" // Updated Bundle ID
        let success = SMLoginItemSetEnabled(bundleIdentifier as CFString, false)
        
        if success {
            print("Successfully unregistered with SMLoginItemSetEnabled")
            return
        }
        
        // Final fallback: Use AppleScript to remove from login items
        print("SMLoginItemSetEnabled failed, trying AppleScript fallback")
        removeFromLoginItemsViaAppleScript()
    }
    
    private func addToLoginItemsViaAppleScript() {
        let appPath = Bundle.main.bundlePath
        
        let script = """
        tell application "System Events"
            make login item at end with properties {path:"\(appPath)", hidden:false}
        end tell
        """
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            let _ = scriptObject.executeAndReturnError(&error)
            if let error = error {
                print("AppleScript error adding login item: \(error)")
            } else {
                print("Successfully added to login items via AppleScript")
            }
        }
    }
    
    private func removeFromLoginItemsViaAppleScript() {
        let script = """
        tell application "System Events"
            delete login item "Refrain"
        end tell
        """
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            let _ = scriptObject.executeAndReturnError(&error)
            if let error = error {
                print("AppleScript error removing login item: \(error)")
            } else {
                print("Successfully removed from login items via AppleScript")
            }
        }
    }
    
    func getCurrentBreakStats() -> BreakStats {
        let now = Date()
        var nextMicroInterval: TimeInterval
        var nextLongInterval: TimeInterval

        // --- Calculate time until next Micro Break ---
        if isWaitingForBreakConfirmation && lastBreakType == .micro {
            // If we are on the micro-break confirmation screen, the *next* micro break will be a full one after this.
            nextMicroInterval = microBreakInterval 
        } else if isMicroBreakTimerPausedPendingOtherBreak {
            // Micro timer is explicitly paused (e.g., a long break is active/confirming).
            // Its remaining time is based on what was accumulated before it was paused.
            nextMicroInterval = max(0, microBreakInterval - microBreakAccumulatedElapsed)
        } else if let microStart = microBreakStartTime {
            // Micro timer is actively running or has a valid start reference for its current segment.
            let elapsedOnCurrentSegment = now.timeIntervalSince(microStart)
            nextMicroInterval = max(0, (microBreakInterval - microBreakAccumulatedElapsed) - elapsedOnCurrentSegment)
        } else {
            // Micro timer is not running and not specifically paused (e.g., app just started, or after a full stop/global pause).
            // It will start fresh, considering any (unlikely here) accumulated time.
            nextMicroInterval = max(0, microBreakInterval - microBreakAccumulatedElapsed) 
        }

        // --- Calculate time until next Long Break ---
        if isWaitingForBreakConfirmation && lastBreakType == .long {
            // If we are on the long-break confirmation screen, the *next* long break will be a full one.
            nextLongInterval = longBreakInterval
        } else if isLongBreakTimerPausedPendingOtherBreak {
            // Long timer is explicitly paused (e.g., a micro break is active/confirming).
            nextLongInterval = max(0, longBreakInterval - longBreakAccumulatedElapsed)
        } else if let longStart = longBreakStartTime {
            // Long timer is actively running or has a valid start reference.
            let elapsedOnCurrentSegment = now.timeIntervalSince(longStart)
            nextLongInterval = max(0, (longBreakInterval - longBreakAccumulatedElapsed) - elapsedOnCurrentSegment)
        } else {
            nextLongInterval = max(0, longBreakInterval - longBreakAccumulatedElapsed)
        }
        
        // Calculate max micro breaks in a long cycle
        // Avoid division by zero, though microBreakInterval should always be > 0
        let maxMicroInLong = microBreakInterval > 0 ? Int(round(longBreakInterval / microBreakInterval)) : 0
        
        // If waiting for confirmation for a specific break type, that break type's *own* timer
        // is what we're currently experiencing. So, the "time until next" for *that* type
        // should reflect the full interval that will start *after* this confirmation.
        // The other timer's remaining time is what's relevant as an upcoming event.

        return BreakStats(
            microBreaksTaken: microBreaksTakenSession,
            longBreaksTaken: longBreaksTakenSession,
            timeUntilNextMicroBreak: nextMicroInterval,
            timeUntilNextLongBreak: nextLongInterval,
            currentBreakType: isWaitingForBreakConfirmation ? lastBreakType : nil,
            microBreaksInCurrentLongCycle: microBreaksInCurrentLongCycle,
            maxMicroBreaksInLongCycle: maxMicroInLong
        )
    }
    
    func confirmBreakComplete() {
        print("[BreakTimer] confirmBreakComplete() called - start")
        
        // Capture lastBreakType before it's nilled, to reset the correct accumulated time
        let completedBreakType = lastBreakType 

        // Increment break counts based on the break that just finished
        if completedBreakType == .micro {
            microBreaksTakenSession += 1
            microBreaksInCurrentLongCycle += 1 // Increment cycle counter
            print("[BreakTimer] confirmBreakComplete: Micro break session count: \(microBreaksTakenSession), cycle count: \(microBreaksInCurrentLongCycle)")
        } else if completedBreakType == .long {
            longBreaksTakenSession += 1
            microBreaksInCurrentLongCycle = 0 // Reset cycle counter
            print("[BreakTimer] confirmBreakComplete: Long break session count: \(longBreaksTakenSession), cycle count reset to 0.")
        }

        let now = Date()
        print("[BreakTimer] now = \(now)")
        print("[BreakTimer] lastBreakType (before nil) = \(String(describing: completedBreakType))")

        // Reset accumulated time for the break type that just finished
        if completedBreakType == .micro {
            microBreakAccumulatedElapsed = 0
            print("[BreakTimer] confirmBreakComplete: Reset microBreakAccumulatedElapsed for next cycle.")
        } else if completedBreakType == .long {
            longBreakAccumulatedElapsed = 0
            print("[BreakTimer] confirmBreakComplete: Reset longBreakAccumulatedElapsed for next cycle.")
        }
        
        print("[BreakTimer] isWaitingForBreakConfirmation = \(isWaitingForBreakConfirmation)")
        isWaitingForBreakConfirmation = false
        print("[BreakTimer] lastBreakType set to nil")
        self.lastBreakType = nil // Explicitly use self.lastBreakType to ensure we are setting the property
        
        print("[BreakTimer] isPaused = \(isPaused)")
        if !isPaused {
            print("[BreakTimer] calling start()")
            start()
        } else {
            print("[BreakTimer] Was paused, so start() was not called.")
        }

        print("[BreakTimer] dispatching appDelegate.updateMenu() and currentBreakWindow = nil asynchronously")
        DispatchQueue.main.async { [weak self] in 
            guard let self = self else { 
                print("[BreakTimer] DispatchQueue.main.async: self is nil, cannot proceed")
                return 
            }
            print("[BreakTimer] DispatchQueue.main.async: calling appDelegate.updateMenu()")
            self.appDelegate?.updateMenu()

            print("[BreakTimer] DispatchQueue.main.async: Setting currentBreakWindow = nil NOW")
            print("[BreakTimer] currentBreakWindow before nil = \(String(describing: self.currentBreakWindow))")
            self.currentBreakWindow = nil
            print("[BreakTimer] currentBreakWindow after nil = \(String(describing: self.currentBreakWindow))")
        }
        print("[BreakTimer] confirmBreakComplete() finished scheduling async tasks")
    }

    func resetAndRestartTimers() {
        print("[BreakTimer] resetAndRestartTimers() called - resetting all states and restarting.")

        // 1. Call stop() to clear core timer states, accumulated values, start times, pending flags, idle flag.
        stop()

        // 2. Dismiss any current break window and clear the reference
        // Ensure this is done on the main thread if BreakWindow interacts with UI for dismissal
        DispatchQueue.main.async { [weak self] in
            if let currentWindow = self?.currentBreakWindow {
                print("[BreakTimer] resetAndRestartTimers: Dismissing current break window.")
                currentWindow.dismiss() // BreakWindow.dismiss() handles UI and nils its own window
                self?.currentBreakWindow = nil
            }
        }

        // 3. Reset break confirmation state
        isWaitingForBreakConfirmation = false
        lastBreakType = nil
        print("[BreakTimer] resetAndRestartTimers: Cleared break confirmation state.")

        // 4. Ensure global pause is off so timers will actually start
        isPaused = false 
        print("[BreakTimer] resetAndRestartTimers: Global pause set to false.")

        // isPausedDueToIdle is already handled by stop()

        // 5. Reset session break counters
        microBreaksTakenSession = 0
        longBreaksTakenSession = 0
        microBreaksInCurrentLongCycle = 0 // Reset cycle counter
        print("[BreakTimer] resetAndRestartTimers: Session break counters and micro break cycle counter reset.")

        // 6. Call start() to schedule fresh timers
        // start() itself is asynchronous and updates menu bar display upon completion of its async block.
        start()
        print("[BreakTimer] resetAndRestartTimers: Called start() to reschedule timers.")

        // 7. Explicitly update menu and menu bar display through appDelegate after reset operations
        // Although start() calls updateMenuBarDisplay(), an immediate update might be good for responsiveness of the menu item itself.
        DispatchQueue.main.async { [weak self] in // Ensure UI updates are on main thread
            print("[BreakTimer] resetAndRestartTimers: Triggering AppDelegate menu and display update.")
            self?.appDelegate?.updateMenu() // This will rebuild the menu
            self?.updateMenuBarDisplay() // This updates the status item's title
        }
        print("[BreakTimer] resetAndRestartTimers() finished.")
    }
}

enum BreakType {
    case micro, long
}

// Helper function to format TimeInterval into a human-readable string (e.g., "1h 5m 10s")
// This can be a global function or a static method within a utility class
func formatTimeInterval(_ interval: TimeInterval) -> String {
    let ti = Int(interval)
    let seconds = ti % 60
    let minutes = (ti / 60) % 60
    let hours = (ti / 3600)

    var parts: [String] = []
    if hours > 0 {
        parts.append("\(hours)h")
    }
    if minutes > 0 {
        parts.append("\(minutes)m")
    }
    if seconds > 0 || parts.isEmpty { // Show seconds if it's the only unit or if it's non-zero
        parts.append("\(seconds)s")
    }
    return parts.joined(separator: " ")
}

// Function to get system idle time in seconds
public func getSystemIdleTime() -> Double? {
    var iterator: io_iterator_t = 0
    defer { IOObjectRelease(iterator) }
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"), &iterator) == KERN_SUCCESS else { return nil }

    let entry: io_registry_entry_t = IOIteratorNext(iterator)
    defer { IOObjectRelease(entry) }
    guard entry != 0 else { return nil }

    var props: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS else { return nil }
    guard let dict = props?.takeRetainedValue() else { return nil }

    let key = "HIDIdleTime" as CFString
    guard let value = CFDictionaryGetValue(dict, Unmanaged.passUnretained(key).toOpaque()) else { return nil }
    
    let number: CFNumber = unsafeBitCast(value, to: CFNumber.self)
    var nanoseconds: Int64 = 0
    guard CFNumberGetValue(number, .sInt64Type, &nanoseconds) else { return nil }
    let interval = Double(nanoseconds) / Double(NSEC_PER_SEC)
    
    return interval
}

class BreakWindow: NSObject { // Make it subclass NSObject if not already for unowned reference
    private var window: NSWindow? // Make optional
    private var dimmingWindows: [NSWindow] = []
    private var backgroundView: NSView! // For fading background separately

    // Declare UI elements that will be set up in setupMainWindow and then laid out in setupUI
    private var titleLabel: NSTextField! 
    private var countdownLabel: NSTextField!
    // statsLabel is already declared
    // skipButton and completeButton are already declared

    private var timer: Timer?
    private var remainingTime: TimeInterval
    private let breakType: BreakType
    unowned var breakTimer: BreakTimer
    let stats: BreakStats // Store the passed stats
    var statsLabel: NSTextField!

    // private var skipButton: NSButton? // Make optional // REMOVED
    private var completeButton: NSButton? // Make optional
    
    init(duration: TimeInterval, breakType: BreakType, breakTimer: BreakTimer, stats: BreakStats) {
        self.remainingTime = duration
        self.breakType = breakType
        self.breakTimer = breakTimer
        self.stats = stats // Store stats
        super.init()
        setupWindows() 
        setupUI() // Call setupUI after windows are created
    }
    
    private func setupWindows() {
        // Get all screens
        let screens = NSScreen.screens
        // guard let mainScreen = NSScreen.main else { return } // mainScreen will be used later

        // Create dimming windows for ALL screens first
        for screen in screens {
            setupDimmingWindow(on: screen) 
        }
        
        // Then set up the main content window (which will have a clear backgroundView)
        // on the main screen.
        if let mainScreen = NSScreen.main {
            setupMainWindow(on: mainScreen) 
        }
    }
    
    private func setupMainWindow(on screen: NSScreen) {
        window = NSWindow(contentRect: screen.frame,
                         styleMask: [.borderless],
                         backing: .buffered,
                         defer: false)
        guard let strongWindow = window else { return }
        strongWindow.isReleasedWhenClosed = false
        strongWindow.level = .screenSaver
        strongWindow.backgroundColor = .clear // Main window is clear
        strongWindow.isOpaque = false // Allow transparency

        let contentView = NSView(frame: screen.frame)
        strongWindow.contentView = contentView

        // Setup the background view. It will be clear.
        backgroundView = NSView(frame: screen.frame)
        backgroundView.wantsLayer = true 
        backgroundView.layer?.backgroundColor = NSColor.clear.cgColor // Ensure it's clear
        contentView.addSubview(backgroundView) // Add it to the hierarchy

        // Create UI elements but do not add to subview or set constraints here.
        // setupUI will handle that.
        titleLabel = NSTextField(labelWithString: breakType == .micro ? 
            "Micro Break - Rest Your Eyes" : "Break Time - Step Away From Screen")
        titleLabel.font = NSFont.systemFont(ofSize: 48, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        // contentView.addSubview(titleLabel) // Moved to setupUI
        
        countdownLabel = NSTextField(labelWithString: formatTime(remainingTime))
        countdownLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 72, weight: .medium)
        countdownLabel.textColor = .white
        countdownLabel.alignment = .center
        countdownLabel.translatesAutoresizingMaskIntoConstraints = false
        // contentView.addSubview(countdownLabel) // Moved to setupUI
        
        // skipButton = NSButton(title: "Skip Break", target: self, action: #selector(skipBreak)) // REMOVED
        // skipButton?.bezelStyle = .rounded // REMOVED
        // skipButton?.translatesAutoresizingMaskIntoConstraints = false // REMOVED
        // if let sb = skipButton { contentView.addSubview(sb) } // Moved to setupUI // REMOVED
        
        completeButton = NSButton(title: "Break Complete", target: self, action: #selector(completeBreak))
        completeButton?.bezelStyle = .rounded
        completeButton?.keyEquivalent = "\r"
        completeButton?.translatesAutoresizingMaskIntoConstraints = false
        // if let cb = completeButton { contentView.addSubview(cb) } // Moved to setupUI
        
        // Remove all NSLayoutConstraint.activate from here. setupUI will handle all layout.
    }
    
    private func setupDimmingWindow(on screen: NSScreen) {
        let dimmingWindow = NSWindow(contentRect: screen.frame,
                                   styleMask: [.borderless],
                                   backing: .buffered,
                                   defer: false)
        dimmingWindow.isReleasedWhenClosed = false
        dimmingWindow.level = .screenSaver
        // Set background to opaque black; alphaValue will control transparency
        dimmingWindow.backgroundColor = NSColor.black 
        dimmingWindow.ignoresMouseEvents = true
        dimmingWindows.append(dimmingWindow)
    }
    
    func show() {
        // Set final visual states directly (no animation)
        
        // Dimming windows (now on ALL screens) are set to target alpha
        for dimmingWindow in self.dimmingWindows {
            dimmingWindow.alphaValue = 0.7 // Dimming windows are instantly at target alpha
        }
        // self.backgroundView.layer?.opacity = 1.0 // No longer needed, backgroundView is clear

        // Order dimming windows to the front first
        for dimmingWindow in self.dimmingWindows {
            dimmingWindow.orderFront(nil)
        }
        // Then order the main content window on top of everything
        window?.makeKeyAndOrderFront(nil)
        
        print("[BreakWindow] Windows shown instantly (no fade-in). Dimming on all screens, main content on top.")
        startCountdown()
    }
    
    private func startCountdown() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.remainingTime -= 1
            self.countdownLabel.stringValue = self.formatTime(self.remainingTime)
            
            if self.remainingTime <= 0 {
                // Stop countdown but don't auto-dismiss
                self.timer?.invalidate()
                self.countdownLabel.stringValue = "Break time is up!"
                self.countdownLabel.textColor = .systemGreen
                
                // Play a sound when the break is done
                NSSound(named: NSSound.Name("Glass"))?.play() // Use "Glass" for all break completions
            }
        }
    }
    
    // @objc private func skipBreak() { // REMOVED
    //     print("[BreakWindow] skipBreak() called") // REMOVED
    //     dismiss() // REMOVED
    //     breakTimer.confirmBreakComplete() // REMOVED
    // } // REMOVED
    
    @objc private func completeBreak() {
        print("[BreakWindow] completeBreak() called")
        dismiss()
        breakTimer.confirmBreakComplete()
    }
    
    func dismiss() {
        print("[BreakWindow] dismiss() called, closing windows instantly.")
        timer?.invalidate()
        timer = nil

        completeButton?.target = nil

        // Set final visual states for instant disappearance (optional, as windows will close)
        // self.backgroundView.layer?.opacity = 0.0 
        // for dimmingWindow in self.dimmingWindows {
        //    dimmingWindow.alphaValue = 0.0
        // }

        // Remove NSAnimationContext block for fade-out
        /*
        NSAnimationContext.runAnimationGroup({
            context in
            context.duration = 0.25 // Quick fade-out
            
            self.backgroundView.animator().layer?.opacity = 0.0
            
            for dimmingWindow in self.dimmingWindows {
                dimmingWindow.animator().alphaValue = 0.0
            }
        }, completionHandler: {
            print("[BreakWindow] Fade-out animation (background and dimming windows) complete.")
            self.performCloseOperations()
        })
        */

        // Close operations are now called directly for instant dismissal
        self.performCloseOperations()
        print("[BreakWindow] Windows dismissed instantly (no fade-out).")
    }
    
    private func performCloseOperations() {
        print("[BreakWindow] performCloseOperations called.")
        if let strongWindow = self.window {
            strongWindow.contentView?.subviews.forEach { $0.removeFromSuperview() }
            strongWindow.contentView = nil
            strongWindow.close()
            self.window = nil
        }
        
        let windowsToClose = self.dimmingWindows
        self.dimmingWindows.removeAll()

        for dimmingWin in windowsToClose {
            dimmingWin.contentView?.subviews.forEach { $0.removeFromSuperview() }
            dimmingWin.contentView = nil
            dimmingWin.close()
        }
    }
    
    // Make BreakWindow conform to CAAnimationDelegate
    // Add this extension if BreakWindow doesn't already conform
    // extension BreakWindow: CAAnimationDelegate { ... }
    // Actually, since BreakWindow is already NSObject, it can be a delegate.
    // We need to implement animationDidStop.

    /*
    @objc func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        // Check if it's our fade-out animation
        // A more robust way would be to give the animation a specific key or check its properties
        // For now, we assume any opacity animation stopping means we should close.
        if flag, let animationName = anim.value(forKey: "animationName") as? String, animationName == "backgroundFadeOut" { // Ensure animation completed fully and it's the correct one
            print("[BreakWindow] opacityFadeOut animationDidStop for 'backgroundFadeOut'. Performing close operations.")
            performCloseOperations()
        } else if flag {
            print("[BreakWindow] animationDidStop for an unknown animation, or not 'backgroundFadeOut'. Flag: \(flag), Name: \(String(describing: anim.value(forKey: "animationName")))")
        }
    }
    */

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    deinit {
        print("[BreakWindow] deinit called")
    }
    
    private func setupUI() {
        guard let contentView = window?.contentView else { 
            print("[BreakWindow] setupUI: contentView is nil!")
            return 
        }

        // Add all UI elements to the contentView, ensuring they are on top of backgroundView
        // backgroundView is already a subview of contentView from setupMainWindow
        contentView.addSubview(titleLabel)
        contentView.addSubview(countdownLabel)

        // Stats Label (Initialization and adding to subview)
        statsLabel = NSTextField(labelWithString: "") // Initialize
        statsLabel.font = NSFont.systemFont(ofSize: 16)
        statsLabel.textColor = .white
        statsLabel.alignment = .center
        statsLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(statsLabel)

        // Populate stats label
        let statsText = { () -> String in // Explicitly define closure return type
            let baseText = "Breaks Taken: 👀 \(stats.microBreaksTaken) | ☕️ \(stats.longBreaksTaken)\n"
            if stats.currentBreakType == .micro {
                // For micro break screen, show its cycle info and when the next long break is
                let cycleInfo = "Cycle \(stats.microBreaksInCurrentLongCycle + 1) of \(stats.maxMicroBreaksInLongCycle)"
                return baseText + "Micro Break \(cycleInfo) - Next Long Break: \(formatTimeInterval(stats.timeUntilNextLongBreak)) (After this: \(formatTimeInterval(stats.timeUntilNextMicroBreak)))"
            } else if stats.currentBreakType == .long {
                return baseText + "Next Micro Break: \(formatTimeInterval(stats.timeUntilNextMicroBreak)) (after this long break: \(formatTimeInterval(stats.timeUntilNextLongBreak)))"
            } else {
                // Fallback, should ideally not be reached if break window is shown for a specific break type
                return baseText + "Next: 👀 \(formatTimeInterval(stats.timeUntilNextMicroBreak)) | ☕️ \(formatTimeInterval(stats.timeUntilNextLongBreak))"
            }
        }() // Immediately-invoked closure
        statsLabel.stringValue = statsText
        
        statsLabel.lineBreakMode = .byWordWrapping
        statsLabel.maximumNumberOfLines = 0

        // Add buttons to contentView
        // if let sb = skipButton { contentView.addSubview(sb) } // REMOVED
        if let cb = completeButton { 
            contentView.addSubview(cb) 
        }


        // --- Layout ALL elements ---
        NSLayoutConstraint.activate([
            // Title Label
            titleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: countdownLabel.topAnchor, constant: -30), // Position above countdown

            // Countdown Label
            countdownLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            countdownLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor), // Vertically centered

            // Stats Label Constraints (Position below countdownLabel)
            statsLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            statsLabel.topAnchor.constraint(equalTo: countdownLabel.bottomAnchor, constant: 30), 
            statsLabel.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 20),
            statsLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -20),

            // Complete Button (Below statsLabel)
            completeButton!.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            completeButton!.topAnchor.constraint(equalTo: statsLabel.bottomAnchor, constant: 40),

            // Skip Button (Below completeButton) // REMOVED
            // skipButton!.centerXAnchor.constraint(equalTo: contentView.centerXAnchor), // REMOVED
            // skipButton!.topAnchor.constraint(equalTo: completeButton!.bottomAnchor, constant: 20) // REMOVED
        ])
        
        // The old code to deactivate constraints is no longer needed as setupMainWindow doesn't set them.
    }
}

class PreferencesViewController: NSViewController {
    private var microBreakIntervalField: NSTextField!
    private var microBreakDurationField: NSTextField!
    private var longBreakIntervalField: NSTextField!
    private var longBreakDurationField: NSTextField!
    private var startOnLoginCheckbox: NSButton!
    
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 350))
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadCurrentSettings()
    }
    
    private func setupUI() {
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.spacing = 20
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)
        
        // Micro break settings
        let microBreakLabel = NSTextField(labelWithString: "Micro Break Settings")
        microBreakLabel.font = NSFont.boldSystemFont(ofSize: 16)
        stackView.addArrangedSubview(microBreakLabel)
        
        let microIntervalStack = createLabeledField(label: "Interval (minutes):", 
                                                   field: &microBreakIntervalField)
        stackView.addArrangedSubview(microIntervalStack)
        
        let microDurationStack = createLabeledField(label: "Duration (seconds):", 
                                                   field: &microBreakDurationField)
        stackView.addArrangedSubview(microDurationStack)
        
        // Long break settings
        let longBreakLabel = NSTextField(labelWithString: "Long Break Settings")
        longBreakLabel.font = NSFont.boldSystemFont(ofSize: 16)
        stackView.addArrangedSubview(longBreakLabel)
        
        let longIntervalStack = createLabeledField(label: "Interval (minutes):", 
                                                  field: &longBreakIntervalField)
        stackView.addArrangedSubview(longIntervalStack)
        
        let longDurationStack = createLabeledField(label: "Duration (minutes):", 
                                                  field: &longBreakDurationField)
        stackView.addArrangedSubview(longDurationStack)
        
        // Start on Login checkbox
        let startOnLoginLabel = NSTextField(labelWithString: "General Settings")
        startOnLoginLabel.font = NSFont.boldSystemFont(ofSize: 16)
        stackView.addArrangedSubview(startOnLoginLabel)
        
        startOnLoginCheckbox = NSButton(checkboxWithTitle: "Start Refrain on Login", target: self, action: #selector(toggleStartOnLogin)) // Updated App Name
        stackView.addArrangedSubview(startOnLoginCheckbox)
        
        // Save button
        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveSettings))
        saveButton.bezelStyle = .rounded
        stackView.addArrangedSubview(saveButton)
        
        // Layout
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stackView.widthAnchor.constraint(equalToConstant: 300)
        ])
    }
    
    private func createLabeledField(label: String, field: inout NSTextField!) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 10
        
        let labelView = NSTextField(labelWithString: label)
        labelView.widthAnchor.constraint(equalToConstant: 150).isActive = true
        
        field = NSTextField()
        field.widthAnchor.constraint(equalToConstant: 100).isActive = true
        
        stack.addArrangedSubview(labelView)
        stack.addArrangedSubview(field)
        
        return stack
    }
    
    private func loadCurrentSettings() {
        let appDelegate = NSApp.delegate as! AppDelegate
        let breakTimer = appDelegate.breakTimer!
        
        microBreakIntervalField.stringValue = String(Int(breakTimer.microBreakInterval / 60))
        microBreakDurationField.stringValue = String(Int(breakTimer.microBreakDuration))
        longBreakIntervalField.stringValue = String(Int(breakTimer.longBreakInterval / 60))
        longBreakDurationField.stringValue = String(Int(breakTimer.longBreakDuration / 60))
        
        // Check both the saved preference and actual login items status
        let savedPreference = breakTimer.isStartOnLoginEnabled()
        let actuallyInLoginItems = breakTimer.isActuallyInLoginItems()
        
        startOnLoginCheckbox.state = actuallyInLoginItems ? .on : .off
        
        // If there's a mismatch, update the saved preference to match reality
        if savedPreference != actuallyInLoginItems {
            UserDefaults.standard.set(actuallyInLoginItems, forKey: "startOnLogin")
        }
        
        // Update the checkbox title to show status
        if actuallyInLoginItems {
            startOnLoginCheckbox.title = "Start Refrain on Login ✅" // Updated App Name
        } else {
            startOnLoginCheckbox.title = "Start Refrain on Login" // Updated App Name
        }
    }
    
    @objc private func toggleStartOnLogin() {
        let appDelegate = NSApp.delegate as! AppDelegate
        let breakTimer = appDelegate.breakTimer!
        let isEnabled = startOnLoginCheckbox.state == .on
        
        breakTimer.setStartOnLogin(isEnabled)
        
        // Give the system a moment to process, then check if it worked
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let actuallyInLoginItems = breakTimer.isActuallyInLoginItems()
            
            if actuallyInLoginItems == isEnabled {
                // Success!
                self.startOnLoginCheckbox.title = actuallyInLoginItems ? 
                    "Start Refrain on Login ✅" : "Start Refrain on Login" // Updated App Name
            } else {
                // Failed - show manual instructions
                self.showManualInstructions()
                // Reset checkbox to actual state
                self.startOnLoginCheckbox.state = actuallyInLoginItems ? .on : .off
                self.startOnLoginCheckbox.title = actuallyInLoginItems ? 
                    "Start Refrain on Login ✅" : "Start Refrain on Login" // Updated App Name
            }
        }
    }
    
    private func showManualInstructions() {
        let alert = NSAlert()
        alert.messageText = "Manual Setup Required"
        alert.informativeText = """
        The automatic login item setup didn't work. You can add Refrain to login items manually:
        
        1. Open System Preferences → Users & Groups
        2. Click your user account
        3. Click "Login Items" tab
        4. Click the "+" button
        5. Navigate to and select Refrain.app
        
        Or copy Refrain.app to your Applications folder first, then try again.
        """ // Updated App Name
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    @objc private func saveSettings() {
        let appDelegate = NSApp.delegate as! AppDelegate
        let breakTimer = appDelegate.breakTimer!
        
        if let microInterval = Double(microBreakIntervalField.stringValue) {
            breakTimer.microBreakInterval = microInterval * 60
        }
        if let microDuration = Double(microBreakDurationField.stringValue) {
            breakTimer.microBreakDuration = microDuration
        }
        if let longInterval = Double(longBreakIntervalField.stringValue) {
            breakTimer.longBreakInterval = longInterval * 60
        }
        if let longDuration = Double(longBreakDurationField.stringValue) {
            breakTimer.longBreakDuration = longDuration * 60
        }
        
        // Save start on login preference
        let isStartOnLoginEnabled = startOnLoginCheckbox.state == .on
        breakTimer.setStartOnLogin(isStartOnLoginEnabled)
        
        breakTimer.saveSettings()
        breakTimer.stop()
        breakTimer.start()
        
        view.window?.close()
    }
}

// App initialization
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run() 