import AppKit
import MetalKit
import MemnoxVoiceCore

/// The only thing Memnox puts on screen: a borderless, see-through panel holding the orb and
/// its pill. It floats over every Space and never takes focus from the editor underneath.
final class OrbPanel: NSPanel, Face {
    private let orb: MTKView
    private let renderer: OrbRenderer?
    private let pill = PillView()

    init(loudness: @escaping () -> Float) {
        let frame = NSRect(x: 0, y: 0, width: 380, height: 440)
        orb = MTKView(frame: NSRect(x: 30, y: 90, width: 320, height: 320), device: MTLCreateSystemDefaultDevice())
        orb.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        orb.layer?.isOpaque = false
        orb.preferredFramesPerSecond = 60
        renderer = OrbRenderer(view: orb)
        renderer?.loudness = loudness
        orb.delegate = renderer
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false

        let content = NSView(frame: frame)
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.clear.cgColor
        orb.wantsLayer = true
        orb.layer?.isOpaque = false
        pill.frame = NSRect(x: 50, y: 24, width: 280, height: 50)
        pill.loudness = loudness
        content.addSubview(orb)
        content.addSubview(pill)
        contentView = content
    }

    override var canBecomeKey: Bool { false }

    /// Fades in at the bottom centre of whichever screen the person is looking at.
    nonisolated func present() {
        DispatchQueue.main.async { [self] in
            if let screen = NSScreen.main?.visibleFrame {
                setFrameOrigin(NSPoint(x: screen.midX - frame.width / 2, y: screen.minY + 40))
            }
            guard !isVisible else { return }
            alphaValue = 0
            orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.25; animator().alphaValue = 1 }
        }
    }

    nonisolated func dismiss() {
        DispatchQueue.main.async { [self] in
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.35; animator().alphaValue = 0 }) {
                self.orderOut(nil)
                self.show(.idle, caption: "")
            }
        }
    }

    nonisolated func show(_ state: VoiceState, caption text: String) {
        DispatchQueue.main.async { [self] in
            renderer?.state = state
            pill.state = state
            if !text.isEmpty || state == .idle { pill.text = text }
        }
    }

    /// A click on the orb sends it away, which is the one gesture it answers to.
    override func mouseDown(with event: NSEvent) {
        dismiss()
    }
}

/// The pill under the orb: a live waveform and one short line of text.
final class PillView: NSView {
    var loudness: () -> Float = { 0 }
    var state: VoiceState = .idle
    var text = "" { didSet { needsDisplay = true } }
    private var history = [Float](repeating: 0, count: 9)
    private var timer: Timer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            let heard = self.state == .listening || self.state == .speaking ? self.loudness() : 0.05
            self.history.removeFirst()
            self.history.append(min(max(heard, 0.05), 1))
            self.needsDisplay = true
        }
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        // The console's dark card and border, so the pill is plainly the same product.
        NSColor(srgbRed: 0x0F / 255, green: 0x0F / 255, blue: 0x0F / 255, alpha: 0.86).setFill()
        shape.fill()
        NSColor(srgbRed: 0x31 / 255, green: 0x31 / 255, blue: 0x31 / 255, alpha: 1).setStroke()
        shape.lineWidth = 1
        shape.stroke()

        let ember = NSColor(red: 1.0, green: 0.52, blue: 0.2, alpha: 1)
        for (index, value) in history.enumerated() {
            let height = 6 + CGFloat(value) * 22
            let bar = NSRect(x: 22 + CGFloat(index) * 9, y: bounds.midY - height / 2, width: 4, height: height)
            ember.withAlphaComponent(0.55 + CGFloat(value) * 0.45).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 2, yRadius: 2).fill()
        }

        let words = text.isEmpty ? placeholder : text
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Memnox.nsSans(14, semibold: true),
            .foregroundColor: NSColor(srgbRed: 0xFD / 255, green: 0xFD / 255, blue: 0xFD / 255, alpha: 1),
        ]
        let size = (words as NSString).size(withAttributes: attributes)
        let room = NSRect(x: 112, y: bounds.midY - size.height / 2, width: bounds.width - 128, height: size.height)
        (words as NSString).draw(with: room, options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin], attributes: attributes)
    }

    private var placeholder: String {
        switch state {
        case .listening: return "Listening"
        case .thinking: return "Checking"
        case .needsYou: return "Touch ID"
        case .speaking, .idle: return "Memnox"
        }
    }
}
