import AppKit

final class PassiveButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

extension AppDelegate {
    func positionClipPalette() {
        guard let panel, let pet else { return }
        let area = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? panel.frame
        let right = panel.frame.maxX + 3
        let placeRight = right + (clipPalette?.frame.width ?? 178) <= area.maxX
        guard let palette = clipPalette, palette.isVisible else {
            pet.paletteButton.title = placeRight ? "▶" : "◀"; return
        }
        let x = placeRight ? right : max(area.minX, panel.frame.minX-palette.frame.width-3)
        let arrowY = panel.frame.minY + pet.paletteButton.frame.midY
        let y = max(area.minY, min(arrowY-palette.frame.height/2, area.maxY-palette.frame.height))
        palette.setFrameOrigin(NSPoint(x: x, y: y))
        pet.paletteButton.title = placeRight ? "◀" : "▶"
    }
    @objc func toggleClipPalette(_ sender: Any?) {
        if let palette = clipPalette, palette.isVisible {
            panel.removeChildWindow(palette); palette.orderOut(nil); positionClipPalette(); return
        }
        let width: CGFloat = 178, height = CGFloat(clips.count * 34 + 12)
        let palette = clipPalette ?? PetPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        if clipPalette == nil {
            palette.isOpaque = false; palette.backgroundColor = .clear; palette.hasShadow = true
            palette.level = .floating; palette.isReleasedWhenClosed = false
            let root = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height)); root.wantsLayer = true
            root.layer?.backgroundColor = NSColor(calibratedRed: 1, green: 0.96, blue: 0.88, alpha: 0.98).cgColor; root.layer?.cornerRadius = 10
            root.layer?.borderColor = NSColor(calibratedRed: 0.30, green: 0.18, blue: 0.11, alpha: 0.85).cgColor; root.layer?.borderWidth = 1
            for (index, clip) in clips.enumerated() {
                let button = PassiveButton(title: clip.label, target: self, action: #selector(selectPaletteClip(_:)))
                button.tag = clip.id; button.frame = NSRect(x: 6, y: height-CGFloat(index+1)*34-3, width: width-12, height: 30)
                button.bezelStyle = .rounded; root.addSubview(button)
            }
            palette.contentView = root; clipPalette = palette
        }
        panel.addChildWindow(palette, ordered: .above); palette.orderFrontRegardless(); positionClipPalette()
    }
    @objc func selectPaletteClip(_ sender: NSButton) {
        guard let clip = clips.first(where: { $0.id == sender.tag }) else { return }
        play(clip); lastPortraitID = clip.id
    }
}
