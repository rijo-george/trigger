import SwiftUI
import AppKit
import Carbon.HIToolbox

@main
struct TriggerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState!

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState = AppState()
    }
}

// MARK: - App State

class AppState: NSObject, ObservableObject {
    let store = IntentionStore()
    lazy var panelController = NotchPanelController(store: store)

    private var statusItem: NSStatusItem!
    private var hotKeyRef: EventHotKeyRef?

    override init() {
        super.init()
        setupStatusItem()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.panelController.statusItem = self.statusItem
            self.panelController.setup()
            self.registerHotKey()
        }
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "Trigger")
            button.action = #selector(statusItemClicked)
            button.target = self
        }
    }

    @objc private func statusItemClicked() {
        panelController.toggle()
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
                state.panelController.toggle()
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
