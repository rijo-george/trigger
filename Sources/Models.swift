import Foundation

// MARK: - Data Model

struct Intention: Codable, Identifiable {
    var id: String
    var what: String
    var trigger: TriggerCondition
    var created: Date
    var status: IntentionStatus

    var isActive: Bool {
        switch status {
        case .pending, .snoozed: return true
        case .done, .fired: return false
        }
    }
}

enum TriggerCondition: Codable, Equatable {
    case time(Date)
    case app(bundleID: String, name: String)
    case appClose(bundleID: String, name: String)
    case returnFromIdle
    case screenLock
    case recurring(hour: Int, minute: Int, weekdaysOnly: Bool)
    case wifiArrive(ssid: String, locationName: String)
    case wifiLeave(ssid: String, locationName: String)
    case powerConnect
    case powerDisconnect
    case batteryLow(percent: Int)
    case displayConnect
    case displayDisconnect
    case newDownload
    case manual

    var label: String {
        switch self {
        case .time(let date):
            let f = DateFormatter()
            f.dateFormat = Calendar.current.isDateInToday(date) ? "h:mm a" : "MMM d, h:mm a"
            return f.string(from: date)
        case .app(_, let name): return "open \(name)"
        case .appClose(_, let name): return "close \(name)"
        case .returnFromIdle: return "when back"
        case .screenLock: return "leaving"
        case .recurring(let hour, let minute, let weekdaysOnly):
            let h = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour)
            let ampm = hour >= 12 ? "PM" : "AM"
            let days = weekdaysOnly ? "weekdays" : "daily"
            return String(format: "%d:%02d %@ %@", h, minute, ampm, days)
        case .wifiArrive(_, let name): return "arrive \(name)"
        case .wifiLeave(_, let name): return "leave \(name)"
        case .powerConnect: return "plugged in"
        case .powerDisconnect: return "unplugged"
        case .batteryLow(let pct): return "battery ≤\(pct)%"
        case .displayConnect: return "docked"
        case .displayDisconnect: return "undocked"
        case .newDownload: return "new download"
        case .manual: return "manual"
        }
    }

    var icon: String {
        switch self {
        case .time: return "clock"
        case .app: return "app.badge"
        case .appClose: return "xmark.app"
        case .returnFromIdle: return "arrow.uturn.backward"
        case .screenLock: return "lock"
        case .recurring: return "repeat"
        case .wifiArrive: return "mappin.and.ellipse"
        case .wifiLeave: return "figure.walk.departure"
        case .powerConnect: return "bolt.fill"
        case .powerDisconnect: return "bolt.slash"
        case .batteryLow: return "battery.25percent"
        case .displayConnect: return "display"
        case .displayDisconnect: return "display.trianglebadge.exclamationmark"
        case .newDownload: return "arrow.down.circle"
        case .manual: return "tray"
        }
    }
}

enum IntentionStatus: Codable, Equatable {
    case pending
    case fired
    case snoozed(until: Date)
    case done
}

// MARK: - Store

class IntentionStore: ObservableObject {
    @Published var intentions: [Intention] = []

    private let dataDir: URL
    private let dataFile: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        dataDir = home.appendingPathComponent(".trigger")
        dataFile = dataDir.appendingPathComponent("data.json")
        load()
    }

    var pending: [Intention] {
        intentions.filter { $0.isActive }
            .sorted { $0.created > $1.created }
    }

    var pendingCount: Int { pending.count }

    // MARK: - Actions

    func add(what: String, trigger: TriggerCondition) {
        let intention = Intention(
            id: UUID().uuidString,
            what: what,
            trigger: trigger,
            created: Date(),
            status: .pending
        )
        intentions.append(intention)
        save()
    }

    func markDone(_ id: String) {
        guard let idx = intentions.firstIndex(where: { $0.id == id }) else { return }
        intentions[idx].status = .done
        save()
    }

    func markFired(_ id: String) {
        guard let idx = intentions.firstIndex(where: { $0.id == id }) else { return }
        intentions[idx].status = .fired
        save()
    }

    func snooze(_ id: String, minutes: Int) {
        guard let idx = intentions.firstIndex(where: { $0.id == id }) else { return }
        intentions[idx].status = .snoozed(until: Date().addingTimeInterval(Double(minutes * 60)))
        save()
    }

    func delete(_ id: String) {
        intentions.removeAll { $0.id == id }
        save()
    }

    // Check snoozed items that should reactivate
    func checkSnoozed() {
        var changed = false
        for i in intentions.indices {
            if case .snoozed(let until) = intentions[i].status, until <= Date() {
                intentions[i].status = .pending
                changed = true
            }
        }
        if changed { save() }
    }

    // MARK: - Persistence

    func load() {
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        guard let raw = try? Data(contentsOf: dataFile),
              let decoded = try? JSONDecoder().decode([Intention].self, from: raw)
        else { return }
        intentions = decoded
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let raw = try? encoder.encode(intentions) else { return }
        try? raw.write(to: dataFile, options: .atomic)
    }
}
