import AppKit
import KeyClickCore

final class OverlayPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class MarkerCanvasView: NSView {
    private var markerViews: [UUID: MarkerDotView] = [:]
    private var markers: [MarkerBinding] = []
    private let guide = EditingGuideView()
    var onMarkerMoved: ((UUID, NormalizedPoint) -> Void)?

    // Match AX/Quartz's top-left origin for saved normalized coordinates.
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        guide.isHidden = true
        addSubview(guide)
    }

    required init?(coder: NSCoder) { nil }

    func render(markers: [MarkerBinding], markerSize: CGFloat, mode: OverlayMode) {
        self.markers = markers
        let oldIDs = Set(markerViews.keys)
        let newIDs = Set(markers.map(\.id))
        for id in oldIDs.subtracting(newIDs) {
            markerViews[id]?.removeFromSuperview()
            markerViews[id] = nil
        }
        for marker in markers {
            let dot: MarkerDotView
            if let existing = markerViews[marker.id] {
                dot = existing
            } else {
                dot = MarkerDotView()
                dot.onDragged = { [weak self] id, center in
                    guard let self, self.bounds.width > 0, self.bounds.height > 0 else { return }
                    self.onMarkerMoved?(id, NormalizedPoint(x: center.x / self.bounds.width, y: center.y / self.bounds.height))
                }
                addSubview(dot)
                markerViews[marker.id] = dot
            }
            // During setup the dots deliberately become larger than the normal
            // keycap size.  A first-time user must be able to locate the exact
            // place where dragging starts without hunting for a faint 32-pt dot.
            let visibleSize = mode == .editing ? max(markerSize, 46) : markerSize
            dot.configure(marker: marker, size: visibleSize, armed: mode == .armed, editable: mode == .editing)
            let center = CGPoint(x: bounds.width * marker.position.x, y: bounds.height * marker.position.y)
            dot.frame = CGRect(x: center.x - visibleSize / 2, y: center.y - visibleSize / 2, width: visibleSize, height: visibleSize)
        }
        guide.isHidden = mode != .editing
        positionGuide()
    }

    override func layout() {
        super.layout()
        for marker in markers {
            guard let dot = markerViews[marker.id] else { continue }
            let size = dot.bounds.width
            let center = CGPoint(x: bounds.width * marker.position.x, y: bounds.height * marker.position.y)
            dot.frame = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
        }
        positionGuide()
    }

    private func positionGuide() {
        guard !guide.isHidden else { return }
        guide.frame = CGRect(x: 16, y: 16, width: min(410, max(180, bounds.width - 32)), height: 58)
    }
}

/// The overlay itself is intentionally the instruction surface: it removes
/// the ambiguous "where do I start dragging?" moment without opening another
/// window or taking focus away from the target application.
private final class EditingGuideView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.18, green: 0.10, blue: 0.34, alpha: 0.94).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
        NSColor.systemPurple.withAlphaComponent(0.95).setFill()
        NSBezierPath(roundedRect: CGRect(x: 10, y: 11, width: 36, height: 36), xRadius: 18, yRadius: 18).fill()
        let numberStyle = NSMutableParagraphStyle(); numberStyle.alignment = .center
        ("↕" as NSString).draw(in: CGRect(x: 10, y: 17, width: 36, height: 24), withAttributes: [
            .font: NSFont.systemFont(ofSize: 19, weight: .bold), .foregroundColor: NSColor.white, .paragraphStyle: numberStyle
        ])
        ("编辑浮标：直接拖动紫色数字到答案中央" as NSString).draw(
            in: CGRect(x: 58, y: 9, width: bounds.width - 68, height: 22), withAttributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.white
            ])
        ("完成后按 ⌃⌥K 开始；Esc 退出" as NSString).draw(
            in: CGRect(x: 58, y: 31, width: bounds.width - 68, height: 18), withAttributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.white.withAlphaComponent(0.78)
            ])
    }
}

final class MarkerDotView: NSView {
    private var markerID = UUID()
    private var label = "?"
    private var fillColor = NSColor.systemPurple
    private var armed = false
    private var editable = false
    var onDragged: ((UUID, CGPoint) -> Void)?

    override var isFlipped: Bool { false }

    func configure(marker: MarkerBinding, size: CGFloat, armed: Bool, editable: Bool) {
        markerID = marker.id
        label = marker.label
        fillColor = NSColor(hex: marker.colorHex) ?? .systemPurple
        self.armed = armed
        self.editable = editable
        frame.size = CGSize(width: size, height: size)
        toolTip = editable ? "拖动以调整 \(label) 的位置" : "\(label)"
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let inset: CGFloat = armed ? 1 : (editable ? 1.5 : 3)
        let circle = bounds.insetBy(dx: inset, dy: inset)
        let color = fillColor.withAlphaComponent(armed ? 0.92 : (editable ? 0.96 : 0.52))
        color.setFill()
        NSBezierPath(ovalIn: circle).fill()
        if armed || editable {
            NSColor.white.withAlphaComponent(0.92).setStroke()
            let border = NSBezierPath(ovalIn: circle.insetBy(dx: 0.8, dy: 0.8))
            border.lineWidth = 1.4
            border.stroke()
        }
        if editable {
            let halo = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
            fillColor.withAlphaComponent(0.40).setStroke()
            halo.lineWidth = 2.5
            halo.stroke()
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: max(12, bounds.height * 0.46), weight: .bold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ]
        let rect = CGRect(x: 0, y: bounds.height * 0.24, width: bounds.width, height: bounds.height * 0.55)
        (label as NSString).draw(in: rect, withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        guard editable else { return }
        NSCursor.closedHand.push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard editable, let superview else { return }
        let point = superview.convert(event.locationInWindow, from: nil)
        let clamped = CGPoint(x: point.x.clamped(to: 0...superview.bounds.width), y: point.y.clamped(to: 0...superview.bounds.height))
        setFrameOrigin(CGPoint(x: clamped.x - bounds.width / 2, y: clamped.y - bounds.height / 2))
        onDragged?(markerID, clamped)
    }

    override func mouseUp(with event: NSEvent) {
        if editable { NSCursor.pop() }
    }
}

@MainActor
final class OverlayController {
    private let panel = OverlayPanel()
    private let canvas = MarkerCanvasView()

    init() {
        panel.contentView = canvas
    }

    func show(snapshot: WindowSnapshot, profile: ClickProfile, mode: OverlayMode, settings: AppSettings) {
        panel.setFrame(snapshot.overlayFrame, display: true)
        canvas.frame = panel.contentView?.bounds ?? .zero
        canvas.render(markers: profile.markers, markerSize: settings.markerSize, mode: mode)
        panel.ignoresMouseEvents = mode != .editing
        panel.alphaValue = mode == .armed ? 1 : settings.markerOpacity
        panel.orderFrontRegardless()
    }

    func setDragHandler(_ handler: @escaping (UUID, NormalizedPoint) -> Void) {
        canvas.onMarkerMoved = handler
    }

    func hide() { panel.orderOut(nil) }
}

private extension NSColor {
    convenience init?(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard clean.count == 6, let value = Int(clean, radix: 16) else { return nil }
        self.init(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255, blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
