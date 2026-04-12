import SwiftUI
import AppKit

// MARK: - NSPanel subclass that accepts keyboard input

class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Make key on any mouse down so buttons work immediately
    override func mouseDown(with event: NSEvent) {
        makeKey()
        super.mouseDown(with: event)
    }
}

// Hosting view that accepts first mouse without requiring activation
class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Menu Panel Controller

class NotchPanelController: ObservableObject {
    private var panel: KeyablePanel?
    private var clickMonitor: Any?

    @Published var isExpanded = false
    @Published var firedIntention: Intention?

    weak var statusItem: NSStatusItem?

    let store: IntentionStore
    let monitor: TriggerMonitor

    init(store: IntentionStore) {
        self.store = store
        self.monitor = TriggerMonitor(store: store)

        monitor.onFire = { [weak self] intention in
            DispatchQueue.main.async {
                self?.showFired(intention)
            }
        }
    }

    // MARK: - Setup

    func setup() {
        createPanel()
        monitor.start()
    }

    // MARK: - Panel Creation

    private func createPanel() {
        let expandedWidth: CGFloat = 340
        let expandedHeight: CGFloat = 400

        let content = NotchContentView(controller: self)
        let hostingView = FirstMouseHostingView(rootView: content)
        hostingView.layer?.backgroundColor = .clear

        let p = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: expandedWidth, height: expandedHeight),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        p.hidesOnDeactivate = false
        p.contentView = hostingView
        p.isMovable = false
        p.ignoresMouseEvents = false
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.standardWindowButton(.closeButton)?.isHidden = true
        p.standardWindowButton(.miniaturizeButton)?.isHidden = true
        p.standardWindowButton(.zoomButton)?.isHidden = true

        panel = p
    }

    // MARK: - Positioning below status item

    private func panelFrame(width: CGFloat, height: CGFloat) -> NSRect {
        if let button = statusItem?.button,
           let window = button.window {
            let buttonRect = button.convert(button.bounds, to: nil)
            let screenRect = window.convertToScreen(buttonRect)
            let x = screenRect.midX - width / 2
            let y = screenRect.minY - height - 4
            return NSRect(x: x, y: y, width: width, height: height)
        }
        // Fallback: top-center of screen
        if let screen = NSScreen.main {
            return NSRect(
                x: screen.frame.midX - width / 2,
                y: screen.frame.maxY - 30 - height,
                width: width,
                height: height
            )
        }
        return NSRect(x: 0, y: 0, width: width, height: height)
    }

    private func statusItemScreenFrame() -> NSRect? {
        guard let button = statusItem?.button, let window = button.window else { return nil }
        let buttonRect = button.convert(button.bounds, to: nil)
        return window.convertToScreen(buttonRect)
    }

    // MARK: - Expand / Collapse

    func expand() {
        guard !isExpanded else { return }
        isExpanded = true

        let expandedWidth: CGFloat = 340
        let expandedHeight: CGFloat = firedIntention != nil ? 160 : 400
        let frame = panelFrame(width: expandedWidth, height: expandedHeight)

        panel?.setFrame(frame, display: false)
        panel?.alphaValue = 0
        panel?.orderFront(nil)
        panel?.makeKey()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
            panel?.animator().alphaValue = 1
        }

        startClickOutsideMonitor()
    }

    func collapse() {
        guard isExpanded else { return }
        isExpanded = false
        firedIntention = nil

        stopClickOutsideMonitor()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel?.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
        })
    }

    func toggle() {
        if isExpanded { collapse() } else { expand() }
    }

    // MARK: - Fire handling

    private func showFired(_ intention: Intention) {
        firedIntention = intention
        if isExpanded {
            // Resize in place for fired content
            let frame = panelFrame(width: 340, height: 160)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel?.animator().setFrame(frame, display: true)
            }
        } else {
            expand()
        }

        // Auto-collapse after 10 seconds if no interaction
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            if self?.firedIntention?.id == intention.id {
                self?.collapse()
            }
        }
    }

    // MARK: - Click outside to dismiss

    private func startClickOutsideMonitor() {
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self, self.isExpanded else { return }
            let mouseLocation = NSEvent.mouseLocation

            // Ignore clicks on the status item (toggle handles those)
            if let buttonFrame = self.statusItemScreenFrame(), buttonFrame.contains(mouseLocation) {
                return
            }

            if let panelFrame = self.panel?.frame, !panelFrame.contains(mouseLocation) {
                self.collapse()
            }
        }
    }

    private func stopClickOutsideMonitor() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }
}
