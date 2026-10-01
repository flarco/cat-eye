import Cocoa

// Repositories tab: a tree of owners (the user and their orgs) and their repos.
// The tree shows the cached catalog at once and updates while it refreshes.
final class SettingsVC: NSViewController {
    // Expanded owners survive a reopen of the settings.
    static var expanded: Set<String> = []
    static var seenOwners: Set<String> = []

    let catalog: RepoCatalog
    let updater: Updater
    var picked: Set<String>
    var orgs: Set<String>
    var repoScroll: NSScrollView?
    var repoDoc: Flipped?
    var statusLabel: NSTextField?
    var syncLabel: NSTextField?
    var syncSpinner: NSProgressIndicator?
    var refreshAllBtn: NSButton?
    var addField: NSTextField?
    var observer: NSObjectProtocol?
    var updateObserver: NSObjectProtocol?
    var updateLabel: NSTextField?
    var updateBtn: NSButton?

    init(catalog: RepoCatalog, updater: Updater, picked: Set<String>, orgs: Set<String>) {
        self.catalog = catalog
        self.updater = updater
        self.picked = picked
        self.orgs = orgs
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        for o in [observer, updateObserver].compactMap({ $0 }) { NotificationCenter.default.removeObserver(o) }
    }

    override func loadView() {
        let w = POP_W
        let container = Flipped(frame: NSRect(x: 0, y: 0, width: w, height: 500))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.85).cgColor
        var y: CGFloat = 0

        container.addSubview(SettingsNav(w: w, selected: 0)); y += 44
        container.addSubview(SeparatorLine(y: y, w: w)); y += 0.5

        // ── Account section ──
        container.addSubview(SettingsHeader("GITHUB ACCOUNT", y: y, w: w)); y += 28
        let accRow = NSView(frame: NSRect(x: 0, y: y, width: w, height: 40))
        let sl = NSTextField(labelWithString: "Checking...")
        sl.font = .systemFont(ofSize: 12); sl.textColor = .secondaryLabelColor
        sl.frame = NSRect(x: 16, y: 10, width: w - 180, height: 20)
        accRow.addSubview(sl)
        statusLabel = sl
        let loginBtn = NSButton(title: "Login...", target: self, action: #selector(doLogin))
        loginBtn.bezelStyle = .inline; loginBtn.font = .systemFont(ofSize: 11)
        loginBtn.frame = NSRect(x: w - 160, y: 10, width: 64, height: 24)
        accRow.addSubview(loginBtn)
        let logoutBtn = NSButton(title: "Logout", target: self, action: #selector(doLogout))
        logoutBtn.bezelStyle = .inline; logoutBtn.font = .systemFont(ofSize: 11)
        logoutBtn.frame = NSRect(x: w - 88, y: 10, width: 64, height: 24)
        accRow.addSubview(logoutBtn)
        container.addSubview(accRow); y += 40
        container.addSubview(SeparatorLine(y: y, w: w)); y += 0.5

        // ── Updates section ──
        container.addSubview(SettingsHeader("UPDATES", y: y, w: w)); y += 28
        let updRow = NSView(frame: NSRect(x: 0, y: y, width: w, height: 40))
        let auto = NSButton(checkboxWithTitle: "Automatically install updates", target: self, action: #selector(toggleAutoUpdate(_:)))
        auto.font = .systemFont(ofSize: 12)
        auto.state = AUTO_UPDATE ? .on : .off
        auto.isEnabled = !updater.isDev
        auto.frame = NSRect(x: 16, y: 10, width: 220, height: 20)
        updRow.addSubview(auto)
        let ul = NSTextField(labelWithString: "")
        ul.font = .systemFont(ofSize: 11); ul.textColor = .secondaryLabelColor
        ul.alignment = .right; ul.lineBreakMode = .byTruncatingTail
        ul.frame = NSRect(x: 240, y: 12, width: w - 350, height: 16)
        updRow.addSubview(ul)
        updateLabel = ul
        let ub = NSButton(title: "Check now", target: self, action: #selector(checkOrRestart))
        ub.bezelStyle = .inline; ub.font = .systemFont(ofSize: 11)
        ub.frame = NSRect(x: w - 104, y: 10, width: 88, height: 24)
        updRow.addSubview(ub)
        updateBtn = ub
        container.addSubview(updRow); y += 40
        container.addSubview(SeparatorLine(y: y, w: w)); y += 0.5

        // ── Repos section ──
        let repoHdr = SettingsHeader("SELECT REPOS TO TRACK", y: y, w: w)
        let sp = NSProgressIndicator(frame: NSRect(x: w - 342, y: 7, width: 14, height: 14))
        sp.style = .spinning; sp.controlSize = .small; sp.isDisplayedWhenStopped = false
        repoHdr.addSubview(sp)
        syncSpinner = sp
        let sync = NSTextField(labelWithString: "")
        sync.font = .systemFont(ofSize: 10); sync.textColor = .secondaryLabelColor
        sync.alignment = .right; sync.lineBreakMode = .byTruncatingTail
        sync.frame = NSRect(x: w - 324, y: 7, width: 220, height: 14)
        repoHdr.addSubview(sync)
        syncLabel = sync
        let refreshBtn = NSButton(title: "Refresh all", target: self, action: #selector(refreshAll))
        refreshBtn.bezelStyle = .inline; refreshBtn.font = .systemFont(ofSize: 10)
        refreshBtn.frame = NSRect(x: w - 96, y: 4, width: 84, height: 20)
        repoHdr.addSubview(refreshBtn)
        refreshAllBtn = refreshBtn
        container.addSubview(repoHdr); y += 28

        let scrollH: CGFloat = 320
        let rd = Flipped(frame: NSRect(x: 0, y: 0, width: w, height: scrollH))
        let rs = NSScrollView(frame: NSRect(x: 0, y: y, width: w, height: scrollH))
        rs.hasVerticalScroller = true; rs.drawsBackground = false
        rs.documentView = rd; rs.autohidesScrollers = true
        container.addSubview(rs)
        repoScroll = rs; repoDoc = rd
        y += scrollH
        container.addSubview(SeparatorLine(y: y, w: w)); y += 0.5

        // ── Add repo manually ──
        container.addSubview(SettingsHeader("ADD REPO MANUALLY", y: y, w: w)); y += 28
        let addRow = NSView(frame: NSRect(x: 0, y: y, width: w, height: 36))
        let tf = NSTextField(frame: NSRect(x: 16, y: 6, width: w - 110, height: 24))
        tf.placeholderString = "owner/repo"
        tf.font = .systemFont(ofSize: 12)
        addRow.addSubview(tf)
        addField = tf
        let addBtn = NSButton(title: "Add", target: self, action: #selector(addManualRepo))
        addBtn.bezelStyle = .inline; addBtn.font = .systemFont(ofSize: 11)
        addBtn.frame = NSRect(x: w - 80, y: 6, width: 56, height: 24)
        addRow.addSubview(addBtn)
        container.addSubview(addRow); y += 36
        container.addSubview(SeparatorLine(y: y, w: w)); y += 0.5

        // ── Save button ──
        let saveRow = NSView(frame: NSRect(x: 0, y: y, width: w, height: 48))
        saveRow.wantsLayer = true; saveRow.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.9).cgColor
        let saveBtn = NSButton(title: "Save & Apply", target: self, action: #selector(doSave))
        saveBtn.bezelStyle = .inline; saveBtn.font = .systemFont(ofSize: 12, weight: .semibold)
        saveBtn.frame = NSRect(x: w / 2 - 60, y: 12, width: 120, height: 28)
        saveRow.addSubview(saveBtn)
        container.addSubview(saveRow); y += 48

        container.frame.size.height = y
        self.view = container
        self.preferredContentSize = NSSize(width: w, height: min(y, POP_MAX_H))

        observer = NotificationCenter.default.addObserver(forName: RepoCatalog.changed, object: catalog,
                                                          queue: .main) { [weak self] _ in self?.reload() }
        updateObserver = NotificationCenter.default.addObserver(forName: Updater.changed, object: updater,
                                                                queue: .main) { [weak self] _ in self?.updateUpdaterUI() }
        updateUpdaterUI()
        reload()
        // The account check is fast, so it runs on its own and does not wait for the repo lists.
        catalog.checkAuth()
        catalog.refreshIfStale()
    }

    func reload() {
        updateAuthUI()
        changed()
    }

    func updateAuthUI() {
        guard let sl = statusLabel, catalog.authChecked else { return }
        if let user = catalog.user {
            let attr = NSMutableAttributedString()
            attr.append(NSAttributedString(string: "Authenticated as ", attributes: [
                .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor,
            ]))
            attr.append(NSAttributedString(string: user, attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.labelColor,
            ]))
            sl.attributedStringValue = attr
        } else {
            // Distinguish "gh CLI missing" (infra) from "not authenticated" (user action).
            if let err = lastFetchError, err.contains("not found") {
                sl.stringValue = err
            } else {
                sl.stringValue = "Not authenticated — click Login"
            }
            sl.textColor = .systemRed
        }
    }

    func updateUpdaterUI() {
        let status = updater.statusText
        updateLabel?.stringValue = "Version \(updater.current)" + (status.isEmpty ? "" : " · \(status)")
        if case .failed = updater.state { updateLabel?.textColor = .systemRed } else { updateLabel?.textColor = .secondaryLabelColor }
        updateLabel?.toolTip = updateLabel?.stringValue
        if case .ready = updater.state { updateBtn?.title = "Restart now" } else { updateBtn?.title = "Check now" }
        updateBtn?.isEnabled = !updater.busy
    }

    @objc func toggleAutoUpdate(_ sender: NSButton) {
        AUTO_UPDATE = sender.state == .on
        saveConfig()
        if AUTO_UPDATE { updater.check(manual: false) }
    }

    @objc func checkOrRestart() {
        if case .ready = updater.state { updater.install() } else { updater.check(manual: true) }
    }

    func updateSyncUI() {
        let tracked = catalog.resolve(picked: Array(picked), orgs: Array(orgs)).count
        var parts = ["\(tracked) tracked"]
        if catalog.listingOwners {
            parts.append("Checking organizations…")
        } else if catalog.loadingCount > 0 {
            let total = catalog.owners.count
            parts.append("Loading \(total - catalog.loadingCount) of \(total) owners…")
        } else if let at = catalog.fetchedAt {
            parts.append("Updated \(relativeTime(at))")
        }
        syncLabel?.stringValue = parts.joined(separator: " · ")
        catalog.refreshing ? syncSpinner?.startAnimation(nil) : syncSpinner?.stopAnimation(nil)
        refreshAllBtn?.isEnabled = !catalog.refreshing
    }

    // Owners from the catalog first, then owners known only from the picks.
    var ownerLogins: [String] {
        var out = catalog.owners.map { $0.login }
        let known = Set(out.map { $0.lowercased() })
        let extra = Set((picked.map(repoOwner) + orgs).filter { !known.contains($0.lowercased()) })
        out += extra.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return out
    }

    func reposOf(_ owner: String) -> [String] {
        var all = catalog.repos(of: owner)
        let known = Set(all.map { $0.lowercased() })
        all += picked.filter { same(repoOwner($0), owner) && !known.contains($0.lowercased()) }
        return all.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func same(_ a: String, _ b: String) -> Bool { a.caseInsensitiveCompare(b) == .orderedSame }
    func isOrgPicked(_ owner: String) -> Bool { orgs.contains { same($0, owner) } }
    func isPicked(_ repo: String) -> Bool { isOrgPicked(repoOwner(repo)) || picked.contains(repo) }

    func rebuildTree() {
        NSApp.withPinnedAppearance {
            guard let doc = repoDoc else { return }
            doc.subviews.forEach { $0.removeFromSuperview() }
            let w = POP_W
            var y: CGFloat = 4

            let owners = ownerLogins
            for owner in owners {
                let repos = reposOf(owner)
                let count = repos.filter(isPicked).count
                // Open owners with a partial pick the first time they appear, so picks are visible.
                if SettingsVC.seenOwners.insert(owner).inserted && count > 0 && !isOrgPicked(owner) {
                    SettingsVC.expanded.insert(owner)
                }
                let open = SettingsVC.expanded.contains(owner)
                y = ownerRow(owner, repos: repos, count: count, open: open, y: y, w: w, in: doc)
                guard open else { continue }
                for repo in repos {
                    let short = repo.split(separator: "/").dropFirst().joined(separator: "/")
                    let cb = NSButton(checkboxWithTitle: " \(short)", target: self, action: #selector(toggleRepo(_:)))
                    cb.font = .systemFont(ofSize: 12)
                    cb.state = isPicked(repo) ? .on : .off
                    cb.frame = NSRect(x: 52, y: y, width: w - 80, height: 22)
                    cb.identifier = NSUserInterfaceItemIdentifier(repo)
                    doc.addSubview(cb)
                    y += 22
                }
                if repos.isEmpty {
                    let l = label(isLoading(owner) ? "Loading…" : "No repos", x: 54, y: y + 3, width: 300)
                    doc.addSubview(l)
                    y += 22
                }
                y += 4
            }

            if owners.isEmpty {
                let text = catalog.refreshing ? "Loading repos…"
                    : (catalog.authChecked && catalog.user == nil ? "Login to see your repos" : "No repos found")
                doc.addSubview(label(text, x: 16, y: 8, width: 300, size: 12))
                y = 36
            }
            doc.frame.size.height = max(y + 4, repoScroll?.frame.height ?? 320)
        }
    }

    func ownerRow(_ owner: String, repos: [String], count: Int, open: Bool,
                  y: CGFloat, w: CGFloat, in doc: NSView) -> CGFloat {
        let disc = NSButton(frame: NSRect(x: 10, y: y + 6, width: 16, height: 16))
        disc.bezelStyle = .disclosure; disc.setButtonType(.pushOnPushOff); disc.title = ""
        disc.state = open ? .on : .off
        disc.target = self; disc.action = #selector(toggleExpand(_:))
        disc.identifier = NSUserInterfaceItemIdentifier(owner)
        doc.addSubview(disc)

        let cb = NSButton(checkboxWithTitle: " \(owner)", target: self, action: #selector(toggleOwner(_:)))
        cb.font = .systemFont(ofSize: 12, weight: .semibold)
        cb.allowsMixedState = true
        cb.state = isOrgPicked(owner) ? .on : (count > 0 ? .mixed : .off)
        cb.toolTip = "Select all repos of \(owner), also repos added later"
        cb.frame = NSRect(x: 30, y: y + 3, width: 230, height: 22)
        cb.identifier = NSUserInterfaceItemIdentifier(owner)
        doc.addSubview(cb)

        let summary: String
        if isOrgPicked(owner) { summary = "All \(repos.count) · includes new repos" }
        else if repos.isEmpty { summary = "" }
        else { summary = "\(count) of \(repos.count) selected" }
        doc.addSubview(label(summary, x: 264, y: y + 7, width: w - 400))

        switch catalog.fetch(owner) {
        case .loading:
            let sp = NSProgressIndicator(frame: NSRect(x: w - 66, y: y + 7, width: 14, height: 14))
            sp.style = .spinning; sp.controlSize = .small
            sp.startAnimation(nil)
            doc.addSubview(sp)
        case .failed(let msg):
            let l = label("Failed", x: w - 130, y: y + 7, width: 76)
            l.alignment = .right; l.textColor = .systemRed; l.toolTip = msg
            doc.addSubview(l)
        case .idle:
            break
        }

        let rb = NSButton(frame: NSRect(x: w - 44, y: y + 4, width: 22, height: 20))
        rb.bezelStyle = .inline; rb.isBordered = false; rb.title = ""
        rb.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh \(owner)")
        let updated = catalog.owners.first { $0.login == owner }?.fetchedAt.map { " · updated \(relativeTime($0))" } ?? ""
        rb.toolTip = "Refresh \(owner)\(updated)"
        rb.isEnabled = !isLoading(owner)
        rb.target = self; rb.action = #selector(refreshOwner(_:))
        rb.identifier = NSUserInterfaceItemIdentifier(owner)
        doc.addSubview(rb)
        return y + 28
    }

    func isLoading(_ owner: String) -> Bool {
        if case .loading = catalog.fetch(owner) { return true }
        return false
    }

    func label(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat = 11) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: size); l.textColor = .secondaryLabelColor
        l.lineBreakMode = .byTruncatingTail
        l.frame = NSRect(x: x, y: y, width: width, height: 16)
        return l
    }

    func changed() {
        updateSyncUI()
        rebuildTree()
    }

    @objc func toggleExpand(_ sender: NSButton) {
        guard let owner = sender.identifier?.rawValue else { return }
        if sender.state == .on { SettingsVC.expanded.insert(owner) } else { SettingsVC.expanded.remove(owner) }
        rebuildTree()
    }

    // Off or partial goes to all; all goes to none.
    @objc func toggleOwner(_ sender: NSButton) {
        guard let owner = sender.identifier?.rawValue else { return }
        let wasAll = isOrgPicked(owner)
        orgs = orgs.filter { !same($0, owner) }
        picked = picked.filter { !same(repoOwner($0), owner) }
        if !wasAll { orgs.insert(owner) }
        changed()
    }

    // Unpicking one repo of a whole-owner pick turns the rest into single picks.
    @objc func toggleRepo(_ sender: NSButton) {
        guard let repo = sender.identifier?.rawValue else { return }
        let owner = repoOwner(repo)
        if sender.state == .on {
            picked.insert(repo)
        } else {
            if isOrgPicked(owner) {
                orgs = orgs.filter { !same($0, owner) }
                picked.formUnion(reposOf(owner))
            }
            picked.remove(repo)
        }
        changed()
    }

    @objc func refreshAll() { catalog.refreshAll() }

    @objc func refreshOwner(_ sender: NSButton) {
        guard let owner = sender.identifier?.rawValue else { return }
        catalog.refresh(owner: owner)
    }

    @objc func addManualRepo() {
        guard let text = addField?.stringValue.trimmingCharacters(in: .whitespaces),
              !text.isEmpty, isValidRepo(text) else {
            addField?.placeholderString = "Format: owner/repo (letters, numbers, hyphens)"
            return
        }
        picked.insert(text)
        SettingsVC.expanded.insert(repoOwner(text))
        addField?.stringValue = ""
        changed()
    }

    @objc func doLogin() { runInTerminal("gh auth login --web -p https") }
    @objc func doLogout() { runInTerminal("gh auth logout") }

    func runInTerminal(_ command: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", "tell application \"Terminal\" to do script \"\(command)\""]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
    }

    @objc func doSave() {
        let byName = { (a: String, b: String) in a.localizedCaseInsensitiveCompare(b) == .orderedAscending }
        PICKED_ORGS = orgs.sorted(by: byName)
        PICKED_REPOS = picked.filter { !isOrgPicked(repoOwner($0)) }.sorted(by: byName)
        saveConfig()
        (NSApp.delegate as? GHActionsBar)?.applyRepoSelection(reopen: true)
    }
}
