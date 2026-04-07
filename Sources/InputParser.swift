import AppKit

// MARK: - Parse "what → when" input

struct InputParser {
    /// Parse input like "Reply to Sarah → 3pm" into (what, triggerCondition)
    static func parse(_ input: String) -> (what: String, trigger: TriggerCondition)? {
        // Split on → or -> or >>
        let separators = ["→", "->", ">>"]
        var what = input
        var when = ""

        for sep in separators {
            if let range = input.range(of: sep) {
                what = String(input[input.startIndex..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                when = String(input[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        guard !what.isEmpty else { return nil }
        guard !when.isEmpty else { return (what, .manual) }

        // Try parsing the "when" part
        let whenLower = when.lowercased()

        // Return from idle
        if whenLower.contains("back") || whenLower.contains("return") || whenLower.contains("later") {
            return (what, .returnFromIdle)
        }

        // Relative time: "in 30 min", "in 1 hour", "in 2h"
        if let trigger = parseRelativeTime(whenLower) {
            return (what, trigger)
        }

        // Absolute time: "3pm", "15:00", "3:30pm"
        if let trigger = parseAbsoluteTime(whenLower) {
            return (what, trigger)
        }

        // App name: try to match running or known apps
        if let trigger = parseAppName(when) {
            return (what, trigger)
        }

        // Fallback: treat as manual with the when as part of what
        return (what, .manual)
    }

    // MARK: - Time parsing

    private static func parseRelativeTime(_ input: String) -> TriggerCondition? {
        // "in 30 min", "in 1 hour", "in 2h", "in 30m"
        let pattern = #"in\s+(\d+)\s*(m|min|mins|minutes|h|hr|hrs|hours?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)),
              match.numberOfRanges >= 3
        else { return nil }

        let numRange = Range(match.range(at: 1), in: input)!
        let unitRange = Range(match.range(at: 2), in: input)!
        let num = Double(input[numRange]) ?? 0
        let unit = String(input[unitRange]).lowercased()

        let seconds: Double
        if unit.starts(with: "h") {
            seconds = num * 3600
        } else {
            seconds = num * 60
        }

        return .time(Date().addingTimeInterval(seconds))
    }

    private static func parseAbsoluteTime(_ input: String) -> TriggerCondition? {
        let formats = [
            "h:mm a", "h:mma", "ha", "h a",
            "HH:mm", "H:mm",
            "h:mm", // ambiguous, assume PM if in the past
        ]

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")

        let cleaned = input
            .replacingOccurrences(of: "at ", with: "")
            .replacingOccurrences(of: "by ", with: "")
            .trimmingCharacters(in: .whitespaces)

        for fmt in formats {
            df.dateFormat = fmt
            if let parsed = df.date(from: cleaned) {
                // Combine with today's date
                let cal = Calendar.current
                let now = Date()
                var comps = cal.dateComponents([.year, .month, .day], from: now)
                let timeComps = cal.dateComponents([.hour, .minute], from: parsed)
                comps.hour = timeComps.hour
                comps.minute = timeComps.minute

                if var date = cal.date(from: comps) {
                    // If time is in the past, bump to tomorrow
                    if date < now {
                        date = cal.date(byAdding: .day, value: 1, to: date)!
                    }
                    return .time(date)
                }
            }
        }

        return nil
    }

    // MARK: - App matching

    private static let knownApps: [String: String] = [
        "slack": "com.tinyspeck.slackmacgap",
        "xcode": "com.apple.dt.Xcode",
        "safari": "com.apple.Safari",
        "chrome": "com.google.Chrome",
        "firefox": "org.mozilla.firefox",
        "vscode": "com.microsoft.VSCode",
        "vs code": "com.microsoft.VSCode",
        "code": "com.microsoft.VSCode",
        "figma": "com.figma.Desktop",
        "notion": "notion.id",
        "linear": "com.linear",
        "terminal": "com.apple.Terminal",
        "iterm": "com.googlecode.iterm2",
        "messages": "com.apple.MobileSMS",
        "mail": "com.apple.mail",
        "finder": "com.apple.finder",
        "notes": "com.apple.Notes",
        "zoom": "us.zoom.xos",
        "teams": "com.microsoft.teams2",
        "discord": "com.hnc.Discord",
        "spotify": "com.spotify.client",
        "music": "com.apple.Music",
        "arc": "company.thebrowser.Browser",
        "cursor": "com.todesktop.230313mzl4w4u92",
        "claude": "com.anthropic.claudefordesktop",
    ]

    private static func parseAppName(_ input: String) -> TriggerCondition? {
        let cleaned = input
            .replacingOccurrences(of: "when I open ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "when i open ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "open ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "opening ", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespaces)

        let lower = cleaned.lowercased()

        // Check known apps first
        if let bundleID = knownApps[lower] {
            return .app(bundleID: bundleID, name: cleaned.capitalized)
        }

        // Try matching running applications
        let running = NSWorkspace.shared.runningApplications
        for app in running {
            guard let name = app.localizedName, let bid = app.bundleIdentifier else { continue }
            if name.lowercased() == lower || name.lowercased().contains(lower) {
                return .app(bundleID: bid, name: name)
            }
        }

        return nil
    }
}
