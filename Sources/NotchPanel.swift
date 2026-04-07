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

// MARK: - Notch Panel Controller

class NotchPanelController: ObservableObject {
    private var panel: KeyablePanel?
    private var mouseTracker: Any?
    private var trackingTimer: Timer?

    @Published var isExpanded = false
    @Published var firedIntention: Intention?

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
        startMouseTracking()
    }

    // MARK: - Panel Creation

    private func createPanel() {
        guard let screen = NSScreen.main else { return }

        let notchWidth: CGFloat = 220
        let collapsedHeight: CGFloat = 12

        let x = screen.frame.midX - notchWidth / 2
        let y = screen.frame.maxY - screen.safeAreaInsets.top

        let content = NotchContentView(controller: self)
        let hostingView = FirstMouseHostingView(rootView: content)
        hostingView.layer?.backgroundColor = .clear

        let p = KeyablePanel(
            contentRect: NSRect(x: x, y: y - collapsedHeight, width: notchWidth, height: collapsedHeight),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
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

        p.orderFront(nil)
        panel = p
    }

    // MARK: - Expand / Collapse

    func expand() {
        guard !isExpanded, let screen = NSScreen.main else { return }
        isExpanded = true
        panel?.makeKey()

        let expandedWidth: CGFloat = 340
        let expandedHeight: CGFloat = firedIntention != nil ? 160 : 400
        let x = screen.frame.midX - expandedWidth / 2
        let y = screen.frame.maxY - screen.safeAreaInsets.top

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1) // ease-out cubic
            panel?.animator().setFrame(
                NSRect(x: x, y: y - expandedHeight, width: expandedWidth, height: expandedHeight),
                display: true
            )
        }
    }

    func collapse() {
        guard isExpanded, let screen = NSScreen.main else { return }
        isExpanded = false
        firedIntention = nil

        let notchWidth: CGFloat = 220
        let collapsedHeight: CGFloat = 12
        let x = screen.frame.midX - notchWidth / 2
        let y = screen.frame.maxY - screen.safeAreaInsets.top

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel?.animator().setFrame(
                NSRect(x: x, y: y - collapsedHeight, width: notchWidth, height: collapsedHeight),
                display: true
            )
        }
    }

    func toggle() {
        if isExpanded { collapse() } else { expand() }
    }

    // MARK: - Fire handling

    private func showFired(_ intention: Intention) {
        firedIntention = intention
        expand()

        // Auto-collapse after 10 seconds if no interaction
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            if self?.firedIntention?.id == intention.id {
                self?.collapse()
            }
        }
    }

    // MARK: - Mouse tracking for proximity detection

    private func startMouseTracking() {
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.checkMouseProximity()
        }
    }

    private func checkMouseProximity() {
        guard let screen = NSScreen.main else { return }
        let mouseLocation = NSEvent.mouseLocation

        let notchCenterX = screen.frame.midX
        let notchTop = screen.frame.maxY

        // Detection zone: 160px wide, 24px tall at top center of screen
        let proximityWidth: CGFloat = 160
        let proximityHeight: CGFloat = 24

        let inZone = abs(mouseLocation.x - notchCenterX) < proximityWidth / 2
            && mouseLocation.y > notchTop - proximityHeight

        if inZone && !isExpanded {
            expand()
        }

        // Collapse if mouse is far from the expanded panel
        if isExpanded && firedIntention == nil {
            let panelFrame = panel?.frame ?? .zero
            let expandedZone = panelFrame.insetBy(dx: -40, dy: -40)
            if !expandedZone.contains(mouseLocation) {
                collapse()
            }
        }
    }
}
