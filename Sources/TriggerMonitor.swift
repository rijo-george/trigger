import AppKit
import CoreWLAN
import IOKit.ps

// MARK: - Watches for trigger conditions and fires intentions

class TriggerMonitor {
    private let store: IntentionStore
    private var timer: Timer?
    private var appActivateObserver: Any?
    private var appTerminateObserver: Any?
    private var screenLockObserver: Any?
    private var screenWakeObserver: Any?
    private var downloadMonitor: DispatchSourceFileSystemObject?
    private var downloadFD: Int32 = -1

    private var lastActivityTime = Date()
    private var wasIdle = false
    private let idleThreshold: TimeInterval = 120

    // Wi-Fi state
    private var lastSSID: String?

    // Power state
    private var lastPowerConnected: Bool?

    // Display state
    private var lastDisplayCount: Int = 0

    // Download tracking
    private var knownDownloads: Set<String> = []

    // Recurring tracking
    private var firedRecurringToday: Set<String> = []
    private var lastRecurringDate: Date?

    // Battery tracking
    private var lowBatteryFired: Set<String> = []

    var onFire: ((Intention) -> Void)?

    init(store: IntentionStore) {
        self.store = store
    }

    func start() {
        // Snapshot initial state
        lastSSID = currentSSID()
        lastPowerConnected = isPowerConnected()
        lastDisplayCount = displayCount()
        snapshotDownloads()

        // Main tick every 5 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.tick()
        }

        // App activations
        appActivateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier
            else { return }
            self?.onAppActivated(bundleID)
        }

        // App terminations
        appTerminateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier
            else { return }
            self?.onAppTerminated(bundleID)
        }

        // Screen lock
        screenLockObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.onScreenLock()
        }

        // Screen wake
        screenWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.onReturnFromIdle()
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.recordActivity()
        }

        // Downloads folder monitor
        startDownloadMonitor()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let obs = appActivateObserver { NSWorkspace.shared.notificationCenter.removeObserver(obs) }
        if let obs = appTerminateObserver { NSWorkspace.shared.notificationCenter.removeObserver(obs) }
        if let obs = screenLockObserver { DistributedNotificationCenter.default().removeObserver(obs) }
        if let obs = screenWakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(obs) }
        downloadMonitor?.cancel()
    }

    func recordActivity() {
        let wasIdleBefore = wasIdle
        lastActivityTime = Date()
        wasIdle = false
        if wasIdleBefore { onReturnFromIdle() }
    }

    // MARK: - Current Wi-Fi SSID

    func currentSSID() -> String? {
        CWWiFiClient.shared().interface()?.ssid()
    }

    // MARK: - Main tick

    private func tick() {
        let now = Date()

        // Reset recurring tracking at midnight
        let today = Calendar.current.startOfDay(for: now)
        if lastRecurringDate != today {
            firedRecurringToday.removeAll()
            lowBatteryFired.removeAll()
            lastRecurringDate = today
        }

        // Check idle state
        if now.timeIntervalSince(lastActivityTime) > idleThreshold {
            wasIdle = true
        }

        store.checkSnoozed()

        // Time-based and recurring
        for intention in store.pending {
            switch intention.trigger {
            case .time(let fireDate):
                if fireDate <= now { fire(intention) }
            case .recurring(let hour, let minute, let weekdaysOnly):
                checkRecurring(intention: intention, hour: hour, minute: minute, weekdaysOnly: weekdaysOnly, now: now)
            default:
                break
            }
        }

        // Wi-Fi changes
        checkWiFi()

        // Power changes
        checkPower()

        // Display changes
        checkDisplays()

        // Battery level
        checkBattery()
    }

    // MARK: - Wi-Fi / Location

    private func checkWiFi() {
        let current = currentSSID()
        defer { lastSSID = current }
        guard current != lastSSID else { return }

        for intention in store.pending {
            switch intention.trigger {
            case .wifiArrive(let ssid, _):
                if current == ssid && lastSSID != ssid {
                    fire(intention)
                }
            case .wifiLeave(let ssid, _):
                if lastSSID == ssid && current != ssid {
                    fire(intention)
                }
            default: break
            }
        }
    }

    // MARK: - Power

    private func isPowerConnected() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [Any],
              !sources.isEmpty
        else { return true } // Assume desktop (always plugged in)

        for source in sources {
            if let desc = IOPSGetPowerSourceDescription(snapshot, source as CFTypeRef)?.takeUnretainedValue() as? [String: Any] {
                if let powerSource = desc[kIOPSPowerSourceStateKey] as? String {
                    return powerSource == kIOPSACPowerValue
                }
            }
        }
        return true
    }

    private func checkPower() {
        let connected = isPowerConnected()
        defer { lastPowerConnected = connected }
        guard let last = lastPowerConnected, connected != last else { return }

        for intention in store.pending {
            switch intention.trigger {
            case .powerConnect:
                if connected && !last { fire(intention) }
            case .powerDisconnect:
                if !connected && last { fire(intention) }
            default: break
            }
        }
    }

    // MARK: - Battery

    private func checkBattery() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [Any]
        else { return }

        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source as CFTypeRef)?.takeUnretainedValue() as? [String: Any],
                  let capacity = desc[kIOPSCurrentCapacityKey] as? Int
            else { continue }

            for intention in store.pending {
                if case .batteryLow(let threshold) = intention.trigger,
                   capacity <= threshold,
                   !lowBatteryFired.contains(intention.id) {
                    lowBatteryFired.insert(intention.id)
                    fire(intention)
                }
            }
        }
    }

    // MARK: - External display

    private func displayCount() -> Int {
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(10, nil, &displayCount)
        return Int(displayCount)
    }

    private func checkDisplays() {
        let current = displayCount()
        defer { lastDisplayCount = current }
        guard current != lastDisplayCount else { return }

        let connected = current > lastDisplayCount
        for intention in store.pending {
            switch intention.trigger {
            case .displayConnect:
                if connected { fire(intention) }
            case .displayDisconnect:
                if !connected { fire(intention) }
            default: break
            }
        }
    }

    // MARK: - Downloads folder

    private func snapshotDownloads() {
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        if let files = try? FileManager.default.contentsOfDirectory(at: downloadsURL, includingPropertiesForKeys: nil) {
            knownDownloads = Set(files.map(\.lastPathComponent))
        }
    }

    private func startDownloadMonitor() {
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let fd = open(downloadsURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        downloadFD = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write], queue: .main)
        source.setEventHandler { [weak self] in
            self?.checkNewDownloads()
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        downloadMonitor = source
    }

    private func checkNewDownloads() {
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        guard let files = try? FileManager.default.contentsOfDirectory(at: downloadsURL, includingPropertiesForKeys: nil)
        else { return }

        let currentFiles = Set(files.map(\.lastPathComponent))
        let newFiles = currentFiles.subtracting(knownDownloads)
            .filter { !$0.hasPrefix(".") && !$0.hasSuffix(".download") && !$0.hasSuffix(".crdownload") }

        if !newFiles.isEmpty {
            knownDownloads = currentFiles
            for intention in store.pending {
                if case .newDownload = intention.trigger {
                    fire(intention)
                }
            }
        } else {
            knownDownloads = currentFiles
        }
    }

    // MARK: - Recurring

    private func checkRecurring(intention: Intention, hour: Int, minute: Int, weekdaysOnly: Bool, now: Date) {
        guard !firedRecurringToday.contains(intention.id) else { return }
        let cal = Calendar.current
        let currentHour = cal.component(.hour, from: now)
        let currentMinute = cal.component(.minute, from: now)
        let weekday = cal.component(.weekday, from: now)

        if weekdaysOnly && (weekday == 1 || weekday == 7) { return }

        if currentHour == hour && currentMinute == minute {
            firedRecurringToday.insert(intention.id)
            onFire?(intention)
        }
    }

    // MARK: - App events

    private func onAppActivated(_ bundleID: String) {
        recordActivity()
        for intention in store.pending {
            if case .app(let targetBundle, _) = intention.trigger, targetBundle == bundleID {
                fire(intention)
            }
        }
    }

    private func onAppTerminated(_ bundleID: String) {
        for intention in store.pending {
            if case .appClose(let targetBundle, _) = intention.trigger, targetBundle == bundleID {
                fire(intention)
            }
        }
    }

    // MARK: - Screen events

    private func onScreenLock() {
        for intention in store.pending {
            if case .screenLock = intention.trigger { fire(intention) }
        }
    }

    private func onReturnFromIdle() {
        for intention in store.pending {
            if case .returnFromIdle = intention.trigger { fire(intention) }
        }
    }

    // MARK: - Fire

    private func fire(_ intention: Intention) {
        store.markFired(intention.id)
        onFire?(intention)
    }
}
