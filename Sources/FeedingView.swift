import AppKit

final class FoodButton: NSView {
    weak var host: PetView?
    let index: Int
    let action: FeedingAction
    let image: NSImage
    var down = false
    var dragging = false
    var start = CGPoint.zero
    init(index: Int, action: FeedingAction, image: NSImage) {
        self.index = index; self.action = action; self.image = image
        super.init(frame: .zero)
        toolTip = action.title; setAccessibilityElement(true); setAccessibilityRole(.button)
        setAccessibilityLabel("投喂：" + action.title); setAccessibilityIdentifier("feed-" + action.id)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
        NSColor(calibratedRed: 1, green: 0.96, blue: 0.86, alpha: 0.98).setFill(); path.fill()
        NSColor(calibratedRed: 0.28, green: 0.16, blue: 0.10, alpha: 1).setStroke(); path.lineWidth = 1.8; path.stroke()
        NSGraphicsContext.saveGraphicsState()
        let tr = NSAffineTransform(); tr.translateX(by: bounds.midX, yBy: bounds.midY); tr.rotate(byDegrees: -action.iconRotation); tr.concat()
        image.draw(in: CGRect(x: -bounds.width * 0.43, y: -bounds.height * 0.43, width: bounds.width * 0.86, height: bounds.height * 0.86))
        NSGraphicsContext.restoreGraphicsState()
    }
    override func mouseDown(with event: NSEvent) { down = true; dragging = false; start = NSEvent.mouseLocation }
    override func mouseDragged(with event: NSEvent) {
        guard down, let host else { return }
        let now = NSEvent.mouseLocation
        if !dragging && hypot(now.x-start.x, now.y-start.y) > 4 {
            dragging = true; host.owner?.feeding.beginDrag(index)
        }
        if dragging { host.owner?.feeding.updateDrag(now) }
    }
    override func mouseUp(with event: NSEvent) {
        guard down, let host else { return }; down = false
        if dragging { host.owner?.feeding.endDrag(NSEvent.mouseLocation) }
        else { host.owner?.feeding.begin(action) }
        dragging = false
    }
    override func accessibilityPerformPress() -> Bool { host?.owner?.feeding.begin(action); return true }
}

final class FeedingController {
    unowned let owner: AppDelegate
    var library: ActionLibrary
    var action: FeedingAction?
    var timer: Timer?
    var started: TimeInterval = 0
    var origin = CGPoint.zero
    var ghost: PetPanel?
    var ghostTimer: Timer?
    var dragIndex: Int?
    var lastReply: Int?
    var visualDone = false
    var isActive: Bool { action != nil }
    init(owner: AppDelegate, library: ActionLibrary) { self.owner = owner; self.library = library }

    func begin(_ next: FeedingAction, from point: CGPoint? = nil) {
        let source = point ?? owner.pet.buttonCenter(library.actions.firstIndex(where: { $0.id == next.id })!)
        let id: Int
        if next.id == "pour" { id = 3 }
        else if owner.lastPortraitID == 6 { id = next.id == "soda" ? 2 : 4 }
        else if next.id == "noodles" { id = 1 }
        else { id = library.responses.randomElement()! }
        guard let clip = owner.clips.first(where: { $0.id == id }) else { return }
        owner.lastPortraitID = nil
        owner.play(clip)
        lastReply = id; action = next; visualDone = false
        origin = CGPoint(x: source.x / owner.pet.bounds.width, y: source.y / owner.pet.bounds.height)
        started = ProcessInfo.processInfo.systemUptime
        owner.pet.animationTimer?.invalidate(); owner.pet.animationTimer = nil
        render(0)
        timer = Timer.scheduledTimer(withTimeInterval: 1 / Double(library.fps), repeats: true) { [weak self] _ in
            guard let self, let active = self.action else { return }
            let time = ProcessInfo.processInfo.systemUptime - self.started
            if time >= active.duration { self.finishVisuals() }
            else { self.render(time) }
        }
    }
    func finishVisuals() {
        timer?.invalidate(); timer = nil; visualDone = true
        owner.pet.overlay.poses = []; owner.pet.animate(false)
        if owner.current == nil { owner.cancelInteraction(cancelDrag: false) }
    }
    func audioFinished() { if visualDone { owner.cancelInteraction(cancelDrag: false) } }
    func render(_ time: Double) {
        guard let action else { return }
        let pet = owner.pet!
        let scale = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : ActionSampler.squash(time, duration: action.duration)
        pet.setPortraitScale(scale)
        pet.overlay.poses = ActionSampler.sample(action, time: time, library: library, avatar: pet.avatarRect,
            start: CGPoint(x: origin.x * pet.bounds.width, y: origin.y * pet.bounds.height), unit: pet.unit, squash: scale)
    }
    func cancel(cancelDrag: Bool = true) {
        timer?.invalidate(); timer = nil; action = nil; visualDone = false
        owner.pet?.overlay.poses = []
        if cancelDrag { self.cancelDrag() }
    }
    func preview(_ next: FeedingAction, time: Double) {
        action = next
        let p = owner.pet.buttonCenter(library.actions.firstIndex(where: { $0.id == next.id })!)
        origin = CGPoint(x: p.x / owner.pet.bounds.width, y: p.y / owner.pet.bounds.height)
        owner.pet.setCaption(next.id == "noodles" ? "牛肉面不要面" : next.id == "pour" ? "这你受得了吗" : "谢谢你啊"); owner.pet.caption.isHidden = false
        render(time)
        if time >= next.duration { owner.pet.overlay.poses = []; owner.pet.caption.isHidden = true; owner.pet.setPortraitScale(1) }
    }
    func beginDrag(_ index: Int) {
        cancelGhost(); dragIndex = index
        let side = 48 * owner.pet.unit
        let panel = PetPanel(contentRect: CGRect(x: 0, y: 0, width: side, height: side),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false; panel.ignoresMouseEvents = true
        panel.level = .popUpMenu; panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let image = ActionOverlay(frame: CGRect(x: 0, y: 0, width: side, height: side))
        image.sprites = owner.pet.overlay.sprites
        let item = library.actions[index]
        image.poses = [SpritePose(sprite: item.icon, center: CGPoint(x: side/2,y: side/2), width: side, height: side, rotation: item.iconRotation, alpha: 1)]
        panel.contentView = image; ghost = panel; updateDrag(NSEvent.mouseLocation); panel.orderFrontRegardless()
    }
    func localPoint(_ screen: CGPoint) -> CGPoint {
        let p = owner.pet.convert(owner.panel.convertPoint(fromScreen: screen), from: nil)
        return CGPoint(x: p.x, y: owner.pet.bounds.height-p.y)
    }
    func updateDrag(_ screen: CGPoint) {
        guard let ghost else { return }
        ghost.setFrameOrigin(CGPoint(x: screen.x-ghost.frame.width/2, y: screen.y-ghost.frame.height/2))
        owner.pet.overlay.target = owner.pet.avatarRect.contains(localPoint(screen)) ? owner.pet.avatarRect : nil
    }
    func endDrag(_ screen: CGPoint) {
        guard let index = dragIndex, let panel = ghost else { return }
        dragIndex = nil; owner.pet.overlay.target = nil
        let point = localPoint(screen)
        if owner.pet.avatarRect.contains(point) { cancelGhost(); begin(library.actions[index], from: point); return }
        let target = owner.pet.buttonCenter(index)
        let p = owner.pet.convert(CGPoint(x: target.x, y: owner.pet.bounds.height-target.y), to: nil)
        let dest = owner.panel.convertPoint(toScreen: p)
        let from = panel.frame.origin, to = CGPoint(x: dest.x-panel.frame.width/2, y: dest.y-panel.frame.height/2)
        let start = ProcessInfo.processInfo.systemUptime
        ghostTimer = Timer.scheduledTimer(withTimeInterval: 1/60, repeats: true) { [weak self, weak panel] tick in
            guard let self, let panel, self.ghost === panel else { tick.invalidate(); return }
            let t = min(1, (ProcessInfo.processInfo.systemUptime-start)/0.18)
            panel.setFrameOrigin(CGPoint(x: from.x+(to.x-from.x)*t, y: from.y+(to.y-from.y)*t))
            if t >= 1 { self.cancelGhost() }
        }
    }
    func cancelGhost() { ghostTimer?.invalidate(); ghostTimer = nil; ghost?.close(); ghost = nil; dragIndex = nil }
    func cancelDrag() {
        cancelGhost(); owner.pet?.overlay.target = nil
        for button in owner.pet?.foodButtons ?? [] { button.down = false; button.dragging = false }
    }
}
