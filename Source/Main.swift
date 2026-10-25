import AppKit
import ApplicationServices
import ScreenCaptureKit
import Vision

let lightroomID = "com.adobe.LightroomClassicCC7"
let eventTag: Int64 = 0x4C525748
let qaEventTag: Int64 = 0x4C525751

final class WheelApp: NSObject, NSApplicationDelegate, @unchecked Sendable {
    var window: NSWindow!
    var statusItem: NSStatusItem!
    var statusLabel: NSTextField!
    var permissionLabel: NSTextField!
    var detailLabel: NSTextField!
    var enableButton: NSButton!
    var enabled = false
    var wantsAutomaticStart = true
    var lastStartAttempt = Date.distantPast
    var scanning = false
    var editing = false
    var rows: [SliderRow] = []
    var cachedPID: pid_t = 0
    var tap: CFMachPort?
    var timer: Timer?
    var accumulator = WheelAccumulator()
    var lastEdit = 0.0
    var pending: (SliderRow, Int, Bool, Bool)?
    var diagnostic = ""
    var lastGesture = 0.0
    var activeGesture: SliderRow?
    var lastWheel = "ยังไม่มีสัญญาณล้อ"
    var mappingSummary = "ยังไม่ได้อ่านหน้าต่าง"
    var debugWindow: NSWindow?
    var lastDetectedRows: [SliderRow] = []
    var testRunning = false
    let bridge = LightroomBridge()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildUI()
        timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            self?.tick()
        }
        updateUI()
        attemptAutomaticStart()
        if !AXIsProcessTrusted() || !CGPreflightScreenCaptureAccess() { show() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return true }

    func buildUI() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem(); mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu(); appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit Lightroom Wheel", action: #selector(quit), keyEquivalent: "q").target = self
        NSApp.mainMenu = mainMenu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 485), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Lightroom Wheel · Free"
        window.center(); window.isReleasedWhenClosed = false
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 15
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 25),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -25),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24)
        ])
        func text(_ value: String, size: CGFloat = 13, bold: Bool = false) -> NSTextField {
            let field = NSTextField(wrappingLabelWithString: value)
            field.font = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
            field.preferredMaxLayoutWidth = 450; return field
        }
        stack.addArrangedSubview(text("ชี้สไลเดอร์ แล้วหมุนล้อ", size: 25, bold: true))
        stack.addArrangedSubview(text("สำหรับ Lightroom Classic บน Mac · รุ่นทดลอง 0.2 · SDK Bridge\nรองรับตัวปรับ 13 รายการในแผง Basic ภาษาอังกฤษ"))
        statusLabel = text("ปิดอยู่", size: 16, bold: true); stack.addArrangedSubview(statusLabel)
        permissionLabel = text(""); stack.addArrangedSubview(permissionLabel)
        let permissions = NSStackView(); permissions.spacing = 8
        for (title, action) in [("1. อนุญาต Accessibility", #selector(accessibility)), ("2. อนุญาตอ่านหน้าต่าง", #selector(screenAccess))] {
            let b = NSButton(title: title, target: self, action: action); b.bezelStyle = .rounded; permissions.addArrangedSubview(b)
        }
        stack.addArrangedSubview(permissions)
        enableButton = NSButton(title: "เริ่มใช้งาน", target: self, action: #selector(toggle)); enableButton.bezelStyle = .rounded
        stack.addArrangedSubview(enableButton)
        detailLabel = text("อ่านแผง Basic และส่งค่าตรงผ่านปลั๊กอินฟรีใน Classic ไม่เก็บภาพ ไม่ส่งข้อมูลออนไลน์")
        stack.addArrangedSubview(detailLabel)
        stack.addArrangedSubview(text("หมุนขึ้น = เพิ่ม · หมุนลง = ลด\nShift = ละเอียด · Control = เร็วขึ้น 5 เท่า\nOption + หมุน = เลื่อนแผงตามปกติ\nหยุดได้จากไอคอนล้อบนแถบเมนู", size: 12))
        let help = NSButton(title: "ตรวจใหม่ / อัปเดตสถานะสิทธิ์", target: self, action: #selector(refresh)); help.bezelStyle = .rounded
        stack.addArrangedSubview(help)
        let debug = NSButton(title: "ดูรายละเอียดสำหรับทดสอบ", target: self, action: #selector(showDebug)); debug.bezelStyle = .rounded
        stack.addArrangedSubview(debug)
        let test = NSButton(title: "ทดสอบล้อ Exposure และคืนค่าเดิม", target: self, action: #selector(selfTest)); test.bezelStyle = .rounded
        stack.addArrangedSubview(test)
        window.setContentSize(NSSize(width: 500, height: 525))
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "computermouse", accessibilityDescription: "Lightroom Wheel")
        let menu = NSMenu()
        menu.addItem(withTitle: "Lightroom Wheel · Free", action: #selector(show), keyEquivalent: "").target = self
        menu.addItem(withTitle: "เริ่ม / หยุด", action: #selector(toggle), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "ออกจากตัวช่วย", action: #selector(quit), keyEquivalent: "").target = self
        statusItem.menu = menu
    }

    @objc func show() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    func activateLightroom() {
        guard let lr=NSRunningApplication.runningApplications(withBundleIdentifier:lightroomID).first else {return}
        NSApp.yieldActivation(to:lr)
        _ = lr.activate(from:.current,options:[])
    }
    @objc func showDebug() {
        let text = "\(mappingSummary)\n\n\(lastWheel)\n\n" + lastDetectedRows.map { "\($0.spec.name) = \($0.value) track=\($0.track) value=\($0.valuePoint)" }.joined(separator: "\n")
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 730, height: 420), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "Lightroom Wheel · Diagnostics"; panel.center(); panel.isReleasedWhenClosed = false
        let scroll=NSScrollView(frame:panel.contentView!.bounds);scroll.hasVerticalScroller=true;scroll.autoresizingMask=[.width,.height]
        let view=NSTextView(frame:scroll.bounds);view.isEditable=false;view.font = .monospacedSystemFont(ofSize:12,weight:.regular);view.string=text;view.autoresizingMask=[.width];view.textContainer?.widthTracksTextView=true
        scroll.documentView=view;panel.contentView!.addSubview(scroll);debugWindow=panel;panel.makeKeyAndOrderFront(nil)
    }
    @objc func selfTest() {
        guard !testRunning, AXIsProcessTrusted(), CGPreflightScreenCaptureAccess(), installTap() else { return }
        testRunning = true; enabled = true; diagnostic = "กำลังทดสอบล้อและคืนค่า…"; updateUI()
        let originalPointer = CGEvent(source:nil)!.location
        activateLightroom()
        Task { @MainActor in
            var original:BridgeState?
            defer { CGWarpMouseCursorPosition(originalPointer); testRunning=false; updateUI(); show() }
            do {
                try await Task.sleep(nanoseconds:650_000_000)
                guard frontIsDevelop() else { throw BridgeError.message("Classic ต้องเป็นแอปด้านหน้าใน Develop") }
                let baseline=try bridge.state(); original=baseline
                guard let old=baseline.values["Exposure"] else { throw BridgeError.message("SDK อ่าน Exposure ไม่ได้") }
                let fresh=try await detectRows(); rows=fresh
                guard let exposure=fresh.first(where:{$0.spec.name == "Exposure"}),old < 4.95 else { throw BridgeError.message("อ่านตำแหน่ง Exposure ไม่ได้ หรือค่าอยู่ใกล้ขอบเขต") }
                var point=CGPoint(x:exposure.track.midX,y:exposure.track.midY)
                func sendWheel(_ delta:Int32) {
                    CGWarpMouseCursorPosition(point)
                    CGEvent(mouseEventSource:nil,mouseType:.mouseMoved,mouseCursorPosition:point,mouseButton:.left)?.post(tap:.cghidEventTap)
                    let e=CGEvent(scrollWheelEvent2Source:nil,units:.line,wheelCount:1,wheel1:delta,wheel2:0,wheel3:0)!
                    e.location=point;e.flags=[];e.setIntegerValueField(.eventSourceUserData,value:qaEventTag);e.post(tap:.cghidEventTap)
                }
                sendWheel(1)
                try await Task.sleep(nanoseconds:2_000_000_000)
                let changed=try bridge.state()
                guard changed.photo==baseline.photo, let value=changed.values["Exposure"],abs(value-exposure.spec.adjusted(old,ticks:1,fineMode:false))<0.004 else { throw BridgeError.message("ล้อยังไม่เพิ่มค่า Exposure ตามที่คาด") }
                activateLightroom()
                try await Task.sleep(nanoseconds:650_000_000)
                enabled=true;rows=try await detectRows()
                guard let latest=rows.first(where:{$0.spec.name == "Exposure"}) else { throw BridgeError.message("อ่านตำแหน่ง Exposure รอบคืนค่าไม่ได้") }
                point=CGPoint(x:latest.track.midX,y:latest.track.midY)
                sendWheel(-1)
                try await Task.sleep(nanoseconds:2_000_000_000)
                let reverted=try bridge.state()
                guard reverted.photo==baseline.photo,let result=reverted.values["Exposure"],abs(result-old)<0.004 else { throw BridgeError.message("ล้อหมุนกลับยังไม่คืนค่าเดิม") }
                diagnostic="ผ่าน · ล้อเพิ่มค่าและคืนค่าเดิมแล้ว"
                detailLabel.stringValue="Exposure \(exposure.spec.format(old)) → \(exposure.spec.format(value)) → \(exposure.spec.format(old)) · ยืนยันผ่าน SDK"
                rows=try await detectRows()
            } catch {
                enabled=false;pending=nil
                diagnostic="ทดสอบหยุด: \(error.localizedDescription)"
                if let baseline=original,let old=baseline.values["Exposure"] {
                    do {
                        let current=try bridge.state()
                        if current.photo==baseline.photo,let value=current.values["Exposure"],abs(value-old)>0.004 {
                            let restored=try await bridge.command("Exposure",amount:old,absolute:true,photo:baseline.photo)
                            if abs(restored.after-old)<0.004 { diagnostic += " · คืนค่าเดิมแล้ว" }
                        }
                    } catch { diagnostic += " · คืนค่าไม่สำเร็จ กรุณาตรวจ Exposure" }
                }
            }
        }
    }
    @objc func quit() { enabled = false; if let tap { CGEvent.tapEnable(tap: tap, enable: false) }; NSApp.terminate(nil) }
    @objc func accessibility() {
        // Permission is requested only after the user presses this explicit button.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        updateUI()
    }
    @objc func screenAccess() { _ = CGRequestScreenCaptureAccess(); updateUI() }
    @objc func refresh() { rows = []; diagnostic = ""; updateUI(); tick() }
    @objc func toggle() {
        if enabled { wantsAutomaticStart = false; enabled = false; rows = []; pending = nil; updateUI(); return }
        wantsAutomaticStart = true
        guard AXIsProcessTrusted(), CGPreflightScreenCaptureAccess() else {
            let alert = NSAlert(); alert.messageText = "ยังขาดสิทธิ์ที่จำเป็น"
            alert.informativeText = "กดปุ่มอนุญาตทั้งสองด้านบน แล้วเปิดสวิตช์ Lightroom Wheel ใน System Settings ตัวช่วยจะอ่านเฉพาะหน้าต่าง Lightroom และส่งการปรับค่าที่คุณสั่งด้วยล้อเมาส์"
            alert.runModal(); updateUI(); return
        }
        guard installTap() else { diagnostic = "เปิดตัวรับล้อไม่ได้ ให้ปิดแล้วเปิดแอปหลังอนุญาต Accessibility"; updateUI(); return }
        do { _ = try bridge.state() } catch { diagnostic = error.localizedDescription; updateUI(); return }
        enabled = true; diagnostic = ""; rows = []; updateUI()
        window.orderBack(nil)
        activateLightroom()
    }
    func updateUI() {
        let ax = AXIsProcessTrusted(), screen = CGPreflightScreenCaptureAccess()
        permissionLabel.stringValue = "Accessibility: \(ax ? "พร้อม" : "ยังไม่อนุญาต")   ·   อ่านหน้าต่าง: \(screen ? "พร้อม" : "ยังไม่อนุญาต")"
        enableButton.title = enabled ? "หยุดใช้งาน" : "เริ่มใช้งาน"
        statusLabel.stringValue = !diagnostic.isEmpty ? diagnostic : (enabled ? (rows.isEmpty ? "กำลังรอแผง Basic ใน Develop…" : "พร้อม · ตรวจพบ \(rows.count) สไลเดอร์") : "ปิดอยู่ · ยังไม่เปลี่ยนค่าภาพ")
        statusItem.button?.contentTintColor = enabled && !rows.isEmpty ? .systemGreen : nil
    }

    func frontIsDevelop() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier == lightroomID else { return false }
        let app = AXUIElementCreateApplication(front.processIdentifier)
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &windowValue) == .success,
              let windowValue else { return false }
        let win = unsafeBitCast(windowValue, to: AXUIElement.self)
        var title: CFTypeRef?, role: CFTypeRef?
        AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &title)
        AXUIElementCopyAttributeValue(win, kAXRoleAttribute as CFString, &role)
        return (title as? String)?.hasSuffix("- Develop") == true && (role as? String) == kAXWindowRole
    }
    func tick() {
        attemptAutomaticStart()
        updateUI()
        guard enabled, !scanning, !editing, frontIsDevelop() else {
            if !frontIsDevelop() { rows = [] }; return
        }
        scanning = true
        Task { @MainActor in
            defer { scanning = false }
            do { let found = try await detectRows(); if enabled && frontIsDevelop() { rows = found; updateUI() } }
            catch { rows = []; diagnostic = "อ่านแผงไม่สำเร็จ: \(error.localizedDescription)"; updateUI() }
        }
    }

    func attemptAutomaticStart() {
        guard wantsAutomaticStart, !enabled, !testRunning,
              Date().timeIntervalSince(lastStartAttempt) >= 5 else { return }
        lastStartAttempt = Date()
        guard AXIsProcessTrusted(), CGPreflightScreenCaptureAccess() else {
            diagnostic = "รอสิทธิ์ Accessibility และอ่านหน้าต่าง"; return
        }
        do { _ = try bridge.state() } catch {
            diagnostic = "รอเปิด Lightroom Classic และปลั๊กอิน · จะเชื่อมต่ออัตโนมัติ"; return
        }
        guard installTap() else { diagnostic = "เปิดตัวรับล้อไม่ได้ · ลองใหม่อัตโนมัติ"; return }
        rows = []; diagnostic = ""; enabled = true
    }

    func detectRows() async throws -> [SliderRow] {
        guard let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier == lightroomID, frontIsDevelop() else { return [] }
        let pid = front.processIdentifier
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let win = content.windows.first(where: { $0.owningApplication?.processID == pid && $0.title?.hasSuffix("- Develop") == true && $0.frame.width > 500 && $0.frame.height > 400 }) else { return [] }
        let frame = win.frame
        let filter = SCContentFilter(desktopIndependentWindow: win)
        let config = SCStreamConfiguration()
        // Capture only the right-hand controls, excluding the photograph and filmstrip.
        // SCStreamConfiguration.sourceRect is in the display's logical coordinates,
        // for both display and independent-window streams (Apple SDK SCStream.h).
        let crop = CGRect(x: frame.minX + max(0, frame.width - 300), y: frame.minY + 140, width: min(300, frame.width), height: max(1, frame.height - 420))
        config.sourceRect = crop; config.width = Int(crop.width * 2); config.height = Int(crop.height * 2)
        config.showsCursor = false; config.ignoreShadowsSingleWindow = true
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        mappingSummary = "SC frame=\(frame) content=\(filter.contentRect) crop=\(crop) image=\(image.width)x\(image.height)"
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]; request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.008
        try VNImageRequestHandler(cgImage: image).perform([request])
        var boxes: [TextBox] = []
        for result in request.results ?? [] {
            guard let candidate = result.topCandidates(1).first else { continue }
            let r = result.boundingBox
            let global = CGRect(x: crop.minX + r.minX * crop.width, y: crop.minY + (1-r.maxY)*crop.height, width: r.width*crop.width, height: r.height*crop.height)
            boxes.append(.init(text: candidate.string, rect: global, confidence: candidate.confidence))
        }
        // OCR identifies labels only; the SDK is authoritative for numeric values.
        let sdk = try bridge.state()
        guard sdk.module == "develop", sdk.count == 1 else { return [] }
        boxes.removeAll { Detector.number($0.text) != nil }
        for spec in ControlSpec.all {
            guard let value = sdk.values[spec.name], (spec.minimum...spec.maximum).contains(value) else { continue }
            for label in boxes.filter({ $0.text == spec.name && $0.confidence >= 0.6 }) {
                boxes.append(.init(text:spec.format(value),rect:CGRect(x:crop.maxX-75,y:label.rect.minY,width:30,height:label.rect.height),confidence:1))
            }
        }
        cachedPID = pid
        mappingSummary += "\nOCR: " + boxes.map(\.text).joined(separator: " | ")
        let detected = Detector.rows(boxes, window: frame, windowID: win.windowID, seen: Date.timeIntervalSinceReferenceDate)
        if !detected.isEmpty { lastDetectedRows = detected }
        if ProcessInfo.processInfo.environment["LRW_DIAGNOSTICS"] == "1" {
            // Diagnostics contain control labels/values only, never image pixels or image names.
            let report = boxes.map { "\($0.text) \($0.rect)" }.joined(separator: "\n")
            try? report.write(toFile: NSTemporaryDirectory()+"lightroom-wheel-controls.txt", atomically: true, encoding: .utf8)
        }
        return detected
    }

    func installTap() -> Bool {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true); return true }
        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        let callback: CGEventTapCallBack = { proxy, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let app = Unmanaged<WheelApp>.fromOpaque(info).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = app.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            return app.handleWheel(event) ? nil : Unmanaged.passUnretained(event)
        }
        guard let created = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        tap = created
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
        return true
    }

    func handleWheel(_ event: CGEvent) -> Bool {
        // During QA, only the tagged test wheels may change SDK values.
        if testRunning && event.getIntegerValueField(.eventSourceUserData) != qaEventTag { return false }
        if testRunning { lastWheel = "QA received: enabled=\(enabled) front=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none") " }

        if enabled && NSWorkspace.shared.frontmostApplication?.bundleIdentifier == lightroomID { lastWheel = "wheel \(event.location), delta=\(event.getDoubleValueField(.scrollWheelEventDeltaAxis1)), precise=\(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)), front=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none")" }
        guard enabled, !event.flags.contains(.maskAlternate), !event.flags.contains(.maskCommand),
              event.getIntegerValueField(.eventSourceUserData) != eventTag,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == lightroomID else { return false }
        let now = Date.timeIntervalSinceReferenceDate
        let inputPoint = event.location
        let candidate = rows.first(where: { $0.track.contains(inputPoint) && now - $0.seen < 0.9 })
            ?? (frontIsDevelop() ? lastDetectedRows.first(where: { $0.track.contains(inputPoint) }) : nil)
        let locked = activeGesture.flatMap { now-lastGesture < 0.7 && $0.track.contains(inputPoint) ? $0 : nil }
        guard let row = candidate ?? locked else {
            if enabled { lastWheel += " · no matching track" }
            // Any native panel scroll invalidates all cached positions immediately.
            rows = []; return false
        }
        let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let delta = continuous ? event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) : event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
        guard delta != 0 else { return false }
        activeGesture = row; lastGesture = now
        // Momentum must not continue changing exposure after the fingers leave a trackpad.
        if event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0 { return true }
        let ticks = accumulator.consume(delta: delta, continuous: continuous, control: row.spec.name, time: now)
        lastWheel += " · matched \(row.spec.name) ticks=\(ticks)"
        guard ticks != 0 else { return true }
        let fine = event.flags.contains(.maskShift), fast = event.flags.contains(.maskControl)
        if let old = pending, old.0.spec.name == row.spec.name { pending = (row, max(-20,min(20,old.1+ticks)), fine, fast) }
        else { pending = (row, ticks, fine, fast) }
        if !editing {
            editing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { self.flushEdit() }
        }
        return true
    }

    func flushEdit() {
        guard let (old, ticks, fine, fast) = pending, enabled, frontIsDevelop() else { lastWheel += " · flush rejected before capture"; editing = false; pending = nil; return }
        lastWheel += " · flush start"
        pending = nil
        Task { @MainActor in
            defer {
                editing = false
                if pending != nil && enabled {
                    editing = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { self.flushEdit() }
                }
            }
            do {
                let fresh = try await detectRows()
                guard enabled, frontIsDevelop(), let row = fresh.first(where: { $0.spec.name == old.spec.name && $0.windowID == old.windowID && $0.window == old.window && abs($0.valuePoint.y-old.valuePoint.y) < 3 && abs($0.valuePoint.x-old.valuePoint.x) < 5 }) else { lastWheel += " · fresh mapping rejected"; rows = []; return }
                let pointer = CGEvent(source: nil)!.location
                guard testRunning || row.track.insetBy(dx: -2, dy: -2).contains(pointer) else { lastWheel += " · pointer moved"; rows = fresh; return }
                let state = try bridge.state()
                let quantum = (fine ? row.spec.fine : row.spec.step) * (fast ? 5 : 1)
                let reply = try await bridge.command(row.spec.name, amount: Double(ticks)*quantum, photo: state.photo)
                let expected = row.spec.adjusted(reply.before,ticks:ticks,fineMode:fine,fast:fast)
                guard abs(reply.after-expected)<0.004 else { throw BridgeError.message("ค่าที่ปลั๊กอินยืนยันไม่ตรงกับคำสั่ง") }
                lastWheel += " · SDK verified \(reply.before) → \(reply.after)"
                detailLabel.stringValue = "ยืนยันผ่าน SDK · \(row.spec.name): \(row.spec.format(reply.before)) → \(row.spec.format(reply.after))"
                lastEdit = Date.timeIntervalSinceReferenceDate
                rows = fresh
            } catch { enabled = false; pending = nil; rows = []; diagnostic = error.localizedDescription; updateUI() }
        }
    }
}

@main struct Launcher {
    static func main() {
        let delegate = WheelApp()
        let app = NSApplication.shared
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
