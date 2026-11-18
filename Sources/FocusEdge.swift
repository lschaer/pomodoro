import AppKit
import QuartzCore

/// A thin, soft line along the bottom edge of every screen while focus time is active.
/// Click-through, fades in and out, and dims while the session is paused.
@MainActor
enum FocusEdge {
    enum State { case hidden, running, paused }

    /// Height of the glow area above the bottom edge.
    static let thickness: CGFloat = 40
    static let color = NSColor.systemRed

    private static var windows: [NSWindow] = []
    private static var lines: [CALayer] = []
    private static var state: State = .hidden
    private static var screenObserver: NSObjectProtocol?

    static func update(_ newState: State) {
        guard newState != state else { return }
        state = newState
        if newState != .hidden && windows.isEmpty { buildWindows() }

        let alpha: CGFloat = switch newState {
            case .running: 1
            case .paused: 0.35
            case .hidden: 0
        }
        setPulsing(newState == .running)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 1.5
            for w in windows { w.animator().alphaValue = alpha }
        }, completionHandler: {
            Task { @MainActor in
                if FocusEdge.state == .hidden { tearDown() }
            }
        })
    }

    /// Slow breathing while focusing: full strength → ~55% → full, about 9 s per cycle.
    private static func setPulsing(_ on: Bool) {
        for layer in lines {
            layer.removeAnimation(forKey: "pulse")
            guard on else { continue }
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1.0
            pulse.toValue = 0.55
            pulse.duration = 4.5
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(pulse, forKey: "pulse")
        }
    }

    /// Soft light rising from the bottom edge (bright at the edge, fading upward over the
    /// whole height), plus a fine bright core line; both fade out gently toward the corners.
    private static func makeGlowLayer(size: CGSize) -> CALayer {
        let container = CALayer()
        container.frame = CGRect(origin: .zero, size: size)

        // Vertical glow: layer y = 0 is the bottom of the screen.
        let glow = CAGradientLayer()
        glow.frame = container.bounds
        glow.colors = [color.withAlphaComponent(0.55).cgColor,
                       color.withAlphaComponent(0.22).cgColor,
                       color.withAlphaComponent(0.06).cgColor,
                       NSColor.clear.cgColor]
        glow.locations = [0, 0.18, 0.5, 1]
        glow.startPoint = CGPoint(x: 0.5, y: 0)
        glow.endPoint = CGPoint(x: 0.5, y: 1)
        container.addSublayer(glow)

        // Fine core line right at the edge.
        let core = CALayer()
        core.frame = CGRect(x: 0, y: 0, width: size.width, height: 1.5)
        core.backgroundColor = color.withAlphaComponent(0.9).cgColor
        container.addSublayer(core)

        // Long, smooth fade toward the left and right corners.
        let mask = CAGradientLayer()
        mask.frame = container.bounds
        mask.colors = [NSColor.clear.cgColor, NSColor.black.cgColor,
                       NSColor.black.cgColor, NSColor.clear.cgColor]
        mask.locations = [0, 0.2, 0.8, 1]
        mask.startPoint = CGPoint(x: 0, y: 0.5)
        mask.endPoint = CGPoint(x: 1, y: 0.5)
        container.mask = mask

        return container
    }

    private static func buildWindows() {
        for screen in NSScreen.screens {
            let f = screen.frame
            let w = NSWindow(contentRect: CGRect(x: f.minX, y: f.minY, width: f.width, height: thickness),
                             styleMask: .borderless, backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.level = .statusBar
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            w.isReleasedWhenClosed = false
            w.alphaValue = 0

            let view = NSView(frame: CGRect(origin: .zero, size: w.frame.size))
            view.wantsLayer = true
            let glow = makeGlowLayer(size: w.frame.size)
            view.layer?.addSublayer(glow)
            lines.append(glow)
            w.contentView = view

            w.orderFrontRegardless()
            windows.append(w)
        }

        // Rebuild when displays are added/removed or rearranged.
        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { _ in
                Task { @MainActor in
                    let current = state
                    tearDown()
                    state = .hidden
                    update(current)
                }
            }
        }
    }

    private static func tearDown() {
        for w in windows { w.orderOut(nil) }
        windows.removeAll()
        lines.removeAll()
    }
}
