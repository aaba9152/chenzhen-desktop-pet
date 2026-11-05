// Adapted from Ganzhe2028/ShaolanPet (MIT), commit 7ce7e2b1ed49c4da66d19d5aac419794af0d32db.
// Reused: ClipSequence, passive NSPanel/NSView interaction, caption and squash animation.
// Copyright (c) 2026 Ganzhe2028. See licenses/.
import AppKit
import AVFoundation

struct Clip: Codable {
    let id: Int
    let label: String
    let file: String
    let duration: Double
}

/// 在 clips.json 中给出的顺序里循环。
struct ClipSequence {
    var remaining: [Int] = []
    var last: Int?
    mutating func next(from ids: [Int]) -> Int? {
        guard !ids.isEmpty else { return nil }
        remaining.removeAll { !ids.contains($0) }
        if remaining.isEmpty { remaining = ids }
        let value = remaining.removeFirst(); last = value; return value
    }

}

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
final class PassiveImage: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
final class PassiveLabel: NSTextField {
    var bubbleImage: NSImage?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        bubbleImage?.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: isFlipped, hints: nil)
        let text = attributedStringValue
        let content = NSRect(x: bounds.width*0.09, y: bounds.height*0.19, width: bounds.width*0.82, height: bounds.height*0.57)
        let size = text.boundingRect(with: NSSize(width: content.width, height: content.height), options: [.usesLineFragmentOrigin, .usesFontLeading]).size
        let rect = NSRect(x: content.minX, y: content.midY-size.height/2, width: content.width, height: min(content.height, ceil(size.height)+1))
        text.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }
}

final class PetView: NSView {
    weak var owner: AppDelegate?
    let face = PassiveImage()
    let caption = PassiveLabel(labelWithString: "")
    let overlay = ActionOverlay()
    let resizeHandle = ResizeHandle()
    let paletteButton = PassiveButton(title: "◀", target: nil, action: nil)
    var foodButtons: [FoodButton] = []
    var portraitScale = 1.0
    var unit: Double { bounds.width / 260 }
    var avatarRect: CGRect {
        let slot = CGRect(x: 8, y: 44 + 70 * unit, width: bounds.width - 16, height: bounds.height - 52 - 114 * unit)
        let ratio = owner?.imageRatio ?? (956.0 / 1070.0)
        let targetHeight = min(slot.height, slot.width * (956.0 / 1070.0))
        let width = min(slot.width, targetHeight / ratio), height = width * ratio
        return CGRect(x: slot.midX - width / 2, y: slot.maxY - height, width: width, height: height)
    }
    var initialMouse = NSPoint.zero
    var initialWindow = NSPoint.zero
    var dragged = false
    var bodyPressed = false
    var animationTimer: Timer?
    var phase = 0.0
    var speaking = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        face.imageScaling = .scaleAxesIndependently
        face.wantsLayer = true
        addSubview(face)
        addSubview(overlay)
        caption.alignment = .center
        caption.textColor = NSColor(calibratedRed: 0.28, green: 0.13, blue: 0.05, alpha: 1)
        caption.font = .systemFont(ofSize: 15, weight: .heavy)
        caption.maximumNumberOfLines = 2
        caption.lineBreakMode = .byTruncatingTail
        caption.wantsLayer = true
        caption.isHidden = true
        addSubview(caption)
        paletteButton.bezelStyle = .rounded; paletteButton.toolTip = "展开或收起台词清单"
        paletteButton.setAccessibilityLabel("展开或收起台词清单")
        paletteButton.target = owner; addSubview(paletteButton)
        resizeHandle.toolTip = "拖动右下角调整大小"; addSubview(resizeHandle)
        toolTip = "点击按顺序说一句 · 拖动移动 · 右键设置"
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("陈震桌宠，点击按顺序播放一句，拖动移动，右键设置")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() {
        super.layout()
        setPortraitScale(portraitScale)
        overlay.frame = bounds
        resizeHandle.frame = NSRect(x: bounds.width-20, y: 0, width: 20, height: 20)
        paletteButton.frame = NSRect(x: bounds.width - 32*unit, y: bounds.height - avatarRect.midY - 15*unit, width: 30*unit, height: 30*unit)
        caption.frame = NSRect(x: bounds.width * 0.12, y: bounds.height - 98*unit, width: bounds.width * 0.76, height: 56*unit)
        owner?.positionClipPalette()
        for (i, button) in foodButtons.enumerated() {
            button.frame = CGRect(x: (bounds.width - 194*unit)/2 + Double(i)*50*unit, y: 2*unit, width: 44*unit, height: 44*unit)
        }
    }
    func configure(_ library: ActionLibrary, sprites: [String:NSImage]) {
        overlay.sprites = sprites
        for (i, action) in library.actions.enumerated() {
            let button = FoodButton(index: i, action: action, image: sprites[action.icon]!)
            button.host = self; foodButtons.append(button); addSubview(button)
        }
        needsLayout = true; layoutSubtreeIfNeeded()
    }
    func setPortraitScale(_ value: Double) {
        portraitScale = value; let r = avatarRect
        face.frame = CGRect(x: r.minX, y: bounds.height-r.maxY, width: r.width, height: r.height*value)
    }
    func setCaption(_ text: String) {
        let style = NSMutableParagraphStyle(); style.alignment = .center
        caption.attributedStringValue = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .heavy), .foregroundColor: NSColor(calibratedRed: 0.28, green: 0.13, blue: 0.05, alpha: 1), .strokeColor: NSColor(calibratedRed: 1, green: 0.79, blue: 0.48, alpha: 1), .strokeWidth: -2.0, .paragraphStyle: style])
    }
    func buttonCenter(_ index: Int) -> CGPoint {
        CGPoint(x: (bounds.width-194*unit)/2 + Double(index)*50*unit + 22*unit, y: bounds.height-24*unit)
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        bodyPressed = avatarRect.contains(CGPoint(x: point.x, y: bounds.height-point.y))
        guard bodyPressed else { return }
        initialMouse = window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
        initialWindow = window?.frame.origin ?? .zero
        dragged = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard bodyPressed else { return }
        let current = window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
        let dx = current.x - initialMouse.x, dy = current.y - initialMouse.y
        if hypot(dx, dy) > 4 { dragged = true }
        if dragged { window?.setFrameOrigin(NSPoint(x: initialWindow.x + dx, y: initialWindow.y + dy)); owner?.positionClipPalette() }
    }
    override func mouseUp(with event: NSEvent) {
        guard bodyPressed else { return }; bodyPressed = false
        if dragged { owner?.keepVisible(); owner?.savePosition() } else { owner?.playNext() }
    }
    override func rightMouseDown(with event: NSEvent) {
        guard let menu = owner?.makeMenu() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    override func accessibilityPerformPress() -> Bool { owner?.playNext(); return true }
    func animate(_ enabled: Bool) {
        speaking = enabled
        animationTimer?.invalidate(); animationTimer = nil
        phase = 0
        setPortraitScale(1)
        guard enabled, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.phase += 0.60
            // Compress vertically by up to 12%, then return to the original height.
            let heightScale = 1.0 - 0.12 * (1.0 - cos(self.phase)) / 2.0
            self.setPortraitScale(heightScale)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let arguments = CommandLine.arguments
    var selfTest: Bool { arguments.contains("--self-test") }
    var diagnostic: Bool { selfTest || arguments.contains("--snapshot") || arguments.contains("--test-play") || arguments.contains("--action") || arguments.contains("--preview-actions") || arguments.contains("--scene-samples") }
    let defaults = UserDefaults.standard
    var panel: PetPanel!
    var pet: PetView!
    var status: NSStatusItem!
    var clips: [Clip] = []
    var portraits: [Portrait] = []
    var portraitImages: [String:NSImage] = [:]
    var currentPortraitID = "original"
    var players: [Int: BufferedClip] = [:]
    var current: BufferedClip?
    var audioOutput: BufferedAudio!
    var bag = ClipSequence()
    var lastPlayed: Int?
    var lastPortraitID: Int?
    var volume: Float = 0.5
    var size: CGFloat = 260
    var imageRatio: CGFloat = 1
    var captionWork: DispatchWorkItem?
    var captionGeneration = 0
    var completionCount = 0
    var schedulingMS: [Double] = []
    var feeding: FeedingController!
    var clipPalette: PetPanel?
    var resources: URL { Bundle.main.resourceURL! }
    var panelSize: NSSize { NSSize(width: size, height: (size - 16) * (956.0 / 1070.0) + 52 + 114 * size / 260) }

    func option(_ key: String) -> String? {
        guard let index = arguments.firstIndex(of: key), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !diagnostic, let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0.processIdentifier != getpid() }) {
            NSApp.terminate(nil); return
        }
        do {
            clips = try JSONDecoder().decode([Clip].self, from: Data(contentsOf: resources.appendingPathComponent("clips.json")))
            guard !clips.isEmpty, Set(clips.map(\.id)).count == clips.count else { throw failure("台词列表为空或编号重复") }
            portraits = try JSONDecoder().decode([Portrait].self, from: Data(contentsOf: resources.appendingPathComponent("portraits.json")))
            guard !portraits.isEmpty, Set(portraits.map(\.id)).count == portraits.count, portraits.allSatisfy({ $0.mouth.count == 2 && $0.head.count == 2 }) else { throw failure("头像配置无效") }
            for portrait in portraits {
                guard !portrait.file.contains(".."), let image = NSImage(contentsOf: resources.appendingPathComponent(portrait.file)), image.size.width > 0 else { throw failure("头像无法读取：\(portrait.name)") }
                portraitImages[portrait.id] = image
            }
            let savedPortrait = diagnostic ? "original" : (defaults.string(forKey: "portrait") ?? "original")
            currentPortraitID = portraitImages[savedPortrait] != nil ? savedPortrait : "original"
            guard let image = portraitImages[currentPortraitID] else { throw failure("缺少默认头像") }
            imageRatio = image.size.height / image.size.width
            let actions = try JSONDecoder().decode(ActionLibrary.self, from: Data(contentsOf: resources.appendingPathComponent("actions.json")))
            try actions.validate()
            var sprites: [String:NSImage] = [:]
            for name in Set(actions.actions.flatMap { $0.layers.map(\.sprite) + [$0.icon] }).subtracting(["stream"]) {
                guard let sprite = NSImage(contentsOf: resources.appendingPathComponent("Actions/\(name).png")) else { throw failure("缺少动作素材：\(name)") }
                sprites[name] = sprite
            }
            for clip in clips {
                guard clip.id > 0, !clip.label.isEmpty, clip.file == (clip.file as NSString).lastPathComponent,
                      clip.duration.isFinite, clip.duration > 0 else { throw failure("台词配置无效") }
                let file = try AVAudioFile(forReading: resources.appendingPathComponent("Clips/\(clip.file)"))
                guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { throw failure("音频无法解码") }
                try file.read(into: buffer)
                if audioOutput == nil {
                    audioOutput = try BufferedAudio(format: buffer.format)
                    audioOutput.onFinish = { [weak self] clip in self?.audioPlayerDidFinishPlaying(clip, successfully: true) }
                }
                let audio = BufferedClip(buffer: buffer, output: audioOutput)
                guard abs(audio.duration - clip.duration) < 0.15 else { throw failure("音频时长不匹配：\(clip.label)") }
                guard audio.prepareToPlay() else { throw failure("音频无法准备：\(clip.label)") }
                players[clip.id] = audio
            }
            if !diagnostic {
                if defaults.object(forKey: "volume") != nil {
                    let saved = defaults.float(forKey: "volume"); volume = saved.isFinite ? min(1, max(0, saved)) : 0.5
                }
                if defaults.object(forKey: "size") != nil {
                    let saved = defaults.double(forKey: "size"); size = saved.isFinite ? min(340, max(190, saved)) : 260
                }
            }
            panel = PetPanel(contentRect: NSRect(origin: .zero, size: panelSize), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "陈震桌宠"
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
            panel.level = .floating; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            pet = PetView(frame: NSRect(origin: .zero, size: panelSize)); pet.owner = self
            pet.paletteButton.target = self; pet.paletteButton.action = #selector(toggleClipPalette(_:)); pet.resizeHandle.owner = self
            pet.face.image = image
            guard let bubble = NSImage(contentsOf: resources.appendingPathComponent("caption-bubble.png")) else { throw failure("字幕框素材无法读取") }
            pet.caption.bubbleImage = bubble; panel.contentView = pet
            feeding = FeedingController(owner: self, library: actions); pet.configure(actions, sprites: sprites)
            if let selected = portraits.first(where: { $0.id == currentPortraitID }) {
                feeding.library.anchors["mouth"] = selected.mouth; feeding.library.anchors["head"] = selected.head
            }
            restorePosition(); panel.orderFrontRegardless()
            status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            status.button?.title = "陈震"
            status.button?.toolTip = "陈震桌宠 1.3.4 · 点击打开设置"
            status.button?.target = self; status.button?.action = #selector(openStatusMenu)
            NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
            if selfTest { Task { @MainActor in await runSelfTest() } }
            else {
                if let directory = option("--preview-actions") { exportActionPreviews(directory); return }
                if let path = option("--scene-samples") { exportSceneSamples(path); return }
                if let value = option("--test-play"), let id = Int(value), let clip = clips.first(where: { $0.id == id }) { play(clip) }
                if let id = option("--action"), let action = feeding.library.actions.first(where: { $0.id == id }) { feeding.begin(action) }
                if let path = option("--snapshot") { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.snapshot(path) } }
                if let value = option("--exit-after"), let seconds = Double(value) { DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { NSApp.terminate(nil) } }
            }
        } catch {
            if diagnostic { print("FAIL: \(error.localizedDescription)"); exit(1) }
            let alert = NSAlert(); alert.messageText = "陈震桌宠无法启动"; alert.informativeText = error.localizedDescription
            alert.runModal(); NSApp.terminate(nil)
        }
    }

    func failure(_ message: String) -> NSError { NSError(domain: "ChenzhenPet", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    @objc func playNext() {
        guard let id = bag.next(from: clips.map(\.id)), let clip = clips.first(where: { $0.id == id }) else { return }
        play(clip)
        lastPortraitID = id
    }
    func play(_ clip: Clip) {
        let requestStart = ProcessInfo.processInfo.systemUptime
        lastPortraitID = nil
        stopPlayback()
        guard let audio = players[clip.id] else { return }
        audio.currentTime = 0; audio.volume = selfTest ? 0 : volume
        current = audio
        guard audio.prepareToPlay(), audio.play() else { current = nil; showCaption("这句暂时无法播放"); return }
        lastPlayed = clip.id; pet.animate(true); showCaption(clip.label)
        schedulingMS.append((ProcessInfo.processInfo.systemUptime-requestStart)*1000)
    }
    func showCaption(_ text: String) {
        captionWork?.cancel(); captionWork = nil
        pet.setCaption(text); pet.caption.isHidden = false
    }
    func audioPlayerDidFinishPlaying(_ player: BufferedClip, successfully flag: Bool) {
        guard player === current, !player.isPlaying else { return }
        completionCount += 1; current = nil
        if feeding?.isActive == true { feeding.audioFinished(); return }
        pet.animate(false)
        let generation = captionGeneration
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.captionGeneration == generation else { return }
            self.pet.caption.isHidden = true
        }
        captionWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
    func audioPlayerDecodeErrorDidOccur(_ player: BufferedClip, error: Error?) {
        guard player === current else { return }; stopPlayback(); showCaption("音频读取失败")
    }
    @objc func stopPlayback() {
        cancelInteraction()
    }
    func cancelInteraction(cancelDrag: Bool = true) {
        captionGeneration += 1
        feeding?.cancel(cancelDrag: cancelDrag)
        current?.stop(); current = nil; captionWork?.cancel(); captionWork = nil
        pet?.animate(false); pet?.caption.isHidden = true
    }
    @objc func chooseClip(_ sender: NSMenuItem) {
        guard let clip = clips.first(where: { $0.id == sender.tag }) else { return }; play(clip)
    }
    @objc func openStatusMenu() {
        guard let event = NSApp.currentEvent, let button = status.button else { return }
        NSMenu.popUpContextMenu(makeMenu(), with: event, for: button)
    }
    func item(_ title: String, _ action: Selector?, tag: Int = 0) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; item.tag = tag; return item
    }
    func makeMenu() -> NSMenu {
        let menu = NSMenu(); menu.autoenablesItems = false
        let title = item("陈震桌宠 1.3.4 · \(clips.count) 句原声", nil); title.isEnabled = false; menu.addItem(title); menu.addItem(.separator())
        let choose = item("挑一句", nil), choices = NSMenu()
        for clip in clips { choices.addItem(item(clip.label, #selector(chooseClip(_:)), tag: clip.id)) }
        choose.submenu = choices; menu.addItem(choose)
        let portraitsItem = item("更换人像", nil), portraitMenu = NSMenu()
        for (index, portrait) in portraits.enumerated() {
            let entry = item(portrait.name, #selector(choosePortrait(_:)), tag: index)
            entry.state = portrait.id == currentPortraitID ? .on : .off; portraitMenu.addItem(entry)
        }
        portraitsItem.submenu = portraitMenu; menu.addItem(portraitsItem)
        let volumeItem = item("音量", nil), volumes = NSMenu()
        for value in [0, 25, 50, 65, 80, 100] {
            let entry = item(value == 0 ? "静音" : "\(value)%", #selector(setVolume(_:)), tag: value)
            entry.state = abs(volume - Float(value) / 100) < 0.01 ? .on : .off; volumes.addItem(entry)
        }
        volumeItem.submenu = volumes; menu.addItem(volumeItem)
        let sizeItem = item("人物大小", nil), sizes = NSMenu()
        for (name, value) in [("小", 190), ("中", 260), ("大", 340)] {
            let entry = item(name, #selector(setSize(_:)), tag: value); entry.state = Int(size) == value ? .on : .off; sizes.addItem(entry)
        }
        sizeItem.submenu = sizes; menu.addItem(sizeItem)
        menu.addItem(item("移回屏幕右下角", #selector(resetPosition)))
        menu.addItem(.separator()); menu.addItem(item("退出桌宠", #selector(quit)))
        return menu
    }
    @objc func setVolume(_ sender: NSMenuItem) {
        volume = min(1, max(0, Float(sender.tag) / 100)); current?.volume = selfTest ? 0 : volume
        if !diagnostic { defaults.set(volume, forKey: "volume") }
    }
    @objc func setSize(_ sender: NSMenuItem) {
        let bottomRight = NSPoint(x: panel.frame.maxX, y: panel.frame.minY)
        size = CGFloat(sender.tag); panel.setContentSize(panelSize)
        panel.setFrameOrigin(NSPoint(x: bottomRight.x - panel.frame.width, y: bottomRight.y))
        keepVisible(); savePosition()
        if !diagnostic { defaults.set(Double(size), forKey: "size") }
    }
    func restorePosition() {
        if !diagnostic, defaults.object(forKey: "petX") != nil {
            let point = NSPoint(x: defaults.double(forKey: "petX"), y: defaults.double(forKey: "petY"))
            if point.x.isFinite && point.y.isFinite { panel.setFrameOrigin(point); keepVisible(); return }
        }
        placeAtCorner()
    }
    func placeAtCorner() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - panel.frame.width - 32, y: screen.visibleFrame.minY + 24))
        keepVisible()
    }
    func clampedOrigin(_ frame: NSRect, in area: NSRect) -> NSPoint {
        NSPoint(x: max(area.minX, min(frame.minX, area.maxX - frame.width)), y: max(area.minY, min(frame.minY, area.maxY - frame.height)))
    }
    func keepVisible() {
        let frame = panel.frame
        let screen = NSScreen.screens.max { a, b in
            let aa = a.visibleFrame.intersection(frame), bb = b.visibleFrame.intersection(frame)
            return (aa.isNull ? 0 : aa.width * aa.height) < (bb.isNull ? 0 : bb.width * bb.height)
        }
        if let screen { panel.setFrameOrigin(clampedOrigin(frame, in: screen.visibleFrame)) }
    }
    func savePosition() {
        guard !diagnostic, let panel else { return }
        defaults.set(panel.frame.origin.x, forKey: "petX"); defaults.set(panel.frame.origin.y, forKey: "petY")
    }
    @objc func screenChanged() { feeding?.cancelDrag(); keepVisible(); savePosition() }
    @objc func resetPosition() { placeAtCorner(); savePosition() }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        savePosition(); stopPlayback(); NotificationCenter.default.removeObserver(self)
        audioOutput?.shutdown()
        if let status { NSStatusBar.system.removeStatusItem(status) }
    }
    func snapshot(_ path: String) {
        pet.layoutSubtreeIfNeeded()
        guard let bitmap = pet.bitmapImageRepForCachingDisplay(in: pet.bounds) else { return }
        pet.cacheDisplay(in: pet.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
    func exportActionPreviews(_ directory: String) {
        do {
            let base = URL(fileURLWithPath: directory)
            for action in feeding.library.actions {
                let folder = base.appendingPathComponent(action.id)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                for i in 0...Int(ceil(action.duration*15)) {
                    feeding.preview(action, time: min(action.duration, Double(i)/15))
                    pet.displayIfNeeded()
                    snapshot(folder.appendingPathComponent(String(format: "%03d.png", i)).path)
                }
            }
            cancelInteraction(); NSApp.terminate(nil)
        } catch { print("FAIL preview: \(error)"); exit(1) }
    }
    func exportSceneSamples(_ path: String) {
        var rows: [[String:Any]] = []
        for width in [190.0,260.0,340.0] {
            let unit = width/260, height = (width-16)*imageRatio+52+114*unit
            let rect = CGRect(x:8,y:44+70*unit,width:width-16,height:(width-16)*imageRatio)
            for (index, action) in feeding.library.actions.enumerated() {
                let start = CGPoint(x:(width-194*unit)/2+Double(index)*50*unit+22*unit,y:height-24*unit)
                for time in [0.0,0.25,0.7,1.0,1.7,action.duration-0.05,action.duration] {
                    let scale = ActionSampler.squash(time,duration:action.duration)
                    let poses = ActionSampler.sample(action,time:time,library:feeding.library,avatar:rect,start:start,unit:unit,squash:scale)
                    rows.append(["action":action.id,"width":width,"height":height,"time":time,"squash":scale,
                        "poses":poses.map { ["sprite":$0.sprite,"x":$0.center.x,"y":$0.center.y,"width":$0.width,"height":$0.height,"rotation":$0.rotation,"alpha":$0.alpha] as [String:Any] }])
                }
            }
        }
        do { try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:path)); NSApp.terminate(nil) }
        catch { print("FAIL scene samples: \(error)"); exit(1) }
    }

    @MainActor func runSelfTest() async {
        var failures: [String] = []
        func check(_ condition: Bool, _ label: String) { print("\(condition ? "OK" : "FAIL") \(label)"); if !condition { failures.append(label) } }
        check(clips.count == 6, "six original clips loaded")
        check(current == nil && !pet.speaking && pet.caption.isHidden, "launch is silent")
        check(panel.level == .floating && !panel.isOpaque && !panel.canBecomeKey && !panel.canBecomeMain, "transparent floating window does not steal focus")
        if let data = pet.face.image?.tiffRepresentation, let image = NSBitmapImageRep(data: data) {
            check(image.hasAlpha && (image.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.05, "transparent portrait")
        } else { check(false, "portrait decoding") }
        var random = ClipSequence(), previous: Int?, randomOK = true
        for _ in 0..<100 {
            var round: [Int] = []
            for _ in clips { let id = random.next(from: clips.map(\.id))!; if previous == id { randomOK = false }; previous = id; round.append(id) }
            if Set(round).count != clips.count { randomOK = false }
        }
        check(randomOK, "100 ordered rounds without boundary repeats")
        var ordered = ClipSequence()
        let expected = [3,1,2,5,4,6]
        check(clips.map(\.id) == expected, "bundled clip order matches requested order")
        check(clipPalette == nil || clipPalette?.isVisible == false, "palette starts collapsed")
        check((0..<12).compactMap { _ in ordered.next(from: expected) } == expected + expected, "ordered playback cycles through six clips")
        pet.paletteButton.performClick(nil)
        check(clipPalette?.isVisible == true && clipPalette?.contentView?.subviews.count == 6 && pet.paletteButton.acceptsFirstMouse(for: nil), "palette opens with six clips and accepts first click")
        if let list = clipPalette { check(list.frame.intersection(panel.frame).isNull || list.frame.intersection(panel.frame).isEmpty, "palette does not cover character window") }
        if let button = clipPalette?.contentView?.subviews.first(where: { ($0 as? NSButton)?.tag == 2 }) as? NSButton {
            selectPaletteClip(button); selectPaletteClip(button)
            check(current === players[2] && clipPalette?.isVisible == true, "palette remains open while replaying selected clip")
        } else { check(false, "palette clip button") }
        pet.paletteButton.performClick(nil); check(clipPalette?.isVisible == false, "palette closes")
        lastPortraitID = 6; feeding.begin(feeding.library.actions.first { $0.id == "soda" }!)
        check(feeding.lastReply == 2, "soda context accepts soda")
        lastPortraitID = 6; feeding.begin(feeding.library.actions.first { $0.id == "coffee" }!)
        check(feeding.lastReply == 4, "soda context rejects coffee")
        lastPortraitID = 6; feeding.begin(feeding.library.actions.first { $0.id == "noodles" }!)
        check(feeding.lastReply == 4, "soda context overrides noodle response")
        feeding.begin(feeding.library.actions.first { $0.id == "noodles" }!)
        check(feeding.lastReply == 1, "noodles default response")
        feeding.begin(feeding.library.actions.first { $0.id == "pour" }!)
        check(feeding.lastReply == 3, "pour fixed response")
        stopPlayback()
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 50, y: 150), modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        pet.mouseDown(with: down); pet.mouseUp(with: down)
        check(current?.isPlaying == true && pet.speaking && !pet.caption.isHidden, "click starts audio caption and motion")
        let old = current; playNext()
        check(old?.isPlaying == false && current?.isPlaying == true && old !== current, "second click replaces audio")
        for _ in 0..<30 { playNext() }
        check(players.values.filter(\.isPlaying).count == 1 && current?.isPlaying == true, "rapid clicks leave one player")
        stopPlayback()
        check(players.values.allSatisfy { !$0.isPlaying } && !pet.speaking && pet.caption.isHidden, "stop clears audio caption and motion")
        let last = lastPlayed
        pet.mouseDown(with: down)
        let drag = NSEvent.mouseEvent(with: .leftMouseDragged, location: NSPoint(x: 90, y: 70), modifierFlags: [], timestamp: 1, windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        pet.mouseDragged(with: drag); pet.mouseUp(with: drag)
        check(lastPlayed == last && current == nil, "drag does not play")
        check(clampedOrigin(NSRect(x: 5000, y: -200, width: 260, height: 300), in: NSRect(x: 0, y: 0, width: 1440, height: 900)) == NSPoint(x: 1180, y: 0), "offscreen origin recovers")
        let originalSize = size
        let fixed = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        resizeByDrag(width: 300, topLeft: fixed); check(Int(size) == 300, "drag resize changes width")
        resizeByDrag(width: 500, topLeft: fixed); check(Int(size) == 340, "drag resize respects maximum")
        resizeByDrag(width: 100, topLeft: fixed); check(Int(size) == 190, "drag resize respects minimum")
        for width in [190, 260, 340] { setSize(item("", nil, tag: width)); check(Int(panel.frame.width) == width, "resize \(width)") }
        setSize(item("", nil, tag: Int(originalSize)))
        setVolume(item("", nil, tag: 0)); check(volume == 0, "mute setting")
        setVolume(item("", nil, tag: 50)); check(volume == 0.5, "volume setting")
        let menu = makeMenu()
        check(menu.items.first(where: { $0.title == "挑一句" })?.submenu?.items.count == 6 && menu.items.contains(where: { $0.title == "退出桌宠" }), "menu contains six clips and exit")
        for clip in clips {
            let before = completionCount
            play(clip)
            let deadline = Date().addingTimeInterval(clip.duration + 2)
            while completionCount == before && Date() < deadline { try? await Task.sleep(nanoseconds: 30_000_000) }
            check(completionCount == before + 1 && !pet.speaking && current == nil, "natural completion \(clip.id): \(clip.label)")
        }
        // Let a completed clip schedule its hide, then ensure that work cannot hide a newer caption.
        play(clips.max(by: { $0.duration < $1.duration })!); try? await Task.sleep(nanoseconds: 450_000_000)
        check(current?.isPlaying == true && !pet.caption.isHidden, "new caption survives cancelled completion timer")
        stopPlayback()
        func screenPoint(_ point: CGPoint) -> CGPoint {
            panel.convertPoint(toScreen: pet.convert(CGPoint(x: point.x,y: pet.bounds.height-point.y), to: nil))
        }
        check(pet.foodButtons.count == 4, "four feeding buttons")
        check(feeding.library.actions.first(where: { $0.id == "noodles" })?.layers.map(\.sprite) == ["beef", "chopsticks-beef"], "beef action has chopsticks")
        check(portraits.map(\.name) == ["黄色长发", "黑色长发", "短发"], "portrait menu labels")
        check(!makeMenu().items.contains(where: { $0.title == "停止互动" }), "stop removed from menu")
        let commonPanelSize = panel.frame.size
        let commonAvatarHeight = pet.avatarRect.height
        check(abs(pet.caption.frame.midX - pet.bounds.midX) < 0.01 && pet.caption.frame.width < pet.bounds.width * 0.8, "caption centered and compact")
        for portrait in portraits {
            applyPortrait(portrait.id)
            check(currentPortraitID == portrait.id && feeding.library.anchors["mouth"] == portrait.mouth && pet.face.image != nil, "portrait selection \(portrait.id)")
            check(abs(panel.frame.width - commonPanelSize.width) < 0.01 && abs(panel.frame.height - commonPanelSize.height) < 0.01 && abs(pet.avatarRect.height - commonAvatarHeight) < 0.01 && abs(pet.avatarRect.height / pet.avatarRect.width - imageRatio) < 0.001, "portrait consistent height and aspect \(portrait.id): frame=\(panel.frame.size) expected=\(commonPanelSize) rect=\(pet.avatarRect) expectedHeight=\(commonAvatarHeight) ratio=\(imageRatio)")
        }
        applyPortrait("original")
        let bagRemaining = bag.remaining, bagLast = bag.last
        for action in feeding.library.actions {
            feeding.begin(action)
            check(feeding.isActive && current?.isPlaying == true && [1,2,3,4].contains(feeding.lastReply ?? 0), "immediate action response: \(action.id)")
            try? await Task.sleep(nanoseconds: 350_000_000)
            // Exercise the completion event deterministically. Device output latency
            // varies; natural completion itself is tested for all six clips above.
            if let response = current { response.stop(); audioPlayerDidFinishPlaying(response, successfully: true) }
            let alive = current == nil && feeding.isActive && pet.speaking && !pet.caption.isHidden && !pet.overlay.poses.isEmpty
            check(alive, "audio completion leaves action and caption alive: \(action.id)")
            try? await Task.sleep(nanoseconds: UInt64((action.duration-0.35+0.12)*1_000_000_000))
            check(!feeding.isActive && feeding.timer == nil && pet.overlay.poses.isEmpty && pet.caption.isHidden && pet.portraitScale == 1, "action cleanup: \(action.id)")
        }
        check(bag.remaining == bagRemaining && bag.last == bagLast, "feeding responses do not advance speech sequence")
        feeding.begin(feeding.library.actions[1])
        let longResponse = current!; longResponse.numberOfLoops = -1
        _ = longResponse.play()
        try? await Task.sleep(nanoseconds: UInt64((feeding.library.actions[1].duration+0.15)*1_000_000_000))
        check(feeding.visualDone && feeding.timer == nil && current === longResponse && pet.overlay.poses.isEmpty && !pet.caption.isHidden, "faster animation never truncates an unfinished response")
        longResponse.stop(); longResponse.numberOfLoops = 0
        audioPlayerDidFinishPlaying(longResponse, successfully: true)
        check(!feeding.isActive && pet.caption.isHidden, "late audio completion cleans finished visual session")
        feeding.begin(feeding.library.actions[0]); let token = captionGeneration
        feeding.beginDrag(1)
        check(feeding.ghost?.canBecomeKey == false && feeding.ghost?.ignoresMouseEvents == true, "drag ghost is passive and click-through")
        feeding.endDrag(CGPoint(x: panel.frame.minX-100,y: panel.frame.maxY+100))
        try? await Task.sleep(nanoseconds: 220_000_000)
        check(feeding.action?.id == "noodles" && captionGeneration == token && feeding.ghost == nil, "invalid drop returns without interrupting action")
        for i in 0..<4 {
            feeding.beginDrag(i); feeding.updateDrag(screenPoint(CGPoint(x: pet.avatarRect.midX,y: pet.avatarRect.midY)))
            check(pet.overlay.target != nil, "valid drop highlight \(i)")
            feeding.endDrag(screenPoint(CGPoint(x: pet.avatarRect.midX,y: pet.avatarRect.midY)))
            check(feeding.action?.id == feeding.library.actions[i].id && feeding.ghost == nil, "drag starts action \(i)")
        }
        for _ in 0..<20 { feeding.begin(feeding.library.actions.randomElement()!) }
        check(players.values.filter(\.isPlaying).count == 1 && feeding.timer != nil, "rapid actions leave one audio and timeline")
        playNext(); check(!feeding.isActive && pet.overlay.poses.isEmpty, "portrait click cancels feeding")
        feeding.begin(feeding.library.actions[3]); stopPlayback()
        try? await Task.sleep(nanoseconds: 450_000_000)
        check(!feeding.isActive && pet.overlay.poses.isEmpty && pet.caption.isHidden && feeding.ghost == nil, "stop clears animation and stale callbacks")
        for width in [190,260,340] {
            setSize(item("",nil,tag:width)); pet.layoutSubtreeIfNeeded()
            feeding.begin(feeding.library.actions[1]); feeding.render(1)
            check(pet.foodButtons.allSatisfy { pet.bounds.contains($0.frame) } && pet.avatarRect.width > 0 && pet.overlay.poses.allSatisfy { $0.center.x.isFinite && $0.center.y.isFinite }, "feeding layout \(width)")
            stopPlayback()
        }
        setSize(item("",nil,tag:Int(originalSize)))
        if !schedulingMS.isEmpty {
            let metrics: [String:Any] = ["backend":"AVAudioEngine / predecoded PCM", "measurement":"main-thread request to scheduled playback; excludes physical device latency", "requests":schedulingMS.count, "meanMS":schedulingMS.reduce(0,+)/Double(schedulingMS.count), "maxMS":schedulingMS.max()!]
            if let path = option("--latency-report"), let data = try? JSONSerialization.data(withJSONObject:metrics,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:URL(fileURLWithPath:path)) }
        }
        if let path = option("--snapshot") { snapshot(path) }
        print(failures.isEmpty ? "PASS all desktop pet checks" : "FAIL \(failures.count) checks")
        fflush(stdout); exit(failures.isEmpty ? 0 : 1)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

