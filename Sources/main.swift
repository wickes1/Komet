import AppKit
import ServiceManagement

// MARK: - Fuzzy Matching

func fuzzyMatch(_ query: String, in text: String) -> (matches: Bool, score: Int) {
    let query = query.lowercased()
    let text = text.lowercased()

    if query.isEmpty { return (true, 0) }
    if text.contains(query) { return (true, 1000) } // Exact substring gets highest score

    var queryIndex = query.startIndex
    var score = 0
    var prevMatchIndex: Int? = nil

    for (i, char) in text.enumerated() {
        if queryIndex < query.endIndex && char == query[queryIndex] {
            // Bonus for consecutive matches
            if let prev = prevMatchIndex, prev + 1 == i {
                score += 10
            }
            // Bonus for matching at start or after space
            if i == 0 || (i > 0 && text[text.index(text.startIndex, offsetBy: i - 1)] == " ") {
                score += 20
            }
            score += 1
            prevMatchIndex = i
            queryIndex = query.index(after: queryIndex)
        }
    }

    return (queryIndex == query.endIndex, score)
}

// MARK: - Custom Views

class RoundedSelectionRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        if selectionHighlightStyle != .none {
            let selectionRect = bounds.insetBy(dx: 10, dy: 0)
            NSColor.selectedContentBackgroundColor.setFill()
            let path = NSBezierPath(roundedRect: selectionRect, xRadius: 8, yRadius: 8)
            path.fill()
        }
    }
}

struct AppItem {
    let name: String
    let url: URL
    let icon: NSImage
    let running: Bool
}

// MARK: - Custom Panel (for keyboard shortcut support)

class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // Prevent Cmd+W from closing the window
    override func performClose(_ sender: Any?) {
        // Do nothing - we handle Cmd+W for quitting apps instead
    }
}

class Komet: NSObject, NSApplicationDelegate, NSTextFieldDelegate {
    let window: KeyablePanel
    let search: NSTextField
    let list: NSTableView

    var apps: [AppItem] = []
    var filtered: [AppItem] = []

    override init() {
        // Borderless floating panel with Visual Effect View
        window = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 450),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.center()

        // Visual Effect View for Glassmorphism
        let visualEffect = NSVisualEffectView(frame: window.contentView!.bounds)
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 16
        visualEffect.layer?.masksToBounds = true

        window.contentView = visualEffect

        // Search field
        search = NSTextField(frame: NSRect(x: 20, y: 390, width: 640, height: 40))
        search.placeholderString = "Search apps..."
        search.focusRingType = .none
        search.isBezeled = false
        search.drawsBackground = false
        search.font = .systemFont(ofSize: 24, weight: .light)
        search.textColor = .white

        // Results list
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 20, width: 680, height: 360))
        list = NSTableView()
        list.headerView = nil
        list.rowHeight = 50
        list.intercellSpacing = NSSize(width: 0, height: 10)
        list.backgroundColor = .clear
        list.style = .plain

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
        col.width = 640
        list.addTableColumn(col)

        scroll.documentView = list
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 20, right: 0)

        window.contentView?.addSubview(search)
        window.contentView?.addSubview(scroll)

        super.init()
        search.delegate = self
        list.dataSource = self
        list.delegate = self
        list.target = self
        list.action = #selector(tableClicked)

        // Mouse hover tracking
        NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.handleMouseMoved(event)
            return event
        }
    }

    @objc func tableClicked() {
        let row = list.clickedRow
        guard row >= 0 && row < filtered.count else { return }

        let clickX = list.convert(window.mouseLocationOutsideOfEventStream, from: nil).x
        if clickX > 615 && filtered[row].running {
            quitApp(filtered[row])
        } else {
            launch()
        }
    }

    func quitApp(_ app: AppItem) {
        guard let runningApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL == app.url }) else { return }
        runningApp.terminate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.refreshApps()
        }
    }

    func handleMouseMoved(_ event: NSEvent) {
        guard window.isVisible else { return }
        let point = list.convert(event.locationInWindow, from: nil)
        let row = list.row(at: point)
        if row >= 0 && row != list.selectedRow {
            list.selectRowIndexes([row], byExtendingSelection: false)
        }
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMenu()
        registerHotkey()
        enableLaunchAtLogin()

        // Load apps in background to avoid blocking startup
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.loadApps()
        }
    }


    func setupMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit Komet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit menu (for Cmd+A/C/V/X)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Quit App", action: #selector(quitSelectedApp), keyEquivalent: "w"))
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    func enableLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                try SMAppService.mainApp.register()
            } catch {
                // Already registered or failed - silently continue
            }
        }
    }

    func registerHotkey() {
        let opts = NSDictionary(object: kCFBooleanTrue!, forKey: kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString) as CFDictionary
        AXIsProcessTrustedWithOptions(opts)

        let isHotkey = { (event: NSEvent) -> Bool in
            event.modifierFlags.contains(.command) && event.keyCode == 49 // Cmd+Space
        }

        // Global monitor - when other apps are focused
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if isHotkey(event) { DispatchQueue.main.async { self?.toggle() } }
        }

        // Local monitor - when Komet is focused
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if isHotkey(event) {
                DispatchQueue.main.async { self.toggle() }
                return nil
            }
            // Handle Enter/Escape when window is visible
            if self.window.isVisible {
                if event.keyCode == 36 { // Enter
                    self.launch()
                    return nil
                }
                if event.keyCode == 53 { // Escape
                    self.window.orderOut(nil)
                    return nil
                }
            }
            return event
        }
    }

    func loadApps() {
        var newApps: [AppItem] = []
        let ws = NSWorkspace.shared
        let running = Set(ws.runningApplications.compactMap { $0.bundleURL })

        let dirs = ["/Applications", "/System/Applications", "\(NSHomeDirectory())/Applications"]
        for dir in dirs {
            guard let urls = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: dir), includingPropertiesForKeys: nil) else { continue }
            for url in urls where url.pathExtension == "app" {
                let name = url.deletingPathExtension().lastPathComponent
                let icon = ws.icon(forFile: url.path)
                icon.size = NSSize(width: 32, height: 32)

                newApps.append(AppItem(name: name, url: url, icon: icon, running: running.contains(url)))
            }
        }
        // Sort: Running first, then alphabetical
        newApps.sort { ($0.running ? 0 : 1, $0.name) < ($1.running ? 0 : 1, $1.name) }

        DispatchQueue.main.async { [weak self] in
            self?.apps = newApps
            self?.filtered = newApps
            self?.list.reloadData()
        }
    }

    func toggle() {
        if window.isVisible {
            window.orderOut(nil)
            search.stringValue = "" // Clear search on close
        } else {
            // Refresh running status
            refreshApps()

            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            window.makeFirstResponder(search)
        }
    }

    func controlTextDidChange(_ n: Notification) {
        applyFilter()
        if !filtered.isEmpty { list.selectRowIndexes([0], byExtendingSelection: false) }
    }

    func applyFilter() {
        let q = search.stringValue
        if q.isEmpty {
            filtered = apps
        } else {
            filtered = apps
                .compactMap { app -> (app: AppItem, score: Int)? in
                    let result = fuzzyMatch(q, in: app.name)
                    return result.matches ? (app, result.score) : nil
                }
                .sorted { $0.score > $1.score }
                .map { $0.app }
        }
        list.reloadData()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.moveDown(_:)):
            list.selectRowIndexes([min(list.selectedRow + 1, filtered.count - 1)], byExtendingSelection: false)
            list.scrollRowToVisible(list.selectedRow)
            return true
        case #selector(NSResponder.moveUp(_:)):
            list.selectRowIndexes([max(list.selectedRow - 1, 0)], byExtendingSelection: false)
            list.scrollRowToVisible(list.selectedRow)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            launch()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            window.orderOut(nil)
            return true
        default:
            return false
        }
    }

    @objc func launch() {
        guard list.selectedRow >= 0 else { return }
        NSWorkspace.shared.open(filtered[list.selectedRow].url)
        window.orderOut(nil)
        search.stringValue = ""
    }

    @objc func quitSelectedApp() {
        guard list.selectedRow >= 0 else { return }
        let app = filtered[list.selectedRow]
        guard app.running else { return }
        quitApp(app)
    }

    func refreshApps() {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL })
        apps = apps.map { AppItem(name: $0.name, url: $0.url, icon: $0.icon, running: running.contains($0.url)) }
        apps.sort { ($0.running ? 0 : 1, $0.name) < ($1.running ? 0 : 1, $1.name) }
        applyFilter()
    }
}

extension Komet: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        return RoundedSelectionRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        let app = filtered[row]
        let id = NSUserInterfaceItemIdentifier("Cell")

        var cell = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView
        if cell == nil {
            cell = NSTableCellView()
            cell?.identifier = id

            // Icon
            let img = NSImageView(frame: NSRect(x: 20, y: 9, width: 32, height: 32))
            img.tag = 1
            cell?.addSubview(img)

            // Text
            let txt = NSTextField(labelWithString: "")
            txt.frame = NSRect(x: 64, y: 14, width: 400, height: 22)
            txt.font = .systemFont(ofSize: 18, weight: .regular)
            txt.textColor = .white
            txt.tag = 2
            cell?.addSubview(txt)

            // Running indicator (green dot)
            let dot = NSTextField(labelWithString: "●")
            dot.frame = NSRect(x: 618, y: 14, width: 20, height: 20)
            dot.font = .systemFont(ofSize: 12)
            dot.textColor = .systemGreen
            dot.tag = 3
            cell?.addSubview(dot)

            // Close button
            let closeBtn = NSTextField(labelWithString: "✕")
            closeBtn.frame = NSRect(x: 640, y: 14, width: 20, height: 20)
            closeBtn.font = .systemFont(ofSize: 14, weight: .medium)
            closeBtn.textColor = .secondaryLabelColor
            closeBtn.tag = 4
            cell?.addSubview(closeBtn)
        }

        // Update content
        (cell?.viewWithTag(1) as? NSImageView)?.image = app.icon
        (cell?.viewWithTag(2) as? NSTextField)?.stringValue = app.name
        cell?.viewWithTag(3)?.isHidden = !app.running
        cell?.viewWithTag(4)?.isHidden = !app.running

        return cell
    }
}

let app = NSApplication.shared
let komet = Komet()
app.delegate = komet
app.run()
