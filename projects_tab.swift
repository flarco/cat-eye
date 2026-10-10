import Cocoa

// ─── Projects tab ────────────────────────────────────────────────────────────

func projectColor(_ name: String) -> NSColor {
    switch name.uppercased() {
    case "GREEN": return C_SUCCESS
    case "RED": return C_FAILURE
    case "ORANGE": return C_QUEUED
    case "YELLOW": return NSColor(srgbRed: 0.94, green: 0.89, blue: 0.26, alpha: 1)
    case "BLUE": return C_RUNNING
    case "PURPLE": return NSColor(srgbRed: 0.80, green: 0.47, blue: 0.65, alpha: 1)
    case "PINK": return NSColor(srgbRed: 0.84, green: 0.37, blue: 0.55, alpha: 1)
    default: return .secondaryLabelColor
    }
}

func runInTerminal(_ command: String) {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    proc.arguments = ["-e", "tell application \"Terminal\" to do script \"\(command)\""]
    proc.standardOutput = FileHandle.nullDevice
    proc.standardError = FileHandle.nullDevice
    try? proc.run()
}

final class StatusGlyph: NSView {
    let category: StatusCategory
    let color: NSColor
    init(category: StatusCategory, color: NSColor, name: String) {
        self.category = category
        self.color = color
        super.init(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
        toolTip = name
        setAccessibilityLabel(name)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let c = color
        let r = bounds.insetBy(dx: 1.5, dy: 1.5)
        switch category {
        case .todo:
            let p = NSBezierPath(ovalIn: r)
            p.lineWidth = 1.3
            let dash: [CGFloat] = [2, 1.5]
            p.setLineDash(dash, count: 2, phase: 0)
            c.setStroke(); p.stroke()
        case .progress:
            let p = NSBezierPath()
            p.appendArc(withCenter: NSPoint(x: bounds.midX, y: bounds.midY), radius: r.width / 2,
                        startAngle: 200, endAngle: -20, clockwise: true)
            p.lineWidth = 1.6; p.lineCapStyle = .round
            c.setStroke(); p.stroke()
        case .review:
            let p = NSBezierPath(ovalIn: r)
            p.lineWidth = 1.4; c.setStroke(); p.stroke()
            c.setFill()
            NSBezierPath(ovalIn: NSRect(x: bounds.midX - 1.6, y: bounds.midY - 1.6, width: 3.2, height: 3.2)).fill()
        case .blocked:
            c.setFill()
            NSBezierPath(roundedRect: NSRect(x: 2, y: 6, width: bounds.width - 4, height: 4), xRadius: 1, yRadius: 1).fill()
        case .done:
            let p = NSBezierPath()
            p.move(to: NSPoint(x: 3, y: 8))
            p.line(to: NSPoint(x: 6.5, y: 4.5))
            p.line(to: NSPoint(x: 13, y: 12))
            p.lineWidth = 1.7; p.lineCapStyle = .round; p.lineJoinStyle = .round
            c.setStroke(); p.stroke()
        }
    }
}

// Borderless panel for text the row had to cut. Shown after a short hover.
enum HoverCard {
    private static var panel: NSPanel?
    private static var timer: Timer?
    static func schedule(_ text: String, from view: NSView) {
        cancel()
        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { _ in show(text, from: view) }
    }
    static func cancel() { timer?.invalidate(); timer = nil }
    static func close() { cancel(); panel?.orderOut(nil); panel = nil }

    static func show(_ text: String, from view: NSView) {
        guard view.window != nil, !text.isEmpty else { return }
        close()
        let font = NSFont.systemFont(ofSize: 12)
        let maxW: CGFloat = 360
        let h = min(160, textHeight(text, font: font, width: maxW - 16) + 16)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: maxW, height: h),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.backgroundColor = .windowBackgroundColor
        panel.isOpaque = false
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = font
        label.frame = NSRect(x: 8, y: 6, width: maxW - 16, height: h - 12)
        let box = NSView(frame: panel.contentView!.bounds)
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        box.layer?.cornerRadius = 6
        box.layer?.borderWidth = 0.5
        box.layer?.borderColor = NSColor.separatorColor.cgColor
        box.addSubview(label)
        panel.contentView = box
        let origin = view.window!.convertToScreen(view.convert(view.bounds, to: nil))
        panel.setFrameOrigin(NSPoint(x: origin.minX, y: origin.maxY + 4))
        panel.orderFront(nil)
        self.panel = panel
    }
}

final class StackedBar: NSView {
    let parts: [(NSColor, Int)]
    init(parts: [(NSColor, Int)], frame: NSRect) {
        self.parts = parts
        super.init(frame: frame)
        let total = parts.map(\.1).reduce(0, +)
        toolTip = parts.map { "\($0.1)" }.joined(separator: " · ") + (total > 0 ? " items" : "")
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        let total = CGFloat(parts.map(\.1).reduce(0, +))
        guard total > 0 else { return }
        var x: CGFloat = 0
        let path = NSBezierPath(roundedRect: bounds, xRadius: 3, yRadius: 3)
        path.addClip()
        for (color, n) in parts where n > 0 {
            let w = bounds.width * CGFloat(n) / total
            color.setFill()
            NSRect(x: x, y: 0, width: w, height: bounds.height).fill()
            x += w
        }
    }
}

final class ProjectHeader: NSView {
    let key: String
    var onRefresh: (() -> Void)?
    var onFilter: ((String) -> Void)?

    init(snap: ProjectSnapshot, live: Bool, refreshing: Bool, filter: String?, updated: String, w: CGFloat) {
        self.key = snap.summary.ref.key
        let chips = snap.statusOptions
        let rows = chips.isEmpty ? 1 : 1
        let h: CGFloat = 36 + CGFloat(rows) * 22 + 14
        super.init(frame: NSRect(x: 0, y: 0, width: w, height: h))
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.9).cgColor

        let owner = Badge(snap.summary.ref.owner, maxChars: 16, tint: repoColor(snap.summary.ref.owner))
        owner.frame.origin = NSPoint(x: 12, y: h - 26)
        addSubview(owner)
        let title = NSTextField(labelWithString: snap.summary.ref.owner.uppercased() + "  ›  " + snap.summary.title)
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        title.frame = NSRect(x: 12 + owner.frame.width + 8, y: h - 26, width: w - 280, height: 18)
        addSubview(title)

        let chip = Badge(live ? "Live" : "Every \(PROJECTS_CFG.pollMinutes) min", tint: live ? C_SUCCESS : nil)
        chip.frame.origin = NSPoint(x: w - 250, y: h - 26)
        addSubview(chip)

        if refreshing {
            let sp = NSProgressIndicator(frame: NSRect(x: w - 148, y: h - 24, width: 16, height: 16))
            sp.style = .spinning; sp.controlSize = .small; sp.startAnimation(nil)
            addSubview(sp)
        } else {
            let reload = NSButton(image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh \(snap.summary.title)")!,
                                  target: self, action: #selector(refresh))
            reload.isBordered = false
            reload.contentTintColor = .secondaryLabelColor
            reload.symbolConfiguration = .init(pointSize: 11, weight: .semibold)
            reload.frame = NSRect(x: w - 150, y: h - 26, width: 20, height: 20)
            reload.toolTip = "Get the latest items from GitHub · updated \(updated)"
            addSubview(reload)
        }
        let link = NSTextField(labelWithString: "Open Project")
        link.font = .systemFont(ofSize: 11, weight: .medium); link.textColor = .linkColor
        link.frame = NSRect(x: w - 120, y: h - 24, width: 108, height: 16); link.alignment = .right
        addSubview(link)
        let click = Clicker(snap.summary.url)
        click.frame = NSRect(x: w - 124, y: h - 32, width: 124, height: 28)
        addSubview(click)

        var x: CGFloat = 12
        for opt in chips {
            let on = filter == opt.id
            let b = NSButton(title: "\(opt.name) \(snap.items.filter { $0.statusOptionId == opt.id }.count)", target: self, action: #selector(chip(_:)))
            b.bezelStyle = .inline
            b.font = .systemFont(ofSize: 10, weight: on ? .bold : .medium)
            b.contentTintColor = projectColor(opt.color)
            b.identifier = NSUserInterfaceItemIdentifier(opt.id)
            b.sizeToFit()
            b.frame = NSRect(x: x, y: 16, width: b.frame.width + 8, height: 18)
            b.toolTip = on ? "Show every status" : "Show only \(opt.name)"
            addSubview(b)
            x += b.frame.width + 4
            if x > w - 140 { break }
        }
        let parts = chips.map { chip in
            (projectColor(chip.color), snap.items.filter { $0.statusOptionId == chip.id }.count)
        }
        addSubview(StackedBar(parts: parts, frame: NSRect(x: 12, y: 6, width: w - 24, height: 6)))
        let counts = snap.counts.map { "\($0.value) \($0.key.label.lowercased())" }.sorted().joined(separator: ", ")
        toolTip = counts
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc func refresh() { onRefresh?() }
    @objc func chip(_ sender: NSButton) { onFilter?(sender.identifier?.rawValue ?? "") }
}

final class ProjectItemRow: NSView {
    var onToggle: (() -> Void)?
    let urlStr: String
    let expanded: Bool
    init(item: ProjectItem, snap: ProjectSnapshot, unread: Bool, last: String?, w: CGFloat, expanded: Bool) {
        self.urlStr = item.url ?? snap.summary.url
        self.expanded = expanded
        super.init(frame: NSRect(x: 0, y: 0, width: w, height: ROW_H))
        wantsLayer = true
        layer?.backgroundColor = expanded ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.1).cgColor : nil
        let opt = snap.option(item.statusOptionId)
        let glyph = StatusGlyph(category: opt?.category ?? .todo, color: projectColor(opt?.color ?? "GRAY"), name: opt?.name ?? "No status")
        glyph.frame.origin = NSPoint(x: 14, y: (ROW_H - 16) / 2)
        addSubview(glyph)
        if unread {
            let dot = Dot(color: C_RUNNING, frame: NSRect(x: 28, y: ROW_H - 16, width: 6, height: 6))
            dot.toolTip = "Unread"
            addSubview(dot)
        }
        let textX: CGFloat = 42
        let title = NSTextField(labelWithString: item.title)
        title.font = .systemFont(ofSize: 12.5, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        title.frame = NSRect(x: textX, y: ROW_H - 24, width: w - textX - 200, height: 18)
        title.toolTip = item.title
        addSubview(title)
        var x = textX
        if let repo = item.repo, let n = item.number {
            let b = Badge("\(repo.split(separator: "/").last ?? "")#\(n)", maxChars: 22)
            b.frame.origin = NSPoint(x: x, y: 6)
            addSubview(b)
            x += b.frame.width + 6
        }
        let kind = item.kind == .pullRequest ? "PR" : item.kind == .draft ? "Draft" : "Issue"
        let kb = Badge(kind)
        kb.frame.origin = NSPoint(x: x, y: 6)
        addSubview(kb)
        x += kb.frame.width + 6
        if let pri = item.fields["Priority"] {
            let pb = Badge(pri, tint: projectColor("ORANGE"))
            pb.frame.origin = NSPoint(x: x, y: 6)
            addSubview(pb)
        }
        let who = item.assignees.isEmpty ? "" : item.assignees.prefix(2).joined(separator: ", ")
        let meta = NSTextField(labelWithString: who)
        meta.font = .systemFont(ofSize: 10); meta.textColor = .secondaryLabelColor
        meta.alignment = .right
        meta.frame = NSRect(x: w - 196, y: ROW_H - 22, width: 120, height: 14)
        addSubview(meta)
        let time = NSTextField(labelWithString: relativeTime(item.updatedAt))
        time.font = .systemFont(ofSize: 10); time.textColor = .secondaryLabelColor; time.alignment = .right
        time.frame = NSRect(x: w - 196, y: 8, width: 120, height: 14)
        addSubview(time)
        if let last = last, !last.isEmpty {
            title.toolTip = (title.toolTip ?? item.title) + "\n" + last
        }
        let cp = NSButton(frame: NSRect(x: w - 36, y: (ROW_H - 22) / 2, width: 28, height: 22))
        cp.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy link")
        cp.isBordered = false; cp.target = self; cp.action = #selector(copyLink)
        cp.toolTip = "Copy link"
        addSubview(cp)
        setAccessibilityLabel("\(item.title), \(opt?.name ?? "no status")")
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc func copyLink() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urlStr, forType: .string)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hover(true) }
    override func mouseExited(with event: NSEvent) { hover(false); HoverCard.close() }
    func hover(_ on: Bool) {
        let base = expanded ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.1).cgColor : nil
        layer?.backgroundColor = on ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.15).cgColor : base
        if on, let title = subviews.compactMap({ $0 as? NSTextField }).first, title.intrinsicContentSize.width > title.bounds.width {
            HoverCard.schedule(title.stringValue, from: title)
        }
    }
    override func mouseUp(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        guard bounds.contains(loc) else { return }
        if subviews.contains(where: { $0 is NSButton && $0.frame.contains(loc) }) { return }
        onToggle?()
    }
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 49 { onToggle?() } else { super.keyDown(with: event) }
    }
}

final class ActivityLine: NSView {
    let urlStr: String
    var expanded = false
    let full: String
    init(_ entry: ActivityEntry, w: CGFloat) {
        urlStr = entry.url
        full = entry.text
        super.init(frame: NSRect(x: 0, y: 0, width: w, height: 22))
        wantsLayer = true
        let who = entry.actor.map { $0 + " · " } ?? ""
        let line = NSTextField(labelWithString: who + entry.text + " · " + relativeTime(entry.at))
        line.font = .systemFont(ofSize: 11)
        line.textColor = .secondaryLabelColor
        line.lineBreakMode = .byTruncatingTail
        line.frame = NSRect(x: 8, y: 3, width: w - 40, height: 16)
        line.identifier = NSUserInterfaceItemIdentifier("line")
        addSubview(line)
        let cp = NSButton(frame: NSRect(x: w - 28, y: 1, width: 22, height: 18))
        cp.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy link")
        cp.isBordered = false; cp.target = self; cp.action = #selector(copyLink)
        cp.alphaValue = 0
        cp.identifier = NSUserInterfaceItemIdentifier("copy")
        addSubview(cp)
        toolTip = entry.text
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc func copyLink() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urlStr, forType: .string)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }
    override func mouseEntered(with event: NSEvent) {
        (subviews.first { $0.identifier?.rawValue == "copy" })?.alphaValue = 1
        if let line = subviews.compactMap({ $0 as? NSTextField }).first, line.intrinsicContentSize.width > line.bounds.width {
            HoverCard.schedule(full, from: self)
        }
    }
    override func mouseExited(with event: NSEvent) {
        (subviews.first { $0.identifier?.rawValue == "copy" })?.alphaValue = 0
        HoverCard.close()
    }
    override func mouseUp(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if subviews.contains(where: { $0 is NSButton && $0.frame.contains(loc) }) { return }
        expanded.toggle()
        guard let line = subviews.compactMap({ $0 as? NSTextField }).first else { return }
        if expanded {
            let h = textHeight(line.stringValue, font: line.font!, width: line.frame.width) + 8
            line.frame.size.height = max(16, h)
            line.lineBreakMode = .byWordWrapping
            line.maximumNumberOfLines = 0
            frame.size.height = line.frame.height + 8
        } else {
            line.frame.size.height = 16
            line.maximumNumberOfLines = 1
            line.lineBreakMode = .byTruncatingTail
            frame.size.height = 22
        }
        superview?.needsLayout = true
    }
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 49 { mouseUp(with: event) } else { super.keyDown(with: event) }
    }
}

final class ProjectItemDetail: Flipped, NSTextFieldDelegate {
    var onStatus: ((String) -> Void)?
    var onComment: ((String) -> Void)?
    var onRead: (() -> Void)?
    var commentField: NSTextField?
    let optionIds: [String]

    init(item: ProjectItem, snap: ProjectSnapshot, activity: [ActivityEntry]?, error: String?, w: CGFloat) {
        optionIds = snap.statusOptions.map(\.id)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
        let pad: CGFloat = 42
        let contentW = w - pad - 16
        var y: CGFloat = 8
        func line(_ name: String, _ value: String) {
            let n = NSTextField(labelWithString: name)
            n.font = .systemFont(ofSize: 10.5); n.textColor = .tertiaryLabelColor
            n.frame = NSRect(x: pad, y: y, width: 90, height: 16)
            addSubview(n)
            let v = NSTextField(labelWithString: value)
            v.font = .systemFont(ofSize: 11); v.lineBreakMode = .byTruncatingTail
            v.frame = NSRect(x: pad + 94, y: y, width: contentW - 94, height: 16)
            addSubview(v)
            y += 18
        }
        let popup = NSPopUpButton(frame: NSRect(x: pad + 94, y: y - 2, width: 180, height: 22), pullsDown: false)
        popup.addItem(withTitle: "No status")
        for opt in snap.statusOptions { popup.addItem(withTitle: opt.name) }
        if let id = item.statusOptionId, let i = optionIds.firstIndex(of: id) { popup.selectItem(at: i + 1) }
        popup.target = self; popup.action = #selector(statusChanged(_:))
        popup.isEnabled = snap.statusFieldId != nil
        let nl = NSTextField(labelWithString: "Status")
        nl.font = .systemFont(ofSize: 10.5); nl.textColor = .tertiaryLabelColor
        nl.frame = NSRect(x: pad, y: y, width: 90, height: 16)
        addSubview(nl); addSubview(popup); y += 26
        if let repo = item.repo { line("Repo", repo + (item.number.map { "#\($0)" } ?? "")) }
        if !item.assignees.isEmpty { line("Assignees", item.assignees.joined(separator: ", ")) }
        if !item.labels.isEmpty { line("Labels", item.labels.joined(separator: ", ")) }
        for (k, v) in item.fields.sorted(by: { $0.key < $1.key }) { line(k, v) }
        if let error = error {
            let e = NSTextField(labelWithString: error)
            e.font = .systemFont(ofSize: 11); e.textColor = C_FAILURE
            e.frame = NSRect(x: pad, y: y, width: contentW, height: 16)
            addSubview(e); y += 18
        }
        y += 4
        let hdr = NSTextField(labelWithString: "ACTIVITY")
        hdr.font = .systemFont(ofSize: 9.5, weight: .bold); hdr.textColor = .secondaryLabelColor
        hdr.frame = NSRect(x: pad, y: y, width: contentW, height: 14)
        addSubview(hdr); y += 18
        if let activity = activity {
            if activity.isEmpty {
                let l = NSTextField(labelWithString: "No recent activity")
                l.font = .systemFont(ofSize: 11); l.textColor = .tertiaryLabelColor
                l.frame = NSRect(x: pad, y: y, width: contentW, height: 16)
                addSubview(l); y += 20
            }
            for e in activity.sorted(by: { $0.at > $1.at }).prefix(12) {
                let row = ActivityLine(e, w: contentW)
                row.frame.origin = NSPoint(x: pad, y: y)
                addSubview(row)
                y += row.frame.height
            }
        } else {
            let l = NSTextField(labelWithString: "Loading activity…")
            l.font = .systemFont(ofSize: 11); l.textColor = .tertiaryLabelColor
            l.frame = NSRect(x: pad, y: y, width: contentW, height: 16)
            addSubview(l); y += 20
        }
        y += 6
        if item.contentId != nil {
            let cf = NSTextField(frame: NSRect(x: pad, y: y, width: contentW - 84, height: 22))
            cf.placeholderString = "Leave a comment…"
            cf.font = .systemFont(ofSize: 11.5)
            cf.delegate = self
            addSubview(cf); commentField = cf
            let send = NSButton(title: "Comment", target: self, action: #selector(sendComment))
            send.bezelStyle = .inline; send.font = .systemFont(ofSize: 11)
            send.frame = NSRect(x: pad + contentW - 76, y: y - 1, width: 76, height: 24)
            addSubview(send)
            y += 30
        }
        let open = NSButton(title: "Open", target: self, action: #selector(openItem))
        open.bezelStyle = .inline; open.font = .systemFont(ofSize: 11)
        open.frame = NSRect(x: pad, y: y, width: 64, height: 22)
        addSubview(open)
        let copy = NSButton(title: "Copy link", target: self, action: #selector(copyLink))
        copy.bezelStyle = .inline; copy.font = .systemFont(ofSize: 11)
        copy.frame = NSRect(x: pad + 70, y: y, width: 80, height: 22)
        addSubview(copy)
        let read = NSButton(title: "Mark as read", target: self, action: #selector(markRead))
        read.bezelStyle = .inline; read.font = .systemFont(ofSize: 11)
        read.frame = NSRect(x: pad + 156, y: y, width: 100, height: 22)
        addSubview(read)
        y += 30
        frame = NSRect(x: 0, y: 0, width: w, height: y)
        self.itemURL = item.url ?? snap.summary.url
    }
    required init?(coder: NSCoder) { fatalError() }
    private var itemURL = ""
    func controlTextDidChange(_ obj: Notification) {
        let app = NSApp.delegate as? GHActionsBar
        let drafting = !(commentField?.stringValue.isEmpty ?? true)
        app?.popover.behavior = drafting ? .semitransient : .transient
    }
    @objc func statusChanged(_ sender: NSPopUpButton) {
        let i = sender.indexOfSelectedItem - 1
        guard i >= 0, i < optionIds.count else { return }
        onStatus?(optionIds[i])
    }
    @objc func sendComment() {
        let body = commentField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !body.isEmpty else { return }
        commentField?.isEnabled = false
        onComment?(body)
    }
    @objc func openItem() { if let u = URL(string: itemURL) { NSWorkspace.shared.open(u) } }
    @objc func copyLink() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(itemURL, forType: .string)
    }
    @objc func markRead() { onRead?() }
}

final class FeedRow: NSView {
    var onToggle: (() -> Void)?
    let expanded: Bool
    init(_ entry: ActivityEntry, itemTitle: String, project: String, status: String?, w: CGFloat, expanded: Bool) {
        self.expanded = expanded
        let bodyH: CGFloat = expanded ? textHeight(entry.text, font: .systemFont(ofSize: 12), width: w - 56) + 8 : 0
        super.init(frame: NSRect(x: 0, y: 0, width: w, height: 48 + bodyH))
        wantsLayer = true
        if entry.unread {
            addSubview(Dot(color: C_RUNNING, frame: NSRect(x: 10, y: 30, width: 6, height: 6)))
        }
        let actor = entry.actor ?? "Someone"
        let head = NSTextField(labelWithString: "\(actor) · \(entry.text)")
        head.font = .systemFont(ofSize: 12, weight: .medium)
        head.lineBreakMode = .byTruncatingTail
        head.frame = NSRect(x: 24, y: 26, width: w - 120, height: 16)
        addSubview(head)
        let sub = NSTextField(labelWithString: "\(itemTitle) · \(project)" + (status.map { " · \($0)" } ?? ""))
        sub.font = .systemFont(ofSize: 11); sub.textColor = .secondaryLabelColor
        sub.lineBreakMode = .byTruncatingTail
        sub.frame = NSRect(x: 24, y: 8, width: w - 120, height: 14)
        addSubview(sub)
        let time = NSTextField(labelWithString: relativeTime(entry.at))
        time.font = .systemFont(ofSize: 10); time.textColor = .tertiaryLabelColor; time.alignment = .right
        time.frame = NSRect(x: w - 90, y: 26, width: 76, height: 14)
        addSubview(time)
        if expanded {
            let body = NSTextField(wrappingLabelWithString: entry.text)
            body.font = .systemFont(ofSize: 12)
            body.frame = NSRect(x: 24, y: 48, width: w - 40, height: bodyH)
            addSubview(body)
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    override func mouseUp(with event: NSEvent) { onToggle?() }
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 49 { onToggle?() } else { super.keyDown(with: event) }
    }
}

extension TabVC {
    func buildProjectsContent(_ w: CGFloat) -> [NSView] {
        let store = (NSApp.delegate as? GHActionsBar)?.projectStore
        let app = NSApp.delegate as? GHActionsBar
        if app?.needsProjectScope == true {
            return [scopeRow(w)]
        }
        guard let store = store else {
            return [EmptyRow("Projects are not ready yet.", w: w)]
        }
        let tracked = (NSApp.delegate as? GHActionsBar)?.projectCatalog.resolve(PROJECTS_CFG) ?? []
        if tracked.isEmpty {
            return [EmptyRow("No projects tracked. Pick projects in Settings → Projects.", w: w, icon: "square.grid.2x2")]
        }
        if let err = store.lastError, store.snapshots.isEmpty {
            return [EmptyRow(err, w: w, icon: "exclamationmark.triangle")]
        }
        if projectView == .activity { return buildActivityFeed(w, store: store) }
        var rows: [NSView] = []
        let shown = selectedProject.map { key in tracked.filter { $0.ref.key == key } } ?? tracked
        for summary in shown {
            guard let snap = store.snapshots[summary.ref.key] else {
                rows.append(LoadingRow(w: w))
                continue
            }
            let live = store.liveKeys.contains(summary.ref.key)
            let header = ProjectHeader(snap: snap, live: live, refreshing: store.refreshing.contains(summary.ref.key),
                                       filter: statusFilter[summary.ref.key],
                                       updated: relativeTime(snap.fetchedAt), w: w)
            header.onRefresh = { [weak store] in store?.refresh([summary.ref.key], force: true) { _ in } }
            header.onFilter = { [weak self] id in
                guard let self = self else { return }
                if self.statusFilter[summary.ref.key] == id { self.statusFilter[summary.ref.key] = nil }
                else { self.statusFilter[summary.ref.key] = id }
                self.rebuildContent()
            }
            rows.append(header)
            var items = snap.items.sorted { $0.updatedAt > $1.updatedAt }
            items = items.filter { !isHiddenDone($0, snap: snap) }
            if assignedOnly { items = items.filter { $0.isMine(app?.viewerLogin) } }
            if unreadOnly { items = items.filter { store.isUnread(itemId: $0.id) } }
            if let fid = statusFilter[summary.ref.key] { items = items.filter { $0.statusOptionId == fid } }
            let cap = PROJECTS_CFG.itemsPerProject
            let limited = (cap > 0 && !showAllProjects.contains(summary.ref.key)) ? Array(items.prefix(cap)) : items
            if limited.isEmpty {
                rows.append(EmptyRow("No items match these filters", w: w))
            }
            for item in limited {
                let last = store.activity(limit: 20, project: summary.ref.key).first { $0.itemId == item.id }?.text
                let row = ProjectItemRow(item: item, snap: snap, unread: store.isUnread(itemId: item.id),
                                         last: last, w: w, expanded: expandedItem == item.id)
                row.onToggle = { [weak self] in self?.toggleItem(item.id) }
                rows.append(row)
                if expandedItem == item.id {
                    rows.append(detail(for: item, snap: snap, store: store, w: w))
                }
            }
            if cap > 0 && items.count > cap && !showAllProjects.contains(summary.ref.key) {
                let more = NSButton(title: "\(limited.count) of \(items.count) items · Show all", target: self, action: #selector(showAll(_:)))
                more.identifier = NSUserInterfaceItemIdentifier(summary.ref.key)
                more.bezelStyle = .inline; more.font = .systemFont(ofSize: 11)
                more.frame = NSRect(x: 0, y: 0, width: w, height: 28)
                rows.append(more)
            }
        }
        if rows.isEmpty { rows.append(EmptyRow("No projects to show", w: w)) }
        return rows
    }

    func buildActivityFeed(_ w: CGFloat, store: ProjectStore) -> [NSView] {
        var entries = store.activity(limit: 100, project: selectedProject)
        let app = NSApp.delegate as? GHActionsBar
        if assignedOnly {
            entries = entries.filter { id in
                store.item(id.itemId)?.item.isMine(app?.viewerLogin) ?? false
            }
        }
        if unreadOnly { entries = entries.filter(\.unread) }
        if entries.isEmpty { return [EmptyRow("No project activity yet.", w: w, icon: "clock")] }
        var rows: [NSView] = []
        var lastDay = ""
        let cal = Calendar.current
        let df = DateFormatter(); df.dateFormat = "MMM d"
        for e in entries {
            let day: String
            if cal.isDateInToday(e.at) { day = "Today" }
            else if cal.isDateInYesterday(e.at) { day = "Yesterday" }
            else { day = df.string(from: e.at) }
            if day != lastDay {
                rows.append(SectionLabel(day.uppercased(), w: w))
                lastDay = day
            }
            let item = store.item(e.itemId)
            let title = item?.item.title ?? "Item"
            let project = item?.snap.summary.title ?? e.projectKey
            let status = item?.snap.statusName(item?.item.statusOptionId)
            let row = FeedRow(e, itemTitle: title, project: project, status: status, w: w, expanded: expandedItem == e.id)
            row.onToggle = { [weak self, weak store] in
                guard let self = self else { return }
                self.expandedItem = self.expandedItem == e.id ? nil : e.id
                store?.markActivityRead(e.id)
                self.rebuildContent()
            }
            rows.append(row)
        }
        return rows
    }

    func detail(for item: ProjectItem, snap: ProjectSnapshot, store: ProjectStore, w: CGFloat) -> NSView {
        let cached = store.activity(limit: 1, project: nil)
        _ = cached
        let detail = ProjectItemDetail(item: item, snap: snap, activity: timelineCache[item.id], error: projectError, w: w)
        if timelineCache[item.id] == nil {
            store.timeline(itemId: item.id) { [weak self] entries in
                self?.timelineCache[item.id] = entries
                if self?.expandedItem == item.id { self?.rebuildContent() }
            }
        }
        detail.onStatus = { [weak self, weak store] option in
            let old = item.statusOptionId
            store?.setStatus(itemId: item.id, optionId: option) { ok in
                if !ok {
                    self?.projectError = store?.lastError ?? "Could not change the status"
                    self?.rebuildContent()
                    _ = old
                } else {
                    self?.projectError = nil
                }
            }
        }
        detail.onComment = { [weak self, weak store] body in
            store?.comment(itemId: item.id, body: body) { ok in
                self?.projectError = ok ? nil : (store?.lastError ?? "Could not post the comment")
                self?.timelineCache[item.id] = nil
                self?.rebuildContent()
            }
        }
        detail.onRead = { [weak store] in store?.markRead(itemId: item.id) }
        return detail
    }

    func toggleItem(_ id: String) {
        expandedItem = expandedItem == id ? nil : id
        let app = NSApp.delegate as? GHActionsBar
        app?.popover.behavior = expandedItem != nil ? .semitransient : .transient
        app?.expandedItem = expandedItem
        rebuildContent()
    }

    func isHiddenDone(_ item: ProjectItem, snap: ProjectSnapshot) -> Bool {
        let days = PROJECTS_CFG.hideDoneAfterDays
        guard days > 0 else { return false }
        let done = item.isClosedState || snap.option(item.statusOptionId)?.category == .done
        guard done else { return false }
        return Date().timeIntervalSince(item.updatedAt) > Double(days) * 86400
    }

    func scopeRow(_ w: CGFloat) -> NSView {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: w, height: 72))
        let l = NSTextField(labelWithString: "Cat Eye needs the project scope.")
        l.font = .systemFont(ofSize: 12); l.textColor = .secondaryLabelColor
        l.frame = NSRect(x: 16, y: 36, width: w - 32, height: 18)
        v.addSubview(l)
        let b = NSButton(title: "Grant access", target: self, action: #selector(grantProjectScope))
        b.bezelStyle = .inline; b.font = .systemFont(ofSize: 12)
        b.frame = NSRect(x: 16, y: 8, width: 120, height: 24)
        v.addSubview(b)
        return v
    }

    @objc func grantProjectScope() { runInTerminal("gh auth refresh -s project") }
    @objc func showAll(_ sender: NSButton) {
        if let key = sender.identifier?.rawValue { showAllProjects.insert(key) }
        rebuildContent()
    }
}
