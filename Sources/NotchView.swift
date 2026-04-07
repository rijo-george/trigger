import SwiftUI
import AppKit

// MARK: - Main notch content

struct NotchContentView: View {
    @ObservedObject var controller: NotchPanelController

    var body: some View {
        ZStack {
            if controller.isExpanded {
                ExpandedView(controller: controller)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            } else {
                CollapsedView(count: controller.store.pendingCount)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: controller.isExpanded)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                Color.black.opacity(0.6)
            }
            .clipShape(RoundedRectangle(cornerRadius: controller.isExpanded ? 18 : 8))
        )
        .overlay(
            RoundedRectangle(cornerRadius: controller.isExpanded ? 18 : 8)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        )
    }
}

// MARK: - Collapsed pill

struct CollapsedView: View {
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(count > 0 ? Color.cyan : Color.gray.opacity(0.4))
                .frame(width: 5, height: 5)
                .shadow(color: count > 0 ? .cyan.opacity(0.6) : .clear, radius: 4)

            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Expanded view

struct ExpandedView: View {
    @ObservedObject var controller: NotchPanelController

    var body: some View {
        VStack(spacing: 0) {
            // Notch bridge
            Rectangle()
                .fill(.black)
                .frame(height: 8)

            if let fired = controller.firedIntention {
                FiredView(intention: fired, controller: controller)
            } else {
                NormalView(controller: controller)
            }
        }
    }
}

// MARK: - Capture flow state

enum CaptureStep {
    case input
    case pickTrigger
    case pickTime
    case pickExactTime
    case pickApp
    case pickAppClose
    case pickRecurring
    case pickLocation
    case pickBattery
}

// MARK: - Normal mode (guided capture + queue)

struct NormalView: View {
    @ObservedObject var controller: NotchPanelController
    @State private var inputText = ""
    @State private var step: CaptureStep = .input
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Capture area
            switch step {
            case .input:
                inputStep
            case .pickTrigger:
                triggerPickerStep
            case .pickTime:
                timePickerStep
            case .pickExactTime:
                exactTimePickerStep
            case .pickApp:
                appPickerStep
            case .pickAppClose:
                appClosePickerStep
            case .pickRecurring:
                recurringPickerStep
            case .pickLocation:
                locationPickerStep
            case .pickBattery:
                batteryPickerStep
            }

            // Queue
            if step == .input && !controller.store.pending.isEmpty {
                Divider()
                    .background(.white.opacity(0.1))
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(controller.store.pending.prefix(5)) { intention in
                            IntentionRow(intention: intention, onDone: {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    controller.store.markDone(intention.id)
                                }
                            }, onDelete: {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    controller.store.delete(intention.id)
                                }
                            })
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
            }

            if step == .input && controller.store.pending.isEmpty {
                VStack(spacing: 4) {
                    Text("No pending triggers")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.25))
                    Text("Type what you need to do")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.15))
                }
                .frame(maxHeight: .infinity)
            }

            Spacer(minLength: 4)
        }
    }

    // MARK: - Step 1: What

    private var inputStep: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.cyan)

            TextField("What do you need to do?", text: $inputText)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .focused($inputFocused)
                .onSubmit {
                    guard !inputText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        step = .pickTrigger
                    }
                }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity(0.08))
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                inputFocused = true
            }
        }
    }

    // MARK: - Step 2: When (trigger picker)

    private var triggerPickerStep: some View {
        VStack(spacing: 10) {
            // Show what they typed
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.cyan)
                Text(inputText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                Spacer()
                Image(systemName: "pencil")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(.white.opacity(0.06)))
                    .contentShape(Circle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            step = .input
                        }
                    }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            // "When?" label
            Text("When should this trigger?")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.3))
                .padding(.top, 2)

            // Trigger options grid
            VStack(spacing: 5) {
                // Row 1: Time triggers
                HStack(spacing: 5) {
                    TriggerOption(icon: "clock", label: "In...", color: .orange) {
                        animateTo(.pickTime)
                    }
                    TriggerOption(icon: "clock.badge", label: "At time", color: .orange) {
                        animateTo(.pickExactTime)
                    }
                    TriggerOption(icon: "repeat", label: "Daily", color: .mint) {
                        animateTo(.pickRecurring)
                    }
                }
                // Row 2: App triggers
                HStack(spacing: 5) {
                    TriggerOption(icon: "app.badge", label: "Open app", color: .cyan) {
                        animateTo(.pickApp)
                    }
                    TriggerOption(icon: "xmark.app", label: "Close app", color: .pink) {
                        animateTo(.pickAppClose)
                    }
                    TriggerOption(icon: "lock", label: "Leaving", color: .indigo) {
                        submit(.screenLock)
                    }
                }
                // Row 3: Context triggers
                HStack(spacing: 5) {
                    TriggerOption(icon: "mappin.and.ellipse", label: "Location", color: .green) {
                        animateTo(.pickLocation)
                    }
                    TriggerOption(icon: "battery.50percent", label: "Battery", color: .yellow) {
                        animateTo(.pickBattery)
                    }
                    TriggerOption(icon: "display", label: "Docked", color: .teal) {
                        submit(.displayConnect)
                    }
                }
                // Row 4: Quick triggers
                HStack(spacing: 5) {
                    TriggerOption(icon: "arrow.down.circle", label: "Download", color: .blue) {
                        submit(.newDownload)
                    }
                    TriggerOption(icon: "arrow.uturn.backward", label: "I'm back", color: .purple) {
                        submit(.returnFromIdle)
                    }
                    TriggerOption(icon: "tray", label: "Queue", color: .gray) {
                        submit(.manual)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
    }

    // MARK: - Step 2a: Time picker

    private var timePickerStep: some View {
        VStack(spacing: 10) {
            // Header
            HStack {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            step = .pickTrigger
                        }
                    }

                Text(inputText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            Text("Remind me in...")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.3))

            // Quick time options
            LazyVGrid(columns: [
                GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())
            ], spacing: 6) {
                TimeChip(label: "5 min", minutes: 5) { submit(.time(Date().addingTimeInterval(5 * 60))) }
                TimeChip(label: "15 min", minutes: 15) { submit(.time(Date().addingTimeInterval(15 * 60))) }
                TimeChip(label: "30 min", minutes: 30) { submit(.time(Date().addingTimeInterval(30 * 60))) }
                TimeChip(label: "1 hour", minutes: 60) { submit(.time(Date().addingTimeInterval(60 * 60))) }
                TimeChip(label: "2 hours", minutes: 120) { submit(.time(Date().addingTimeInterval(120 * 60))) }
                TimeChip(label: "Tomorrow", minutes: 0) {
                    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!
                        .addingTimeInterval(9 * 3600) // 9am tomorrow
                    submit(.time(tomorrow))
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
    }

    // MARK: - Step 2b: App picker

    private var appPickerStep: some View {
        VStack(spacing: 10) {
            // Header
            HStack {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            step = .pickTrigger
                        }
                    }

                Text(inputText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            Text("When I open...")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.3))

            // Running apps grid
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())
                ], spacing: 8) {
                    ForEach(runningApps, id: \.bundleID) { app in
                        AppChip(app: app) {
                            submit(.app(bundleID: app.bundleID, name: app.name))
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
    }

    // MARK: - Step 2c: Close app picker

    private var appClosePickerStep: some View {
        VStack(spacing: 10) {
            stepHeader(title: "When I close...")

            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())
                ], spacing: 8) {
                    ForEach(runningApps, id: \.bundleID) { app in
                        AppChip(app: app) {
                            submit(.appClose(bundleID: app.bundleID, name: app.name))
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
    }

    // MARK: - Step 2a2: Exact time picker

    @State private var selectedHour = Calendar.current.component(.hour, from: Date())
    @State private var selectedMinute = 0

    private var exactTimePickerStep: some View {
        VStack(spacing: 10) {
            stepHeader(title: "At what time?")

            // Hour : Minute pickers
            HStack(spacing: 4) {
                Picker("", selection: $selectedHour) {
                    ForEach(0..<24, id: \.self) { h in
                        let display = h == 0 ? "12 AM" : h < 12 ? "\(h) AM" : h == 12 ? "12 PM" : "\(h-12) PM"
                        Text(display).tag(h)
                    }
                }
                .frame(width: 90)
                .labelsHidden()

                Text(":")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))

                Picker("", selection: $selectedMinute) {
                    ForEach([0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55], id: \.self) { m in
                        Text(String(format: "%02d", m)).tag(m)
                    }
                }
                .frame(width: 70)
                .labelsHidden()
            }

            // Quick presets
            HStack(spacing: 6) {
                ExactTimePreset(label: "End of day", hour: 17, minute: 0) { h, m in submitExactTime(h, m) }
                ExactTimePreset(label: "Lunch", hour: 12, minute: 0) { h, m in submitExactTime(h, m) }
                ExactTimePreset(label: "9 AM", hour: 9, minute: 0) { h, m in submitExactTime(h, m) }
            }
            .padding(.horizontal, 12)

            // Set button
            Text("Set trigger")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Capsule().fill(.orange.opacity(0.3)))
                .overlay(Capsule().strokeBorder(.orange.opacity(0.3), lineWidth: 0.5))
                .contentShape(Capsule())
                .onTapGesture { submitExactTime(selectedHour, selectedMinute) }
            .padding(.horizontal, 24)
            .padding(.bottom, 10)
        }
    }

    private func submitExactTime(_ hour: Int, _ minute: Int) {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = hour
        comps.minute = minute
        if var date = cal.date(from: comps) {
            if date < Date() {
                date = cal.date(byAdding: .day, value: 1, to: date)!
            }
            submit(.time(date))
        }
    }

    // MARK: - Step 2d: Recurring picker

    @State private var recurHour = 9
    @State private var recurMinute = 0
    @State private var weekdaysOnly = true

    private var recurringPickerStep: some View {
        VStack(spacing: 10) {
            stepHeader(title: "Every day at...")

            HStack(spacing: 4) {
                Picker("", selection: $recurHour) {
                    ForEach(0..<24, id: \.self) { h in
                        let display = h == 0 ? "12 AM" : h < 12 ? "\(h) AM" : h == 12 ? "12 PM" : "\(h-12) PM"
                        Text(display).tag(h)
                    }
                }
                .frame(width: 90)
                .labelsHidden()

                Text(":")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))

                Picker("", selection: $recurMinute) {
                    ForEach([0, 15, 30, 45], id: \.self) { m in
                        Text(String(format: "%02d", m)).tag(m)
                    }
                }
                .frame(width: 70)
                .labelsHidden()
            }

            // Weekdays toggle
            HStack(spacing: 12) {
                DayToggle(label: "Weekdays only", isOn: true, selected: weekdaysOnly) {
                    weekdaysOnly = true
                }
                DayToggle(label: "Every day", isOn: false, selected: !weekdaysOnly) {
                    weekdaysOnly = false
                }
            }
            .padding(.horizontal, 12)

            Text("Set recurring trigger")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Capsule().fill(.mint.opacity(0.3)))
                .overlay(Capsule().strokeBorder(.mint.opacity(0.3), lineWidth: 0.5))
                .contentShape(Capsule())
                .onTapGesture {
                    submit(.recurring(hour: recurHour, minute: recurMinute, weekdaysOnly: weekdaysOnly))
                }
            .padding(.horizontal, 24)
            .padding(.bottom, 10)
        }
    }

    // MARK: - Step: Location (Wi-Fi)

    private var locationPickerStep: some View {
        VStack(spacing: 10) {
            stepHeader(title: "Location trigger")

            // Current Wi-Fi
            if let ssid = controller.monitor.currentSSID() {
                HStack(spacing: 6) {
                    Image(systemName: "wifi")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.green)
                    Text("Current: \(ssid)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.vertical, 4)

                HStack(spacing: 6) {
                    LocationButton(label: "Arrive here", icon: "mappin.and.ellipse", color: .green) {
                        submit(.wifiArrive(ssid: ssid, locationName: ssid))
                    }
                    LocationButton(label: "Leave here", icon: "figure.walk.departure", color: .orange) {
                        submit(.wifiLeave(ssid: ssid, locationName: ssid))
                    }
                }
                .padding(.horizontal, 12)
            } else {
                Text("No Wi-Fi connected")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
            }

            Spacer(minLength: 4)
        }
        .padding(.bottom, 10)
    }

    // MARK: - Step: Battery

    private var batteryPickerStep: some View {
        VStack(spacing: 10) {
            stepHeader(title: "Battery trigger")

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    TriggerOption(icon: "bolt.fill", label: "Plugged in", color: .green) {
                        submit(.powerConnect)
                    }
                    TriggerOption(icon: "bolt.slash", label: "Unplugged", color: .orange) {
                        submit(.powerDisconnect)
                    }
                }
                HStack(spacing: 6) {
                    TriggerOption(icon: "battery.25percent", label: "≤ 20%", color: .red) {
                        submit(.batteryLow(percent: 20))
                    }
                    TriggerOption(icon: "battery.50percent", label: "≤ 50%", color: .yellow) {
                        submit(.batteryLow(percent: 50))
                    }
                }
                TriggerOption(icon: "display.trianglebadge.exclamationmark", label: "Undocked (display removed)", color: .teal) {
                    submit(.displayDisconnect)
                }
            }
            .padding(.horizontal, 12)

            Spacer(minLength: 4)
        }
        .padding(.bottom, 10)
    }

    // MARK: - Helpers

    private func animateTo(_ newStep: CaptureStep) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            step = newStep
        }
    }

    // MARK: - Shared step header

    private func stepHeader(title: String) -> some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            step = .pickTrigger
                        }
                    }

                Text(inputText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.3))
        }
    }

    // MARK: - Submit

    private func submit(_ trigger: TriggerCondition) {
        let what = inputText.trimmingCharacters(in: .whitespaces)
        guard !what.isEmpty else { return }
        controller.store.add(what: what, trigger: trigger)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            inputText = ""
            step = .input
        }
    }

    // MARK: - Running apps

    private var runningApps: [AppInfo] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .compactMap { app in
                guard let bid = app.bundleIdentifier, let name = app.localizedName else { return nil }
                // Skip self
                if bid == Bundle.main.bundleIdentifier { return nil }
                return AppInfo(bundleID: bid, name: name, icon: app.icon)
            }
            .sorted { $0.name < $1.name }
    }
}

// MARK: - Supporting types

struct AppInfo {
    let bundleID: String
    let name: String
    let icon: NSImage?
}

// MARK: - Trigger option button

struct TriggerOption: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(label)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(isHovered ? .white : color)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovered ? color.opacity(0.25) : color.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(color.opacity(isHovered ? 0.4 : 0.15), lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture { action() }
        .onHover { h in withAnimation(.easeInOut(duration: 0.12)) { isHovered = h } }
    }
}

// MARK: - Time chip

struct TimeChip: View {
    let label: String
    let minutes: Int
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(isHovered ? .white : .orange)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.orange.opacity(0.25) : Color.orange.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.orange.opacity(isHovered ? 0.4 : 0.15), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .onTapGesture { action() }
            .onHover { h in withAnimation(.easeInOut(duration: 0.12)) { isHovered = h } }
    }
}

// MARK: - App chip

struct AppChip: View {
    let app: AppInfo
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 4) {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.cyan.opacity(0.6))
            }
            Text(app.name)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? .cyan.opacity(0.15) : .white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.cyan.opacity(isHovered ? 0.3 : 0), lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture { action() }
        .onHover { h in withAnimation(.easeInOut(duration: 0.12)) { isHovered = h } }
    }
}

// MARK: - Intention row

struct IntentionRow: View {
    let intention: Intention
    let onDone: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: intention.trigger.icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(triggerColor)
                .frame(width: 18)

            Text(intention.what)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)

            Spacer(minLength: 4)

            Text(intention.trigger.label)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(triggerColor.opacity(0.7))

            // Always-visible action buttons
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.green.opacity(0.7))
                .contentShape(Rectangle())
                .onTapGesture { onDone() }

            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.25))
                .contentShape(Rectangle())
                .onTapGesture { onDelete() }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var triggerColor: Color {
        switch intention.trigger {
        case .time: return .orange
        case .app: return .cyan
        case .appClose: return .pink
        case .returnFromIdle: return .purple
        case .screenLock: return .indigo
        case .recurring: return .mint
        case .wifiArrive: return .green
        case .wifiLeave: return .orange
        case .powerConnect: return .green
        case .powerDisconnect: return .orange
        case .batteryLow: return .red
        case .displayConnect: return .teal
        case .displayDisconnect: return .teal
        case .newDownload: return .blue
        case .manual: return .gray
        }
    }
}

// MARK: - Location button

struct LocationButton: View {
    let label: String
    let icon: String
    let color: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(label)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(isHovered ? .white : color)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovered ? color.opacity(0.25) : color.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(color.opacity(isHovered ? 0.4 : 0.15), lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture { action() }
        .onHover { h in withAnimation(.easeInOut(duration: 0.12)) { isHovered = h } }
    }
}

// MARK: - Exact time preset chip

struct ExactTimePreset: View {
    let label: String
    let hour: Int
    let minute: Int
    let action: (Int, Int) -> Void

    @State private var isHovered = false

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(isHovered ? .white : .orange.opacity(0.8))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(isHovered ? .orange.opacity(0.2) : .orange.opacity(0.08)))
            .overlay(Capsule().strokeBorder(.orange.opacity(0.15), lineWidth: 0.5))
            .contentShape(Capsule())
            .onTapGesture { action(hour, minute) }
            .onHover { h in withAnimation(.easeInOut(duration: 0.12)) { isHovered = h } }
    }
}

// MARK: - Day toggle

struct DayToggle: View {
    let label: String
    let isOn: Bool
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: selected ? .semibold : .regular, design: .rounded))
            .foregroundStyle(selected ? .white : .white.opacity(0.4))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? .mint.opacity(0.2) : .white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(selected ? .mint.opacity(0.3) : .clear, lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .onTapGesture { action() }
    }
}

// MARK: - Fired intention view

struct FiredView: View {
    let intention: Intention
    @ObservedObject var controller: NotchPanelController

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: intention.trigger.icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(intention.trigger.label)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
            }
            .foregroundStyle(.cyan)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(.cyan.opacity(0.15)))

            Text(intention.what)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                    Text("Done")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(.green.opacity(0.3)))
                .overlay(Capsule().strokeBorder(.green.opacity(0.3), lineWidth: 0.5))
                .contentShape(Capsule())
                .onTapGesture {
                    controller.store.markDone(intention.id)
                    controller.collapse()
                }

                HStack(spacing: 5) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 11, weight: .medium))
                    Text("15m")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(.white.opacity(0.08)))
                .contentShape(Capsule())
                .onTapGesture {
                    controller.store.snooze(intention.id, minutes: 15)
                    controller.collapse()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - NSVisualEffectView wrapper

struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
