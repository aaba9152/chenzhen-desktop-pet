import AppKit

final class ResizeHandle: NSView {
    weak var owner: AppDelegate?
    private var startMouse = NSPoint.zero
    private var startWidth: CGFloat = 260
    private var topLeft = NSPoint.zero
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.35, green: 0.18, blue: 0.09, alpha: 0.8).setStroke()
        let path = NSBezierPath(); path.lineWidth = 2; path.lineCapStyle = .round
        path.move(to: NSPoint(x: 5, y: 4)); path.line(to: NSPoint(x: 15, y: 14))
        path.move(to: NSPoint(x: 10, y: 3)); path.line(to: NSPoint(x: 16, y: 9)); path.stroke()
    }
    override func mouseDown(with event: NSEvent) {
        guard let owner else { return }
        startMouse = NSEvent.mouseLocation; startWidth = owner.size
        topLeft = NSPoint(x: owner.panel.frame.minX, y: owner.panel.frame.maxY)
    }
    override func mouseDragged(with event: NSEvent) {
        owner?.resizeByDrag(width: startWidth + NSEvent.mouseLocation.x - startMouse.x, topLeft: topLeft)
    }
    override func mouseUp(with event: NSEvent) { owner?.keepVisible(); owner?.savePosition() }
}

extension AppDelegate {
    func resizeByDrag(width: CGFloat, topLeft: NSPoint) {
        size = min(340, max(190, width)); panel.setContentSize(panelSize)
        panel.setFrameOrigin(NSPoint(x: topLeft.x, y: topLeft.y-panel.frame.height))
        keepVisible(); pet.needsLayout = true
        if !diagnostic { defaults.set(Double(size), forKey: "size") }
    }
}
