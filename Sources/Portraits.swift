import AppKit

struct Portrait: Codable {
    let id, name, file: String
    let mouth, head: [Double]
}

extension AppDelegate {
    @objc func choosePortrait(_ sender: NSMenuItem) {
        guard sender.tag >= 0 && sender.tag < portraits.count else { return }
        applyPortrait(portraits[sender.tag].id)
    }
    func applyPortrait(_ id: String) {
        guard let portrait = portraits.first(where: { $0.id == id }), let image = portraitImages[id], image.size.width > 0 else { return }
        stopPlayback()
        let bottomRight = NSPoint(x: panel.frame.maxX, y: panel.frame.minY)
        currentPortraitID = id
        imageRatio = image.size.height / image.size.width
        pet.face.image = image
        feeding.library.anchors["mouth"] = portrait.mouth
        feeding.library.anchors["head"] = portrait.head
        panel.setContentSize(panelSize)
        panel.setFrameOrigin(NSPoint(x: bottomRight.x-panel.frame.width, y: bottomRight.y))
        pet.needsLayout = true; pet.layoutSubtreeIfNeeded(); keepVisible(); savePosition()
        if !diagnostic { defaults.set(id, forKey: "portrait") }
    }
}
