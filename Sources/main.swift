import AppKit
import Carbon.HIToolbox

// MARK: - Configuration

enum Config {
    static let githubURL = "https://github.com/wickes1/Komet"
    static let appDirectories = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
    static let specialApps = ["/System/Library/CoreServices/Finder.app"]
}

// MARK: - Matching

/// The words of an app name, lowercased: split at spaces and punctuation and at camel-case humps,
/// so "BetterDisplay" is "better", "display".
func words(of name: String) -> [String] {
    var result: [String] = [], current = ""
    var previous: Character?
    for c in name {
        let startsWord = c.isUppercase && (previous?.isLowercase ?? false)
        if !(c.isLetter || c.isNumber) {
            if !current.isEmpty { result.append(current); current = "" }
        } else {
            if startsWord, !current.isEmpty { result.append(current); current = "" }
            current.append(c)
        }
        previous = c
    }
    if !current.isEmpty { result.append(current) }
    return result.map { $0.lowercased() }
}

/// How well `query` matches an app `name`; higher is better, `nil` for no match.
///
/// Tiers, best first: the name starts with the query ("te" → Terminal), a word does ("code" →
/// Visual Studio Code), the words' initials do ("vsc"), the query appears anywhere, the query's
/// letters appear in order. Within a tier a running app beats one that is not, then a shorter name.
func matchScore(_ query: String, name: String, running: Bool) -> Int? {
    let q = query.lowercased(), t = name.lowercased()
    guard !q.isEmpty else { return 0 }
    let ws = words(of: name)
    let tier: Int
    if t.hasPrefix(q) {
        tier = 5000
    } else if ws.contains(where: { $0.hasPrefix(q) }) {
        tier = 4000
    } else if String(ws.compactMap(\.first)).hasPrefix(q) {
        tier = 3000
    } else if let r = t.range(of: q) {
        tier = 2000 - min(t.distance(from: t.startIndex, to: r.lowerBound), 50) * 10
    } else {
        // Letters in order, rewarding runs of consecutive letters and letters that start a word.
        var qi = q.startIndex, score = 0, prev: Int?
        for (i, c) in t.enumerated() {
            guard qi < q.endIndex, c == q[qi] else { continue }
            score += (prev == i - 1 ? 10 : 0) + (i == 0 || t[t.index(t.startIndex, offsetBy: i - 1)] == " " ? 20 : 0) + 1
            prev = i
            qi = q.index(after: qi)
        }
        guard qi == q.endIndex else { return nil }
        tier = min(score, 900)
    }
    return tier + (running ? 100 : 0) - min(t.count, 99)
}

// MARK: - Data Model

struct AppItem {
    let name: String, url: URL, icon: NSImage, running: Bool
    static func < (a: AppItem, b: AppItem) -> Bool {
        (a.running ? 0 : 1, a.name.lowercased()) < (b.running ? 0 : 1, b.name.lowercased())
    }
}

// MARK: - Custom Views

class RoundedSelectionRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        NSColor.selectedContentBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 10, dy: 0), xRadius: 8, yRadius: 8).fill()
    }
}

class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func performClose(_ sender: Any?) {}
}

/// A system-wide hotkey registered with the Carbon event manager.
///
/// Unlike a global `NSEvent` monitor, this needs no Accessibility permission, and the keystroke goes
/// to Komet alone instead of also reaching the app in front.
final class Hotkey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    /// `nil` when the key combination cannot be registered, usually because something else owns it.
    init?(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            Unmanaged<Hotkey>.fromOpaque(context).takeUnretainedValue().action()
            return noErr
        }, 1, &pressed, Unmanaged.passUnretained(self).toOpaque(), &handler)
        let id = EventHotKeyID(signature: OSType(0x4B4D_4554), id: 1) // "KMET"
        guard installed == noErr,
              RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &hotKey) == noErr
        else {
            if let handler { RemoveEventHandler(handler) }
            return nil
        }
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}

// MARK: - Helpers

func makeVisualEffectView(_ frame: NSRect, cornerRadius: CGFloat = 16) -> NSVisualEffectView {
    let v = NSVisualEffectView(frame: frame)
    v.autoresizingMask = [.width, .height]
    v.material = .hudWindow
    v.state = .active
    v.wantsLayer = true
    v.layer?.cornerRadius = cornerRadius
    v.layer?.masksToBounds = true
    return v
}

// MARK: - Main Application

class Komet: NSObject, NSApplicationDelegate, NSTextFieldDelegate {
    let window: KeyablePanel
    let search: NSTextField
    let list: NSTableView
    let filterIndicator: NSTextField
    let statusItem: NSStatusItem

    var apps: [AppItem] = []
    var filtered: [AppItem] = []
    var showRunningOnly = false
    var monitors: [Any] = []
    var aboutPanel: NSPanel?
    var aboutMonitor: Any?
    var hotkey: Hotkey?
    var loadingApps = false

    deinit {
        monitors.forEach { NSEvent.removeMonitor($0) }
        if let m = aboutMonitor { NSEvent.removeMonitor(m) }
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Komet")

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
        window.contentView = makeVisualEffectView(window.contentView!.bounds)

        search = NSTextField(frame: NSRect(x: 20, y: 390, width: 560, height: 40))
        search.placeholderString = "Search apps..."
        search.focusRingType = .none
        search.isBezeled = false
        search.drawsBackground = false
        search.font = .systemFont(ofSize: 24, weight: .light)
        search.textColor = .white

        filterIndicator = NSTextField(labelWithString: "All")
        filterIndicator.frame = NSRect(x: 590, y: 398, width: 70, height: 24)
        filterIndicator.font = .systemFont(ofSize: 14, weight: .medium)
        filterIndicator.textColor = .secondaryLabelColor
        filterIndicator.alignment = .right

        list = NSTableView()
        list.headerView = nil
        list.rowHeight = 50
        list.intercellSpacing = NSSize(width: 0, height: 10)
        list.backgroundColor = .clear
        list.style = .plain
        list.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app")))
        list.tableColumns.first?.width = 640

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 20, width: 680, height: 360))
        scroll.documentView = list
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 20, right: 0)

        window.contentView?.addSubview(search)
        window.contentView?.addSubview(filterIndicator)
        window.contentView?.addSubview(scroll)

        super.init()

        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggle)
        search.delegate = self
        list.dataSource = self
        list.delegate = self
        list.target = self
        list.action = #selector(tableClicked)

        setupMouseTracking()
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMenu()
        registerHotkey()
        // A launcher left floating over the app you switched to is in the way: losing focus closes it.
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            // The About panel takes focus from the launcher without replacing it.
            DispatchQueue.main.async { if let self, NSApp.keyWindow == nil || NSApp.keyWindow !== self.aboutPanel { self.hide() } }
        }
        reloadApps()
    }

    // MARK: - App Discovery

    /// Rescans the installed apps in the background, so an app installed since the last scan shows up.
    func reloadApps() {
        guard !loadingApps else { return }
        loadingApps = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = self?.loadApps() ?? []
            DispatchQueue.main.async {
                guard let self else { return }
                self.loadingApps = false
                guard result.map(\.url) != self.apps.map(\.url) else { return }
                self.apps = result
                self.applyFilter(selectFirst: true)
            }
        }
    }

    func loadApps() -> [AppItem] {
        let ws = NSWorkspace.shared
        let running = Set(ws.runningApplications.compactMap { $0.bundleURL?.resolvingSymlinksInPath() })
        var seen = Set<String>()
        var result: [AppItem] = []

        // Spotlight discovery
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        task.arguments = ["kMDItemKind == 'Application'"]
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()

        var paths = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .components(separatedBy: "\n").filter { !$0.isEmpty } ?? []

        // Direct filesystem scan to catch apps Spotlight missed
        let fm = FileManager.default
        for dir in Config.appDirectories {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                paths.append((dir as NSString).appendingPathComponent(entry))
            }
        }

        for path in paths + Config.specialApps {
            let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            guard seen.insert(url.path.lowercased()).inserted,
                  url.pathComponents.filter({ $0.hasSuffix(".app") }).count == 1,
                  Config.appDirectories.contains(where: { path.hasPrefix($0) }) || Config.specialApps.contains(path)
            else { continue }

            let bundle = Bundle(url: url)
            let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? url.deletingPathExtension().lastPathComponent
            let icon = ws.icon(forFile: url.path)
            icon.size = NSSize(width: 32, height: 32)
            result.append(AppItem(name: name, url: url, icon: icon, running: running.contains(url)))
        }

        result.sort(by: <)
        return result
    }

    func refreshApps() {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.resolvingSymlinksInPath() })
        apps = apps.map { AppItem(name: $0.name, url: $0.url, icon: $0.icon, running: running.contains($0.url)) }
        apps.sort(by: <)
        applyFilter()
    }

    // MARK: - Window

    @objc func toggle() {
        if window.isVisible {
            hide()
        } else {
            refreshApps()
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            useLatinKeyboard()
            window.makeFirstResponder(search)
            applyFilter(selectFirst: true)
            reloadApps()
        }
    }

    /// Closes the launcher and clears it, so it opens fresh next time.
    func hide() {
        guard window.isVisible else { return }
        window.orderOut(nil)
        search.stringValue = ""
        showRunningOnly = false
        filterIndicator.stringValue = "All"
        restoreKeyboard()
    }

    // MARK: - Keyboard Layout

    /// The input source that was active before Komet switched to a Latin keyboard, to switch back to on close.
    var keyboardBeforeShow: TISInputSource?

    /// App names are typed in Latin letters. With a Chinese or Japanese input method active they would turn into
    /// candidate characters first, so the launcher switches to the last Latin keyboard while it is open.
    func useLatinKeyboard() {
        let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let latin = TISCopyCurrentASCIICapableKeyboardInputSource().takeRetainedValue()
        guard sourceID(current) != sourceID(latin) else { return }
        keyboardBeforeShow = current
        TISSelectInputSource(latin)
    }

    func restoreKeyboard() {
        guard let previous = keyboardBeforeShow else { return }
        keyboardBeforeShow = nil
        TISSelectInputSource(previous)
    }

    func sourceID(_ source: TISInputSource) -> String? {
        guard let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
    }

    // MARK: - Filter

    func controlTextDidChange(_ n: Notification) { applyFilter(selectFirst: true) }

    func applyFilter(selectFirst: Bool = false) {
        let q = search.stringValue
        let source = showRunningOnly ? apps.filter(\.running) : apps
        filtered = q.isEmpty ? source : source
            .compactMap { app -> (AppItem, Int)? in
                // The bundle's own name can differ from its file: VS Code calls itself "Code".
                let file = app.url.deletingPathExtension().lastPathComponent
                let scores = [app.name, file].compactMap { matchScore(q, name: $0, running: app.running) }
                return scores.max().map { (app, $0) }
            }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.name.lowercased() < $1.0.name.lowercased() }
            .map(\.0)
        list.reloadData()
        if selectFirst && !filtered.isEmpty { list.selectRowIndexes([0], byExtendingSelection: false) }
    }

    func toggleRunningFilter() {
        showRunningOnly.toggle()
        filterIndicator.stringValue = showRunningOnly ? "Running" : "All"
        applyFilter(selectFirst: true)
    }

    // MARK: - Actions

    @objc func tableClicked() {
        let row = list.clickedRow
        guard row >= 0, row < filtered.count else { return }
        if list.convert(window.mouseLocationOutsideOfEventStream, from: nil).x > 615, filtered[row].running {
            quitApp(filtered[row])
        } else {
            launch()
        }
    }

    @objc func launch() {
        guard list.selectedRow >= 0, list.selectedRow < filtered.count else { return }
        NSWorkspace.shared.open(filtered[list.selectedRow].url)
        hide()
    }

    func quitApp(_ app: AppItem) {
        NSWorkspace.shared.runningApplications.first { $0.bundleURL?.resolvingSymlinksInPath() == app.url }?.terminate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.refreshApps() }
    }

    @objc func quitSelectedApp() {
        guard list.selectedRow >= 0, list.selectedRow < filtered.count, filtered[list.selectedRow].running else { return }
        quitApp(filtered[list.selectedRow])
    }

    func restartApp() {
        guard let path = Bundle.main.executablePath else { return }
        let pid = ProcessInfo.processInfo.processIdentifier
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; \"\(path)\""]
        try? p.run()
        NSApp.terminate(nil)
    }

    // MARK: - Keyboard

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.moveDown(_:)):
            guard !filtered.isEmpty else { return true }
            let row = min(list.selectedRow + 1, filtered.count - 1)
            list.selectRowIndexes([row], byExtendingSelection: false)
            list.scrollRowToVisible(row)
        case #selector(NSResponder.moveUp(_:)):
            guard !filtered.isEmpty else { return true }
            let row = max(list.selectedRow - 1, 0)
            list.selectRowIndexes([row], byExtendingSelection: false)
            list.scrollRowToVisible(row)
        case #selector(NSResponder.insertNewline(_:)): launch()
        case #selector(NSResponder.cancelOperation(_:)): hide()
        default: return false
        }
        return true
    }

    // MARK: - Mouse

    func setupMouseTracking() {
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] e in
            guard let self = self, self.window.isVisible, e.window == self.window else { return e }
            let row = self.list.row(at: self.list.convert(e.locationInWindow, from: nil))
            if row >= 0, row != self.list.selectedRow { self.list.selectRowIndexes([row], byExtendingSelection: false) }
            return e
        }!)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            guard let self = self, self.window.isVisible, self.window.frame.contains(NSEvent.mouseLocation), !self.window.isKeyWindow else { return }
            self.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }!)
    }

    // MARK: - Menu & Hotkey

    func setupMenu() {
        let mainMenu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit Komet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Quit App", action: #selector(quitSelectedApp), keyEquivalent: "w"))
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        NSApp.mainMenu = mainMenu
    }

    func registerHotkey() {
        hotkey = Hotkey(keyCode: kVK_Space, modifiers: cmdKey) { [weak self] in self?.toggle() }
        if hotkey == nil {
            let alert = NSAlert()
            alert.messageText = "Komet cannot use ⌘Space"
            alert.informativeText = "Another app or a system shortcut already owns ⌘Space. Turn off Spotlight's shortcut in System Settings → Keyboard → Keyboard Shortcuts → Spotlight, then restart Komet. Until then, open Komet from its menu bar icon."
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }

        // Keys while the launcher is open; a local monitor sees only Komet's own events and needs no permission.
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self = self else { return e }
            guard self.window.isVisible else { return e }
            switch (e.keyCode, e.modifierFlags.contains(.command)) {
            case (48, _): self.toggleRunningFilter(); return nil
            case (12, true): NSApp.terminate(nil); return nil
            case (15, true): self.restartApp(); return nil
            case (43, true): self.showAbout(); return nil
            default: return e
            }
        }!)
    }

    // MARK: - About

    func showAbout() {
        if aboutPanel?.isVisible == true { closeAbout(); return }

        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 180),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.center()
        let content = makeVisualEffectView(panel.contentView!.bounds)
        panel.contentView = content

        let icon = NSImageView(frame: NSRect(x: 98, y: 110, width: 64, height: 64))
        icon.image = Bundle.main.resourcePath.flatMap { NSImage(contentsOfFile: ($0 as NSString).appendingPathComponent("AppIcon.icns")) } ?? NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        content.addSubview(icon)

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        for (text, y, size, weight, color): (String, CGFloat, CGFloat, NSFont.Weight, NSColor) in [
            ("Komet", 80, 18, .semibold, .white),
            ("v\(version)", 58, 12, .regular, .tertiaryLabelColor)
        ] {
            let l = NSTextField(labelWithString: text)
            l.frame = NSRect(x: 0, y: y, width: 260, height: 24)
            l.font = .systemFont(ofSize: size, weight: weight)
            l.textColor = color
            l.alignment = .center
            content.addSubview(l)
        }

        for (text, x, url): (String, CGFloat, String) in [("GitHub", 70, Config.githubURL), ("Releases", 138, Config.githubURL + "/releases/latest")] {
            let l = NSTextField(labelWithString: text)
            l.frame = NSRect(x: x, y: 20, width: 55, height: 16)
            l.font = .systemFont(ofSize: 12, weight: .medium)
            l.textColor = .linkColor
            l.tag = url.hashValue
            l.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(openLink(_:))))
            content.addSubview(l)
        }

        let sep = NSTextField(labelWithString: "·")
        sep.frame = NSRect(x: 122, y: 20, width: 16, height: 16)
        sep.font = .systemFont(ofSize: 12)
        sep.textColor = .tertiaryLabelColor
        sep.alignment = .center
        content.addSubview(sep)

        aboutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == 53 { self?.closeAbout() }
            return e
        }
        aboutPanel = panel
        panel.makeKeyAndOrderFront(nil)
    }

    func closeAbout() {
        aboutPanel?.close()
        aboutPanel = nil
        if let m = aboutMonitor { NSEvent.removeMonitor(m); aboutMonitor = nil }
    }

    @objc func openLink(_ gesture: NSClickGestureRecognizer) {
        guard let tag = gesture.view?.tag else { return }
        let url = tag == Config.githubURL.hashValue ? Config.githubURL : Config.githubURL + "/releases/latest"
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }
}

// MARK: - TableView

extension Komet: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { RoundedSelectionRowView() }

    func tableView(_ tableView: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        guard row < filtered.count else { return nil }
        let app = filtered[row]
        let id = NSUserInterfaceItemIdentifier("Cell")

        var cell = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView
        if cell == nil {
            let c = NSTableCellView()
            c.identifier = id

            let icon = NSImageView(frame: NSRect(x: 20, y: 9, width: 32, height: 32))
            icon.tag = 1
            c.addSubview(icon)

            let name = NSTextField(labelWithString: "")
            name.frame = NSRect(x: 64, y: 14, width: 400, height: 22)
            name.font = .systemFont(ofSize: 18)
            name.textColor = .white
            name.tag = 2
            c.addSubview(name)

            let dot = NSTextField(labelWithString: "●")
            dot.frame = NSRect(x: 618, y: 14, width: 20, height: 20)
            dot.font = .systemFont(ofSize: 12)
            dot.textColor = .systemGreen
            dot.tag = 3
            c.addSubview(dot)

            let close = NSTextField(labelWithString: "✕")
            close.frame = NSRect(x: 640, y: 14, width: 20, height: 20)
            close.font = .systemFont(ofSize: 14, weight: .medium)
            close.textColor = .secondaryLabelColor
            close.tag = 4
            c.addSubview(close)

            cell = c
        }

        (cell?.viewWithTag(1) as? NSImageView)?.image = app.icon
        (cell?.viewWithTag(2) as? NSTextField)?.stringValue = app.name
        cell?.viewWithTag(3)?.isHidden = !app.running
        cell?.viewWithTag(4)?.isHidden = !app.running
        return cell
    }
}

// MARK: - Entry Point

// One Komet at a time: a second copy could not register the hotkey the first one holds.
if let id = Bundle.main.bundleIdentifier,
   let other = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == id && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
    other.activate()
    exit(0)
}
// Left behind by versions that needed Accessibility permission.
UserDefaults.standard.removeObject(forKey: "KometWasTrustedOnce")

let app = NSApplication.shared
let komet = Komet()
app.delegate = komet
app.run()
