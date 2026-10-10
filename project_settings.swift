import Cocoa

// Settings → Projects: which projects to track, notifications, display, and the poll interval.
final class ProjectSettingsVC: NSViewController {
    let catalog: ProjectCatalog
    let store: ProjectStore
    var cfg: ProjectsConfig
    var filterField: NSTextField?
    var doc: Flipped?
    var scroll: NSScrollView?
    var observer: NSObjectProtocol?
    static var expanded: Set<String> = []

    init(catalog: ProjectCatalog, store: ProjectStore, cfg: ProjectsConfig) {
        self.catalog = catalog
        self.store = store
        self.cfg = cfg
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { if let o = observer { NotificationCenter.default.removeObserver(o) } }

    override func loadView() {
        let w = POP_W
        let container = Flipped(frame: NSRect(x: 0, y: 0, width: w, height: POP_MAX_H))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.85).cgColor
        container.addSubview(SettingsNav(w: w, selected: .projects))
        container.addSubview(SeparatorLine(y: 44, w: w))
        scroll = NSScrollView(frame: NSRect(x: 0, y: 44.5, width: w, height: POP_MAX_H - 44.5))
        scroll?.hasVerticalScroller = true
        scroll?.drawsBackground = false
        scroll?.autohidesScrollers = true
        doc = Flipped(frame: NSRect(x: 0, y: 0, width: w, height: 100))
        scroll?.documentView = doc
        container.addSubview(scroll!)
        view = container
        preferredContentSize = NSSize(width: w, height: POP_MAX_H)
        observer = NotificationCenter.default.addObserver(forName: ProjectCatalog.changed, object: catalog, queue: .main) { [weak self] _ in
            self?.rebuild()
        }
        rebuild()
        catalog.refreshIfStale()
    }

    func rebuild() {
        guard let doc = doc else { return }
        NSApp.withPinnedAppearance {
            doc.subviews.forEach { $0.removeFromSuperview() }
            let w = POP_W
            var y: CGFloat = 0
            y = header("PROJECTS TO TRACK", y: y, button: ("Refresh all", #selector(refreshAll)))
            let filter = NSTextField(frame: NSRect(x: 16, y: y + 4, width: w - 32, height: 22))
            filter.placeholderString = "Filter projects"
            filter.font = .systemFont(ofSize: 12)
            filter.stringValue = filterField?.stringValue ?? ""
            filter.target = self; filter.action = #selector(filterChanged)
            doc.addSubview(filter); filterField = filter
            y += 32
            y = tree(y: y, w: w, in: doc)
            y += 8
            y = header("NOTIFY ME WHEN", y: y, button: nil)
            y = matrix(y: y, w: w, in: doc)
            y = header("DISPLAY", y: y, button: nil)
            y = display(y: y, w: w, in: doc)
            y = header("REFRESH", y: y, button: nil)
            y = refreshSection(y: y, w: w, in: doc)
            let save = NSButton(title: "Save & Apply", target: self, action: #selector(doSave))
            save.bezelStyle = .inline; save.font = .systemFont(ofSize: 12, weight: .semibold)
            save.frame = NSRect(x: w / 2 - 60, y: y + 12, width: 120, height: 28)
            doc.addSubview(save)
            y += 52
            doc.frame.size.height = y
        }
    }

    func header(_ title: String, y: CGFloat, button: (String, Selector)?) -> CGFloat {
        let hdr = SettingsHeader(title, y: y, w: POP_W)
        if let (t, sel) = button {
            let b = NSButton(title: t, target: self, action: sel)
            b.bezelStyle = .inline; b.font = .systemFont(ofSize: 10)
            b.frame = NSRect(x: POP_W - 96, y: 4, width: 84, height: 20)
            b.isEnabled = !catalog.refreshing
            hdr.addSubview(b)
        }
        doc?.addSubview(hdr)
        return y + 28
    }

    func tree(y: CGFloat, w: CGFloat, in doc: NSView) -> CGFloat {
        var y = y
        let q = (filterField?.stringValue ?? "").lowercased()
        let owners = catalog.owners
        if owners.isEmpty {
            let l = NSTextField(labelWithString: catalog.refreshing ? "Loading projects…" : "No projects found. Login, then refresh.")
            l.font = .systemFont(ofSize: 12); l.textColor = .secondaryLabelColor
            l.frame = NSRect(x: 16, y: y + 4, width: w - 32, height: 18)
            doc.addSubview(l)
            return y + 28
        }
        for owner in owners {
            let projects = catalog.projects(of: owner.login).filter { p in
                q.isEmpty || p.title.lowercased().contains(q) || owner.login.lowercased().contains(q)
            }
            if !q.isEmpty && projects.isEmpty { continue }
            let open = ProjectSettingsVC.expanded.contains(owner.login) || !q.isEmpty
            let disc = NSButton(frame: NSRect(x: 10, y: y + 4, width: 16, height: 16))
            disc.bezelStyle = .disclosure; disc.setButtonType(.pushOnPushOff); disc.title = ""
            disc.state = open ? .on : .off
            disc.target = self; disc.action = #selector(toggleExpand(_:))
            disc.identifier = NSUserInterfaceItemIdentifier(owner.login)
            doc.addSubview(disc)
            let kind = owner.kind == .user ? "you" : "org"
            let cb = NSButton(checkboxWithTitle: " \(owner.login)  \(kind) · \(projects.count)", target: self, action: #selector(toggleAll(_:)))
            cb.font = .systemFont(ofSize: 12, weight: .semibold)
            cb.state = cfg.allOf.contains { $0.caseInsensitiveCompare(owner.login) == .orderedSame } ? .on : .off
            cb.toolTip = "Track all, also new ones"
            cb.frame = NSRect(x: 30, y: y + 2, width: 280, height: 22)
            cb.identifier = NSUserInterfaceItemIdentifier(owner.login)
            doc.addSubview(cb)
            let rb = NSButton(frame: NSRect(x: w - 36, y: y + 2, width: 22, height: 20))
            rb.bezelStyle = .inline; rb.isBordered = false
            rb.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh \(owner.login)")
            rb.target = self; rb.action = #selector(refreshOwner(_:))
            rb.identifier = NSUserInterfaceItemIdentifier(owner.login)
            doc.addSubview(rb)
            y += 26
            guard open else { continue }
            for p in projects {
                let row = NSButton(checkboxWithTitle: " \(p.title)  #\(p.ref.number) · \(p.itemCount)", target: self, action: #selector(toggleProject(_:)))
                row.font = .systemFont(ofSize: 12)
                row.identifier = NSUserInterfaceItemIdentifier(p.ref.key)
                let on = cfg.allOf.contains { $0.caseInsensitiveCompare(p.ref.owner) == .orderedSame } || cfg.picked.contains(p.ref.key)
                row.state = on && !p.closed ? .on : .off
                row.isEnabled = !p.closed
                row.frame = NSRect(x: 52, y: y, width: w - 180, height: 22)
                if p.closed { row.alphaValue = 0.45 }
                doc.addSubview(row)
                let live = p.ownerKind == .org && isOrgLive(p.ref.owner)
                let chip = Badge(live ? "Live" : "\(cfg.pollMinutes) min")
                chip.frame.origin = NSPoint(x: w - 90, y: y + 1)
                doc.addSubview(chip)
                y += 22
            }
            y += 4
        }
        return y
    }

    func isOrgLive(_ org: String) -> Bool {
        let st = (NSApp.delegate as? GHActionsBar)?.relayDeployer.hooks.statuses["org:\(org)"]
        if case .live = st { return true }
        if case .waiting = st { return true }
        return false
    }

    func matrix(y: CGFloat, w: CGFloat, in doc: NSView) -> CGFloat {
        var y = y
        let heads = NSTextField(labelWithString: "Any item")
        heads.font = .systemFont(ofSize: 10, weight: .semibold); heads.textColor = .secondaryLabelColor
        heads.frame = NSRect(x: w - 180, y: y, width: 70, height: 14)
        doc.addSubview(heads)
        let mine = NSTextField(labelWithString: "My items")
        mine.font = .systemFont(ofSize: 10, weight: .semibold); mine.textColor = .secondaryLabelColor
        mine.frame = NSRect(x: w - 100, y: y, width: 70, height: 14)
        doc.addSubview(mine)
        y += 18
        let rows: [(String, String, Bool, Bool)] = [
            ("Someone mentions me", "mention", false, cfg.notifications.mention),
            ("New comment", "comment", cfg.notifications.comment.any, cfg.notifications.comment.mine),
            ("Status changes", "status", cfg.notifications.status.any, cfg.notifications.status.mine),
            ("Item is added to a project", "added", cfg.notifications.added.any, cfg.notifications.added.mine),
            ("Item is assigned to me", "assigned", false, cfg.notifications.assigned),
            ("Item is closed or set to Done", "closed", cfg.notifications.closed.any, cfg.notifications.closed.mine),
            ("Other field changes", "other", cfg.notifications.otherFields.any, cfg.notifications.otherFields.mine),
        ]
        let anyDisabled: Set<String> = ["mention", "assigned"]
        for row in rows {
            let l = NSTextField(labelWithString: row.0)
            l.font = .systemFont(ofSize: 12)
            l.frame = NSRect(x: 16, y: y, width: w - 220, height: 18)
            doc.addSubview(l)
            let any = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleNotify(_:)))
            any.identifier = NSUserInterfaceItemIdentifier(row.1 + ":any")
            any.state = row.2 ? .on : .off
            any.isEnabled = !anyDisabled.contains(row.1)
            any.frame = NSRect(x: w - 164, y: y - 2, width: 24, height: 20)
            doc.addSubview(any)
            let my = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleNotify(_:)))
            my.identifier = NSUserInterfaceItemIdentifier(row.1 + ":mine")
            my.state = row.3 ? .on : .off
            my.frame = NSRect(x: w - 84, y: y - 2, width: 24, height: 20)
            doc.addSubview(my)
            y += 24
        }
        return y + 4
    }

    func display(y: CGFloat, w: CGFloat, in doc: NSView) -> CGFloat {
        var y = y
        y = popupRow("Default view", ["Board", "Activity"], cfg.defaultView == .activity ? 1 : 0, #selector(viewChanged(_:)), y: y, in: doc)
        let itemIdx = cfg.itemsPerProject == 0 ? 2 : (cfg.itemsPerProject == 25 ? 1 : 0)
        y = popupRow("Items per project", ["10", "25", "All"], itemIdx, #selector(itemsChanged(_:)), y: y, in: doc)
        let hideIdx = [1, 7, 30, 0].firstIndex(of: cfg.hideDoneAfterDays) ?? 1
        y = popupRow("Hide Done items older than", ["1 day", "7 days", "30 days", "Never"], hideIdx, #selector(hideChanged(_:)), y: y, in: doc)
        let dot = NSButton(checkboxWithTitle: "Show a blue dot on the menu bar icon", target: self, action: #selector(toggleDot(_:)))
        dot.font = .systemFont(ofSize: 12)
        dot.state = cfg.menuDot ? .on : .off
        dot.frame = NSRect(x: 16, y: y, width: w - 32, height: 22)
        doc.addSubview(dot)
        return y + 28
    }

    func refreshSection(y: CGFloat, w: CGFloat, in doc: NSView) -> CGFloat {
        let idx = [2, 5, 10, 15, 30].firstIndex(of: cfg.pollMinutes) ?? 1
        let y = popupRow("Poll projects without live updates every", ["2 min", "5 min", "10 min", "15 min", "30 min"], idx, #selector(pollChanged(_:)), y: y, in: doc)
        let help = NSTextField(wrappingLabelWithString: "GitHub sends project webhooks only for organizations. Personal projects, and org projects without an org webhook, use this interval. Live projects also use it when the relay is disconnected.")
        help.font = .systemFont(ofSize: 11); help.textColor = .secondaryLabelColor
        help.frame = NSRect(x: 16, y: y, width: w - 32, height: 44)
        doc.addSubview(help)
        return y + 48
    }

    func popupRow(_ title: String, _ items: [String], _ selected: Int, _ action: Selector, y: CGFloat, in doc: NSView) -> CGFloat {
        let l = NSTextField(labelWithString: title)
        l.font = .systemFont(ofSize: 12)
        l.frame = NSRect(x: 16, y: y + 4, width: 280, height: 18)
        doc.addSubview(l)
        let pop = NSPopUpButton(frame: NSRect(x: 310, y: y, width: 140, height: 24), pullsDown: false)
        pop.addItems(withTitles: items)
        pop.selectItem(at: selected)
        pop.target = self; pop.action = action
        pop.font = .systemFont(ofSize: 12)
        doc.addSubview(pop)
        return y + 30
    }

    @objc func filterChanged() { rebuild() }
    @objc func refreshAll() { catalog.refreshAll() }
    @objc func refreshOwner(_ sender: NSButton) { if let o = sender.identifier?.rawValue { catalog.refresh(owner: o) } }
    @objc func toggleExpand(_ sender: NSButton) {
        guard let o = sender.identifier?.rawValue else { return }
        if sender.state == .on { ProjectSettingsVC.expanded.insert(o) } else { ProjectSettingsVC.expanded.remove(o) }
        rebuild()
    }
    @objc func toggleAll(_ sender: NSButton) {
        guard let owner = sender.identifier?.rawValue else { return }
        cfg.allOf.removeAll { $0.caseInsensitiveCompare(owner) == .orderedSame }
        cfg.picked.removeAll { $0.lowercased().hasPrefix(owner.lowercased() + "/") }
        if sender.state == .on { cfg.allOf.append(owner) }
        rebuild()
    }
    @objc func toggleProject(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue else { return }
        let owner = key.split(separator: "/").first.map(String.init) ?? key
        if cfg.allOf.contains(where: { $0.caseInsensitiveCompare(owner) == .orderedSame }) {
            cfg.allOf.removeAll { $0.caseInsensitiveCompare(owner) == .orderedSame }
            cfg.picked = catalog.projects(of: owner).filter { !$0.closed && $0.ref.key != key }.map(\.ref.key)
        } else if sender.state == .on {
            if !cfg.picked.contains(key) { cfg.picked.append(key) }
        } else {
            cfg.picked.removeAll { $0 == key }
        }
        rebuild()
    }
    @objc func toggleNotify(_ sender: NSButton) {
        let parts = (sender.identifier?.rawValue ?? "").split(separator: ":").map(String.init)
        guard parts.count == 2 else { return }
        let on = sender.state == .on
        switch (parts[0], parts[1]) {
        case ("mention", "mine"): cfg.notifications.mention = on
        case ("comment", "any"): cfg.notifications.comment.any = on
        case ("comment", "mine"): cfg.notifications.comment.mine = on
        case ("status", "any"): cfg.notifications.status.any = on
        case ("status", "mine"): cfg.notifications.status.mine = on
        case ("added", "any"): cfg.notifications.added.any = on
        case ("added", "mine"): cfg.notifications.added.mine = on
        case ("assigned", "mine"): cfg.notifications.assigned = on
        case ("closed", "any"): cfg.notifications.closed.any = on
        case ("closed", "mine"): cfg.notifications.closed.mine = on
        case ("other", "any"): cfg.notifications.otherFields.any = on
        case ("other", "mine"): cfg.notifications.otherFields.mine = on
        default: break
        }
    }
    @objc func viewChanged(_ sender: NSPopUpButton) { cfg.defaultView = sender.indexOfSelectedItem == 1 ? .activity : .board }
    @objc func itemsChanged(_ sender: NSPopUpButton) { cfg.itemsPerProject = [10, 25, 0][sender.indexOfSelectedItem] }
    @objc func hideChanged(_ sender: NSPopUpButton) { cfg.hideDoneAfterDays = [1, 7, 30, 0][sender.indexOfSelectedItem] }
    @objc func toggleDot(_ sender: NSButton) { cfg.menuDot = sender.state == .on }
    @objc func pollChanged(_ sender: NSPopUpButton) { cfg.pollMinutes = [2, 5, 10, 15, 30][sender.indexOfSelectedItem] }

    @objc func doSave() {
        PROJECTS_CFG = cfg
        saveConfig()
        let app = NSApp.delegate as? GHActionsBar
        app?.applyProjectSelection()
    }
}
