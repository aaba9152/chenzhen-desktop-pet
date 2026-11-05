import AppKit

struct ActionFrame: Codable {
    let t: Double
    let anchor: String
    let x, y, sx, sy, rotation, alpha: Double
}
struct ActionLayer: Codable { let sprite: String; let width, height: Double; let frames: [ActionFrame] }
struct FeedingAction: Codable {
    let id, title, icon: String
    let iconRotation, duration: Double
    let layers: [ActionLayer]
}
struct ActionLibrary: Codable {
    let version, fps: Int
    let responses: [Int]
    var anchors: [String: [Double]]
    let actions: [FeedingAction]
    func validate() throws {
        guard version == 1, fps == 30, responses == [2, 3], Set(actions.map(\.id)).count == 4,
              anchors["mouth"]?.count == 2, anchors["head"]?.count == 2 else { throw NSError(domain: "Actions", code: 1) }
        for a in actions {
            guard a.duration > 0, !a.layers.isEmpty else { throw NSError(domain: "Actions", code: 2) }
            for layer in a.layers {
                guard layer.width > 0, layer.height > 0, layer.frames.count >= 2,
                      layer.frames.first?.t == 0, layer.frames.last?.t == a.duration else { throw NSError(domain: "Actions", code: 3) }
                for pair in zip(layer.frames, layer.frames.dropFirst()) {
                    guard pair.0.t < pair.1.t else { throw NSError(domain: "Actions", code: 4) }
                }
                for f in layer.frames {
                    guard f.anchor == "start" || anchors[f.anchor] != nil,
                          [f.t,f.x,f.y,f.sx,f.sy,f.rotation,f.alpha].allSatisfy(\.isFinite) else { throw NSError(domain: "Actions", code: 5) }
                }
            }
        }
    }
}
struct SpritePose {
    let sprite: String
    let center: CGPoint
    let width, height, rotation, alpha: Double
}
enum ActionSampler {
    static func squash(_ t: Double, duration: Double = .infinity) -> Double {
        1 - 0.06 * (1 - cos(t * 2 * .pi / 0.35)) * min(1, max(0, (duration-t)/0.22))
    }
    static func sample(_ action: FeedingAction, time: Double, library: ActionLibrary,
                       avatar: CGRect, start: CGPoint, unit: Double, squash: Double) -> [SpritePose] {
        func location(_ f: ActionFrame) -> CGPoint {
            let p = library.anchors[f.anchor] ?? [0,0]
            let base = f.anchor == "start" ? start : CGPoint(x: avatar.minX + p[0] * avatar.width,
                y: avatar.maxY - (1 - p[1]) * avatar.height * squash)
            return CGPoint(x: base.x + f.x * unit, y: base.y + f.y * unit)
        }
        return action.layers.map { layer in
            let t = max(0, min(time, action.duration))
            let i = min(layer.frames.count - 2, max(0, layer.frames.lastIndex(where: { $0.t <= t }) ?? 0))
            let a = layer.frames[i], b = layer.frames[i+1]
            let raw = max(0, min(1, (t - a.t)/(b.t - a.t))), u = raw * raw * (3 - 2 * raw)
            func lerp(_ x: Double, _ y: Double) -> Double { x + (y-x)*u }
            let p = location(a), q = location(b)
            return SpritePose(sprite: layer.sprite, center: CGPoint(x: lerp(p.x,q.x), y: lerp(p.y,q.y)),
                width: layer.width * unit * lerp(a.sx,b.sx), height: layer.height * unit * lerp(a.sy,b.sy),
                rotation: lerp(a.rotation,b.rotation), alpha: lerp(a.alpha,b.alpha))
        }
    }
}

final class ActionOverlay: NSView {
    var sprites: [String:NSImage] = [:]
    var poses: [SpritePose] = [] { didSet { needsDisplay = true } }
    var target: CGRect? { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        if let rect = target {
            NSColor.systemOrange.withAlphaComponent(0.12).setFill()
            let path = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12); path.fill()
            NSColor.systemOrange.withAlphaComponent(0.7).setStroke(); path.lineWidth = 2; path.stroke()
        }
        for p in poses where p.alpha > 0.001 && p.width > 0.01 && p.height > 0.01 {
            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform(); transform.translateX(by: p.center.x, yBy: p.center.y)
            transform.rotate(byDegrees: p.rotation); transform.concat()
            let rect = CGRect(x: -p.width/2, y: -p.height/2, width: p.width, height: p.height)
            if p.sprite == "stream" {
                NSColor(calibratedRed: 0.47, green: 0.22, blue: 0.07, alpha: p.alpha).setStroke()
                let path = NSBezierPath(); path.lineWidth = p.width * 0.7; path.lineCapStyle = .round
                path.move(to: CGPoint(x: -p.width * 0.15, y: rect.minY))
                path.curve(to: CGPoint(x: p.width * 0.15, y: rect.maxY), controlPoint1: CGPoint(x: p.width * 0.5, y: -p.height * 0.15), controlPoint2: CGPoint(x: -p.width * 0.5, y: p.height * 0.15)); path.stroke()
            } else {
                sprites[p.sprite]?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: p.alpha, respectFlipped: true, hints: nil)
            }
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}
