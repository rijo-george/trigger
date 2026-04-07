import SwiftUI
import AppKit
import Carbon.HIToolbox

@main
struct TriggerApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(appState)
        } label: {
            Image(systemName: "bolt.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - App State

class AppState: ObservableObject {
    let store = IntentionStore()
    lazy var notchController = NotchPanelController(store: store)

    private var hotKeyRef: EventHotKeyRef?

    init() {
        DispatchQueue.main.async { [weak self] in
            self?.notchController.setup()
            self?.registerHotKey()
        }
    }

    // MARK: - Global hotkey (⌥T)

    private func registerHotKey() {
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x54524947) // "TRIG"
        hotKeyID.id = 1

        let keyCode: UInt32 = 17 // 't' key
        let modifiers: UInt32 = UInt32(optionKey)

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            hotKeyRef = ref
        }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            let state = Unmanaged<AppState>.fromOpaque(userData!).takeUnretainedValue()
            DispatchQueue.main.async {
                state.notchController.toggle()
            }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    deinit {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
        }
    }
}

// MARK: - Menu bar dropdown

struct MenuContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.cyan)

                Text("Trigger")
                    .font(.system(size: 15, weight: .semibold))

                Text("\(appState.store.pendingCount) pending")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 16)
            .padding(.bottom, 14)

            Divider()

            // Toggle notch panel
            Button(action: { appState.notchController.toggle() }) {
                HStack {
                    Label("Toggle Panel", systemImage: "rectangle.topthird.inset.filled")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text("⌥T")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // Pending intentions
            if !appState.store.pending.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Pending")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                    ForEach(appState.store.pending.prefix(8)) { intention in
                        HStack(spacing: 8) {
                            Image(systemName: intention.trigger.icon)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .frame(width: 16)

                            Text(intention.what)
                                .font(.system(size: 12))
                                .lineLimit(1)

                            Spacer()

                            Text(intention.trigger.label)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    }
                }
                .padding(.bottom, 6)

                Divider()
            }

            // Quit
            Button(action: {
                appState.store.save()
                NSApplication.shared.terminate(nil)
            }) {
                HStack {
                    Text("Quit Trigger")
                        .font(.system(size: 12))
                    Spacer()
                    Text("⌘Q")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .keyboardShortcut("q", modifiers: .command)
        }
        .frame(width: 260)
    }
}
